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
                case .ended:
                    if camera.settings.drive == .burst { camera.cancelCapture() }
                    else { camera.shutter() }
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
        uiView.setNeedsLayout()
    }
}

final class PreviewSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    weak var camera: CameraController?
    var captureInteraction: AVCaptureEventInteraction?
    private var angle: CGFloat = -1
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let orientation = window?.windowScene?.interfaceOrientation else { return }
        let newAngle: CGFloat
        switch orientation {
        case .landscapeLeft: newAngle = 0
        case .landscapeRight: newAngle = 180
        case .portraitUpsideDown: newAngle = 270
        default: newAngle = 90
        }
        if angle != newAngle || previewLayer.connection?.videoRotationAngle != newAngle {
            angle = newAngle
            camera?.rotate(to: newAngle)
        }
    }
}
