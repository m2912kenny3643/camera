import Foundation

/// Monotonic deadlines, bounded admission, and no queued catch-up after a stall.
struct BurstCadence {
    private(set) var interval: Double
    private(set) var nextDeadline: Double
    private(set) var accepted = 0
    private(set) var blocked = 0
    private(set) var lastAccepted: Double?
    private(set) var intervals: [Double] = []
    init(fps: Double, exposure: Double, now: Double) {
        interval = max(1 / max(0.1, fps), exposure + 0.03)
        nextDeadline = now
    }
    mutating func admit(at now: Double, ready: Bool) -> Bool {
        guard now >= nextDeadline else { return false }
        guard ready else {
            blocked += 1
            // Back off, rather than polling on a main-thread tight loop.
            nextDeadline = now + 0.05
            return false
        }
        if let last = lastAccepted {
            let elapsed = now - last
            intervals.append(elapsed)
            if intervals.count > 120 { intervals.removeFirst() }
            // Reduce speed for this hold; do not oscillate back to a faster rate.
            if elapsed > interval * 1.2 { interval = elapsed }
        }
        accepted += 1
        lastAccepted = now
        nextDeadline = now + interval
        return true
    }
    var measuredFPS: Double? {
        guard !intervals.isEmpty else { return nil }
        return Double(intervals.count) / intervals.reduce(0, +)
    }
}
