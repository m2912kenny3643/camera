import UIKit
import AVKit

/// One receiver follows actual visible content views as full-screen pages appear/disappear.
final class HardwareCaptureReceiver {
    private struct Host { weak var view: UIView? }
    private weak var window: UIWindow?
    private weak var activeView: UIView?
    private var hosts: [Host] = []
    private var requestedEnabled = false
    private var interaction: AVCaptureEventInteraction?
    private(set) var receivedEvents = 0
    var onInput: ((HardwareShutter.Input, Double) -> Void)?
    var attached: Bool { activeView?.window != nil && interaction?.view === activeView }
    var enabled: Bool { attached && interaction?.isEnabled == true }
    var host: String {
        guard let activeView else { return "none" }
        return "\(activeView.accessibilityIdentifier ?? String(describing: type(of: activeView))):\(window?.windowScene?.session.persistentIdentifier ?? "no-scene")"
    }

    /// Register actual content views, never the UIWindow event-routing container.
    /// Returns whether a new scene/window revoked the previous host registry.
    @discardableResult func bind(_ view: UIView) -> Bool {
        guard !(view is UIWindow), let targetWindow = view.window else { return false }
        let changedWindow = window !== targetWindow
        if changedWindow { detach(); hosts = []; window = targetWindow }
        hosts.removeAll { $0.view == nil || $0.view === view }
        hosts.append(Host(view: view))
        refresh()
        return changedWindow
    }
    func unbind(_ view: UIView) {
        hosts.removeAll { $0.view == nil || $0.view === view }
        refresh()
    }
    func setEnabled(_ enabled: Bool) {
        requestedEnabled = enabled
        refresh()
    }
    private func refresh() {
        hosts.removeAll { $0.view == nil }
        let target = hosts.reversed().compactMap(\.view).first { $0.window === window && $0.window != nil && !$0.isHidden }
        if activeView !== target { detach(); activeView = target }
        guard requestedEnabled, let activeView, activeView.window != nil else { detach(); return }
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
                let deliver = { [weak self] in
                    guard let self else { return }
                    self.receivedEvents += 1
                    self.onInput?(input, time)
                }
                if Thread.isMainThread { deliver() }
                else { DispatchQueue.main.async(execute: deliver) }
            }
            let receiver = AVCaptureEventInteraction(primary: { handle($0, false) }, secondary: { handle($0, true) })
            receiver.isEnabled = false
            interaction = receiver
        }
        guard let interaction else { return }
        if interaction.view !== activeView { activeView.addInteraction(interaction) }
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
