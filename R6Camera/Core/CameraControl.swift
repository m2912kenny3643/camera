import Foundation

enum CameraControl: String, CaseIterable, Identifiable {
    case mode = "拍攝模式", shutter = "快門速度", iso = "ISO 感光度", exposure = "曝光補償"
    case autofocus = "自動對焦操作", subject = "要偵測的主體", eye = "眼睛偵測", drive = "驅動模式"
    case whiteBalance = "白平衡", style = "相片風格", format = "影像畫質", lens = "鏡頭切換"
    case kelvin = "色溫", manualFocus = "手動對焦", contrast = "對比", saturation = "飽和度"
    case sharpness = "銳利度", hue = "色調", stickiness = "遮擋寬限", sensitivity = "候選切換靈敏度"
    case area = "自動對焦區域", meter = "測光模式"
    case level = "水平儀顯示大小"
    var id: String { rawValue }
    var isAF: Bool { [.area, .autofocus, .subject, .eye, .manualFocus, .stickiness, .sensitivity].contains(self) }
    func value(_ requested: CameraSettings) -> String {
        let s = requested.effective
        switch self {
        case .mode: return s.program.rawValue
        case .shutter: return s.controlsShutter ? s.shutterLabel : "AUTO"
        case .iso: return s.controlsISO ? "\(Int(s.iso))" : "AUTO"
        case .exposure: return String(format: "%+.1f", s.exposureBias)
        case .autofocus: return s.autofocus.rawValue
        case .subject: return s.subjects.rawValue
        case .eye: return s.eyes.rawValue
        case .drive: return s.drive.label
        case .whiteBalance: return s.whiteBalance.rawValue
        case .style: return s.style.rawValue
        case .format: return s.format.rawValue
        case .lens: return s.lockLens ? "鎖定" : "自動"
        case .kelvin: return "\(Int(s.kelvin)) K"
        case .manualFocus: return String(format: "%.2f", s.manualFocus)
        case .contrast: return String(format: "%+.1f", s.contrast)
        case .saturation: return String(format: "%+.1f", s.saturation)
        case .sharpness: return String(format: "%.1f", s.sharpness)
        case .hue: return String(format: "%+.1f", s.hue)
        case .stickiness: return String(format: "%.1f 秒", s.trackingStickiness)
        case .sensitivity: return String(format: "%.1f", s.switchSensitivity)
        case .area: return s.focusArea.mode.rawValue
        case .meter: return "系統測光"
        case .level: return s.levelSize.rawValue
        }
    }
    var isLivePalette: Bool { [.mode, .area, .drive, .whiteBalance, .shutter, .iso, .exposure].contains(self) }
    func isEditable(_ settings: CameraSettings) -> Bool {
        if settings.program == .auto { return [.mode, .drive, .format, .lens, .level].contains(self) }
        return self != .exposure || settings.permitsExposureCompensation
    }
    /// Commit only edited fields; do not overwrite zoom or concurrent changes.
    func apply(_ draft: CameraSettings, to target: inout CameraSettings) {
        switch self {
        case .mode: target.program = draft.program
        case .shutter, .iso:
            target.program = draft.program; target.autoShutter = draft.autoShutter; target.autoISO = draft.autoISO
            target.manualISOAutomatic = draft.manualISOAutomatic
            if self == .shutter { target.shutterSeconds = draft.shutterSeconds } else { target.iso = draft.iso }
        case .exposure: target.exposureBias = draft.exposureBias
        case .autofocus: target.autofocus = draft.autofocus
        case .subject: target.subjects = draft.subjects
        case .eye: target.eyes = draft.eyes
        case .drive: target.drive = draft.drive; target.timerCount = draft.timerCount; target.burstRateTrial = draft.burstRateTrial
        case .whiteBalance, .kelvin: target.whiteBalance = draft.whiteBalance; target.kelvin = draft.kelvin
        case .style: target.style = draft.style
        case .format: target.format = draft.format
        case .lens: target.lockLens = draft.lockLens
        case .manualFocus: target.autofocus = draft.autofocus; target.manualFocus = draft.manualFocus
        case .contrast: target.contrast = draft.contrast
        case .saturation: target.saturation = draft.saturation
        case .sharpness: target.sharpness = draft.sharpness
        case .hue: target.hue = draft.hue
        case .stickiness: target.trackingStickiness = draft.trackingStickiness
        case .sensitivity: target.switchSensitivity = draft.switchSensitivity
        case .level: target.levelSize = draft.levelSize
        case .area: target.focusArea = draft.focusArea
        case .meter: break
        }
    }
}

