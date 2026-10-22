import Foundation

/// Monotonic deadlines, bounded admission, and no queued catch-up after a stall.
struct BurstCadence {
    let minimumInterval: Double
    private(set) var interval: Double
    private(set) var nextDeadline: Double
    private(set) var accepted = 0
    private(set) var blocked = 0
    private(set) var lastAccepted: Double?
    private(set) var intervals: [Double] = []
    private var pressureStreak = 0
    private var stableStreak = 0
    init(fps: Double, exposure: Double, now: Double) {
        minimumInterval = max(1 / max(0.1, fps), exposure + 0.03)
        interval = minimumInterval
        nextDeadline = now
    }
    mutating func admit(at now: Double, ready: Bool) -> Bool {
        guard now >= nextDeadline else { return false }
        guard ready else {
            blocked += 1
            registerPressure(elapsed: lastAccepted.map { now - $0 } ?? interval)
            // Back off, rather than polling on a main-thread tight loop.
            nextDeadline = now + 0.05
            return false
        }
        if let last = lastAccepted {
            let elapsed = now - last
            intervals.append(elapsed)
            if intervals.count > 120 { intervals.removeFirst() }
            if elapsed > interval * 1.2 {
                registerPressure(elapsed: elapsed)
            } else {
                pressureStreak = 0
                stableStreak += 1
                // Recover one step only after a sustained run, never above the selected ceiling.
                if stableStreak >= 12 {
                    interval = max(minimumInterval, interval / 1.25)
                    stableStreak = 0
                }
            }
        }
        accepted += 1
        lastAccepted = now
        nextDeadline = now + interval
        return true
    }
    private mutating func registerPressure(elapsed: Double) {
        stableStreak = 0
        pressureStreak += 1
        // One scheduler hiccup must not permanently throttle a whole hold.
        guard pressureStreak >= 3 else { return }
        interval = min(minimumInterval * 8, max(interval * 1.25, elapsed))
        pressureStreak = 0
    }
    var measuredFPS: Double? {
        guard !intervals.isEmpty else { return nil }
        return Double(intervals.count) / intervals.reduce(0, +)
    }
}
