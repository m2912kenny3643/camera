import Foundation
import CoreGraphics

struct BirdPoseObservation {
    enum Landmark: Int, CaseIterable { case beak, leftEye, rightEye, headTop, leftShoulder, rightShoulder }
    struct Point {
        let position: CGPoint
        let confidence: Float
    }
    let body: CGRect
    let confidence: Float
    let keypoints: [Landmark: Point]
    let timestamp: Double
    var imageAspect: CGFloat = 1

    var detection: SubjectDetection {
        func point(_ name: Landmark, minimum: Float) -> CGPoint? {
            guard let p = keypoints[name], p.confidence.isFinite, p.confidence >= minimum,
                  p.position.x.isFinite, p.position.y.isFinite, body.contains(p.position) else { return nil }
            return p.position
        }
        let left = point(.leftEye, minimum: 0.65), right = point(.rightEye, minimum: 0.65)
        let beak = point(.beak, minimum: 0.5), crown = point(.headTop, minimum: 0.65)
        let measuredPair: (CGPoint, CGPoint, CGFloat)?
        if let eye = point(.leftEye, minimum: 0.35) ?? point(.rightEye, minimum: 0.35), let beak {
            measuredPair = (eye, beak, 1.25)
        } else if let left, let right { measuredPair = (left, right, 1) }
        else if let beak, let crown { measuredPair = (beak, crown, 1) }
        else { measuredPair = nil }
        var head: CGRect?
        if let (a, b, radiusScale) = measuredPair, imageAspect > 0 {
            let span = hypot((a.x-b.x)*imageAspect, a.y-b.y)
            let extent = max(body.width*imageAspect, body.height)
            if span > 0.002, span <= extent * 0.45 {
                let radius = span * radiusScale
                let candidate = CGRect(x: (a.x+b.x)/2-radius/imageAspect, y: (a.y+b.y)/2-radius,
                                       width: 2*radius/imageAspect, height: 2*radius).intersection(body)
                if !candidate.isNull, candidate.area > 0 { head = candidate }
            }
        }
        return SubjectDetection(kind: .bird, bounds: body, confidence: confidence,
                                leftEye: left, rightEye: right,
                                headBounds: head)
    }
}

/// Pinned synthet six-point contract: [1,23,8400], model pixels, TOP LEFT.
/// The caller supplies strided tensor access, so no ML framework leaks into tracking.
enum BirdPoseDecoder {
    enum Contract { case coreML640, android320
        var size: CGFloat { self == .android320 ? 320 : 640 }
        var anchors: Int { self == .android320 ? 2100 : 8400 }
    }
    static let androidSHA256 = "350f370aac45ec120bb73434eb0add0446a5f327344c65b03a633229dc2c551b"
    static let checkpointSHA256 = "ec9e4b80a93eb6e2b21633e2ff2df30c49faa1eb7919dd24345c7dc295b2d1be"
    static func decode(imageSize: CGSize, anchors: Int, at timestamp: Double,
                       contract: Contract = .coreML640, region: CGRect? = nil, padding: CGFloat = 1,
                       value: (Int, Int) -> Double) -> [BirdPoseObservation] {
        guard imageSize.width.isFinite, imageSize.height.isFinite, imageSize.width > 0, imageSize.height > 0, anchors == contract.anchors,
              timestamp.isFinite, padding.isFinite, padding > 0 else { return [] }
        let crop = BirdCrop(imageSize: imageSize, region: region ?? CGRect(x: 0, y: 0, width: 1, height: 1), padding: padding)
        guard [crop.square.minX,crop.square.minY,crop.square.width].allSatisfy({ $0.isFinite }), crop.square.width > 0 else { return [] }
        func point(_ x: Double, _ y: Double) -> CGPoint {
            crop.imagePoint(CGPoint(x: CGFloat(x)/contract.size, y: CGFloat(y)/contract.size))
        }
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        var candidates: [BirdPoseObservation] = []
        for i in 0..<anchors {
            let score = value(4, i)
            guard score.isFinite, score >= (contract == .android320 ? 0.45 : 0.5), score <= 1 else { continue }
            let x = value(0,i), y = value(1,i), w = value(2,i), h = value(3,i)
            guard [x,y,w,h].allSatisfy(\.isFinite), w > 0, h > 0 else { continue }
            let a = point(x-w/2,y-h/2), b = point(x+w/2,y+h/2)
            let body = CGRect(x: a.x, y: a.y, width: b.x-a.x, height: b.y-a.y).intersection(unit)
            guard !body.isNull, body.area > 0.00001 else { continue }
            var points: [BirdPoseObservation.Landmark: BirdPoseObservation.Point] = [:]
            for landmark in BirdPoseObservation.Landmark.allCases {
                let row = 5 + landmark.rawValue * 3
                let px = value(row,i), py = value(row+1,i), confidence = value(row+2,i)
                guard px.isFinite, py.isFinite, confidence.isFinite, confidence >= (contract == .android320 ? 0.35 : 0.6), confidence <= 1 else { continue }
                let p = point(px,py)
                guard body.contains(p) else { continue }
                points[landmark] = .init(position: p, confidence: Float(confidence))
            }
            candidates.append(.init(body: body, confidence: Float(score), keypoints: points, timestamp: timestamp,
                                    imageAspect: imageSize.width/imageSize.height))
        }
        var kept: [BirdPoseObservation] = []
        for candidate in candidates.sorted(by: { $0.confidence > $1.confidence }) {
            guard !kept.contains(where: { SubjectTracker.intersectionOverUnion($0.body, candidate.body) > 0.45 }) else { continue }
            kept.append(candidate)
            if kept.count == 20 { break }
        }
        return kept
    }
}

/// The Android square crop is permitted to extend beyond the image; those pixels are gray114.
struct BirdCrop {
    let imageSize: CGSize
    let square: CGRect // source pixels, origin TOP LEFT
    init(imageSize: CGSize, region: CGRect, padding: CGFloat) {
        self.imageSize = imageSize
        let side = max(region.width*imageSize.width, region.height*imageSize.height)*padding
        square = CGRect(x: region.midX*imageSize.width-side/2, y: region.midY*imageSize.height-side/2, width: side, height: side)
    }
    func imagePoint(_ modelPoint: CGPoint) -> CGPoint {
        CGPoint(x: (square.minX+modelPoint.x*square.width)/imageSize.width,
                y: (square.minY+modelPoint.y*square.height)/imageSize.height)
    }
}
