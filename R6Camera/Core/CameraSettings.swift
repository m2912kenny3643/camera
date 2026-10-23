import Foundation

enum ExposureProgram: String, CaseIterable, Codable, Identifiable {
    case auto = "A+", program = "P", shutterPriority = "Tv", manual = "M", flexible = "Fv"
    var id: String { rawValue }
}

enum SubjectMode: String, CaseIterable, Codable, Identifiable {
    case automatic = "自動", people = "人物", birds = "鳥類", animals = "動物", vehicles = "車輛", none = "無"
    var id: String { rawValue }
    func accepts(_ kind: SubjectKind) -> Bool {
        switch self {
        case .automatic: return true
        case .people: return kind == .person
        case .birds: return kind == .bird
        case .animals: return kind.isAnimal
        case .vehicles: return kind.isVehicle
        case .none: return false
        }
    }
}

enum EyePriority: String, CaseIterable, Codable, Identifiable {
    case automatic = "自動", left = "左眼優先", right = "右眼優先", off = "關閉"
    var id: String { rawValue }
}
enum AutofocusMode: String, CaseIterable, Codable, Identifiable {
    case servo = "SERVO AF", single = "ONE SHOT", manual = "MF"
    var id: String { rawValue }
}
enum PhotoFormat: String, CaseIterable, Codable, Identifiable {
    case heif = "HEIF", jpeg = "JPEG", raw = "RAW＋JPEG"
    var id: String { rawValue }
}
enum DriveMode: String, CaseIterable, Codable, Identifiable {
    // Keep the legacy raw value for saved 0.3 presets.
    case single = "單張", burstHighPlus = "H+", burst = "連拍", burstLow = "L"
    case timer10 = "自拍 10 秒", timer2 = "自拍 2 秒", timerContinuous = "自拍連拍"
    var id: String { rawValue }
    var delay: Int { self == .timer2 ? 2 : (self == .timer10 || self == .timerContinuous) ? 10 : 0 }
    var isBurst: Bool { [.burstHighPlus, .burst, .burstLow].contains(self) }
    var fps: Double { self == .burstHighPlus ? 4 : self == .burst ? 2 : 1 }
    var label: String {
        switch self {
        case .burstHighPlus: return "高速連拍 H+"
        case .burst: return "高速連拍 H"
        case .burstLow: return "低速連拍 L"
        default: return rawValue
        }
    }
    var code: String {
        switch self {
        case .single: return ""
        case .burstHighPlus: return "H+"
        case .burst: return "H"
        case .burstLow: return "L"
        case .timer10: return "10"
        case .timer2: return "2"
        case .timerContinuous: return "10+"
        }
    }
}
enum PictureStyle: String, CaseIterable, Codable, Identifiable {
    case standard = "標準", portrait = "人像", landscape = "風景", neutral = "中性", faithful = "忠實", mono = "單色"
    var id: String { rawValue }
}
enum WhiteBalance: String, CaseIterable, Codable, Identifiable {
    case automatic = "AWB", daylight = "日光", shade = "陰影", tungsten = "鎢絲燈", custom = "色溫 K"
    var id: String { rawValue }
}

struct CameraSettings: Codable, Equatable {
    static let shutterSpeeds: [Double] = [8000.0, 4000, 2000, 1000, 500, 250, 125, 60, 30, 15, 8, 4, 2, 1].map { 1.0 / $0 }
    static let isoValues: [Double] = [50, 100, 200, 400, 800, 1600, 3200]
    var program: ExposureProgram = .program
    var autofocus: AutofocusMode = .servo
    var subjects: SubjectMode = .automatic
    var eyes: EyePriority = .automatic
    var format: PhotoFormat = .heif
    var drive: DriveMode = .single
    var style: PictureStyle = .standard
    var whiteBalance: WhiteBalance = .automatic
    var kelvin: Double = 5200
    var shutterSeconds: Double = 1.0 / 125
    var iso: Double = 200
    var autoShutter = true
    var autoISO = true
    var exposureBias: Double = 0
    var manualFocus: Float = 0.5
    var zoom: CGFloat = 1
    var lockLens = false
    var grid = true
    var histogram = true
    var peaking = false
    var contrast: Double = 0
    var saturation: Double = 0
    var sharpness: Double = 0
    var hue: Double = 0
    /// Grace period before a locked target is declared lost. Never selects a different target.
    var trackingStickiness: Double = 0.8
    /// Unlocked auto-selection needs this many seconds of a stable challenger.
    var switchSensitivity: Double = 0.5
    // Optional storage preserves decoding of older current/C1-C3 payloads.
    private var storedManualISOAutomatic: Bool?
    private var storedTimerCount: Int?
    private var storedLevelSize: LevelSize?
    private var storedBurstRateTrial: BurstRateTrial?
    private var storedExperimentalHardwareShutter: Bool?
    /// Missing in older current/C1-C3 payloads: retain the shared hardware shutter.
    var experimentalHardwareShutter: Bool {
        get { storedExperimentalHardwareShutter ?? false }
        set { storedExperimentalHardwareShutter = newValue }
    }
    var burstRateTrial: BurstRateTrial {
        get { storedBurstRateTrial ?? .standard }
        set { storedBurstRateTrial = newValue }
    }
    var manualISOAutomatic: Bool {
        get { storedManualISOAutomatic ?? false }
        set { storedManualISOAutomatic = newValue }
    }
    var timerCount: Int {
        get { min(10, max(2, storedTimerCount ?? 3)) }
        set { storedTimerCount = min(10, max(2, newValue)) }
    }
    var levelSize: LevelSize {
        get { storedLevelSize ?? .large }
        set { storedLevelSize = newValue }
    }
    /// A+ overrides device policy without erasing user settings for other programs.
    var effective: CameraSettings {
        guard program == .auto else { return self }
        var value = self
        value.whiteBalance = .automatic; value.autofocus = .servo
        value.subjects = .automatic; value.eyes = .automatic
        value.style = .standard; value.exposureBias = 0
        value.contrast = 0; value.saturation = 0; value.sharpness = 0; value.hue = 0
        return value
    }

    var controlsShutter: Bool {
        program == .manual || program == .shutterPriority || (program == .flexible && !autoShutter)
    }
    var controlsISO: Bool { (program == .manual && !manualISOAutomatic) || (program == .flexible && !autoISO) }
    var permitsExposureCompensation: Bool { program != .auto && !(program == .manual && controlsISO) }
    var requiresExactExposure: Bool { controlsShutter || controlsISO }
    mutating func useAutomaticShutter() {
        let keepISOAutomatic = !controlsISO
        program = .flexible; autoShutter = true; autoISO = keepISOAutomatic
    }
    mutating func useAutomaticISO() {
        if program == .manual { manualISOAutomatic = true; return }
        let keepShutterAutomatic = !controlsShutter
        program = .flexible; autoISO = true; autoShutter = keepShutterAutomatic
    }
    mutating func selectISO(_ value: Double) {
        let keepShutterAutomatic = !controlsShutter
        iso = value
        if program == .manual { manualISOAutomatic = false }
        else { program = .flexible; autoISO = false; autoShutter = keepShutterAutomatic }
    }
    var shutterLabel: String {
        Self.shutterLabel(shutterSeconds)
    }
    static func shutterLabel(_ seconds: Double) -> String {
        seconds >= 1 ? String(format: "%.1f\"", seconds) : "1/\(Int((1 / max(seconds, 0.000001)).rounded()))"
    }
}

struct SettingsStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load(_ key: String = "current") -> CameraSettings? {
        guard let data = defaults.data(forKey: "camera.\(key)") else { return nil }
        return try? JSONDecoder().decode(CameraSettings.self, from: data)
    }
    func save(_ settings: CameraSettings, key: String = "current") {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: "camera.\(key)")
    }
}
