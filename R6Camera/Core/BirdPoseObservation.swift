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

    var detection: SubjectDetection {
        let headPoints = [Landmark.beak, .leftEye, .rightEye, .headTop].compactMap { keypoints[$0]?.position }
        var head: CGRect?
        // A head envelope requires observed beak and crown; never infer from the body.
        if keypoints[.beak] != nil, keypoints[.headTop] != nil,
           let x0 = headPoints.map(\.x).min(), let x1 = headPoints.map(\.x).max(),
           let y0 = headPoints.map(\.y).min(), let y1 = headPoints.map(\.y).max(),
           x1 - x0 > 0.002, y1 - y0 > 0.002 {
            head = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
                .insetBy(dx: -(x1-x0)*0.1, dy: -(y1-y0)*0.1).intersection(body)
        }
        return SubjectDetection(kind: .bird, bounds: body, confidence: confidence,
                                leftEye: keypoints[.leftEye]?.position, rightEye: keypoints[.rightEye]?.position,
                                headBounds: head)
    }
}

/// Pinned synthet six-point contract: [1,23,8400], model pixels, TOP LEFT.
/// The caller supplies strided tensor access, so no ML framework leaks into tracking.
enum BirdPoseDecoder {
    static let checkpointSHA256 = "ec9e4b80a93eb6e2b21633e2ff2df30c49faa1eb7919dd24345c7dc295b2d1be"
    static func decode(imageSize: CGSize, anchors: Int, at timestamp: Double,
                       value: (Int, Int) -> Double) -> [BirdPoseObservation] {
        guard imageSize.width > 0, imageSize.height > 0, anchors == 8400 else { return [] }
        let scale = 640 / max(imageSize.width, imageSize.height)
        let padX = (640 - imageSize.width * scale) / 2
        let padY = (640 - imageSize.height * scale) / 2
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: (CGFloat(x) - padX) / (scale * imageSize.width),
                    y: (CGFloat(y) - padY) / (scale * imageSize.height))
        }
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        var candidates: [BirdPoseObservation] = []
        for i in 0..<anchors {
            let score = value(4, i)
            guard score.isFinite, score >= 0.5, score <= 1 else { continue }
            let x = value(0,i), y = value(1,i), w = value(2,i), h = value(3,i)
            guard [x,y,w,h].allSatisfy(\.isFinite), w > 0, h > 0 else { continue }
            let a = point(x-w/2,y-h/2), b = point(x+w/2,y+h/2)
            let body = CGRect(x: a.x, y: a.y, width: b.x-a.x, height: b.y-a.y).intersection(unit)
            guard !body.isNull, body.area > 0.00001 else { continue }
            var points: [BirdPoseObservation.Landmark: BirdPoseObservation.Point] = [:]
            for landmark in BirdPoseObservation.Landmark.allCases {
                let row = 5 + landmark.rawValue * 3
                let px = value(row,i), py = value(row+1,i), confidence = value(row+2,i)
                guard px.isFinite, py.isFinite, confidence.isFinite, confidence >= 0.6, confidence <= 1 else { continue }
                let p = point(px,py)
                guard body.contains(p) else { continue }
                points[landmark] = .init(position: p, confidence: Float(confidence))
            }
            candidates.append(.init(body: body, confidence: Float(score), keypoints: points, timestamp: timestamp))
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
