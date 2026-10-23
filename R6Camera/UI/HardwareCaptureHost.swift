import SwiftUI
import UIKit

/// A normal content view in each full-screen page receives events while preview is detached.
struct HardwareCaptureHost: UIViewRepresentable {
    let camera: CameraController
    let name: String
    func makeUIView(context: Context) -> HardwareCaptureContentView {
        let view = HardwareCaptureContentView()
        view.camera = camera
        view.accessibilityIdentifier = "hardware.host.\(name)"
        return view
    }
    func updateUIView(_ view: HardwareCaptureContentView, context: Context) {}
    static func dismantleUIView(_ view: HardwareCaptureContentView, coordinator: ()) {
        // The view can still belong to a window while SwiftUI dismantles its page.
        DispatchQueue.main.async { [weak camera = view.camera] in
            camera?.unbindHardwareView(view)
        }
    }
}

final class HardwareCaptureContentView: UIView {
    weak var camera: CameraController?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.window != nil { self.camera?.bindHardwareView(self) }
            else { self.camera?.unbindHardwareView(self) }
        }
    }
}
