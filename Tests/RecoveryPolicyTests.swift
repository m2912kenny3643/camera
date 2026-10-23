import XCTest
@testable import R6Camera

final class RecoveryPolicyTests: XCTestCase {
    func testLatePermissionAndOldStartsCannotSurviveStopOrNewStart() throws {
        let intent = SessionLifecycle()
        let old = try XCTUnwrap(intent.begin(active: true))
        XCTAssertTrue(intent.permits(old))
        intent.invalidate()
        XCTAssertFalse(intent.permits(old))
        let new = try XCTUnwrap(intent.begin(active: true))
        XCTAssertFalse(intent.permits(old)); XCTAssertTrue(intent.permits(new))
        XCTAssertNil(intent.begin(active: false)); XCTAssertFalse(intent.permits(new))
    }
    func testBirdLoadAndRuntimeFailuresUseBodyFallbackNextFrame() {
        XCTAssertFalse(DetectionPolicy.needsBodyModel(subjects: .birds, birdAvailable: true))
        XCTAssertTrue(DetectionPolicy.needsBodyModel(subjects: .birds, birdAvailable: false))
        XCTAssertTrue(DetectionPolicy.needsBodyModel(subjects: .automatic, birdAvailable: true))
        XCTAssertFalse(DetectionPolicy.needsBodyModel(subjects: .none, birdAvailable: false))
        XCTAssertTrue(DetectionPolicy.birdFailure("failure", bodyAvailable: true).contains("一般身體辨識"))
        XCTAssertTrue(DetectionPolicy.birdFailure("failure", bodyAvailable: false).contains("不可用"))
    }
}
