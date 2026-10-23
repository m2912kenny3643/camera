import AVFoundation
import Photos
import SwiftUI
import CoreImage
import UniformTypeIdentifiers

final class CameraController: NSObject, ObservableObject, AVCaptureSessionControlsDelegate, AVCapturePhotoOutputReadinessCoordinatorDelegate {
    let session = AVCaptureSession()
    let vision = SubjectVision()
    let sessionQueue = DispatchQueue(label: "camera.session", qos: .userInitiated)
    let photos = PhotoLibraryStore()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let store = SettingsStore()
    private let lifecycle = SessionLifecycle()
    private var startTask: Task<Void, Never>?
    private var device: AVCaptureDevice?
    private var input: AVCaptureDeviceInput?
    private var observations: [NSKeyValueObservation] = []
    private var jobs: [Int64: PhotoJob] = [:]
    private var renderingPhotos = 0 // sessionQueue owns both stages and total capacity.
    private var preparedPhotoKey: String?
    private var readinessCoordinator: AVCapturePhotoOutputReadinessCoordinator?
    private var captureCancellation: CaptureCancellation?
    private var burstMeasurement: CaptureCancellation?
    private var burstDiagnostics: BurstDiagnostics?
    private let calibrationStore = BurstCalibrationStore()
    private var calibration: BurstCalibration?
    private var calibrationMeasurement: CaptureCancellation?
    private var calibrationConsumed: CaptureCancellation?
    private var measurementKey: String?
    private var lensIdentifier = "unknown"
    @Published private(set) var calibrationStatus = "未校準：使用保守連拍上限"
    @Published private(set) var burstStableTarget: Double?
    @Published private(set) var isCalibrating = false
    private var frameGate = VisionFrameGate()
    private var zoomCommand = 0 // main queue; latest command reconciles hardware clamping.
    private var configured = false
    private var referenceZoom: CGFloat = 1
    private var appliedSettings = CameraSettings()
    private var exposureTimer: DispatchSourceTimer?
    private var appliedExposureLock = false
    private var captureTask: Task<Void, Never>?
    private enum LensStrategy { case scene, subject, point, manual }
    private var lensStrategy = LensStrategy.scene
    private var sawFocusAdjustment = false
    private var lastFocusPoint = CGPoint(x: -1, y: -1)
    private var trackingFocusSuspended = false
    private var lastTrackedLensPosition: Float?
    private var notificationTokens: [NSObjectProtocol] = []
    private var focusModeControl: AVCaptureIndexPicker? // sessionQueue only.
    private var hardwareShutter = HardwareShutter() // main queue only.
    private var hardwareResetTime = 0.0
    @Published private var hardwareRecords: [HardwareShutterRecord] = []
    private var hardwareFocusAfterReturn = false
    @Published private(set) var capturePageReturnRequest: UInt64 = 0
    @Published private(set) var hardwareReturningToCapture = false
    @Published private(set) var hardwareControlsSupported = false { didSet { syncHardwareReceiver() } }
    @Published private(set) var hardwareControlStatus = "實驗性兩段硬體快門未啟用"
    weak var previewLayer: AVCaptureVideoPreviewLayer?
    weak var presentationWindow: UIWindow?
    let hardwareReceiver = HardwareCaptureReceiver()
    var sceneIsActive = true {
        didSet {
            if !sceneIsActive { lifecycle.invalidate(); startTask?.cancel(); cancelCapture(reason: "scene-inactive") }
            syncHardwareReceiver()
        }
    }
    private var twoStageAvailable: Bool { settings.experimentalHardwareShutter && hardwareControlsSupported }
    func bindHardwareView(_ view: UIView) {
        guard let window = view.window else { return }
        presentationWindow = window
        let changedWindow = hardwareReceiver.bind(view)
        if changedWindow { resetHardwareShutter(reason: "receiver-scene-changed") }
        syncHardwareReceiver()
        recordHardware(.reset, time: CACurrentMediaTime(), available: hardwareReceiver.enabled,
            decision: HardwareShutter.Decision(actions: [], reason: "receiver-content-host-installed-not-hardware-proof"), eventName: "receiverHostBound")
    }
    func unbindHardwareView(_ view: UIView) {
        hardwareReceiver.unbind(view)
        syncHardwareReceiver()
        recordHardware(.reset, time: CACurrentMediaTime(), available: hardwareReceiver.enabled,
            decision: HardwareShutter.Decision(actions: [], reason: "receiver-content-host-removed-not-hardware-proof"), eventName: "receiverHostRemoved")
    }
    private func syncHardwareReceiver() {
        hardwareReceiver.setEnabled(sceneIsActive && isRunning && (captureEnabled || twoStageAvailable))
    }

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
    func simulateCaptureFeedback() {
        guard isUIFixture else { return }
        captureFeedback &+= 1
    }

    @Published var settings: CameraSettings {
        didSet { if oldValue != settings { resetHardwareShutter(preservingOverlay: true, reason: "settings-changed") }; syncHardwareReceiver() }
    }
    @Published var isRunning = false {
        didSet { if !isRunning { controlsActive = false; cancelCapture(reason: "session-not-running") }; syncHardwareReceiver() }
    }
    @Published var captureEnabled = true {
        didSet { if !captureEnabled { cancelCapture(reason: "capture-page-covered") }; syncHardwareReceiver() }
    }
    @Published var error: String?
    @Published var status = "正在啟動相機"
    @Published private(set) var settingsRecoveryMessage: String?
    @Published private(set) var birdStatus = "鳥眼模型尚未載入"
    @Published var tracking = TrackingResult()
    @Published private(set) var frameSize = CGSize(width: 4, height: 3)
    var frameAspect: CGFloat { frameSize.width / max(1, frameSize.height) }
    var framingWarning: String? {
        abs(frameAspect - ViewfinderGeometry.photoAspect) > 0.01 ? "預覽來源非 4:3，已完整等比顯示" : nil
    }
    @Published var histogram: [Float] = []
    @Published var styledFrame: CGImage?
    @Published var actualExposureOffset: Float = 0
    @Published var actualISO: Float = 0
    @Published var actualShutter: Double = 1.0 / 125
    @Published var aperture: Float = 1.6
    @Published var zoom: CGFloat = 1
    @Published var zoomRange: ClosedRange<CGFloat> = 0.5...10
    @Published var supportsRAW = false
    @Published private(set) var photoResolution: String?
    @Published var supportsNativeZoom = false
    @Published var controlsActive = false
    @Published var singleFocused = false
    @Published var exposureLocked = false
    @Published var countdown = 0
    @Published var pendingPhotos = 0
    @Published private(set) var captureBusy = false
    @Published private(set) var captureReady = false
    @Published private(set) var burstFPS: Double?
    @Published private(set) var burstIntervals: [Double] = []
    @Published private(set) var burstRequestFPS: Double?
    @Published private(set) var burstLimitReason: String?
    @Published private(set) var burstReportText: String?
    @Published private(set) var lastPhotoDimensions: String?
    private var requestedPhotoPixels: Int64 = 0 // main queue snapshot of output configuration.
    private var responsiveCapture = false
    @Published var lastPhotoURL: URL?
    @Published private(set) var captureFeedback = 0
    @Published private(set) var hardwareInjectionCount = 0 // Simulator fixture only, never SDK delivery.
    @Published var battery: Float = -1

    override init() {
        let restored = SettingsStore().load() ?? CameraSettings()
        settings = restored
        super.init()
        settingsRecoveryMessage = store.diagnostics
        hardwareReceiver.onInput = { [weak self] input, time in self?.hardwareInput(input, at: time) }
        UIDevice.current.isBatteryMonitoringEnabled = true
        vision.onFrame = { [weak self] result, size, histogram, styled in
            DispatchQueue.main.async {
                guard let self else { return }
                guard result.configuration == FocusConfiguration(self.settings),
                      self.frameGate.accept(result, currentEpoch: self.vision.currentEpoch, now: CACurrentMediaTime()) else { return }
                if self.styledFrame == nil { self.frameSize = size }
                guard abs(self.frameAspect - size.width / max(1, size.height)) < 0.01 else { return }
                self.tracking = result
                self.histogram = histogram
                guard self.settings.effective.autofocus != .manual else { return }
                switch result.focusAction {
                case .scene: self.resumeSceneFocus()
                case .continuous(let point): self.focusOnImagePoint(point, single: false)
                case .single(let point): self.focusOnImagePoint(point, single: true, force: true)
                case .hold: self.holdTrackedFocus()
                case .none: break
                }
            }
        }
        vision.onPreview = { [weak self] image, size in
            // Hold the render slot until displayed, so a busy main queue cannot accumulate frames.
            // Acknowledgement retains the bounded render slot until the main queue consumes it.
            DispatchQueue.main.async {
                defer { self?.vision.finishPreview() }
                guard let self, self.isRunning else { return }
                if abs(self.frameAspect - size.width / max(1, size.height)) > 0.01 { self.tracking = TrackingResult() }
                self.frameSize = size
                self.styledFrame = image
            }
        }
        vision.onModelError = { [weak self] message in
            DispatchQueue.main.async { self?.error = message }
        }
        vision.onBirdStatus = { [weak self] message in
            DispatchQueue.main.async {
                guard let self else { return }
                self.birdStatus = message
                if !message.contains("已載入"), self.isCalibrating { self.cancelBurstCalibration(); self.calibrationStatus = "鳥眼推論中斷，校準結果不保存" }
            }
        }
        notificationTokens.append(NotificationCenter.default.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main
        ) { [weak self] _ in
            self?.lifecycle.invalidate(); self?.startTask?.cancel()
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
            self?.lifecycle.invalidate(); self?.startTask?.cancel()
            self?.isRunning = false
            self?.error = (notification.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription ?? "相機發生錯誤，請重新開啟 App。"
        })
    }
    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        exposureTimer?.cancel()
        captureTask?.cancel()
        startTask?.cancel()
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
        frameSize = CGSize(width: 1200, height: 900); focalAtOne = nil
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
        guard let token = lifecycle.begin(active: sceneIsActive) else { return }
        startTask?.cancel()
        #if targetEnvironment(simulator)
        DispatchQueue.main.async {
            guard self.lifecycle.permits(token), self.sceneIsActive else { return }
            self.status = "模擬器 UI 檢視 · 未啟動鏡頭"
            if self.isUIFixture {
                self.prepareUIFixture()
                if self.hardwareReturnFixture { self.hardwareControlsSupported = true; self.isRunning = true }
            }
        }
        #else
        startTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let allowed: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: allowed = true
            case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
            default: allowed = false
            }
            guard !Task.isCancelled, self.lifecycle.permits(token), self.sceneIsActive else { return }
            guard allowed else {
                self.error = "需要相機權限。請在 iPhone 設定中允許 R6 Camera 使用相機。"
                self.status = "相機權限未開啟"
                return
            }
            self.startSession(initial: self.settings, token: token)
        }
        #endif
    }
    private func startSession(initial startupSettings: CameraSettings, token: UInt64) {
            sessionQueue.async {
                guard self.lifecycle.permits(token) else { return }
                do {
                    if !self.configured { try self.configureSession(initial: startupSettings) }
                    if !self.session.isRunning {
                        self.trackingFocusSuspended = false
                        self.lensStrategy = .scene
                        self.lastFocusPoint = CGPoint(x: -1, y: -1)
                        try self.applyToDevice(startupSettings)
                        self.preparePhotoResources(startupSettings)
                        guard self.lifecycle.permits(token) else { return }
                        self.session.startRunning()
                    }
                    DispatchQueue.main.async {
                        guard self.lifecycle.permits(token), self.sceneIsActive else { return }
                        self.isRunning = self.session.isRunning
                        self.status = "就緒"
                        self.battery = UIDevice.current.batteryLevel
                    }
                } catch { self.report(error) }
            }
    }
    func stop() {
        lifecycle.invalidate(); startTask?.cancel()
        isRunning = false // Revoke the window receiver before waiting for sessionQueue.
        controlsActive = false
        cancelCapture()
        vision.reset()
        singleFocused = false
        sessionQueue.async {
            self.lensStrategy = .scene
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
        DispatchQueue.main.async {
            let coordinator = AVCapturePhotoOutputReadinessCoordinator(photoOutput: self.photoOutput)
            coordinator.delegate = self
            self.readinessCoordinator = coordinator
        }
        configureHardwareControls(initial)
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
                    else if self.sawFocusAdjustment && self.lensStrategy == .point {
                        self.sawFocusAdjustment = false
                        DispatchQueue.main.async { self.singleFocused = true }
                    }
                }
            }
        ]
        let minimum = device.minAvailableVideoZoomFactor / referenceZoom
        let maximum = min(device.maxAvailableVideoZoomFactor / referenceZoom, 10)
        let raw = !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty
        let dimensions = photoOutput.maxPhotoDimensions
        let responsive = photoOutput.isResponsiveCaptureEnabled
        DispatchQueue.main.async {
            self.zoomRange = minimum...max(minimum, maximum)
            self.supportsRAW = raw
            self.photoResolution = "\(dimensions.width) × \(dimensions.height)"
            self.lensIdentifier = device.uniqueID
            self.requestedPhotoPixels = Int64(dimensions.width) * Int64(dimensions.height)
            self.responsiveCapture = responsive
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
        if previous.experimentalHardwareShutter != settings.experimentalHardwareShutter {
            hardwareControlsSupported = false
            hardwareControlStatus = settings.experimentalHardwareShutter
                ? "等待裝置控制浮層；模擬器不能驗證硬體手勢"
                : "實驗性兩段硬體快門未啟用"
        }
        if previous != settings {
            // settings.didSet already reset the gate while preserving a still-visible overlay.
            captureCancellation?.cancel(); captureTask?.cancel()
        }
        if previous != settings, isCalibrating {
            calibration = nil; isCalibrating = false; calibrationStatus = "設定已變更，校準中止"
        }
        if previous.effective.autofocus != settings.effective.autofocus ||
           previous.effective.subjects != settings.effective.subjects ||
           previous.effective.focusArea != settings.effective.focusArea {
            holdTrackedFocus()
            tracking = TrackingResult(); singleFocused = false
            fixtureTracker.reset()
            if isUIFixture { tracking = fixtureTracker.update(fixtureDetections, at: 0, settings: settings.effective) }
        }
        persistSettings()
        let snapshot = settings.effective
        vision.configure(snapshot)
        if snapshot.autofocus != .single { singleFocused = false }
        sessionQueue.async {
            do {
                if self.configured {
                    if previous.experimentalHardwareShutter != snapshot.experimentalHardwareShutter {
                        self.session.beginConfiguration()
                        self.configureHardwareControls(snapshot)
                        self.session.commitConfiguration()
                    } else { self.syncHardwareFocusControl(snapshot) }
                }
                try self.applyToDevice(snapshot)
                self.preparePhotoResources(snapshot)
            } catch { self.report(error) }
        }
    }
    private func applyToDevice(_ requested: CameraSettings) throws {
        let settings = requested.effective
        guard let device else { return }
        if !settings.permitsExposureCompensation {
            appliedExposureLock = false
            DispatchQueue.main.async { self.exposureLocked = false }
        }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        let changedAF = appliedSettings.autofocus != settings.autofocus
        if changedAF { trackingFocusSuspended = false; lastTrackedLensPosition = nil }
        appliedSettings = settings
        if settings.autofocus == .manual {
            lensStrategy = .manual
            if device.isLockingFocusWithCustomLensPositionSupported {
                device.setFocusModeLocked(lensPosition: settings.manualFocus, completionHandler: nil)
            }
        } else if changedAF || lensStrategy == .scene {
            configureSceneFocus(device)
        }
        if settings.requiresExactExposure {
            let seconds = settings.controlsShutter ? settings.shutterSeconds : device.exposureDuration.seconds
            let iso = settings.controlsISO ? Float(settings.iso) : device.iso
            setCustomExposure(device, seconds: seconds, iso: iso)
        } else if !appliedExposureLock && device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        let bias = settings.permitsExposureCompensation ? settings.exposureBias : 0
        device.setExposureTargetBias(min(device.maxExposureTargetBias, max(device.minExposureTargetBias, Float(bias))), completionHandler: nil)
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
        let count = jobs.count + renderingPhotos
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
        if abs(settings.zoom-factor) > 0.001 {
            cancelCapture()
            if isCalibrating { calibration = nil; isCalibrating = false; calibrationStatus = "縮放已變更，校準中止" }
        }
        settings.zoom = factor
        vision.reset()
        persistSettings()
        // Draw from touch immediately; hardware KVO must not animate the dial backwards.
        self.zoom = factor
        zoomCommand &+= 1
        let command = zoomCommand
        sessionQueue.async {
            guard let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = max(device.minAvailableVideoZoomFactor,
                                             min(device.maxAvailableVideoZoomFactor, factor * self.referenceZoom))
                device.unlockForConfiguration()
                let actual = device.videoZoomFactor / self.referenceZoom
                DispatchQueue.main.async { self.reconcileZoom(actual, command: command) }
            } catch {
                let actual = device.videoZoomFactor / self.referenceZoom
                DispatchQueue.main.async { self.reconcileZoom(actual, command: command) }
                self.report(error)
            }
        }
    }
    private func reconcileZoom(_ actual: CGFloat, command: Int) {
        guard command == zoomCommand else { return }
        zoom = actual
        if abs(settings.zoom - actual) > 0.001 { settings.zoom = actual; persistSettings() }
    }
    private func syncNativeZoom(_ value: CGFloat) {
        // No hardware zoom control is registered. Ignore stale intermediate KVO values
        // while commands are draining; the requested value already drives the dial.
        if abs(settings.zoom - value) < 0.001 { zoom = value }
    }
    func tap(at imagePoint: CGPoint) {
        guard isRunning || isUIFixture, settings.effective.autofocus != .manual else { return }
        guard settings.effective.focusArea.contains(imagePoint) else { return }
        singleFocused = false
        if isUIFixture {
            fixtureTracker.select(at: imagePoint, eyes: settings.effective.eyes, mode: settings.effective.autofocus, area: settings.effective.focusArea)
            tracking = fixtureTracker.result
        } else { vision.select(imagePoint) }
    }
    func autofocus() {
        guard settings.effective.autofocus != .manual else { return }
        if isUIFixture {
            fixtureTracker.acquire(settings: settings.effective, at: 0)
            tracking = fixtureTracker.result
        } else { vision.acquire() }
    }
    func moveFocusArea(to point: CGPoint) {
        guard settings.program != .auto, settings.effective.autofocus != .manual else { return }
        update { $0.focusArea.move(to: point) }
    }
    func unlockTracking() {
        if isUIFixture { fixtureTracker.unlock(); _ = fixtureTracker.update(fixtureDetections, at: 1, settings: settings); tracking = fixtureTracker.result }
        else { vision.unlock() }
        singleFocused = false
    }
    /// Called with the device configuration lock held, on sessionQueue only.
    private func configureSceneFocus(_ device: AVCaptureDevice) {
        if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5) }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        lensStrategy = .scene
        trackingFocusSuspended = false
        lastTrackedLensPosition = nil
        lastFocusPoint = CGPoint(x: -1, y: -1)
    }
    private func resumeSceneFocus() {
        if settings.effective.focusArea.mode != .whole {
            focusOnImagePoint(settings.effective.focusArea.center, single: false)
            return
        }
        sessionQueue.async {
            guard self.session.isRunning, self.appliedSettings.autofocus != .manual,
                  let device = self.device else { return }
            // White-box updates must not repeatedly reset the system's AF search.
            guard self.lensStrategy != .scene || device.focusMode != .continuousAutoFocus else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                self.configureSceneFocus(device)
            } catch { self.report(error) }
        }
    }
    private func holdTrackedFocus() {
        sessionQueue.async {
            guard !self.trackingFocusSuspended, self.session.isRunning, let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                let position = self.lensStrategy == .point ? device.lensPosition : self.lastTrackedLensPosition
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
        guard isRunning, settings.effective.autofocus != .manual, let layer = previewLayer else { return }
        // Vision points describe the delivered pixel buffer, not the preview layer's FOV.
        let pixelRect = CGRect(x: min(frameSize.width - 1, max(0, point.x * frameSize.width)),
                               y: min(frameSize.height - 1, max(0, point.y * frameSize.height)), width: 1, height: 1)
        let metadata = videoOutput.metadataOutputRectConverted(fromOutputRect: pixelRect)
        let layerRect = layer.layerRectConverted(fromMetadataOutputRect: metadata)
        let display = CGPoint(x: layerRect.midX, y: layerRect.midY)
        guard display.x.isFinite, display.y.isFinite else { return }
        let devicePoint = layer.captureDevicePointConverted(fromLayerPoint: display)
        sessionQueue.async {
            guard self.session.isRunning, let device = self.device else { return }
            self.lastTrackedLensPosition = device.lensPosition
            if !force && self.lensStrategy == .subject && !self.trackingFocusSuspended && hypot(self.lastFocusPoint.x - devicePoint.x, self.lastFocusPoint.y - devicePoint.y) < 0.015 { return }
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
                self.lensStrategy = single ? .point : .subject
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
        if !settings.effective.permitsExposureCompensation {
            exposureLocked = false
            sessionQueue.async { self.appliedExposureLock = false }
            return
        }
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
        let snapshot = settings.effective
        let cancellation = CaptureCancellation()
        captureCancellation = cancellation
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.countdown = 0; self.captureBusy = false; self.captureTask = nil; self.captureCancellation = nil }
            for second in stride(from: snapshot.drive.delay, through: 1, by: -1) {
                self.countdown = second
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            }
            guard !Task.isCancelled else { return }
            self.countdown = 0
            guard !Task.isCancelled else { return }
            let count = snapshot.drive == .timerContinuous ? snapshot.timerCount : 1
            var cadence = BurstCadence(fps: 1, exposure: snapshot.controlsShutter ? snapshot.shutterSeconds : self.actualShutter,
                                       now: ProcessInfo.processInfo.systemUptime)
            var completed = 0
            while completed < count && !Task.isCancelled && !cancellation.isCancelled && self.isRunning && self.captureEnabled {
                let now = ProcessInfo.processInfo.systemUptime
                if now >= cadence.nextDeadline {
                    let attempt = await self.capture(snapshot, cancellation: cancellation)
                    let accepted = attempt.accepted
                    _ = cadence.admit(at: ProcessInfo.processInfo.systemUptime, ready: accepted)
                    self.captureBusy = !accepted
                    if accepted { completed += 1 }
                }
                if completed < count {
                    do { try await Task.sleep(nanoseconds: 20_000_000) } catch { break }
                }
            }
        }
    }
    private func calibrationKey(_ snapshot: CameraSettings, exposure: Double) -> String {
        BurstCalibrationKey.make(lens: lensIdentifier, os: ProcessInfo.processInfo.operatingSystemVersionString,
                                 settings: snapshot, pixels: requestedPhotoPixels, exposure: exposure,
                                 model: birdStatus.contains("已載入") ? BirdPoseDecoder.androidSHA256 : "bird-unavailable")
    }
    func startBurstCalibration() {
        guard captureTask == nil, pendingPhotos == 0, isRunning, settings.drive.isBurst,
              settings.effective.autofocus != .manual, settings.effective.eyes != .off,
              settings.effective.subjects.accepts(.bird), birdStatus.contains("已載入") else {
            calibrationStatus = "請開啟鳥眼、自動對焦與連拍，並等候相機及存檔就緒"; return
        }
        var snapshot = settings.effective; snapshot.burstRateTrial = .fastest
        let exposure = snapshot.controlsShutter ? snapshot.shutterSeconds : actualShutter
        let profile = BurstProfile(settings: snapshot, responsive: responsiveCapture, photoPixels: requestedPhotoPixels, exposure: exposure)
        calibration = BurstCalibration(key: calibrationKey(snapshot, exposure: exposure), drive: snapshot.drive, maximum: profile.requestFPS)
        calibrationStatus = calibration!.status; isCalibrating = true
    }
    func cancelBurstCalibration() {
        cancelCapture(); calibration = nil; isCalibrating = false
        calibrationStatus = "已結束校準；未通過的速度不會保存"
    }
    func beginBurst() {
        guard settings.drive.isBurst, isRunning, captureEnabled, captureTask == nil else { shutter(); return }
        // Do not discard diagnostics for accepted photos still being stored.
        guard burstDiagnostics?.hasPendingStorage != true else { burstLimitReason = "等待上一段照片存檔"; return }
        let snapshot = settings.effective
        let cancellation = CaptureCancellation()
        captureCancellation = cancellation
        burstFPS = nil; burstIntervals = []; lastBurstExposureTime = nil
        burstMeasurement = cancellation
        let exposure = snapshot.controlsShutter ? snapshot.shutterSeconds : actualShutter
        let key = calibrationKey(snapshot, exposure: exposure)
        measurementKey = key
        var capability = snapshot; capability.burstRateTrial = .fastest
        let profile = BurstProfile(settings: capability, responsive: responsiveCapture,
                                   photoPixels: requestedPhotoPixels, exposure: exposure)
        if let current = calibration, current.key != key {
            calibration = nil; isCalibrating = false; calibrationStatus = "配置已變更，請重新開始校準"
        }
        let saved = calibrationStore.rate(for: key)
        let trial = calibration?.verifiedFPS == nil && calibration?.failed == false ? calibration?.rate : nil
        calibrationMeasurement = trial == nil ? nil : cancellation
        let target = min(trial ?? calibrationStore.requestRate(conservative: snapshot.drive.fps, for: key), profile.requestFPS)
        burstStableTarget = target
        burstRequestFPS = target
        let initialReason = trial != nil ? "校準測試；會實際拍照存檔" : saved == nil ? "未校準：保守上限" : profile.reason
        burstLimitReason = initialReason
        burstDiagnostics = BurstDiagnostics(mode: snapshot.drive.code, format: snapshot.format.rawValue,
                                            requestedPixels: requestedPhotoPixels, exposure: exposure,
                                            requestFPS: target,
                                            device: "\(UIDevice.current.model) · \(ProcessInfo.processInfo.operatingSystemVersionString)",
                                            startedAt: ProcessInfo.processInfo.systemUptime)
        burstReportText = nil
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.captureTask = nil; self.captureCancellation = nil; self.captureBusy = false
                self.burstDiagnostics?.stop(at: ProcessInfo.processInfo.systemUptime)
                self.publishBurstReport()
            }
            var cadence = BurstCadence(fps: target, exposure: exposure, now: ProcessInfo.processInfo.systemUptime)
            while !Task.isCancelled && !cancellation.isCancelled && self.isRunning && self.captureEnabled {
                if ProcessInfo.processInfo.systemUptime >= cadence.nextDeadline {
                    let previousRate = cadence.effectiveFPS
                    let attempt = await self.capture(snapshot, cancellation: cancellation)
                    _ = cadence.admit(at: ProcessInfo.processInfo.systemUptime, ready: attempt.accepted)
                    self.captureBusy = !attempt.accepted
                    if cadence.effectiveFPS < previousRate - 0.000001 {
                        self.calibrationStore.restrict(to: cadence.effectiveFPS, for: key)
                        self.burstDiagnostics?.reduced(to: cadence.effectiveFPS)
                        self.burstStableTarget = cadence.effectiveFPS
                    }
                    if !attempt.accepted {
                        self.burstLimitReason = attempt.reason
                        if let reason = attempt.reason { self.burstDiagnostics?.blocked(reason) }
                    } else { self.burstLimitReason = cadence.hasReducedRate ? "持續受阻降檔；本次長按不升速" : initialReason }
                }
                do { try await Task.sleep(nanoseconds: 5_000_000) } catch { break }
            }
        }
    }
    func cancelCapture(reason: String = "capture-cancelled") {
        resetHardwareShutter(reason: reason)
        captureCancellation?.cancel(); captureTask?.cancel()
    }
    private func publishBurstReport() {
        guard let report = burstDiagnostics, report.stoppedAt != nil else { return }
        burstReportText = report.reportText()
        guard !report.hasPendingStorage, let token = burstMeasurement,
              calibrationMeasurement === token, calibrationConsumed !== token else { return }
        calibrationConsumed = token
        guard var current = calibration, current.key == measurementKey,
              birdStatus.contains("已載入"), current.key == calibrationKey(settings.effective,
                  exposure: settings.effective.controlsShutter ? settings.effective.shutterSeconds : actualShutter) else {
            calibration = nil; isCalibrating = false; calibrationStatus = "量測配置已變更，結果不保存"; return
        }
        current.consume(report); calibration = current
        calibrationStatus = current.status
        if let rate = current.verifiedFPS {
            calibrationStore.save(rate, for: current.key); isCalibrating = false
        } else if current.failed { isCalibrating = false }
    }
    private func makePhotoSettings(_ settings: CameraSettings) throws -> (AVCapturePhotoSettings, UTType) {
        let raw = settings.format == .raw ? photoOutput.availableRawPhotoPixelFormatTypes.first : nil
        guard settings.format != .raw || raw != nil else {
            throw cameraError("目前鏡頭不支援 RAW；請重新選擇影像畫質。")
        }
        let useHEIF = settings.format == .heif && photoOutput.availablePhotoCodecTypes.contains(.hevc)
        let codec: AVVideoCodecType = useHEIF ? .hevc : .jpeg
        let capture: AVCapturePhotoSettings
        if let raw {
            capture = AVCapturePhotoSettings(rawPixelFormatType: raw, processedFormat: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        } else { capture = AVCapturePhotoSettings(format: [AVVideoCodecKey: codec]) }
        capture.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        // Exact exposure requires speed prioritization; don't alter shutter/ISO to meet cadence.
        capture.photoQualityPrioritization = settings.requiresExactExposure ? .speed : .balanced
        return (capture, useHEIF ? .heic : .jpeg)
    }
    private func preparePhotoResources(_ settings: CameraSettings) {
        let dimensions = photoOutput.maxPhotoDimensions
        let key = "\(settings.format.rawValue):\(settings.requiresExactExposure):\(dimensions.width)x\(dimensions.height)"
        guard preparedPhotoKey != key, let (capture, _) = try? makePhotoSettings(settings) else { return }
        preparedPhotoKey = key
        // Preparation is asynchronous; never wait for completion on the session owner.
        photoOutput.setPreparedPhotoSettingsArray([capture], completionHandler: nil)
    }
    private func capture(_ settings: CameraSettings, cancellation: CaptureCancellation) async -> CaptureAdmission {
        await withCheckedContinuation { continuation in
        sessionQueue.async { [self] in
            guard self.session.isRunning, !cancellation.isCancelled else {
                continuation.resume(returning: .cancelled); return
            }
            guard self.photoOutput.captureReadiness == .ready else {
                continuation.resume(returning: .systemNotReady); return
            }
            guard self.jobs.count < 2, self.jobs.count + self.renderingPhotos < 3 else {
                continuation.resume(returning: .bufferFull); return
            }
            let capture: AVCapturePhotoSettings
            let type: UTType
            do { (capture, type) = try self.makePhotoSettings(settings) }
            catch {
                self.report(error); cancellation.cancel()
                continuation.resume(returning: .unsupportedFormat); return
            }
            let job = PhotoJob(settings: settings, type: type, onCaptured: { [weak self] in
                let timestamp = ProcessInfo.processInfo.systemUptime
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.captureFeedback &+= 1
                    if settings.drive.isBurst && self.burstMeasurement === cancellation {
                        self.burstDiagnostics?.captured(id: capture.uniqueID, at: timestamp)
                        if let previous = self.lastBurstExposureTime {
                            self.burstIntervals.append(timestamp - previous)
                            if self.burstIntervals.count > 120 { self.burstIntervals.removeFirst() }
                            self.burstFPS = Double(self.burstIntervals.count) / self.burstIntervals.reduce(0, +)
                        }
                        self.lastBurstExposureTime = timestamp
                    }
                }
            }) { [weak self] result in
                guard let self else { return }
                let processedAt = ProcessInfo.processInfo.systemUptime
                DispatchQueue.main.async {
                    if self.burstMeasurement === cancellation { self.burstDiagnostics?.processed(id: capture.uniqueID, at: processedAt) }
                }
                self.sessionQueue.async {
                    self.jobs.removeValue(forKey: capture.uniqueID)
                    self.renderingPhotos += 1
                    DispatchQueue.main.async { self.readinessCoordinator?.stopTrackingCaptureRequest(using: capture.uniqueID) }
                    self.photos.store(result, id: capture.uniqueID, rendering: {
                        let time = ProcessInfo.processInfo.systemUptime
                        DispatchQueue.main.async {
                            if self.burstMeasurement === cancellation { self.burstDiagnostics?.rendering(id: capture.uniqueID, at: time) }
                        }
                    }) { saved in
                        let time = ProcessInfo.processInfo.systemUptime
                        self.sessionQueue.async {
                            self.renderingPhotos -= 1
                            let count = self.jobs.count + self.renderingPhotos
                            DispatchQueue.main.async { self.pendingPhotos = count }
                        }
                        DispatchQueue.main.async {
                            var success = false
                            var dimensions: String?
                            switch saved {
                            case .success(let photo):
                                success = photo.complete; dimensions = photo.dimensions
                                self.lastPhotoURL = photo.url; self.lastPhotoDimensions = photo.dimensions
                                self.status = "照片已存於 App"
                                if let warning = photo.warning { self.error = warning }
                            case .failure(let error): self.error = error.localizedDescription
                            }
                            if self.burstMeasurement === cancellation {
                                self.burstDiagnostics?.stored(id: capture.uniqueID, at: time, succeeded: success, dimensions: dimensions)
                                self.publishBurstReport()
                            }
                        }
                    }
                }
            }
            self.jobs[capture.uniqueID] = job
            let count = self.jobs.count + self.renderingPhotos
            DispatchQueue.main.async { self.pendingPhotos = count }
            DispatchQueue.main.async {
                self.readinessCoordinator?.startTrackingCaptureRequest(using: capture)
                self.sessionQueue.async {
                    guard !cancellation.isCancelled else {
                        self.jobs.removeValue(forKey: capture.uniqueID)
                        DispatchQueue.main.async { self.readinessCoordinator?.stopTrackingCaptureRequest(using: capture.uniqueID) }
                        let count = self.jobs.count + self.renderingPhotos
                        DispatchQueue.main.async { self.pendingPhotos = count }
                        continuation.resume(returning: .cancelled); return
                    }
                    let requestedAt = ProcessInfo.processInfo.systemUptime
                    DispatchQueue.main.async {
                        if self.burstMeasurement === cancellation { self.burstDiagnostics?.requested(id: capture.uniqueID, at: requestedAt) }
                    }
                    self.photoOutput.capturePhoto(with: capture, delegate: job)
                    continuation.resume(returning: .accepted)
                }
            }
        }
        }
    }
    private func persistSettings() {
        _ = store.save(settings)
        settingsRecoveryMessage = store.diagnostics
    }
    func recoverSettingsStorage() {
        store.recoverInvalid(); persistSettings()
        status = "已備份無法讀取的設定並保存目前設定；損壞的 C1–C3 請重新儲存"
    }
    func savePreset(_ name: String) {
        status = store.save(settings, key: name) ? "已儲存 \(name)" : "\(name) 未覆寫，請先復原設定資料"
        settingsRecoveryMessage = store.diagnostics
    }
    func recallPreset(_ name: String) {
        let result = store.inspect(name)
        guard let saved = result.settings else { status = result.diagnostic ?? "\(name) 尚未儲存；長按可儲存目前設定"; return }
        update { $0 = saved }
        setZoom(saved.zoom)
        status = "已載入 \(name)"
    }
    private func cameraError(_ message: String) -> NSError {
        NSError(domain: "Camera", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private func report(_ error: Error) { DispatchQueue.main.async { self.error = error.localizedDescription } }
    /// Called only on sessionQueue, inside a session configuration transaction.
    private func configureHardwareControls(_ requested: CameraSettings) {
        if !requested.experimentalHardwareShutter {
            if let control = focusModeControl { session.removeControl(control) }
            focusModeControl = nil
            publishHardwareControls(false, status: "實驗性兩段硬體快門未啟用")
            return
        }
        guard session.supportsControls else {
            publishHardwareControls(false, status: "此裝置不支援控制浮層；取景頁使用一般硬體快門")
            return
        }
        session.setControlsDelegate(self, queue: .main)
        if focusModeControl == nil {
            let modes = AutofocusMode.allCases
            let picker = AVCaptureIndexPicker("對焦模式", symbolName: "scope", localizedIndexTitles: modes.map(\.rawValue))
            picker.setActionQueue(sessionQueue) { [weak self] index in
                let time = CACurrentMediaTime()
                DispatchQueue.main.async {
                    guard let self, time >= self.hardwareResetTime, self.settings.experimentalHardwareShutter,
                          self.isRunning, self.captureEnabled, self.settings.program != .auto,
                          modes.indices.contains(index), self.settings.autofocus != modes[index] else { return }
                    self.update { $0.autofocus = modes[index] }
                }
            }
            guard session.canAddControl(picker) else {
                publishHardwareControls(false, status: "無法註冊對焦控制；取景頁使用一般硬體快門")
                return
            }
            session.addControl(picker)
            focusModeControl = picker
        }
        syncHardwareFocusControl(requested)
        publishHardwareControls(true, status: "實驗模式：輕按返回拍攝／對焦，浮層啟用期間可連續全按；音量減仍可能拍攝")
    }
    /// Value updates stay on the control's action queue and do not reconfigure the capture graph.
    private func syncHardwareFocusControl(_ requested: CameraSettings) {
        focusModeControl?.selectedIndex = AutofocusMode.allCases.firstIndex(of: requested.effective.autofocus) ?? 0
        focusModeControl?.isEnabled = requested.program != .auto
    }
    private func publishHardwareControls(_ supported: Bool, status: String) {
        DispatchQueue.main.async {
            self.hardwareControlsSupported = supported
            self.hardwareControlStatus = status
            if !supported { self.resetHardwareShutter(reason: "controls-unavailable") }
        }
    }
    var hardwareShutterReport: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(hardwareRecords) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
    func hardwareInput(_ input: HardwareShutter.Input, at time: Double = CACurrentMediaTime()) {
        let experimental = twoStageAvailable
        let available = sceneIsActive && isRunning && (experimental || captureEnabled)
        guard time >= hardwareResetTime else {
            recordHardware(input, time: time, available: available,
                           decision: HardwareShutter.Decision(actions: [], reason: "stale-input-before-reset"))
            return
        }
        let decision = hardwareShutter.receive(input, at: time, experimental: experimental,
                                              available: available, burst: settings.drive.isBurst,
                                              captureAllowed: captureEnabled && !hardwareReturningToCapture,
                                              returningToCapture: hardwareReturningToCapture)
        if input == .controlsActive, experimental, available, !hardwareReturningToCapture {
            hardwareReturningToCapture = true
            capturePageReturnRequest &+= 1
        }
        recordHardware(input, time: time, available: available, decision: decision)
        for action in decision.actions {
            switch action {
            case .focus:
                if hardwareReturningToCapture { hardwareFocusAfterReturn = true }
                else { prepareHardwareFocus() }
            case .photo:
                if hardwareReturnFixture { captureFeedback &+= 1 }
                else { shutter() }
            case .beginBurst: beginBurst()
            case .stopBurst: captureCancellation?.cancel(); captureTask?.cancel()
            }
        }
        if input == .primaryCancelled || input == .secondaryCancelled {
            captureCancellation?.cancel(); captureTask?.cancel()
        }
    }
    private func resetHardwareShutter(preservingOverlay: Bool = false, reason: String = "capture-cancelled") {
        let time = CACurrentMediaTime()
        hardwareResetTime = time
        let resumeOverlay = preservingOverlay && controlsActive && settings.experimentalHardwareShutter
            && isRunning && hardwareControlsSupported && captureEnabled && !hardwareReturningToCapture
        let decision = hardwareShutter.receive(.reset, at: time, experimental: settings.experimentalHardwareShutter,
                                              available: false, burst: false)
        if resumeOverlay {
            _ = hardwareShutter.receive(.controlsActive, at: time, experimental: true, available: true, burst: false)
        }
        recordHardware(.reset, time: time, available: isRunning && hardwareControlsSupported,
                       decision: HardwareShutter.Decision(actions: decision.actions,
                           reason: reason + (resumeOverlay ? "-overlay-preserved" : "")))
        // Cancel only a hardware burst here; cancelCapture also cancels timers/UI captures.
        if decision.actions.contains(.stopBurst) { captureCancellation?.cancel(); captureTask?.cancel() }
        hardwareFocusAfterReturn = false
        hardwareReturningToCapture = false
    }
    private func recordHardware(_ input: HardwareShutter.Input, time: Double, available: Bool,
                                decision: HardwareShutter.Decision, eventName: String? = nil) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        hardwareRecords.append(HardwareShutterRecord(appVersion: "\(version) (\(build))", time: time, event: eventName ?? input.rawValue, source: "unknown",
            experimental: settings.experimentalHardwareShutter, available: available,
            receiverAttached: hardwareReceiver.attached, receiverEnabled: hardwareReceiver.enabled,
            receiverHost: hardwareReceiver.host, receivedEvents: hardwareReceiver.receivedEvents, sceneActive: sceneIsActive, sessionRunning: isRunning,
            page: hardwareReturningToCapture ? "returning" : captureEnabled ? "capture" : "covered",
            captureAllowed: captureEnabled && !hardwareReturningToCapture,
            captureTaskBusy: captureTask != nil, returningToCapture: hardwareReturningToCapture,
            pendingCapture: hardwareShutter.pendingCapture?.rawValue,
            controlsActive: hardwareShutter.controlsActive, primaryDown: hardwareShutter.primaryDown,
            deadline: hardwareShutter.deadline, actions: decision.actions.map(\.rawValue), reason: decision.reason))
        if hardwareRecords.count > 200 { hardwareRecords.removeFirst(hardwareRecords.count - 200) }
    }
    private func prepareHardwareFocus() {
        guard settings.effective.autofocus != .manual else { return }
        singleFocused = false
        if tracking.missing { holdTrackedFocus(); return }
        if let selected = tracking.selected, tracking.locked {
            focusOnImagePoint(selected.focusPoint(settings.effective.eyes), single: settings.effective.autofocus == .single, force: true)
        } else if let point = tracking.touchPoint {
            focusOnImagePoint(point, single: true, force: true)
        } else { autofocus() }
    }
    /// Complete only after the UI has dismissed its covers. A queued burst still requires a held press.
    func capturePageDidReturn(request: UInt64) {
        guard request == capturePageReturnRequest, hardwareReturningToCapture, isRunning else { return }
        hardwareReturningToCapture = false
        captureEnabled = true
        if hardwareFocusAfterReturn { hardwareFocusAfterReturn = false; prepareHardwareFocus() }
        hardwareInput(.capturePageReady)
    }
    func dismissPresentedCameraUI(completion: @escaping () -> Void) {
        guard let host = presentationWindow?.rootViewController else {
            hardwareControlStatus = "無法確認頁面返回，請重新開啟相機；未放行快門"
            resetHardwareShutter(reason: "return-window-unavailable"); return
        }
        guard host.presentedViewController != nil else { completion(); return }
        // Dismiss the entire presented stack, including a nested editor/share/diagnostics screen.
        host.dismiss(animated: false, completion: completion)
    }
    var hardwareReturnFixture: Bool {
        isUIFixture && ProcessInfo.processInfo.environment["R6_UI_HARDWARE_RETURN_TEST"] == "1"
    }
    func simulateHardwareReturn() {
        guard hardwareReturnFixture else { return }
        hardwareInjectionCount &+= 1
        guard hardwareReceiver.enabled else {
            recordHardware(.reset, time: CACurrentMediaTime(), available: false,
                decision: HardwareShutter.Decision(actions: [], reason: "fixture-receiver-disabled"), eventName: "fixtureInjectionRejected")
            return
        }
        hardwareControlsSupported = true
        isRunning = true
        controlsActive = true
        hardwareInput(.controlsActive)
        // Exercise an immediate full click during the page transition, without taking a real photo.
        hardwareInput(.primaryBegan)
        hardwareInput(.primaryEnded)
    }
    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {
        // Delegate is explicitly delivered on main; these are overlay states, not pressure events.
        controlsActive = true
        hardwareInput(.controlsActive)
    }
    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {
        controlsActive = false
        hardwareInput(.controlsInactive)
    }
    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {
        if controlsActive { hardwareInput(.controlsActive) }
    }
    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {}
    func readinessCoordinator(_ coordinator: AVCapturePhotoOutputReadinessCoordinator,
                              captureReadinessDidChange captureReadiness: AVCapturePhotoOutput.CaptureReadiness) {
        captureReady = captureReadiness == .ready
    }
    private var lastBurstExposureTime: Double?
}

private final class CaptureCancellation {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
