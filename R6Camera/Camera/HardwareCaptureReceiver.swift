import UIKit
import AVKit

/// One receiver per camera scene. Full-screen presentations may detach the preview view.
final class HardwareCaptureReceiver {
    private weak var window: UIWindow?
    private var interaction: AVCaptureEventInteraction?
    var onInput: ((HardwareShutter.Input, Double) -> Void)?
    var attached: Bool { interaction?.view === window && window != nil }
    var enabled: Bool { attached && interaction?.isEnabled == true }
    var host: String { window.map { "\(type(of: $0)):\($0.windowScene?.session.persistentIdentifier ?? "no-scene")" } ?? "none" }

    /// Returns true on a scene/window change, which must revoke previous authorizations.
    func bind(_ window: UIWindow) -> Bool {
        guard self.window !== window else { return false }
        detach()
        self.window = window
        return true
    }
    func setEnabled(_ enabled: Bool) {
        guard enabled, let window else { detach(); return }
        if interaction == nil {
            let handle: (AVCaptureEvent, Bool) -> Void = { [weak self] event, secondary in
                let input: HardwareShutter.Input
                switch event.phase {
                case .began: input = secondary ? .secondaryBegan : .primaryBegan
                case .ended: input = secondary ? .secondaryEnded : .primaryEnded
                case .cancelled: input = secondary ? .secondaryCancelled : .primaryCancelled
                @unknown default: input = .primaryCancelled
                }
                let time = CACurrentMediaTime()
                if Thread.isMainThread { self?.onInput?(input, time) }
                else { DispatchQueue.main.async { self?.onInput?(input, time) } }
            }
            let receiver = AVCaptureEventInteraction(primary: { handle($0, false) }, secondary: { handle($0, true) })
            receiver.isEnabled = false
            interaction = receiver
        }
        guard let interaction else { return }
        if interaction.view !== window { window.addInteraction(interaction) }
        interaction.isEnabled = true
    }
    deinit {
        let receiver = interaction
        let cleanup = {
            receiver?.isEnabled = false
            if let receiver { receiver.view?.removeInteraction(receiver) }
        }
        if Thread.isMainThread { cleanup() }
        else { DispatchQueue.main.async(execute: cleanup) }
    }
    private func detach() {
        interaction?.isEnabled = false
        if let interaction { interaction.view?.removeInteraction(interaction) }
    }
}
