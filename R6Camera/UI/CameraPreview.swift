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
        view.previewLayer.videoGravity = .resizeAspectFill
        camera.previewLayer = view.previewLayer
        let interaction = AVCaptureEventInteraction { [weak camera] event in
            guard let camera else { return }
            DispatchQueue.main.async {
                switch event.phase {
                case .began:
                    if camera.settings.drive == .burst { camera.beginBurst() }
                    else { camera.shutter() }
                case .ended:
                    if camera.settings.drive == .burst { camera.cancelCapture() }
                case .cancelled: camera.cancelCapture()
                @unknown default: break
                }
            }
        }
        view.addInteraction(interaction)
        view.captureInteraction = interaction
        return view
    }
    func updateUIView(_ uiView: PreviewSurface, context: Context) {
        uiView.captureInteraction?.isEnabled = camera.isRunning
        uiView.rotationAngle = camera.fixedRotation
        uiView.setNeedsLayout()
    }
}

final class PreviewSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    weak var camera: CameraController?
    var captureInteraction: AVCaptureEventInteraction?
    var rotationAngle: CGFloat = 0
    override func layoutSubviews() {
        super.layoutSubviews()
        // Preview orientation is fixed once; layout never mutates the capture graph.
        if let connection = previewLayer.connection, connection.videoRotationAngle != rotationAngle,
           connection.isVideoRotationAngleSupported(rotationAngle) { connection.videoRotationAngle = rotationAngle }
    }
}
