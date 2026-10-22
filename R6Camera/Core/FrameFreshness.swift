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
