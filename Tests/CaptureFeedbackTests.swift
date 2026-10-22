import XCTest
@testable import R6Camera

final class CaptureFeedbackTests: XCTestCase {
    func testExposurePulseHoldsThenFadesWithoutAReviewImage() {
        var feedback = CaptureFeedback()
        XCTAssertEqual(feedback.opacity(at: 0), 0)
        XCTAssertTrue(feedback.begin(event: 1, at: 10))
        XCTAssertTrue(feedback.isActive)
        XCTAssertEqual(feedback.opacity(at: 10), 1)
        XCTAssertEqual(feedback.opacity(at: 10.12), 1, accuracy: 0.00001)
        XCTAssertEqual(feedback.opacity(at: 10.16), 0.5, accuracy: 0.00001)
        XCTAssertEqual(feedback.opacity(at: 10.2), 0, accuracy: 0.00001)
        feedback.finish(event: 1)
        XCTAssertFalse(feedback.isActive)
    }
    func testBurstRestartsPulseAndOldCompletionCannotClearNewExposure() {
        var feedback = CaptureFeedback()
        _ = feedback.begin(event: 1, at: 0)
        _ = feedback.begin(event: 2, at: 0.15)
        feedback.finish(event: 1)
        XCTAssertTrue(feedback.isActive)
        XCTAssertEqual(feedback.opacity(at: 0.2), 1)
        feedback.finish(event: 2)
        XCTAssertFalse(feedback.isActive)
    }
    func testReturningFromMenuCannotReplayConsumedExposure() {
        var feedback = CaptureFeedback()
        _ = feedback.begin(event: 1, at: 0)
        feedback.cancel()
        XCTAssertFalse(feedback.begin(event: 1, at: 2))
        XCTAssertEqual(feedback.opacity(at: 2), 0)
        XCTAssertTrue(feedback.begin(event: 2, at: 3))
        XCTAssertEqual(feedback.opacity(at: 3), 1)
    }
}
