import AVFoundation
import Photos
import SwiftUI
import CoreImage
import UniformTypeIdentifiers

final class CameraController: NSObject, ObservableObject, AVCaptureSessionControlsDelegate {
    let session = AVCaptureSession()
    let vision = SubjectVision()
    let sessionQueue = DispatchQueue(label: "camera.session", qos: .userInitiated)
    private let renderQueue = DispatchQueue(label: "camera.photo", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let store = SettingsStore()
    private var device: AVCaptureDevice?
    private var input: AVCaptureDeviceInput?
    private var observations: [NSKeyValueObservation] = []
    private var jobs: [Int64: PhotoJob] = [:]
    private var configured = false
    private var referenceZoom: CGFloat = 1
    private var appliedSettings = CameraSettings()
    private var exposureTimer: DispatchSourceTimer?
    private var appliedExposureLock = false
    private var captureTask: Task<Void, Never>?
    private var focusLocked = false
    private var focusWasSingle = false
    private var sawFocusAdjustment = false
    private var lastFocusPoint = CGPoint(x: -1, y: -1)
    private var trackingFocusSuspended = false
    private var lastTrackedLensPosition: Float?
    private var notificationTokens: [NSObjectProtocol] = []
    weak var previewLayer: AVCaptureVideoPreviewLayer?

    @Published var fixedRotation: CGFloat = 0
    @Published var uiFixture: UIImage?
    @Published var remainingShots: Int?
    @Published private var focalAtOne: CGFloat?
    var isUIFixture: Bool {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["R6_UI_TESTING"] == "1"
        #else
        return false
        #endif
    }
    func equivalentFocalLength(at zoom: CGFloat) -> CGFloat? { focalAtOne.map { $0 * zoom } }

    @Published var settings: CameraSettings
    @Published var isRunning = false
    @Published var captureEnabled = true
    @Published var error: String?
    @Published var status = "正在啟動相機"
    @Published var tracking = TrackingResult()
    @Published var frameAspect: CGFloat = 0.75
    @Published var histogram: [Float] = []
    @Published var styledFrame: CGImage?
    @Published var actualExposureOffset: Float = 0
    @Published var actualISO: Float = 0
    @Published var actualShutter: Double = 1.0 / 125
    @Published var aperture: Float = 1.6
    @Published var zoom: CGFloat = 1
    @Published var zoomRange: ClosedRange<CGFloat> = 0.5...10
    @Published var supportsRAW = false
    @Published var supportsNativeZoom = false
    @Published var controlsActive = false
    @Published var singleFocused = false
    @Published var exposureLocked = false
    @Published var countdown = 0
    @Published var pendingPhotos = 0
    @Published var lastPhotoURL: URL?
    @Published var reviewImage: UIImage?
    @Published var battery: Float = -1

    override init() {
        var restored = SettingsStore().load() ?? CameraSettings()
        if restored.autofocus == .single { restored.autofocus = .servo }
        settings = restored
        super.init()
        UIDevice.current.isBatteryMonitoringEnabled = true
        vision.onFrame = { [weak self] result, aspect, histogram, styled in
            DispatchQueue.main.async {
                guard let self else { return }
                guard result.configuration == FocusConfiguration(self.settings) else { return }
                self.tracking = result
                self.frameAspect = aspect
                self.histogram = histogram
                guard self.settings.autofocus != .manual else { return }
                switch result.focusAction {
                case .continuous(let point): self.focusOnImagePoint(point, single: false)
                case .single(let point): self.focusOnImagePoint(point, single: true, force: true)
                case .hold: self.holdTrackedFocus()
                case .none: break
                }
            }
        }
        vision.onPreview = { [weak self] image in
            // Hold the render slot until displayed, so a busy main queue cannot accumulate frames.
            // Acknowledgement retains the bounded render slot until the main queue consumes it.
            DispatchQueue.main.async {
                defer { self?.vision.finishPreview() }
                guard let self, self.isRunning else { return }
                self.styledFrame = image
            }
        }
        vision.onModelError = { [weak self] message in
            DispatchQueue.main.async { self?.error = message }
        }
        notificationTokens.append(NotificationCenter.default.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main
        ) { [weak self] _ in
            self?.isRunning = false
            self?.status = "相機暫時中斷"
            self?.cancelCapture()
        })
        notificationTokens.append(NotificationCenter.default.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main
        ) { [weak self] _ in self?.start() })
        notificationTokens.append(NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main
        ) { [weak self] notification in
            self?.isRunning = false
            self?.error = (notification.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription ?? "相機發生錯誤，請重新開啟 App。"
        })
    }
    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        exposureTimer?.cancel()
        captureTask?.cancel()
    }

    private var fixtureTracker = SubjectTracker()
    private var fixtureDetections: [SubjectDetection] {
        [SubjectDetection(kind: .person, bounds: CGRect(x: 0.35, y: 0.2, width: 0.2, height: 0.6), confidence: 0.9,
                          leftEye: CGPoint(x: 0.42, y: 0.28), headBounds: CGRect(x: 0.38, y: 0.22, width: 0.12, height: 0.15))]
    }
    private func prepareUIFixture() {
        guard uiFixture == nil else { return }
        settings = CameraSettings(); settings.program = .manual; settings.grid = false
        settings.histogram = false; settings.shutterSeconds = 1.0 / 1000; settings.iso = 400
        actualShutter = settings.shutterSeconds; actualISO = 400; battery = 0.8
        frameAspect = 4.0 / 3; focalAtOne = nil
        let size = CGSize(width: 1200, height: 900)
        uiFixture = UIGraphicsImageRenderer(size: size).image { c in
            UIColor(red: 0.24, green: 0.32, blue: 0.28, alpha: 1).setFill(); c.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.3, green: 0.38, blue: 0.32, alpha: 1).setFill(); c.fill(CGRect(x: 0, y: 470, width: 1200, height: 430))
            UIColor(red: 0.42, green: 0.51, blue: 0.48, alpha: 1).setFill(); c.fill(CGRect(x: 420, y: 180, width: 240, height: 540))
            UIColor(red: 0.63, green: 0.59, blue: 0.48, alpha: 1).setFill(); c.cgContext.fillEllipse(in: CGRect(x: 456, y: 198, width: 144, height: 135))
        }
        tracking = fixtureTracker.update(fixtureDetections, at: 0, settings: settings)
    }

    func start() {
        #if targetEnvironment(simulator)
        DispatchQueue.main.async {
            self.status = "模擬器 UI 檢視 · 未啟動鏡頭"
            if self.isUIFixture { self.prepareUIFixture() }
        }
        #else
        Task { @MainActor in
            let allowed: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: allowed = true
            case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
            default: allowed = false
            }
            guard allowed else {
                self.error = "需要相機權限。請在 iPhone 設定中允許 R6 Camera 使用相機。"
                self.status = "相機權限未開啟"
                return
            }
            self.startSession(initial: self.settings)
        }
        #endif
    }
    private func startSession(initial startupSettings: CameraSettings) {
            sessionQueue.async {
                do {
                    if !self.configured { try self.configureSession(initial: startupSettings) }
                    if !self.session.isRunning {
                        self.trackingFocusSuspended = false
                        self.focusLocked = false
                        self.lastFocusPoint = CGPoint(x: -1, y: -1)
                        try self.applyToDevice(startupSettings)
                        self.session.startRunning()
                    }
                    DispatchQueue.main.async {
                        self.isRunning = self.session.isRunning
                        self.status = "就緒"
                        self.battery = UIDevice.current.batteryLevel
                    }
                } catch { self.report(error) }
            }
    }
    func stop() {
        cancelCapture()
        vision.reset()
        singleFocused = false
        sessionQueue.async {
            self.focusLocked = false
            self.trackingFocusSuspended = false
            self.lastTrackedLensPosition = nil
            self.lastFocusPoint = CGPoint(x: -1, y: -1)
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.isRunning = false }
        }
    }
    private func configureSession(initial: CameraSettings) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw cameraError("沒有可用的後置相機。")
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input), session.canAddOutput(photoOutput), session.canAddOutput(videoOutput) else {
            throw cameraError("無法配置相機輸入與輸出。")
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        session.addOutput(videoOutput)
        self.device = device
        self.input = input
        referenceZoom = CGFloat(device.virtualDeviceSwitchOverVideoZoomFactors.first?.doubleValue ?? 1)
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(vision, queue: vision.captureQueue)
        let rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        var angle: CGFloat = 0
        if #available(iOS 27.0, *) {
            angle = rotation.videoRotationAngleRelative(toDeviceOrientation: .landscapeRight)
        }
        for output in [videoOutput as AVCaptureOutput, photoOutput as AVCaptureOutput] {
            if let connection = output.connection(with: .video) {
                if #available(iOS 27.0, *) {
                    if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
                } else if connection.isVideoOrientationSupported { connection.videoOrientation = .landscapeRight }
            }
        }
        let fixedAngle = angle
        DispatchQueue.main.async { self.fixedRotation = fixedAngle }
        photoOutput.maxPhotoQualityPrioritization = .quality
        if let dimensions = device.activeFormat.supportedMaxPhotoDimensions.max(by: {
            Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height)
        }) { photoOutput.maxPhotoDimensions = dimensions }
        if photoOutput.isResponsiveCaptureSupported { photoOutput.isResponsiveCaptureEnabled = true }
        if photoOutput.isZeroShutterLagSupported { photoOutput.isZeroShutterLagEnabled = true }
        // No AVCaptureControl is registered: hardware light-press/slide must not alter zoom.
        let nativeZoom = false
        observations = [
            device.observe(\.videoZoomFactor, options: [.initial, .new]) { [weak self] device, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.syncNativeZoom(device.videoZoomFactor / self.referenceZoom)
                }
            },
            device.observe(\.isAdjustingFocus, options: [.new]) { [weak self] device, _ in
                guard let self else { return }
                self.sessionQueue.async {
                    if device.isAdjustingFocus { self.sawFocusAdjustment = true }
                    else if self.sawFocusAdjustment && self.appliedSettings.autofocus == .single {
                        self.sawFocusAdjustment = false
                        DispatchQueue.main.async { self.singleFocused = true }
                    }
                }
            }
        ]
        let minimum = device.minAvailableVideoZoomFactor / referenceZoom
        let maximum = min(device.maxAvailableVideoZoomFactor / referenceZoom, 10)
        let raw = !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty
        DispatchQueue.main.async {
            self.zoomRange = minimum...max(minimum, maximum)
            self.supportsRAW = raw
            self.supportsNativeZoom = nativeZoom
        }
        configured = true
        try applyToDevice(initial)
        try device.lockForConfiguration()
        device.videoZoomFactor = min(device.maxAvailableVideoZoomFactor,
                                    max(device.minAvailableVideoZoomFactor, initial.zoom * referenceZoom))
        device.unlockForConfiguration()
        vision.configure(initial)
        vision.loadModel()
        let timer = DispatchSource.makeTimerSource(queue: sessionQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(200))
        timer.setEventHandler { [weak self] in self?.updateMetering() }
        timer.resume()
        exposureTimer = timer
    }

    /// UI mutations are persisted once and sent as immutable snapshots to serial owners.
    func update(_ transform: (inout CameraSettings) -> Void) {
        let previous = settings
        transform(&settings)
        if settings.autofocus == .single { settings.autofocus = .servo }
        if previous.autofocus != settings.autofocus || previous.subjects != settings.subjects {
            holdTrackedFocus()
        }
        store.save(settings)
        let snapshot = settings
        vision.configure(snapshot)
        if snapshot.autofocus != .single { singleFocused = false }
        sessionQueue.async {
            do { try self.applyToDevice(snapshot) } catch { self.report(error) }
        }
    }
    private func applyToDevice(_ settings: CameraSettings) throws {
        guard let device else { return }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        let changedAF = appliedSettings.autofocus != settings.autofocus
        if changedAF { trackingFocusSuspended = false; lastTrackedLensPosition = nil }
        appliedSettings = settings
        if settings.autofocus == .manual {
            if device.isLockingFocusWithCustomLensPositionSupported {
                device.setFocusModeLocked(lensPosition: settings.manualFocus, completionHandler: nil)
            }
        } else if changedAF || !focusLocked {
            if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
        }
        if settings.requiresExactExposure {
            let seconds = settings.controlsShutter ? settings.shutterSeconds : device.exposureDuration.seconds
            let iso = settings.controlsISO ? Float(settings.iso) : device.iso
            setCustomExposure(device, seconds: seconds, iso: iso)
        } else if !appliedExposureLock && device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        device.setExposureTargetBias(min(device.maxExposureTargetBias, max(device.minExposureTargetBias, Float(settings.exposureBias))), completionHandler: nil)
        if settings.whiteBalance == .automatic {
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
        } else if device.isWhiteBalanceModeSupported(.locked) {
            let temperature: Float
            switch settings.whiteBalance {
            case .daylight: temperature = 5200
            case .shade: temperature = 7000
            case .tungsten: temperature = 3200
            default: temperature = Float(settings.kelvin)
            }
            var gains = device.deviceWhiteBalanceGains(for: .init(temperature: temperature, tint: 0))
            gains.redGain = min(device.maxWhiteBalanceGain, max(1, gains.redGain))
            gains.greenGain = min(device.maxWhiteBalanceGain, max(1, gains.greenGain))
            gains.blueGain = min(device.maxWhiteBalanceGain, max(1, gains.blueGain))
            device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
        }
        if device.isVirtualDevice {
            device.setPrimaryConstituentDeviceSwitchingBehavior(settings.lockLens ? .locked : .auto,
                                                               restrictedSwitchingBehaviorConditions: [])
        }
    }
    private func setCustomExposure(_ device: AVCaptureDevice, seconds: Double, iso: Float) {
        guard device.isExposureModeSupported(.custom) else { return }
        let duration = max(device.activeFormat.minExposureDuration.seconds,
                           min(device.activeFormat.maxExposureDuration.seconds, seconds))
        device.setExposureModeCustom(duration: CMTime(seconds: duration, preferredTimescale: 1_000_000_000),
                                     iso: max(device.activeFormat.minISO, min(device.activeFormat.maxISO, iso)), completionHandler: nil)
    }
    private func updateMetering() {
        guard let device, session.isRunning else { return }
        let settings = appliedSettings
        if settings.requiresExactExposure && !appliedExposureLock && settings.controlsISO != settings.controlsShutter {
            // Feedback-based priority AE: targetOffset already reflects exposureTargetBias.
            let factor = pow(2.0, Double(-device.exposureTargetOffset) * 0.35)
            if factor.isFinite, abs(device.exposureTargetOffset) > 0.08 {
                do {
                    try device.lockForConfiguration()
                    if settings.controlsShutter {
                        setCustomExposure(device, seconds: settings.shutterSeconds, iso: device.iso * Float(factor))
                    } else {
                        setCustomExposure(device, seconds: device.exposureDuration.seconds * factor, iso: Float(settings.iso))
                    }
                    device.unlockForConfiguration()
                } catch { report(error) }
            }
        }
        let count = jobs.count
        DispatchQueue.main.async {
            self.actualExposureOffset = device.exposureTargetOffset.isFinite ? device.exposureTargetOffset : 0
            self.actualISO = device.iso
            self.actualShutter = device.exposureDuration.seconds
            self.aperture = device.lensAperture
            self.pendingPhotos = count
            let fov = Double(device.activeFormat.videoFieldOfView) * .pi / 180
            let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            let aspect = Double(dimensions.width) / Double(max(1, dimensions.height))
            let diagonal = 2 * tan(fov / 2) * sqrt(1 + 1 / (aspect * aspect))
            if diagonal > 0 { self.focalAtOne = CGFloat(43.2666 / diagonal) * self.referenceZoom }
        }
    }
    func setZoom(_ zoom: CGFloat) {
        let factor = min(zoomRange.upperBound, max(zoomRange.lowerBound, zoom))
        settings.zoom = factor
        store.save(settings)
        if isUIFixture { self.zoom = factor }
        sessionQueue.async {
            guard let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = max(device.minAvailableVideoZoomFactor,
                                             min(device.maxAvailableVideoZoomFactor, factor * self.referenceZoom))
                device.unlockForConfiguration()
            } catch { self.report(error) }
        }
    }
    private func syncNativeZoom(_ value: CGFloat) {
        zoom = value
        if abs(settings.zoom - value) > 0.001 {
            settings.zoom = value
            store.save(settings)
        }
    }
    func tap(at imagePoint: CGPoint) {
        guard isRunning || isUIFixture, settings.autofocus != .manual else { return }
        singleFocused = false
        if isUIFixture {
            fixtureTracker.select(at: imagePoint, eyes: settings.eyes)
            tracking = fixtureTracker.result
        } else { vision.select(imagePoint) }
    }
    func autofocus() { tap(at: CGPoint(x: 0.5, y: 0.5)) }
    func unlockTracking() {
        if isUIFixture { fixtureTracker.unlock(); _ = fixtureTracker.update(fixtureDetections, at: 1, settings: settings); tracking = fixtureTracker.result }
        else { vision.unlock() }
        singleFocused = false
    }
    private func holdTrackedFocus() {
        sessionQueue.async {
            guard !self.trackingFocusSuspended, self.session.isRunning, let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                let position = self.focusWasSingle ? device.lensPosition : self.lastTrackedLensPosition
                if device.isLockingFocusWithCustomLensPositionSupported, let position {
                    device.setFocusModeLocked(lensPosition: position, completionHandler: nil)
                    self.trackingFocusSuspended = true
                } else if device.isFocusModeSupported(.locked) {
                    device.focusMode = .locked
                    self.trackingFocusSuspended = true
                }
            } catch { self.report(error) }
        }
    }
    private func focusOnImagePoint(_ point: CGPoint, single: Bool, force: Bool = false) {
        guard isRunning, settings.autofocus != .manual, let layer = previewLayer else { return }
        let display = ViewfinderGeometry.display(point, imageAspect: frameAspect, size: layer.bounds.size)
        let devicePoint = layer.captureDevicePointConverted(fromLayerPoint: display)
        sessionQueue.async {
            guard self.session.isRunning, let device = self.device else { return }
            self.lastTrackedLensPosition = device.lensPosition
            if !force && !self.trackingFocusSuspended && hypot(self.lastFocusPoint.x - devicePoint.x, self.lastFocusPoint.y - devicePoint.y) < 0.015 { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = devicePoint }
                let mode: AVCaptureDevice.FocusMode = single ? .autoFocus : .continuousAutoFocus
                if device.isFocusModeSupported(mode) {
                    device.focusMode = mode
                    self.trackingFocusSuspended = false
                    self.lastFocusPoint = devicePoint
                }
                self.focusLocked = true
                self.focusWasSingle = single
                self.sawFocusAdjustment = false
                if !self.appliedExposureLock && !self.appliedSettings.requiresExactExposure,
                   device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                }
            } catch { self.report(error) }
        }
    }
    func toggleExposureLock() {
        exposureLocked.toggle()
        let locked = exposureLocked
        sessionQueue.async {
            self.appliedExposureLock = locked
            guard let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                if locked && device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
                device.unlockForConfiguration()
                if !locked { try self.applyToDevice(self.appliedSettings) }
            } catch { self.report(error) }
        }
    }

    func shutter() {
        guard isRunning, captureEnabled, captureTask == nil else { return }
        let snapshot = settings
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.countdown = 0; self.captureTask = nil }
            for second in stride(from: snapshot.drive.delay, through: 1, by: -1) {
                self.countdown = second
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            }
            guard !Task.isCancelled else { return }
            self.countdown = 0
            guard !Task.isCancelled else { return }
            self.capture(snapshot)
        }
    }
    func beginBurst() {
        guard settings.drive == .burst, isRunning, captureEnabled, captureTask == nil else { shutter(); return }
        let snapshot = settings
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.captureTask = nil }
            while !Task.isCancelled && self.isRunning {
                self.capture(snapshot)
                do { try await Task.sleep(nanoseconds: 350_000_000) } catch { break }
            }
        }
    }
    func cancelCapture() { captureTask?.cancel() }
    private func capture(_ settings: CameraSettings) {
        sessionQueue.async { [self] in
            guard self.session.isRunning else { return }
            // Back pressure: no unbounded RAW/full-resolution work while the button is held.
            guard self.jobs.count < 2 else { return }
            let raw = settings.format == .raw ? self.photoOutput.availableRawPhotoPixelFormatTypes.first : nil
            let useHEIF = settings.format == .heif && self.photoOutput.availablePhotoCodecTypes.contains(.hevc)
            let codec: AVVideoCodecType = useHEIF ? .hevc : .jpeg
            let capture: AVCapturePhotoSettings
            if let raw {
                capture = AVCapturePhotoSettings(rawPixelFormatType: raw, processedFormat: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else { capture = AVCapturePhotoSettings(format: [AVVideoCodecKey: codec]) }
            capture.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            capture.photoQualityPrioritization = settings.requiresExactExposure ? .speed : .balanced
            let job = PhotoJob(settings: settings, type: useHEIF ? .heic : .jpeg) { [weak self] result in
                guard let self else { return }
                self.renderQueue.async { self.finishPhoto(result, id: capture.uniqueID) }
            }
            self.jobs[capture.uniqueID] = job
            let count = self.jobs.count
            DispatchQueue.main.async { self.pendingPhotos = count }
            self.photoOutput.capturePhoto(with: capture, delegate: job)
        }
    }
    private func finishPhoto(_ result: Result<PhotoJob.Output, Error>, id: Int64) {
        defer {
            sessionQueue.async {
                self.jobs.removeValue(forKey: id)
                let count = self.jobs.count
                DispatchQueue.main.async { self.pendingPhotos = count }
            }
        }
        do {
            let output = try result.get()
            let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let stem = "R6_\(Int(Date().timeIntervalSince1970))_\(id)"
            let url = directory.appendingPathComponent(stem).appendingPathExtension(output.type == .heic ? "heic" : "jpg")
            // Persist original capture first. A failed style render must never discard a photo.
            try output.processed.write(to: url, options: .atomic)
            var rawURL: URL?
            if let raw = output.raw {
                let target = directory.appendingPathComponent(stem).appendingPathExtension("dng")
                try raw.write(to: target, options: .atomic)
                rawURL = target
            }
            var rendered = output.processed
            do {
                rendered = try PhotoRenderer.render(output.processed, settings: output.settings, type: output.type, context: CIContext())
                try rendered.write(to: url, options: .atomic)
            } catch {
                rendered = output.processed
                self.report(self.cameraError("風格處理失敗，已保留原始照片：\(error.localizedDescription)"))
            }
            DispatchQueue.main.async {
                self.lastPhotoURL = url
                self.reviewImage = UIImage(data: rendered)
                self.status = "照片已存於 App"
                if output.settings.reviewSeconds > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(output.settings.reviewSeconds)) {
                        if self.lastPhotoURL == url { self.reviewImage = nil }
                    }
                } else { self.reviewImage = nil }
            }
            saveToLibrary(url, rawURL: rawURL)
        } catch { report(error) }
    }
    private func saveToLibrary(_ url: URL, rawURL: URL?) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] authorization in
            guard authorization == .authorized || authorization == .limited else {
                DispatchQueue.main.async { self?.status = "相簿權限未開啟，照片仍保存在 App 內，可從回放分享。" }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: url, options: nil)
                if let rawURL { request.addResource(with: .alternatePhoto, fileURL: rawURL, options: nil) }
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    self?.status = success ? "已儲存到相簿" : "相簿儲存失敗；原檔保留在 App"
                    if let error { self?.error = error.localizedDescription }
                }
            }
        }
    }
    func savePreset(_ name: String) { store.save(settings, key: name); status = "已儲存 \(name)" }
    func recallPreset(_ name: String) {
        guard let saved = store.load(name) else { status = "\(name) 尚未儲存；長按可儲存目前設定"; return }
        update { $0 = saved }
        setZoom(saved.zoom)
        status = "已載入 \(name)"
    }
    func galleryURLs() -> [URL] {
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["heic", "jpg"].contains($0.pathExtension) }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
    private func cameraError(_ message: String) -> NSError {
        NSError(domain: "Camera", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private func report(_ error: Error) { DispatchQueue.main.async { self.error = error.localizedDescription } }
    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {
        DispatchQueue.main.async { self.controlsActive = true }
    }
    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {
        DispatchQueue.main.async { self.controlsActive = false }
    }
    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {}
    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {}
}

private final class PhotoJob: NSObject, AVCapturePhotoCaptureDelegate {
    struct Output {
        let processed: Data
        let raw: Data?
        let settings: CameraSettings
        let type: UTType
    }
    let settings: CameraSettings
    let type: UTType
    let completion: (Result<Output, Error>) -> Void
    private var processed: Data?
    private var raw: Data?
    private var processingError: Error?
    init(settings: CameraSettings, type: UTType, completion: @escaping (Result<Output, Error>) -> Void) {
        self.settings = settings; self.type = type; self.completion = completion
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { processingError = error; return }
        guard let data = photo.fileDataRepresentation() else { return }
        if photo.isRawPhoto { raw = data } else { processed = data }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error ?? processingError { completion(.failure(error)); return }
        guard let processed else {
            completion(.failure(NSError(domain: "Photo", code: 1, userInfo: [NSLocalizedDescriptionKey: "相機未傳回照片資料。"])))
            return
        }
        completion(.success(Output(processed: processed, raw: raw, settings: settings, type: type)))
    }
}
