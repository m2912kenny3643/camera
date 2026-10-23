import SwiftUI
import AVFoundation
import AVKit

struct CameraPreview: UIViewRepresentable {
    @ObservedObject var camera: CameraController
    func makeUIView(context: Context) -> PreviewSurface {
        let view = PreviewSurface()
        view.camera = camera
        #if !targetEnvironment(simulator)
        view.previewLayer.session = camera.session
        #endif
        view.previewLayer.videoGravity = .resizeAspect
        camera.previewLayer = view.previewLayer
        let handle: (AVCaptureEvent, Bool) -> Void = { [weak camera] event, secondary in
            let input: HardwareShutter.Input
            switch event.phase {
            case .began: input = secondary ? .secondaryBegan : .primaryBegan
            case .ended: input = secondary ? .secondaryEnded : .primaryEnded
            case .cancelled: input = secondary ? .secondaryCancelled : .primaryCancelled
            @unknown default: input = .primaryCancelled
            }
            let time = CACurrentMediaTime()
            if Thread.isMainThread { camera?.hardwareInput(input, at: time) }
            else { DispatchQueue.main.async { camera?.hardwareInput(input, at: time) } }
        }
        let interaction = AVCaptureEventInteraction(primary: { handle($0, false) }, secondary: { handle($0, true) })
        view.addInteraction(interaction)
        view.captureInteraction = interaction
        return view
    }
    func updateUIView(_ uiView: PreviewSurface, context: Context) {
        uiView.captureInteraction?.isEnabled = camera.isRunning && (camera.captureEnabled || camera.settings.experimentalHardwareShutter)
        uiView.rotationAngle = camera.fixedRotation
        uiView.setNeedsLayout()
    }
}

/// Simulator-only injection uses the same controller/event path; it never claims hardware validation.
struct HardwareReturnTestButton: View {
    @ObservedObject var camera: CameraController
    var body: some View {
        if camera.hardwareReturnFixture {
            Button("輕按測試") { camera.simulateHardwareReturn() }
                .accessibilityIdentifier("fixture.hardwareReturn")
                .buttonStyle(.plain).font(.caption).padding(6).background(.black).foregroundStyle(.yellow)
                .fixedSize()
        }
    }
}

final class PreviewSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    weak var camera: CameraController?
    var captureInteraction: AVCaptureEventInteraction?
    var rotationAngle: CGFloat = 0
    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Full-screen presentations may detach the preview; keep the scene's window as the anchor.
        if let window { camera?.presentationWindow = window }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        // Preview orientation is fixed once; layout never mutates the capture graph.
        if let connection = previewLayer.connection, connection.videoRotationAngle != rotationAngle,
           connection.isVideoRotationAngleSupported(rotationAngle) { connection.videoRotationAngle = rotationAngle }
    }
}
