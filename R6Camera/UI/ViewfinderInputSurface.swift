import SwiftUI
import UIKit

/// Touch counts are explicit: a one-finger pan cannot commit a focus move during a pinch.
struct ViewfinderInputSurface: UIViewRepresentable {
    let tap: (CGPoint) -> Void
    let pan: (UIGestureRecognizer.State, CGPoint, CGSize) -> Void
    let pinch: (UIGestureRecognizer.State, CGFloat) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isMultipleTouchEnabled = true
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.drag(_:)))
        pan.minimumNumberOfTouches = 1; pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.zoom(_:)))
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.select(_:)))
        tap.require(toFail: pan); tap.require(toFail: pinch)
        pan.delegate = context.coordinator; pinch.delegate = context.coordinator
        view.addGestureRecognizer(pan); view.addGestureRecognizer(pinch); view.addGestureRecognizer(tap)
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { context.coordinator.parent = self }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ViewfinderInputSurface
        init(_ parent: ViewfinderInputSurface) { self.parent = parent }
        func gestureRecognizer(_ first: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith second: UIGestureRecognizer) -> Bool {
            (first is UIPanGestureRecognizer && second is UIPinchGestureRecognizer) ||
            (first is UIPinchGestureRecognizer && second is UIPanGestureRecognizer)
        }
        @objc func select(_ gesture: UITapGestureRecognizer) {
            if gesture.state == .ended { parent.tap(gesture.location(in: gesture.view)) }
        }
        @objc func drag(_ gesture: UIPanGestureRecognizer) {
            let position = gesture.location(in: gesture.view), delta = gesture.translation(in: gesture.view)
            parent.pan(gesture.state, CGPoint(x: position.x - delta.x, y: position.y - delta.y), CGSize(width: delta.x, height: delta.y))
        }
        @objc func zoom(_ gesture: UIPinchGestureRecognizer) { parent.pinch(gesture.state, gesture.scale) }
    }
}
