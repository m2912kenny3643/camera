import AVFoundation
import UniformTypeIdentifiers

final class PhotoJob: NSObject, AVCapturePhotoCaptureDelegate {
    struct Output {
        let data: PhotoCaptureData
        let settings: CameraSettings
        let type: UTType
        let dimensions: String?
    }
    let settings: CameraSettings
    let type: UTType
    let onCaptured: () -> Void
    let completion: (Result<Output, Error>) -> Void
    private var processed: Data?
    private var raw: Data?
    private var processingError: Error?
    private var captured = false
    private var dimensions: String?
    init(settings: CameraSettings, type: UTType, onCaptured: @escaping () -> Void, completion: @escaping (Result<Output, Error>) -> Void) {
        self.settings = settings; self.type = type; self.onCaptured = onCaptured; self.completion = completion
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { processingError = error; return }
        if !photo.isRawPhoto {
            let size = photo.resolvedSettings.photoDimensions
            dimensions = "\(size.width) × \(size.height)"
        }
        guard let data = photo.fileDataRepresentation() else { return }
        if photo.isRawPhoto { raw = data } else { processed = data }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        guard !captured else { return }
        captured = true
        onCaptured()
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        let data = PhotoCaptureData(processed: processed, raw: raw, requiresRAW: settings.format == .raw,
                                    error: (error ?? processingError)?.localizedDescription)
        guard !data.isEmpty else {
            completion(.failure(NSError(domain: "Photo", code: 1, userInfo: [NSLocalizedDescriptionKey: data.warning ?? "相機未傳回照片資料。"])))
            return
        }
        completion(.success(Output(data: data, settings: settings, type: type, dimensions: dimensions)))
    }
}
