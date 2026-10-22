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
        XCTAssertNil(lost.selected)
        XCTAssertFalse(lost.locked)
        XCTAssertEqual(missing.focusAction, .hold)
        XCTAssertEqual(lost.focusAction, .scene)
        let candidate = tracker.update([person(0.7)], at: 2.2, settings: settings)
        XCTAssertFalse(candidate.locked)
        XCTAssertEqual(candidate.focusAction, .scene)
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
    func testAmbiguousCrossingRequiresExplicitReselection() {
        var tracker = SubjectTracker()
        let settings = CameraSettings()
        _ = tracker.update([person(0.1)], at: 0, settings: settings)
        tracker.select(at: CGPoint(x: 0.15, y: 0.3))
        let ambiguous = tracker.update([person(0.09), person(0.11)], at: 0.2, settings: settings)
        XCTAssertTrue(ambiguous.lost)
        XCTAssertNil(ambiguous.selected)
        XCTAssertFalse(ambiguous.locked)
        XCTAssertEqual(ambiguous.focusAction, .scene)
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
    func testCandidatesRequestSceneAFWithoutSubjectFocusPoints() {
        var tracker = SubjectTracker()
        for i in 0..<20 {
            let frame = tracker.update([person(0.1 + CGFloat(i) * 0.01)], at: Double(i) * 0.12, settings: CameraSettings())
            XCTAssertNotNil(frame.selected)
            XCTAssertFalse(frame.locked)
            XCTAssertEqual(frame.focusAction, .scene)
        }
    }
    func testMissedTouchRequestsExactlyOneSingleAF() {
        var tracker = SubjectTracker()
        _ = tracker.update([person(0.1)], at: 0, settings: CameraSettings())
        let point = CGPoint(x: 0.85, y: 0.7)
        tracker.select(at: point)
        XCTAssertEqual(tracker.result.focusAction, .single(point))
        for i in 1...10 {
            let frame = tracker.update([person(0.8)], at: Double(i), settings: CameraSettings())
            XCTAssertEqual(frame.touchPoint, point)
            XCTAssertNil(frame.selected)
            XCTAssertEqual(frame.focusAction, .none)
        }
    }
    func testTouchEnablesSubjectFocusAndUnlockRestoresSceneAF() {
        var tracker = SubjectTracker()
        _ = tracker.update([person(0.1)], at: 0, settings: CameraSettings())
        tracker.select(at: CGPoint(x: 0.15, y: 0.3))
        XCTAssertTrue(tracker.result.locked)
        if case .continuous = tracker.result.focusAction {} else { XCTFail("Touch must enable servo") }
        let moving = tracker.update([person(0.12)], at: 0.1, settings: CameraSettings())
        if case .continuous = moving.focusAction {} else { XCTFail("Locked movement must drive lens") }
        tracker.unlock()
        XCTAssertEqual(tracker.result.focusAction, .scene)
        XCTAssertEqual(tracker.update([person(0.14)], at: 0.2, settings: CameraSettings()).focusAction, .scene)
    }
    func testSceneAFWorksWithoutDetectionsAndMFNeverRequestsAF() {
        var tracker = SubjectTracker()
        var settings = CameraSettings()
        XCTAssertEqual(tracker.update([], at: 0, settings: settings).focusAction, .scene)
        settings.autofocus = .manual
        let manual = tracker.update([person(0.1)], at: 0.1, settings: settings)
        XCTAssertEqual(manual.focusAction, .none)
        XCTAssertNil(manual.selected)
    }
    func testUnlockFromFixedPointRestoresSceneAF() {
        var tracker = SubjectTracker()
        tracker.select(at: CGPoint(x: 0.8, y: 0.8))
        tracker.unlock()
        XCTAssertNil(tracker.result.touchPoint)
        XCTAssertEqual(tracker.result.focusAction, .scene)
    }
    func testEyeHeadBodyFallbackUsesOneRegion() {
        var target = person(0.2)
        let head = CGRect(x: 0.22, y: 0.21, width: 0.08, height: 0.1)
        target.headBounds = head
        XCTAssertEqual(target.focusBounds(.automatic), head)
        target.leftEye = CGPoint(x: 0.24, y: 0.24)
        XCTAssertLessThan(target.focusBounds(.automatic).width, head.width)
        target.leftEye = nil; target.headBounds = nil
        XCTAssertEqual(target.focusBounds(.automatic), target.bounds)
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
    func testLegacyReviewSettingDoesNotBreakPresetDecoding() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(CameraSettings())) as? [String: Any])
        json["reviewSeconds"] = 4
        let decoded = try JSONDecoder().decode(CameraSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded, CameraSettings())
    }
    func testISOAutoDoesNotReleaseManualShutter() {
        var settings = CameraSettings(); settings.program = .manual
        settings.useAutomaticISO()
        XCTAssertFalse(settings.controlsISO)
        XCTAssertTrue(settings.controlsShutter)
    }
    func testHeadObservationMaintainsLockWhenBodyDetectorDropsOut() {
        var tracker = SubjectTracker()
        var full = person(0.2)
        let head = CGRect(x: 0.22, y: 0.21, width: 0.07, height: 0.08)
        full.headBounds = head
        _ = tracker.update([full], at: 0, settings: CameraSettings())
        tracker.select(at: CGPoint(x: 0.25, y: 0.25))
        let identity = tracker.result.selected?.id
        let faceOnly = SubjectDetection(kind: .person, bounds: head, confidence: 0.9, headBounds: head)
        let frame = tracker.update([faceOnly], at: 0.1, settings: CameraSettings())
        XCTAssertTrue(frame.locked)
        XCTAssertFalse(frame.missing)
        XCTAssertEqual(frame.selected?.id, identity)
        if case .continuous = frame.focusAction {} else { XCTFail("Observed head must keep lens tracking") }
    }
    func testShutterAutoDoesNotReleaseManualISO() {
        var settings = CameraSettings(); settings.program = .manual
        settings.useAutomaticShutter()
        XCTAssertFalse(settings.controlsShutter)
        XCTAssertTrue(settings.controlsISO)
    }
    func testOneShotSubjectFocusDoesNotContinuouslyDriveLens() {
        var settings = CameraSettings(); settings.autofocus = .single
        var tracker = SubjectTracker()
        _ = tracker.update([person(0.2)], at: 0, settings: settings)
        tracker.select(at: CGPoint(x: 0.25, y: 0.3), mode: .single)
        if case .single = tracker.result.focusAction {} else { XCTFail("ONE SHOT must focus once") }
        let frame = tracker.update([person(0.21)], at: 0.1, settings: settings)
        XCTAssertTrue(frame.locked)
        XCTAssertEqual(frame.focusAction, .none)
    }
}
