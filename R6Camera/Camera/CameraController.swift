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
    private var sawFocusAdjustment = false
    private var lastFocusPoint = CGPoint(x: -1, y: -1)
    private var notificationTokens: [NSObjectProtocol] = []
    weak var previewLayer: AVCaptureVideoPreviewLayer?

    @Published var settings: CameraSettings
    @Published var isRunning = false
    @Published var error: String?
    @Published var status = "正在啟動相機"
    @Published var tracking = TrackingResult()
    @Published var frameAspect: CGFloat = 0.75
    @Published var histogram: [Float] = []
    @Published var styledFrame: CGImage?
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
        settings = store.load() ?? CameraSettings()
        super.init()
        UIDevice.current.isBatteryMonitoringEnabled = true
        vision.onFrame = { [weak self] result, aspect, histogram, styled in
            DispatchQueue.main.async {
                guard let self else { return }
                self.tracking = result
                self.frameAspect = aspect
                self.histogram = histogram
                if let subject = result.selected, !result.missing,
                   self.settings.autofocus == .servo {
                    self.focusOnImagePoint(subject.focusPoint(self.settings.eyes), single: false)
                }
            }
        }
        vision.onPreview = { [weak self] image in
            // Hold the render slot until displayed, so a busy main queue cannot accumulate frames.
            DispatchQueue.main.sync {
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

    func start() {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["R6_UI_TESTING"] == "1" {
            status = "模擬器 UI 檢視 · 未啟動鏡頭"
            return
        }
        #endif
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
    }
    private func startSession(initial startupSettings: CameraSettings) {
            sessionQueue.async {
                do {
                    if !self.configured { try self.configureSession(initial: startupSettings) }
                    if !self.session.isRunning { self.session.startRunning() }
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
        if let connection = videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        photoOutput.maxPhotoQualityPrioritization = .quality
        if let dimensions = device.activeFormat.supportedMaxPhotoDimensions.max(by: {
            Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height)
        }) { photoOutput.maxPhotoDimensions = dimensions }
        if photoOutput.isResponsiveCaptureSupported { photoOutput.isResponsiveCaptureEnabled = true }
        if photoOutput.isZeroShutterLagSupported { photoOutput.isZeroShutterLagEnabled = true }
        let nativeZoom: Bool
        if session.supportsControls {
            let control = AVCaptureSystemZoomSlider(device: device) { [weak self] value in
                guard let self else { return }
                self.syncNativeZoom(value / self.referenceZoom)
            }
            nativeZoom = session.canAddControl(control)
            if nativeZoom { session.addControl(control) }
            session.setControlsDelegate(self, queue: sessionQueue)
        } else { nativeZoom = false }
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
        transform(&settings)
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
        appliedSettings = settings
        if settings.autofocus == .manual {
            if device.isLockingFocusWithCustomLensPositionSupported {
                device.setFocusModeLocked(lensPosition: settings.manualFocus, completionHandler: nil)
            }
        } else if changedAF || !focusLocked {
            let mode: AVCaptureDevice.FocusMode = settings.autofocus == .servo ? .continuousAutoFocus : .autoFocus
            if device.isFocusModeSupported(mode) { device.focusMode = mode }
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
            self.actualISO = device.iso
            self.actualShutter = device.exposureDuration.seconds
            self.aperture = device.lensAperture
            self.pendingPhotos = count
        }
    }
    func setZoom(_ zoom: CGFloat) {
        let factor = min(zoomRange.upperBound, max(zoomRange.lowerBound, zoom))
        settings.zoom = factor
        store.save(settings)
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
    func rotate(to angle: CGFloat) {
        guard let connection = previewLayer?.connection else { return }
        if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
        vision.reset()
        sessionQueue.async {
            for output in [self.videoOutput as AVCaptureOutput, self.photoOutput as AVCaptureOutput] {
                if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            }
            self.lastFocusPoint = CGPoint(x: -1, y: -1)
        }
    }
    func tap(at imagePoint: CGPoint) {
        vision.select(imagePoint)
        singleFocused = false
        let subject = tracking.candidates.filter { $0.bounds.contains(imagePoint) }
            .min { $0.bounds.area < $1.bounds.area }
        if let subject, settings.eyes != .off {
            let leftDistance = subject.leftEye.map { hypot($0.x - imagePoint.x, $0.y - imagePoint.y) } ?? .infinity
            let rightDistance = subject.rightEye.map { hypot($0.x - imagePoint.x, $0.y - imagePoint.y) } ?? .infinity
            if min(leftDistance, rightDistance) < 0.05 {
                update { $0.eyes = leftDistance < rightDistance ? .left : .right }
            }
        }
        let target = subject?.focusPoint(settings.eyes) ?? imagePoint
        focusOnImagePoint(target, single: settings.autofocus == .single, force: true)
    }
    func autofocus() {
        guard settings.autofocus != .manual else { return }
        singleFocused = false
        let point = tracking.selected?.focusPoint(settings.eyes) ?? CGPoint(x: 0.5, y: 0.5)
        focusOnImagePoint(point, single: true, force: true)
    }
    func unlockTracking() {
        vision.unlock()
        singleFocused = false
        sessionQueue.async { self.focusLocked = false; self.lastFocusPoint = CGPoint(x: -1, y: -1) }
    }
    private func focusOnImagePoint(_ point: CGPoint, single: Bool, force: Bool = false) {
        guard settings.autofocus != .manual, let layer = previewLayer else { return }
        let display = ViewfinderGeometry.display(point, imageAspect: frameAspect, size: layer.bounds.size)
        let devicePoint = layer.captureDevicePointConverted(fromLayerPoint: display)
        sessionQueue.async {
            guard let device = self.device else { return }
            if !force && hypot(self.lastFocusPoint.x - devicePoint.x, self.lastFocusPoint.y - devicePoint.y) < 0.015 { return }
            self.lastFocusPoint = devicePoint
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = devicePoint }
                let mode: AVCaptureDevice.FocusMode = single ? .autoFocus : .continuousAutoFocus
                if device.isFocusModeSupported(mode) { device.focusMode = mode }
                self.focusLocked = single
                self.sawFocusAdjustment = false
                if !self.appliedExposureLock && !self.appliedSettings.requiresExactExposure,
                   device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                }
                device.unlockForConfiguration()
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
        guard isRunning, captureTask == nil else { return }
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
            self.capture(snapshot)
        }
    }
    func beginBurst() {
        guard settings.drive == .burst, isRunning, captureTask == nil else { shutter(); return }
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
