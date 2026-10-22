import XCTest
@testable import R6Camera

final class BirdPoseTests: XCTestCase {
    func testActualPointsHeadAndBodyFallbackWithoutInventedEyes() {
        let body = CGRect(x: 0.1, y: 0.1, width: 0.7, height: 0.8)
        let head: [BirdPoseObservation.Landmark: BirdPoseObservation.Point] = [
            .beak: .init(position: CGPoint(x: 0.6, y: 0.35), confidence: 0.9),
            .headTop: .init(position: CGPoint(x: 0.4, y: 0.2), confidence: 0.9)]
        var pose = BirdPoseObservation(body: body, confidence: 0.9, keypoints: head, timestamp: 0)
        XCTAssertNotNil(pose.detection.headBounds)
        XCTAssertNil(pose.detection.eye(.automatic))
        var eye = head; eye[.leftEye] = .init(position: CGPoint(x: 0.45, y: 0.28), confidence: 0.9)
        pose = .init(body: body, confidence: 0.9, keypoints: eye, timestamp: 0)
        XCTAssertLessThan(pose.detection.focusBounds(.automatic).area, pose.detection.headBounds!.area)
        pose = .init(body: body, confidence: 0.9, keypoints: [:], timestamp: 0)
        XCTAssertEqual(pose.detection.focusBounds(.automatic), body)
    }
    func testLetterboxInversionAndLowConfidenceRejection() {
        // 1280x720 -> 640x360 + 140px top/bottom padding.
        let rows: [Double] = [320,320,320,180,0.9, 400,290,0.9, 300,280,0.9,
                              340,280,0.1, 310,250,0.9, 240,340,0.2, 390,340,0.2]
        let observations = BirdPoseDecoder.decode(imageSize: CGSize(width: 1280, height: 720), anchors: 8400, at: 1) { row, index in
            index == 0 ? rows[row] : 0
        }
        XCTAssertEqual(observations.count, 1)
        let pose = observations[0]
        XCTAssertEqual(pose.body.minX, 0.25, accuracy: 0.00001)
        XCTAssertEqual(pose.body.minY, 0.25, accuracy: 0.00001)
        XCTAssertEqual(pose.keypoints[.leftEye]?.position.x ?? 0, 300.0/640, accuracy: 0.00001)
        XCTAssertNil(pose.keypoints[.rightEye])
        XCTAssertEqual(pose.timestamp, 1)
    }
    func testNonfiniteAndWrongTensorContractReturnNoBird() {
        XCTAssertTrue(BirdPoseDecoder.decode(imageSize: CGSize(width: 640, height: 640), anchors: 8400, at: 0) { _,_ in .nan }.isEmpty)
        XCTAssertTrue(BirdPoseDecoder.decode(imageSize: CGSize(width: 640, height: 640), anchors: 23, at: 0) { _,_ in 1 }.isEmpty)
    }
    func testBirdLockSurvivesEyeHeadBodyDetailChanges() {
        let body = CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.4)
        var bird = SubjectDetection(kind: .bird, bounds: body, confidence: 0.9,
                                   leftEye: CGPoint(x: 0.3, y: 0.25), headBounds: CGRect(x: 0.25, y: 0.21, width: 0.1, height: 0.1))
        var tracker = SubjectTracker()
        _ = tracker.update([bird], at: 0, settings: CameraSettings())
        tracker.select(at: CGPoint(x: 0.3, y: 0.3))
        let id = tracker.result.selected?.id
        bird.leftEye = nil
        XCTAssertEqual(tracker.update([bird], at: 0.1, settings: CameraSettings()).selected?.id, id)
        bird.headBounds = nil
        let result = tracker.update([bird], at: 0.2, settings: CameraSettings())
        XCTAssertEqual(result.selected?.id, id)
        XCTAssertEqual(result.selected?.focusBounds(.automatic), body)
    }
}
