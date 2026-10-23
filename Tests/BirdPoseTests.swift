import XCTest
@testable import R6Camera

final class BirdPoseTests: XCTestCase {
    func testAndroid320CropInversionAndSeparateTensorContract() {
        let rows: [Double] = [160,160,160,160,0.9, 185,140,0.9, 150,130,0.9,
                              165,130,0.1, 155,110,0.9, 120,190,0.2, 200,190,0.2]
        let poses = BirdPoseDecoder.decode(imageSize: CGSize(width: 1000, height: 750), anchors: 2100, at: 1,
                                          contract: .android320, region: CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)) { r,i in i == 0 ? rows[r] : 0 }
        XCTAssertEqual(poses.count, 1)
        XCTAssertEqual(poses[0].body.midX, 0.4, accuracy: 0.000001)
        XCTAssertEqual(poses[0].body.midY, 0.4, accuracy: 0.000001)
        XCTAssertNotNil(poses[0].detection.leftEye)
        XCTAssertNil(poses[0].detection.rightEye)
        XCTAssertTrue(BirdPoseDecoder.decode(imageSize: CGSize(width: 640, height: 480), anchors: 8400, at: 1, contract: .android320) { _,_ in 1 }.isEmpty)
        XCTAssertEqual(BirdCrop(imageSize: CGSize(width: 640, height: 480), region: CGRect(x: 0,y: 0,width: 1,height: 1), padding: 1).square.minY, -80)
    }
    func testObservedPairHeadFallbackDoesNotInventInvisibleEye() {
        let body = CGRect(x: 0.1,y: 0.1,width: 0.8,height: 0.8)
        let points: [BirdPoseObservation.Landmark: BirdPoseObservation.Point] = [
            .leftEye: .init(position: CGPoint(x: 0.4,y: 0.3), confidence: 0.5),
            .beak: .init(position: CGPoint(x: 0.5,y: 0.35), confidence: 0.9)]
        let pose = BirdPoseObservation(body: body, confidence: 0.9, keypoints: points, timestamp: 1)
        XCTAssertNil(pose.detection.leftEye)
        XCTAssertNotNil(pose.detection.headBounds)
        let frontal = BirdPoseObservation(body: body, confidence: 0.9, keypoints: [
            .leftEye: .init(position: CGPoint(x: 0.4,y: 0.3), confidence: 0.9),
            .rightEye: .init(position: CGPoint(x: 0.5,y: 0.3), confidence: 0.9)], timestamp: 1)
        XCTAssertNotNil(frontal.detection.headBounds)
    }
    func testStaleFutureNonfiniteAndOutOfOrderFramesNeverOverwriteNewerTracking() {
        var freshness = FrameFreshness()
        XCTAssertTrue(freshness.accept(1, now: 1.1))
        XCTAssertFalse(freshness.accept(0.99, now: 1.1))
        XCTAssertFalse(freshness.accept(1, now: 1.1))
        XCTAssertFalse(freshness.accept(1.2, now: 1.6))
        XCTAssertFalse(freshness.accept(2, now: 1.6))
        XCTAssertFalse(freshness.accept(.nan, now: 1.6))
        XCTAssertTrue(freshness.accept(1.5, now: 1.6))
        XCTAssertEqual(freshness.lastApplied, 1.5)
    }
    func testExpiredInferenceAgesLockWithoutUsingOldBirdOrJumpingToAnother() {
        var tracker = SubjectTracker()
        let bird = SubjectDetection(kind: .bird, bounds: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.4), confidence: 0.9)
        let settings = CameraSettings()
        _ = tracker.update([bird], at: 1, settings: settings)
        tracker.select(at: CGPoint(x: 0.3, y: 0.3))
        let held = tracker.update([], at: 1.3, settings: settings)
        XCTAssertEqual(held.focusAction, .hold)
        let expired = tracker.update([], at: 2, settings: settings)
        XCTAssertFalse(expired.locked)
        XCTAssertNil(expired.selected)
        XCTAssertEqual(expired.focusAction, .scene)
    }
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
