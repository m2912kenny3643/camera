import Foundation

/// A controls-overlay gesture authorizes an action; it never identifies a hardware button.
struct HardwareShutter {
    enum Input: String { case controlsActive, controlsInactive, primaryBegan, primaryEnded, primaryCancelled, secondaryBegan, secondaryEnded, secondaryCancelled, capturePageReady, reset }
    enum Action: String { case focus, photo, beginBurst, stopBurst }
    struct Decision {
        let actions: [Action]
        let reason: String
    }
    static let dismissalGrace = 0.3
    private(set) var deadline: Double?
    private var authorizedAt: Double?
    private(set) var controlsActive = false
    private(set) var primaryDown = false
    private(set) var bursting = false
    private(set) var pendingCapture: Action?

    mutating func receive(_ input: Input, at now: Double, experimental: Bool,
                          available: Bool, burst: Bool, captureAllowed: Bool = true,
                          returningToCapture: Bool = false) -> Decision {
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
            // The overlay can stay active for many seconds without another activation callback.
            // Its active lifetime, rather than a timer or one-use token, is the proxy authorization.
            deadline = nil
            authorizedAt = now
            guard !primaryDown else { return decision("press-in-progress") }
            return Decision(actions: [.focus], reason: "overlay-authorized-source-unknown")
        case .controlsInactive:
            guard controlsActive else { return decision("duplicate-controls-inactive") }
            controlsActive = false
            if authorizedAt != nil { deadline = now + Self.dismissalGrace }
            return decision("overlay-dismissed")
        case .primaryBegan, .secondaryBegan:
            // In legacy mode both handlers retain their shared-shutter behavior.
            if experimental && input == .secondaryBegan { return decision("secondary-rejected") }
            guard !primaryDown, pendingCapture == nil else { return decision("duplicate-began-or-pending") }
            primaryDown = true // Rejected presses must end before another began is accepted.
            guard !experimental || (authorizedAt.map { now >= $0 } == true && (controlsActive || deadline != nil)) else { return decision("not-authorized") }
            if !controlsActive { deadline = nil; authorizedAt = nil }
            guard captureAllowed else {
                guard returningToCapture else { return decision("capture-page-covered") }
                pendingCapture = burst ? .beginBurst : .photo
                return decision("waiting-for-capture-page")
            }
            bursting = burst
            return Decision(actions: [burst ? .beginBurst : .photo], reason: experimental ? "authorized-source-unknown" : "legacy-shared-event")
        case .primaryEnded, .secondaryEnded:
            if experimental && input == .secondaryEnded { return decision("secondary-rejected") }
            let actions: [Action] = bursting ? [.stopBurst] : []
            bursting = false; primaryDown = false
            if pendingCapture == .beginBurst { pendingCapture = nil }
            return Decision(actions: actions, reason: "released")
        case .capturePageReady:
            guard captureAllowed, let pending = pendingCapture else { return decision("capture-page-ready") }
            pendingCapture = nil
            bursting = pending == .beginBurst
            return Decision(actions: [pending], reason: "capture-page-returned-source-unknown")
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
    let appVersion: String
    let time: Double
    let event: String
    let source: String
    let experimental: Bool
    let available: Bool
    let receiverAttached: Bool
    let receiverEnabled: Bool
    let receiverHost: String
    let sceneActive: Bool
    let sessionRunning: Bool
    let page: String
    let captureAllowed: Bool
    let captureTaskBusy: Bool
    let returningToCapture: Bool
    let pendingCapture: String?
    let controlsActive: Bool
    let primaryDown: Bool
    let deadline: Double?
    let actions: [String]
    let reason: String
}
