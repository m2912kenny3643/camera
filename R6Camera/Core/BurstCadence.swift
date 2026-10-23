import Foundation

/// Fixed monotonic slots; a hold may slow down, but never speed up or catch up.
struct BurstCadence {
    let minimumInterval: Double
    private(set) var interval: Double
    private(set) var nextDeadline: Double
    private(set) var accepted = 0
    private(set) var blocked = 0
    private(set) var lastAccepted: Double?
    private(set) var intervals: [Double] = []
    private(set) var hasReducedRate = false
    private var pressureStreak = 0
    var effectiveFPS: Double { 1 / interval }
    init(fps: Double, exposure: Double, now: Double) {
        minimumInterval = max(1 / max(0.1, fps), exposure + 0.03)
        interval = minimumInterval
        nextDeadline = now
    }
    mutating func admit(at now: Double, ready: Bool) -> Bool {
        guard now.isFinite, now >= nextDeadline else { return false }
        guard ready else {
            blocked += 1
            registerPressure()
            advanceDeadline(past: now)
            return false
        }
        if let last = lastAccepted {
            let elapsed = now - last
            intervals.append(elapsed)
            if intervals.count > 120 { intervals.removeFirst() }
            if elapsed > interval * 1.2 {
                registerPressure()
            } else {
                pressureStreak = 0
            }
        }
        accepted += 1
        lastAccepted = now
        advanceDeadline(past: now)
        return true
    }
    private mutating func registerPressure() {
        pressureStreak += 1
        // One scheduler hiccup is recorded but does not change the target rate.
        guard pressureStreak >= 3 else { return }
        pressureStreak = 0
        let ladder = [12.0, 10, 8, 6, 4, 2, 1]
        guard let slower = ladder.first(where: { $0 < effectiveFPS - 0.000001 }) else { return }
        interval = max(minimumInterval, 1 / slower)
        hasReducedRate = true
    }
    private mutating func advanceDeadline(past now: Double) {
        let elapsedSlots = floor(max(0, now - nextDeadline) / interval) + 1
        let candidate = nextDeadline + elapsedSlots * interval
        // Small scheduler jitter stays on the original phase. A genuinely late
        // arrival cannot be followed by a short compensating request interval.
        nextDeadline = candidate - now >= interval * 0.8 ? candidate : now + interval
    }
    var measuredFPS: Double? {
        guard !intervals.isEmpty else { return nil }
        return Double(intervals.count) / intervals.reduce(0, +)
    }
}
