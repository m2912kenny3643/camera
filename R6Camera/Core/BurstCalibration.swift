import Foundation

enum BurstCalibrationKey {
    static func make(lens: String, os: String, settings: CameraSettings, pixels: Int64, exposure: Double, model: String) -> String {
        // Quality/zoom/exposure/model changes must never reuse a different configuration's result.
        var normalized = settings.effective
        normalized.burstRateTrial = .standard
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let payload = (try? encoder.encode(normalized)).flatMap { String(data: $0, encoding: .utf8) } ?? "invalid"
        let bucket = Int((log2(max(0.000001, exposure))*2).rounded())
        return "v1|\(lens)|\(os)|\(pixels)|\(bucket)|\(model)|\(payload)"
    }
}

struct BurstCalibration {
    let key: String
    let rates: [Double]
    private(set) var index = 0
    private(set) var consecutivePasses = 0
    private(set) var verifiedFPS: Double?
    private(set) var failed = false
    var rate: Double { rates[index] }
    var status: String {
        if let verifiedFPS { return String(format: "已校準 %.1f 張/s，三段通過", verifiedFPS) }
        if failed { return "最低檔仍未穩定，未建立校準結果" }
        return String(format: "校準 %.1f 張/s：%d/3；按住相機鍵至少10秒", rate, consecutivePasses)
    }
    init(key: String, drive: DriveMode, maximum: Double) {
        self.key = key
        let ladder: [Double] = drive == .burstHighPlus ? [12,10,8,6,4,2,1] : drive == .burst ? [6,4,2,1] : [1]
        let allowed = ladder.filter { $0 <= maximum + 0.000001 }
        rates = allowed.isEmpty ? [maximum] : allowed
    }
    mutating func consume(_ report: BurstDiagnostics) {
        guard !failed, verifiedFPS == nil, !report.hasPendingStorage,
              let stop = report.stoppedAt, stop-report.startedAt >= 10,
              abs(report.requestFPS-rate) < 0.000001 else { return }
        if report.tenSecondCadencePassed {
            consecutivePasses += 1
            if consecutivePasses == 3 { verifiedFPS = rate }
        } else {
            consecutivePasses = 0
            if index+1 < rates.count { index += 1 } else { failed = true }
        }
    }
}

struct BurstCalibrationStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func rate(for key: String) -> Double? {
        guard let value = defaults.dictionary(forKey: "burst.calibrated.v1")?[key] as? Double,
              value.isFinite, value > 0, value <= 12 else { return nil }
        return value
    }
    func requestRate(conservative: Double, for key: String) -> Double {
        let limit = (defaults.dictionary(forKey: "burst.pressure.v1")?[key] as? Double).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        return min(rate(for: key) ?? conservative, limit ?? .infinity)
    }
    func restrict(to limit: Double, for key: String) {
        guard limit.isFinite, limit > 0 else { return }
        var verified = defaults.dictionary(forKey: "burst.calibrated.v1") ?? [:]
        if let prior = rate(for: key), prior > limit { verified.removeValue(forKey: key) }
        defaults.set(verified, forKey: "burst.calibrated.v1")
        var limits = defaults.dictionary(forKey: "burst.pressure.v1") ?? [:]
        limits[key] = min(limits[key] as? Double ?? .infinity, limit)
        defaults.set(limits, forKey: "burst.pressure.v1")
    }
    func save(_ rate: Double, for key: String) {
        guard rate.isFinite, rate > 0, rate <= 12 else { return }
        var values = defaults.dictionary(forKey: "burst.calibrated.v1") ?? [:]
        // Bounded cache; clearing old calibration never silently qualifies a new configuration.
        if values.count >= 50, values[key] == nil { values.removeAll() }
        var limits = defaults.dictionary(forKey: "burst.pressure.v1") ?? [:]
        limits[key] = rate; defaults.set(limits, forKey: "burst.pressure.v1")
        values[key] = rate
        defaults.set(values, forKey: "burst.calibrated.v1")
    }
}
