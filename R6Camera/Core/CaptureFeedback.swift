import Foundation

/// One exposure pulse. Explicit time keeps its visible lifetime testable without sleeping.
struct CaptureFeedback {
    private(set) var lastEvent = 0
    private var startedAt: TimeInterval?
    var isActive: Bool { startedAt != nil }
    static let holdDuration: TimeInterval = 0.12
    static let fadeDuration: TimeInterval = 0.08
    static var duration: TimeInterval { holdDuration + fadeDuration }

    mutating func begin(event: Int, at now: TimeInterval) -> Bool {
        guard event > lastEvent else { return false }
        lastEvent = event
        startedAt = now
        return true
    }
    func opacity(at now: TimeInterval) -> Double {
        guard let startedAt else { return 0 }
        return min(1, max(0, 1 - (now - startedAt - Self.holdDuration) / Self.fadeDuration))
    }
    mutating func finish(event: Int) {
        guard event == lastEvent else { return }
        startedAt = nil
    }
    mutating func cancel() { startedAt = nil }
}
