import Foundation

/// A controls-overlay gesture authorizes an action; it never identifies a hardware button.
struct HardwareShutter {
    enum Input: String { case controlsActive, controlsInactive, primaryBegan, primaryEnded, primaryCancelled, secondaryBegan, secondaryEnded, secondaryCancelled, reset }
    enum Action: String { case focus, photo, beginBurst, stopBurst }
    struct Decision {
        let actions: [Action]
        let reason: String
    }
    static let authorizationDuration = 2.0
    static let dismissalGrace = 0.3
    private(set) var deadline: Double?
    private var authorizedAt: Double?
    private(set) var controlsActive = false
    private(set) var primaryDown = false
    private(set) var bursting = false

    mutating func receive(_ input: Input, at now: Double, experimental: Bool,
                          available: Bool, burst: Bool) -> Decision {
        if input == .reset || !available || !now.isFinite {
            let actions: [Action] = bursting ? [.stopBurst] : []
            self = HardwareShutter()
            return Decision(actions: actions, reason: input == .reset ? "reset" : "unavailable")
        }
        if let deadline, now >= deadline { self.deadline = nil; authorizedAt = nil }
        switch input {
        case .controlsActive:
            guard experimental, !controlsActive else { return decision("duplicate-or-disabled-controls") }
            controlsActive = true
            guard !primaryDown else { return decision("press-in-progress") }
            deadline = now + Self.authorizationDuration
            authorizedAt = now
            return Decision(actions: [.focus], reason: "overlay-authorized-source-unknown")
        case .controlsInactive:
            guard controlsActive else { return decision("duplicate-controls-inactive") }
            controlsActive = false
            if let deadline { self.deadline = min(deadline, now + Self.dismissalGrace) }
            return decision("overlay-dismissed")
        case .primaryBegan, .secondaryBegan:
            // In legacy mode both handlers retain their shared-shutter behavior.
            if experimental && input == .secondaryBegan { return decision("secondary-rejected") }
            guard !primaryDown else { return decision("duplicate-began") }
            primaryDown = true // Rejected presses must end before another began is accepted.
            guard !experimental || (deadline != nil && authorizedAt.map { now >= $0 } == true) else { return decision("not-authorized") }
            deadline = nil
            authorizedAt = nil
            bursting = burst
            return Decision(actions: [burst ? .beginBurst : .photo], reason: experimental ? "authorized-source-unknown" : "legacy-shared-event")
        case .primaryEnded, .secondaryEnded:
            if experimental && input == .secondaryEnded { return decision("secondary-rejected") }
            let actions: [Action] = bursting ? [.stopBurst] : []
            bursting = false; primaryDown = false
            return Decision(actions: actions, reason: "released")
        case .primaryCancelled, .secondaryCancelled:
            let actions: [Action] = bursting ? [.stopBurst] : []
            self = HardwareShutter()
            return Decision(actions: actions, reason: "cancelled")
        case .reset: return decision("reset") // Handled above.
        }
    }
    private func decision(_ reason: String) -> Decision { Decision(actions: [], reason: reason) }
}

struct HardwareShutterRecord: Codable {
    let time: Double
    let event: String
    let source: String
    let experimental: Bool
    let available: Bool
    let controlsActive: Bool
    let primaryDown: Bool
    let deadline: Double?
    let actions: [String]
    let reason: String
}
