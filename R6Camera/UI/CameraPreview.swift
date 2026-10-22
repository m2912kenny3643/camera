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
        let interaction = AVCaptureEventInteraction { [weak camera, weak view] event in
            guard let camera, let view else { return }
            DispatchQueue.main.async {
                switch event.phase {
                case .began:
                    view.hardwareBurst = camera.settings.drive.isBurst
                    if view.hardwareBurst { camera.beginBurst() }
                    else { camera.shutter() }
                case .ended:
                    if view.hardwareBurst { camera.cancelCapture() }
                    view.hardwareBurst = false
                case .cancelled: camera.cancelCapture(); view.hardwareBurst = false
                @unknown default: break
                }
            }
        }
        view.addInteraction(interaction)
        view.captureInteraction = interaction
        return view
    }
    func updateUIView(_ uiView: PreviewSurface, context: Context) {
        uiView.captureInteraction?.isEnabled = camera.isRunning && camera.captureEnabled
        uiView.rotationAngle = camera.fixedRotation
        uiView.setNeedsLayout()
    }
}

final class PreviewSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    weak var camera: CameraController?
    var captureInteraction: AVCaptureEventInteraction?
    var hardwareBurst = false
    var rotationAngle: CGFloat = 0
    override func layoutSubviews() {
        super.layoutSubviews()
        // Preview orientation is fixed once; layout never mutates the capture graph.
        if let connection = previewLayer.connection, connection.videoRotationAngle != rotationAngle,
           connection.isVideoRotationAngleSupported(rotationAngle) { connection.videoRotationAngle = rotationAngle }
    }
}
