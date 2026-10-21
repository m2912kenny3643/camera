import XCTest
@testable import R6Camera

final class SubjectTrackerTests: XCTestCase {
    private func person(_ x: CGFloat) -> SubjectDetection {
        SubjectDetection(kind: .person, bounds: CGRect(x: x, y: 0.2, width: 0.15, height: 0.4), confidence: 0.9)
    }
    func testLockedSubjectDoesNotJumpToBystanderAfterOcclusion() {
        var tracker = SubjectTracker()
        let settings = CameraSettings()
        _ = tracker.update([person(0.1), person(0.7)], at: 0, settings: settings)
        tracker.select(at: CGPoint(x: 0.15, y: 0.3))
        let id = tracker.result.selected?.id
        let missing = tracker.update([person(0.7)], at: 0.4, settings: settings)
        XCTAssertTrue(missing.missing)
        XCTAssertEqual(missing.selected?.id, id)
        let lost = tracker.update([person(0.7)], at: 2, settings: settings)
        XCTAssertTrue(lost.lost)
        XCTAssertEqual(lost.selected?.id, id)
    }
    func testRecoveryWithinGracePeriodKeepsIdentity() {
        var tracker = SubjectTracker()
        let settings = CameraSettings()
        _ = tracker.update([person(0.1)], at: 0, settings: settings)
        tracker.select(at: CGPoint(x: 0.15, y: 0.3))
        let id = tracker.result.selected?.id
        _ = tracker.update([], at: 0.2, settings: settings)
        let recovered = tracker.update([person(0.12)], at: 0.4, settings: settings)
        XCTAssertFalse(recovered.missing)
        XCTAssertEqual(recovered.selected?.id, id)
    }
    func testEyeFallbackUsesOtherActualEye() {
        var subject = person(0.2)
        subject.rightEye = CGPoint(x: 0.25, y: 0.3)
        XCTAssertEqual(subject.eye(.left), subject.rightEye)
        XCTAssertNil(subject.eye(.off))
        subject.rightEye = nil
        XCTAssertEqual(subject.focusPoint(.left), CGPoint(x: subject.bounds.midX, y: subject.bounds.midY))
    }
    func testCategoryFilteringAndDisableClearsLock() {
        var tracker = SubjectTracker()
        var settings = CameraSettings()
        settings.subjects = .animals
        XCTAssertNil(tracker.update([person(0.3)], at: 0, settings: settings).selected)
        settings.subjects = .none
        XCTAssertTrue(tracker.update([person(0.3)], at: 1, settings: settings).candidates.isEmpty)
    }
    func testAspectFillRoundTripInBothOrientations() {
        for size in [CGSize(width: 390, height: 600), CGSize(width: 700, height: 330)] {
            let original = CGPoint(x: 0.4, y: 0.6)
            let display = ViewfinderGeometry.display(original, imageAspect: 0.75, size: size)
            let result = ViewfinderGeometry.normalized(display, imageAspect: 0.75, size: size)
            XCTAssertEqual(result.x, original.x, accuracy: 0.00001)
            XCTAssertEqual(result.y, original.y, accuracy: 0.00001)
        }
    }
    func testCustomPresetRoundTrip() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = SettingsStore(defaults: defaults)
        var settings = CameraSettings()
        settings.subjects = .animals
        settings.eyes = .right
        settings.switchSensitivity = 0.9
        store.save(settings, key: "C1")
        XCTAssertEqual(store.load("C1"), settings)
        XCTAssertNil(store.load("C2"))
    }
}
