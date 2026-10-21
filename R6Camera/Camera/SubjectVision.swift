import AVFoundation
import Vision
import CoreML
import CoreImage

/// One serial queue owns inference, identity association and settings snapshots.
final class SubjectVision: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let queue = DispatchQueue(label: "camera.vision", qos: .userInitiated)
    let captureQueue = DispatchQueue(label: "camera.frames", qos: .userInteractive)
    private let renderQueue = DispatchQueue(label: "camera.preview", qos: .userInteractive)
    private let inferenceSlot = DispatchSemaphore(value: 1)
    private let renderSlot = DispatchSemaphore(value: 1)
    private let snapshotLock = NSLock()
    private var previewSettings = CameraSettings()
    var onFrame: ((TrackingResult, CGFloat, [Float], CGImage?) -> Void)?
    var onPreview: ((CGImage) -> Void)?
    var onModelError: ((String) -> Void)?
    private var settings = CameraSettings()
    private var tracker = SubjectTracker()
    private var model: VNCoreMLModel?
    private var lastFrame: Double = 0
    private var lastAspect: CGFloat = 0
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let renderContext = CIContext(options: [.cacheIntermediates: false])

    func configure(_ settings: CameraSettings) {
        snapshotLock.lock()
        previewSettings = settings
        snapshotLock.unlock()
        queue.async {
            if self.settings.subjects != settings.subjects || self.settings.autofocus != settings.autofocus {
                self.tracker.reset()
                self.settings = settings
                var cleared = self.tracker.result
                cleared.focusAction = .hold
                self.publish(cleared, aspect: max(self.lastAspect, 1), histogram: [])
            }
            self.settings = settings
        }
    }
    func select(_ point: CGPoint) {
        queue.async {
            guard self.settings.autofocus != .manual else { return }
            self.tracker.select(at: point, eyes: self.settings.eyes)
            self.publish(self.tracker.result, aspect: max(self.lastAspect, 1), histogram: [])
        }
    }
    func unlock() {
        queue.async {
            self.tracker.unlock()
            self.publish(self.tracker.result, aspect: max(self.lastAspect, 1), histogram: [])
        }
    }
    func reset() { queue.async { self.tracker.reset(); self.lastAspect = 0 } }
    func loadModel() {
        queue.async {
            do {
                guard let url = Bundle.main.url(forResource: "YOLOv3TinyInt8LUT", withExtension: "mlmodelc") else {
                    throw NSError(domain: "Model", code: 1, userInfo: [NSLocalizedDescriptionKey: "缺少主體模型；請使用含模型的完整建置。"])
                }
                let config = MLModelConfiguration()
                config.computeUnits = .all
                self.model = try VNCoreMLModel(for: MLModel(contentsOf: url, configuration: config))
            } catch { self.onModelError?(error.localizedDescription) }
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        snapshotLock.lock()
        let snapshot = previewSettings
        snapshotLock.unlock()
        // Both paths drop frames while busy. Inference never blocks the visible preview.
        if renderSlot.wait(timeout: .now()) == .success {
            renderQueue.async {
                self.renderPreview(buffer, settings: snapshot)
            }
        }
        guard now - lastFrame >= 0.12, inferenceSlot.wait(timeout: .now()) == .success else { return }
        lastFrame = now
        queue.async {
            defer { self.inferenceSlot.signal() }
            self.processFrame(buffer, at: now)
        }
    }
    private func processFrame(_ buffer: CVPixelBuffer, at now: Double) {
        let aspect = CGFloat(CVPixelBufferGetWidth(buffer)) / CGFloat(CVPixelBufferGetHeight(buffer))
        if abs(aspect - lastAspect) > 0.1 { tracker.reset(); lastAspect = aspect }
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
        var detections: [SubjectDetection] = []
        if settings.autofocus != .manual && settings.subjects != .none {
            do {
                if let model {
                    let request = VNCoreMLRequest(model: model)
                    request.imageCropAndScaleOption = .scaleFill
                    try handler.perform([request])
                    detections = (request.results as? [VNRecognizedObjectObservation] ?? []).compactMap { observation in
                        guard let label = observation.labels.first, label.confidence >= 0.35,
                              let kind = SubjectKind.fromModelLabel(label.identifier) else { return nil }
                        return SubjectDetection(kind: kind, bounds: observation.boundingBox.fromVision,
                                                confidence: label.confidence)
                    }
                }
                if settings.subjects == .automatic || settings.subjects == .people {
                    try addHumanEyes(handler, to: &detections)
                }
                if settings.eyes != .off && (settings.subjects == .automatic || settings.subjects == .animals) {
                    try addAnimalEyes(handler, to: &detections)
                }
            } catch {
                // Empty detections pass through the normal grace/lost state. Do not preserve fake live boxes.
                detections = []
            }
        }
        let result = tracker.update(detections, at: now, settings: settings)
        let original = CIImage(cvPixelBuffer: buffer)
        let scale = min(1, 960 / original.extent.width)
        let image = original.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let histogram = settings.histogram ? luminanceHistogram(image) : []
        publish(result, aspect: aspect, histogram: histogram)
    }
    private func publish(_ result: TrackingResult, aspect: CGFloat, histogram: [Float]) {
        var snapshot = result
        snapshot.configuration = FocusConfiguration(settings)
        onFrame?(snapshot, aspect, histogram, nil)
    }
    func finishPreview() { renderSlot.signal() }
    private func renderPreview(_ buffer: CVPixelBuffer, settings: CameraSettings) {
        let original = CIImage(cvPixelBuffer: buffer)
        let scale = min(1, 960 / original.extent.width)
        let image = original.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rendered: CIImage
        if settings.peaking && settings.autofocus == .manual {
            let edges = image.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 4])
            rendered = edges
        } else {
            rendered = PhotoRenderer.applyStyle(image, settings: settings)
        }
        if let preview = renderContext.createCGImage(rendered, from: image.extent), let onPreview {
            onPreview(preview)
        } else { finishPreview() }
    }
    private func addHumanEyes(_ handler: VNImageRequestHandler, to detections: inout [SubjectDetection]) throws {
        let request = VNDetectFaceLandmarksRequest()
        try handler.perform([request])
        for face in request.results ?? [] where face.confidence > 0.5 {
            let bounds = face.boundingBox.fromVision
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let index = detections.indices.filter { detections[$0].kind == .person && detections[$0].bounds.contains(center) }
                .min { detections[$0].bounds.area < detections[$1].bounds.area }
            func eye(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
                guard let region, region.pointCount > 0 else { return nil }
                let points = region.normalizedPoints
                let x = points.map(\.x).reduce(0, +) / CGFloat(points.count)
                let y = points.map(\.y).reduce(0, +) / CGFloat(points.count)
                return CGPoint(x: face.boundingBox.minX + x * face.boundingBox.width,
                               y: 1 - (face.boundingBox.minY + y * face.boundingBox.height))
            }
            let left = eye(face.landmarks?.leftPupil ?? face.landmarks?.leftEye)
            let right = eye(face.landmarks?.rightPupil ?? face.landmarks?.rightEye)
            if let index {
                detections[index].leftEye = left
                detections[index].rightEye = right
                detections[index].headBounds = bounds
            } else {
                detections.append(SubjectDetection(kind: .person, bounds: bounds, confidence: face.confidence,
                                                   leftEye: left, rightEye: right, headBounds: bounds))
            }
        }
    }
    private func addAnimalEyes(_ handler: VNImageRequestHandler, to detections: inout [SubjectDetection]) throws {
        guard detections.contains(where: { $0.kind == .cat || $0.kind == .dog }) else { return }
        let request = VNDetectAnimalBodyPoseRequest()
        try handler.perform([request])
        for animal in request.results ?? [] {
            func eye(_ name: VNAnimalBodyPoseObservation.JointName) -> CGPoint? {
                guard let point = try? animal.recognizedPoint(name), point.confidence > 0.5 else { return nil }
                return CGPoint(x: point.location.x, y: 1 - point.location.y)
            }
            let left = eye(.leftEye), right = eye(.rightEye)
            guard let anchor = left ?? right ?? eye(.nose) ?? eye(.leftEarTop) ?? eye(.rightEarTop) else { continue }
            guard let index = detections.indices.filter({
                (detections[$0].kind == .cat || detections[$0].kind == .dog) && detections[$0].bounds.contains(anchor)
            }).min(by: { detections[$0].bounds.area < detections[$1].bounds.area }) else { continue }
            detections[index].leftEye = left
            detections[index].rightEye = right
            let headNames: [VNAnimalBodyPoseObservation.JointName] = [.leftEye, .rightEye, .nose,
                .leftEarTop, .leftEarMiddle, .leftEarBottom, .rightEarTop, .rightEarMiddle, .rightEarBottom]
            let points = headNames.compactMap { eye($0) }.filter { detections[index].bounds.contains($0) }
            if points.count >= 3, let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
               let minY = points.map(\.y).min(), let maxY = points.map(\.y).max(), maxX - minX > 0.01, maxY - minY > 0.01 {
                // Envelope of actual high-confidence landmarks, not a guessed head proportion.
                detections[index].headBounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            }
        }
    }
    private func luminanceHistogram(_ image: CIImage) -> [Float] {
        let small = image.transformed(by: CGAffineTransform(scaleX: 64 / image.extent.width, y: 64 / image.extent.height))
        var bytes = [UInt8](repeating: 0, count: 64 * 64 * 4)
        context.render(small, toBitmap: &bytes, rowBytes: 64 * 4,
                       bounds: CGRect(x: 0, y: 0, width: 64, height: 64), format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())
        var bins = [Float](repeating: 0, count: 32)
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let value = 0.2126 * Float(bytes[offset]) + 0.7152 * Float(bytes[offset + 1]) + 0.0722 * Float(bytes[offset + 2])
            bins[min(31, Int(value) / 8)] += 1
        }
        let maxValue = bins.max() ?? 1
        return bins.map { $0 / max(1, maxValue) }
    }
}
