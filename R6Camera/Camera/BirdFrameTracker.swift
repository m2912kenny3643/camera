import Vision
import AVFoundation

/// Fast lane tracks only a measured, explicitly selected bird. It never creates landmarks.
final class BirdFrameTracker {
    struct Seed {
        let result: TrackingResult
        let buffer: CVPixelBuffer
        let time: Double
        let epoch: UInt64
        let sequence: UInt64
        let settings: CameraSettings
    }
    private var handler = VNSequenceRequestHandler()
    private var body: VNTrackObjectRequest?
    private var head: VNTrackObjectRequest?
    private var eye: VNTrackObjectRequest?
    private var seededSequence: UInt64?
    private var lastBody: CGRect?
    func reset() { handler = VNSequenceRequestHandler(); body = nil; head = nil; eye = nil; seededSequence = nil; lastBody = nil }
    func update(_ buffer: CVPixelBuffer, seed: Seed, at now: Double, sequence: UInt64) throws -> TrackingResult? {
        guard sequence > seed.sequence, now >= seed.time, now-seed.time <= seed.settings.trackingStickiness,
              let selected = seed.result.selected, selected.kind == .bird else { reset(); return nil }
        func request(_ bounds: CGRect) -> VNTrackObjectRequest {
            let r = VNTrackObjectRequest(detectedObjectObservation: VNDetectedObjectObservation(boundingBox: bounds.fromVision))
            r.trackingLevel = .accurate
            return r
        }
        if seededSequence != seed.sequence {
            reset(); seededSequence = seed.sequence
            body = request(selected.bounds)
            if let bounds = selected.headBounds { head = request(bounds) }
            if selected.eye(seed.settings.eyes) != nil { eye = request(selected.focusBounds(seed.settings.eyes)) }
            try handler.perform([body,head,eye].compactMap { $0 }, on: seed.buffer, orientation: .up)
            lastBody = selected.bounds
        }
        let requests = [body,head,eye].compactMap { $0 }
        guard !requests.isEmpty else { return nil }
        try handler.perform(requests, on: buffer, orientation: .up)
        func tracked(_ request: VNTrackObjectRequest?) -> CGRect? {
            guard let observation = request?.results?.first as? VNDetectedObjectObservation, observation.confidence >= 0.6 else { return nil }
            request?.inputObservation = observation
            return observation.boundingBox.fromVision
        }
        guard let bounds = tracked(body), bounds.area > 0, let previous = lastBody,
              bounds.area/previous.area >= 0.5, bounds.area/previous.area <= 2,
              hypot(bounds.midX-previous.midX,bounds.midY-previous.midY) <= max(0.15, previous.width*0.75) else { reset(); return nil }
        // Refuse a nearby competing bird rather than carrying a rectangle through a crossing.
        let competitors = seed.result.candidates.filter { $0.kind == .bird && $0.id != selected.id && SubjectTracker.intersectionOverUnion($0.bounds, selected.bounds) < 0.5 && SubjectTracker.intersectionOverUnion($0.bounds, selected.bounds) < 0.5 }
        if competitors.contains(where: { SubjectTracker.intersectionOverUnion($0.bounds, bounds) > 0.25 }) { reset(); return nil }
        lastBody = bounds
        var result = seed.result
        var bird = selected
        bird.bounds = bounds
        bird.leftEye = nil; bird.rightEye = nil
        if let h = tracked(head), bounds.contains(CGPoint(x: h.midX,y: h.midY)) { bird.headBounds = h }
        else { bird.headBounds = nil }
        if now-seed.time <= FrameFreshness.maximumAge, let e = tracked(eye), bounds.contains(CGPoint(x: e.midX,y: e.midY)) {
            let point = CGPoint(x: e.midX,y: e.midY)
            if selected.leftEye == selected.eye(seed.settings.eyes) { bird.leftEye = point } else { bird.rightEye = point }
        }
        result.selected = bird
        result.observedAt = now; result.epoch = seed.epoch; result.frameSequence = sequence
        result.focusAction = seed.settings.autofocus == .single ? .none : .continuous(bird.focusPoint(seed.settings.eyes))
        return result
    }
}
