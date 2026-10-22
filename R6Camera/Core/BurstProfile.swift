import Foundation

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
        let canOverlapFaster = responsive && photoPixels > 0 && photoPixels <= 24_000_000
            && settings.format != .raw && !settings.requiresExactExposure
        let ceiling = canOverlapFaster
            ? (settings.drive == .burstHighPlus ? 8.0 : settings.drive == .burst ? 4.0 : 1.0)
            : settings.drive.fps
        requestFPS = min(ceiling, 1 / max(0.001, exposure + 0.03))
        if requestFPS < ceiling { reason = "曝光時間限制" }
        else if settings.format == .raw { reason = "RAW 保留畫質" }
        else if photoPixels > 24_000_000 { reason = "高解析度保留畫質" }
        else if settings.requiresExactExposure { reason = "精確手動曝光" }
        else if !responsive { reason = "裝置拍攝能力限制" }
        else { reason = nil }
    }
}
