import Foundation

/// Bounded, monotonic measurements from real photo delegate callbacks, not scheduled requests.
struct BurstDiagnostics: Codable {
    struct Sample: Codable {
        let id: Int64
        let requestedAt: Double
        var capturedAt: Double?
        var processedAt: Double?
        var renderStartedAt: Double?
        var storedAt: Double?
        var succeeded: Bool?
        var dimensions: String?
    }
    let mode: String
    let format: String
    let requestedPixels: Int64
    let exposure: Double
    let requestFPS: Double
    let device: String
    let startedAt: Double
    private(set) var stoppedAt: Double?
    private(set) var blockedReasons: [String: Int] = [:]
    private(set) var samples: [Sample] = []
    private(set) var totalRequests = 0
    private(set) var truncated = false
    private(set) var reducedRates: [Double] = []
    mutating func reduced(to rate: Double) {
        if reducedRates.last != rate { reducedRates.append(rate) }
    }
    var hasPendingStorage: Bool { samples.contains { $0.storedAt == nil } }

    mutating func requested(id: Int64, at time: Double) {
        totalRequests += 1
        samples.append(Sample(id: id, requestedAt: time))
        if samples.count > 256 { samples.removeFirst(); truncated = true }
    }
    mutating func blocked(_ reason: String) { blockedReasons[reason, default: 0] += 1 }
    mutating func captured(id: Int64, at time: Double) {
        guard let i = samples.firstIndex(where: { $0.id == id }) else { return }
        samples[i].capturedAt = time
    }
    mutating func processed(id: Int64, at time: Double) {
        guard let i = samples.firstIndex(where: { $0.id == id }) else { return }
        samples[i].processedAt = time
    }
    mutating func rendering(id: Int64, at time: Double) {
        guard let i = samples.firstIndex(where: { $0.id == id }) else { return }
        samples[i].renderStartedAt = time
    }
    mutating func stored(id: Int64, at time: Double, succeeded: Bool, dimensions: String?) {
        guard let i = samples.firstIndex(where: { $0.id == id }) else { return }
        samples[i].storedAt = time; samples[i].succeeded = succeeded; samples[i].dimensions = dimensions
    }
    mutating func stop(at time: Double) { stoppedAt = time }
    var captureIntervals: [Double] {
        let times = samples.compactMap(\.capturedAt).sorted()
        return zip(times.dropFirst(), times).map { $0 - $1 }
    }
    var measuredFPS: Double? {
        let values = captureIntervals
        guard !values.isEmpty, values.reduce(0, +) > 0 else { return nil }
        return Double(values.count) / values.reduce(0, +)
    }
    var p95RelativeDeviation: Double? {
        let target = 1 / requestFPS
        let values = captureIntervals.map { abs($0 - target) / target }.sorted()
        guard !values.isEmpty else { return nil }
        return values[max(0, Int(ceil(Double(values.count) * 0.95)) - 1)]
    }
    /// This is one measured hold, never automatic device/format qualification.
    var tenSecondCadencePassed: Bool {
        guard let stoppedAt, stoppedAt - startedAt >= 10,
              !truncated, reducedRates.isEmpty, samples.count >= Int(ceil(requestFPS * (stoppedAt - startedAt) * 0.9)),
              samples.allSatisfy({ $0.capturedAt != nil && $0.succeeded == true }),
              let first = samples.compactMap(\.capturedAt).min(),
              let last = samples.compactMap(\.capturedAt).max(),
              first - startedAt <= max(0.5, 1.2 / requestFPS),
              stoppedAt - last <= max(0.5, 1.2 / requestFPS),
              (captureIntervals.max() ?? .infinity) <= 2 / requestFPS,
              let deviation = p95RelativeDeviation else { return false }
        return deviation <= 0.2
    }
    func reportText() -> String? {
        struct Report: Encodable {
            let schema = 1
            let measurement: BurstDiagnostics
            let measuredFPS: Double?
            let p95RelativeDeviation: Double?
            let tenSecondCadencePassed: Bool
            let note = "快門時間為 didCapturePhoto 回呼；儲存時間為 App 原檔與風格處理完成，不含相簿匯出。單次量測不代表裝置或格式已全面驗收。"
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(Report(measurement: self, measuredFPS: measuredFPS,
                                                  p95RelativeDeviation: p95RelativeDeviation,
                                                  tenSecondCadencePassed: tenSecondCadencePassed)) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
