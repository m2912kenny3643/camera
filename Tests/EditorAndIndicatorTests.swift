import XCTest
@testable import R6Camera

final class EditorAndIndicatorTests: XCTestCase {
    func testOnlyLatestVisibleEditorCanCommitOnceAndPreservesOtherSettings() throws {
        let registry = CameraEditorRegistry()
        let old = CameraEditSession(control: .eye, settings: CameraSettings())
        registry.register(old); old.draft.eyes = .right
        let current = CameraEditSession(control: .area, settings: CameraSettings())
        registry.register(current); current.draft.focusArea.mode = .flexible2
        XCTAssertFalse(registry.cancel(old.id), "An old Back callback must not close the current editor")
        XCTAssertNil(registry.take(old.id))
        let commit = try XCTUnwrap(registry.take(current.id))
        var live = CameraSettings(); live.zoom = 2.5; live.eyes = .left
        commit.control.apply(commit.draft, to: &live)
        XCTAssertEqual(live.focusArea.mode, .flexible2)
        XCTAssertEqual(live.eyes, .left); XCTAssertEqual(live.zoom, 2.5)
        XCTAssertNil(registry.take(current.id))
        registry.register(old); XCTAssertNil(registry.take(), "A replaced editor cannot re-register")
    }
    func testBackCancelsAndTheLatestDraftIncludesSliderAndGeometryEdits() throws {
        let registry = CameraEditorRegistry()
        let session = CameraEditSession(control: .area, settings: CameraSettings())
        registry.register(session)
        session.draft.focusArea.mode = .flexible3
        session.draft.focusArea.resize(width: 0.55, height: 0.3)
        session.draft.focusArea.move(to: CGPoint(x: 0.7, y: 0.4))
        let commit = try XCTUnwrap(registry.take())
        XCTAssertEqual(commit.draft.focusArea, session.draft.focusArea)
        let cancelled = CameraEditSession(control: .iso, settings: CameraSettings())
        registry.register(cancelled); registry.cancel(cancelled.id)
        XCTAssertNil(registry.take()); registry.register(cancelled); XCTAssertNil(registry.take())
    }
    func testSevenAreaModesShowCenterCommandOnlyAfterAcquisition() {
        for mode in FocusAreaMode.allCases where mode != .whole {
            for af in [AutofocusMode.single, .servo] {
                var settings = CameraSettings(); settings.focusArea.mode = mode; settings.autofocus = af
                settings.focusArea.move(to: CGPoint(x: 0.65, y: 0.4))
                var tracker = SubjectTracker()
                XCTAssertNil(FocusIndicator.resolve(tracker.result, settings: settings))
                tracker.acquire(settings: settings, at: 1)
                XCTAssertEqual(FocusIndicator.resolve(tracker.result, settings: settings), .point(settings.focusArea.center))
                XCTAssertEqual(tracker.result.focusAction, af == .single ? .single(settings.focusArea.center) : .continuous(settings.focusArea.center))
                tracker.unlock(); XCTAssertNil(FocusIndicator.resolve(tracker.result, settings: settings))
            }
        }
    }
    func testSubjectSelectionWinsAndMFAndWholeAreaKeepTheirDisplayPolicy() {
        var settings = CameraSettings(); settings.focusArea.mode = .flexible1
        var tracker = SubjectTracker()
        let target = SubjectDetection(kind: .person, bounds: CGRect(x: 0.45, y: 0.4, width: 0.1, height: 0.2), confidence: 0.9)
        _ = tracker.update([target], at: 1, settings: settings)
        tracker.acquire(settings: settings, at: 1)
        XCTAssertEqual(FocusIndicator.resolve(tracker.result, settings: settings), .subject(target.bounds, selected: true))
        settings.autofocus = .manual
        XCTAssertNil(FocusIndicator.resolve(tracker.result, settings: settings))
        settings = CameraSettings(); tracker.reset(); tracker.acquire(settings: settings, at: 1)
        XCTAssertNil(FocusIndicator.resolve(tracker.result, settings: settings), "Whole-area fallback display is unchanged")
    }
}
