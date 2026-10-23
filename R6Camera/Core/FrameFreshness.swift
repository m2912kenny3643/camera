import Foundation

/// Capture timestamps and now must use the same monotonic clock.
struct FrameFreshness {
    static let maximumAge = 0.25
    private(set) var lastApplied: Double?
    static func isCurrent(_ timestamp: Double, now: Double) -> Bool {
        timestamp.isFinite && now.isFinite && timestamp <= now && now - timestamp <= maximumAge
    }
    mutating func accept(_ timestamp: Double, now: Double) -> Bool {
        guard Self.isCurrent(timestamp, now: now), lastApplied.map({ timestamp > $0 }) ?? true else { return false }
        lastApplied = timestamp
        return true
    }
}

/// Main-thread admission, including callbacks queued before an occlusion invalidation.
struct VisionFrameGate {
    private var epoch: UInt64?
    private var sequence: UInt64?
    private var freshness = FrameFreshness()
    mutating func accept(_ result: TrackingResult, currentEpoch: UInt64, now: Double) -> Bool {
        if let candidate = result.epoch {
            guard candidate == currentEpoch else { return false }
            if epoch != candidate { epoch = candidate; sequence = nil }
            if let next = result.frameSequence, let sequence, next <= sequence { return false }
        }
        if let time = result.observedAt, !freshness.accept(time, now: now) { return false }
        if result.epoch != nil, let next = result.frameSequence { sequence = next }
        return true
    }
}
