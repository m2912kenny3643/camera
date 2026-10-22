import Foundation

enum BurstRateTrial: Int, Codable, CaseIterable {
    case standard = 8, faster = 10, fastest = 12
    var label: String { self == .standard ? "8 張/s" : "測試 \(rawValue) 張/s" }
    var highFPS: Double { self == .standard ? 4 : 6 }
}

enum CaptureAdmission {
    case accepted, systemNotReady, bufferFull, cancelled, unsupportedFormat
    var accepted: Bool { if case .accepted = self { return true }; return false }
    var reason: String? {
        switch self {
        case .systemNotReady: return "等待系統拍攝就緒"
        case .bufferFull: return "處理緩衝已滿"
        case .unsupportedFormat: return "目前格式不可用"
        default: return nil
        }
    }
}

/// Request ceilings, never a claim of measured hardware throughput.
struct BurstProfile {
    let requestFPS: Double
    let reason: String?

    init(settings: CameraSettings, responsive: Bool, photoPixels: Int64, exposure: Double) {
        // 24MP formats may contain slightly more than 24 million pixels. Higher
        // resolutions can be explicitly tried without silently reducing dimensions.
        let highResolution = photoPixels > 25_000_000
        let explicitTrial = settings.burstRateTrial != .standard
        let canOverlapFaster = responsive && photoPixels > 0 && (!highResolution || explicitTrial)
            && settings.format != .raw && !settings.requiresExactExposure
        let ceiling = canOverlapFaster
            ? (settings.drive == .burstHighPlus ? Double(settings.burstRateTrial.rawValue) : settings.drive == .burst ? settings.burstRateTrial.highFPS : 1.0)
            : settings.drive.fps
        requestFPS = min(ceiling, 1 / max(0.001, exposure + 0.03))
        if requestFPS < ceiling { reason = "曝光時間限制" }
        else if settings.format == .raw { reason = "RAW 保留畫質" }
        else if settings.requiresExactExposure { reason = "精確手動曝光" }
        else if !responsive { reason = "裝置拍攝能力限制" }
        else if photoPixels <= 0 { reason = "等待拍攝解析度" }
        else if highResolution { reason = explicitTrial ? "高解析度試速；待真機驗證" : "高解析度保留畫質" }
        else if settings.burstRateTrial != .standard && settings.drive != .burstLow { reason = "測試請求上限；待真機驗證" }
        else { reason = nil }
    }
}
