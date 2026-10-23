import AVFoundation
import Vision
import CoreML
import CoreImage

/// One serial queue owns inference, identity association and settings snapshots.
final class SubjectVision: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let queue = DispatchQueue(label: "camera.vision", qos: .userInitiated)
    let captureQueue = DispatchQueue(label: "camera.frames", qos: .userInteractive)
    private let renderQueue = DispatchQueue(label: "camera.preview", qos: .userInteractive)
    private let trackingQueue = DispatchQueue(label: "camera.bird.tracking", qos: .userInitiated)
    private let trackingSlot = DispatchSemaphore(value: 1)
    private let birdFlow = BirdFrameTracker() // trackingQueue only
    private let inferenceSlot = DispatchSemaphore(value: 1)
    private let renderSlot = DispatchSemaphore(value: 1)
    private let snapshotLock = NSLock()
    private var previewSettings = CameraSettings()
    private var epoch: UInt64 = 0 // snapshotLock
    private var frameSequence: UInt64 = 0 // captureQueue
    private var trackingSeed: BirdFrameTracker.Seed? // snapshotLock
    var currentEpoch: UInt64 { snapshotLock.lock(); defer { snapshotLock.unlock() }; return epoch }
    @discardableResult private func invalidate() -> UInt64 {
        snapshotLock.lock(); defer { snapshotLock.unlock() }
        epoch &+= 1; trackingSeed = nil
        return epoch
    }
    /// Invalidates already queued fast callbacks when a model declares loss/occlusion.
    private func stopContinuation(expected: UInt64) -> UInt64? {
        snapshotLock.lock(); defer { snapshotLock.unlock() }
        guard epoch == expected else { return nil }
        if trackingSeed != nil { epoch &+= 1 }
        trackingSeed = nil
        return epoch
    }
    var onFrame: ((TrackingResult, CGSize, [Float], CGImage?) -> Void)?
    var onPreview: ((CGImage, CGSize) -> Void)?
    var onModelError: ((String) -> Void)?
    var onBirdStatus: ((String) -> Void)?
    private var settings = CameraSettings()
    private var tracker = SubjectTracker()
    private var model: VNCoreMLModel?
    private var birdModel: (any BirdPosePredicting)?
    private var lastFrame: Double = 0
    private var lastAspect: CGFloat = 0
    private var lastFrameSize = CGSize(width: 4, height: 3)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let renderContext = CIContext(options: [.cacheIntermediates: false])

    func configure(_ requested: CameraSettings) {
        let settings = requested.effective
        snapshotLock.lock()
        if FocusConfiguration(previewSettings) != FocusConfiguration(settings) { epoch &+= 1; trackingSeed = nil }
        previewSettings = settings
        snapshotLock.unlock()
        queue.async {
            if FocusConfiguration(self.settings) != FocusConfiguration(settings) {
                self.tracker.reset()
                self.settings = settings
                var cleared = self.tracker.result
                cleared.focusAction = settings.autofocus == .manual ? .none : .scene
                self.publish(cleared, histogram: [])
            }
            self.settings = settings
        }
    }
    func select(_ point: CGPoint) {
        let selectionEpoch = invalidate()
        queue.async {
            guard self.settings.autofocus != .manual else { return }
            self.tracker.select(at: point, eyes: self.settings.eyes, mode: self.settings.autofocus, area: self.settings.focusArea, now: CACurrentMediaTime())
            self.publish(self.tracker.result, histogram: [], epoch: selectionEpoch)
        }
    }
    func acquire() {
        let selectionEpoch = invalidate()
        queue.async {
            guard self.settings.autofocus != .manual else { return }
            self.tracker.acquire(settings: self.settings, at: CACurrentMediaTime())
            self.publish(self.tracker.result, histogram: [], epoch: selectionEpoch)
        }
    }
    func unlock() {
        let unlockEpoch = invalidate()
        queue.async {
            self.tracker.unlock()
            self.publish(self.tracker.result, histogram: [], epoch: unlockEpoch)
        }
    }
    func reset() { invalidate(); queue.async { self.tracker.reset(); self.lastAspect = 0 } }
    func loadModel() {
        queue.async {
            do {
                if Bundle.main.url(forResource: BirdONNXModel.resource, withExtension: "onnx") != nil { self.birdModel = try BirdONNXModel() }
                else { self.birdModel = try BirdPoseModel() }
                self.onBirdStatus?("鳥眼模型已載入；真機準確度與效能待驗收")
            } catch {
                self.birdModel = nil
                self.onBirdStatus?(error.localizedDescription)
            }
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
        let frameEpoch = epoch
        let seed = trackingSeed
        snapshotLock.unlock()
        frameSequence &+= 1
        let sequence = frameSequence
        if let seed, seed.epoch == frameEpoch, trackingSlot.wait(timeout: .now()) == .success {
            trackingQueue.async {
                defer { self.trackingSlot.signal() }
                do {
                    if let result = try self.birdFlow.update(buffer, seed: seed, at: now, sequence: sequence) {
                        self.snapshotLock.lock()
                        let valid = self.epoch == frameEpoch && self.trackingSeed?.sequence == seed.sequence
                        self.snapshotLock.unlock()
                        guard valid else { return }
                        if !snapshot.focusArea.wholeAreaTracking,
                           let selected = result.selected,
                           !snapshot.focusArea.contains(selected.focusPoint(snapshot.eyes)) { return }
                        self.onFrame?(result, CGSize(width: CVPixelBufferGetWidth(buffer),height: CVPixelBufferGetHeight(buffer)), [], nil)
                    }
                } catch { self.birdFlow.reset() }
            }
        }
        // Both paths drop frames while busy. Inference never blocks the visible preview.
        if renderSlot.wait(timeout: .now()) == .success {
            renderQueue.async {
                self.renderPreview(buffer, settings: snapshot)
            }
        }
        guard now - lastFrame >= 0.08, inferenceSlot.wait(timeout: .now()) == .success else { return }
        lastFrame = now
        queue.async {
            defer { self.inferenceSlot.signal() }
            self.processFrame(buffer, at: now, epoch: frameEpoch, sequence: sequence)
        }
    }
    private func processFrame(_ buffer: CVPixelBuffer, at now: Double, epoch: UInt64, sequence: UInt64) {
        guard currentEpoch == epoch else { return }
        let aspect = CGFloat(CVPixelBufferGetWidth(buffer)) / CGFloat(CVPixelBufferGetHeight(buffer))
        lastFrameSize = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        if abs(aspect - lastAspect) > 0.1 { tracker.reset(); lastAspect = aspect }
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
        var detections: [SubjectDetection] = []
        if settings.autofocus != .manual && settings.subjects != .none {
            do {
                if settings.subjects != .birds, let model {
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
                if [.automatic, .animals, .birds].contains(settings.subjects), let birdModel {
                    do {
                        let selected = tracker.result.locked ? tracker.result.selected : nil
                        let region = selected?.kind == .bird ? selected?.bounds : nil
                        let poses = try birdModel.observations(buffer, at: now, region: region,
                                                              padding: region == nil ? 1 : tracker.result.missing ? 1.7 : 1.2)
                        let birds = poses.filter { $0.timestamp == now }.map(\.detection)
                        // Replace duplicate body detections; identity remains tied to observed body geometry.
                        detections.removeAll { old in old.kind == .bird && birds.contains {
                            SubjectTracker.intersectionOverUnion(old.bounds, $0.bounds) > 0.2
                        } }
                        detections.append(contentsOf: birds)
                    } catch {
                        self.birdModel = nil
                        onBirdStatus?("鳥眼推論失敗，已回到身體辨識：\(error.localizedDescription)")
                    }
                }
            } catch {
                // Empty detections pass through the normal grace/lost state. Do not preserve fake live boxes.
                detections = []
            }
        }
        // A slow prediction must not move a lens or mutate identity using an old scene.
        let finishedAt = CACurrentMediaTime()
        guard currentEpoch == epoch else { return }
        guard FrameFreshness.isCurrent(now, now: finishedAt) else {
            // Age the existing lock with no observations: a perpetually slow model must
            // not leave an old blue box and lens lock alive forever.
            var expired = tracker.update([], at: finishedAt, settings: settings)
            expired.frameSequence = sequence
            guard let generation = stopContinuation(expected: epoch) else { return }
            expired.observedAt = CACurrentMediaTime() // Control transition after invalidation, not a new eye measurement.
            publish(expired, histogram: [], epoch: generation)
            return
        }
        var result = tracker.update(detections, at: now, settings: settings)
        result.observedAt = now
        result.frameSequence = sequence
        var publicationEpoch = epoch
        if !result.locked || result.missing {
            guard let generation = stopContinuation(expected: epoch) else { return }
            publicationEpoch = generation
            if result.missing || result.lost { result.observedAt = CACurrentMediaTime() }
        }
        result.epoch = publicationEpoch
        result.configuration = FocusConfiguration(settings)
        snapshotLock.lock()
        if self.epoch == publicationEpoch {
            if !result.locked || result.missing { trackingSeed = nil }
            else if !result.missing, result.selected?.kind == .bird {
                trackingSeed = BirdFrameTracker.Seed(result: result, buffer: buffer, time: now, epoch: publicationEpoch, sequence: sequence, settings: settings)
            }
        }
        snapshotLock.unlock()
        let original = CIImage(cvPixelBuffer: buffer)
        let scale = min(1, 960 / original.extent.width)
        let image = original.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let histogram = settings.histogram ? luminanceHistogram(image) : []
        publish(result, histogram: histogram, epoch: publicationEpoch)
    }
    private func publish(_ result: TrackingResult, histogram: [Float], epoch: UInt64? = nil) {
        var snapshot = result
        snapshot.configuration = FocusConfiguration(settings)
        snapshot.epoch = epoch ?? currentEpoch
        onFrame?(snapshot, lastFrameSize, histogram, nil)
    }
    func finishPreview() { renderSlot.signal() }
    private func renderPreview(_ buffer: CVPixelBuffer, settings: CameraSettings) {
        let original = CIImage(cvPixelBuffer: buffer)
        let scale = min(1, 960 / original.extent.width)
        let image = original.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rendered = PhotoRenderer.preview(image, settings: settings)
        if let preview = renderContext.createCGImage(rendered, from: image.extent), let onPreview {
            onPreview(preview, original.extent.size)
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
