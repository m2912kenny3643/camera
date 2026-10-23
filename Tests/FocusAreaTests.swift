import XCTest
@testable import R6Camera

final class FocusAreaTests: XCTestCase {
    func testEightRegionsAndExpansionCenterPriority() {
        XCTAssertEqual(FocusAreaMode.allCases.count, 8)
        var area = FocusArea(); area.mode = .expanded
        XCTAssertEqual(area.cells.count, 5)
        XCTAssertEqual(area.acquisitionRank(area.center), 0)
        XCTAssertFalse(area.contains(CGPoint(x: area.bounds.minX + 0.001, y: area.bounds.minY + 0.001)))
        area.mode = .surround
        XCTAssertEqual(area.cells.count, 9)
        XCTAssertTrue(area.contains(CGPoint(x: area.bounds.minX + 0.001, y: area.bounds.minY + 0.001)))
        area.mode = .spot; let spot = area.bounds
        area.mode = .point
        XCTAssertLessThan(spot.width, area.bounds.width)
    }
    func testMoveResizeClampAndIndependentZoneMemory() {
        var area = FocusArea(); area.mode = .flexible1
        area.resize(width: 0.4, height: 0.5); area.move(to: CGPoint(x: 3, y: -4))
        let first = area.bounds
        XCTAssertEqual(first.maxX, 1, accuracy: 0.00001)
        XCTAssertEqual(first.minY, 0, accuracy: 0.00001)
        area.mode = .flexible2; XCTAssertNotEqual(area.bounds, first)
        XCTAssertGreaterThan(area.bounds.height, area.bounds.width)
        area.mode = .flexible3; XCTAssertGreaterThan(area.bounds.width, area.bounds.height)
        area.mode = .flexible1; XCTAssertEqual(area.bounds, first)
        area.resetShape(); XCTAssertEqual(area.center, CGPoint(x: 0.5, y: 0.5))
        area.resize(width: 3, height: 4); XCTAssertEqual(area.bounds.size, CGSize(width: 1, height: 1))
        area.move(to: CGPoint(x: CGFloat.nan, y: 0)); XCTAssertTrue(area.center.x.isFinite)
    }
    func testDefaultsExplicitOptOutLegacyAndPresetRoundTrip() throws {
        XCTAssertTrue(CameraSettings().experimentalHardwareShutter)
        var s = CameraSettings(); s.experimentalHardwareShutter = false
        s.focusArea.mode = .flexible2; s.focusArea.move(to: CGPoint(x: 0.6, y: 0.5))
        s.focusArea.wholeAreaTracking = false
        let decoded = try JSONDecoder().decode(CameraSettings.self, from: JSONEncoder().encode(s))
        XCTAssertFalse(decoded.experimentalHardwareShutter)
        XCTAssertEqual(decoded.focusArea, s.focusArea)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
        json.removeValue(forKey: "storedExperimentalHardwareShutter"); json.removeValue(forKey: "storedFocusArea")
        let legacy = try JSONDecoder().decode(CameraSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(legacy.experimentalHardwareShutter); XCTAssertEqual(legacy.focusArea, FocusArea())
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = SettingsStore(defaults: defaults)
        for key in ["camera.current", "C1", "C2", "C3"] { store.save(s, key: key); XCTAssertEqual(store.load(key), s) }
        s.program = .auto
        XCTAssertEqual(s.effective.focusArea.mode, .whole)
        XCTAssertEqual(s.focusArea.mode, .flexible2)
    }
    private func subject(_ point: CGPoint, confidence: Float = 0.9) -> SubjectDetection {
        SubjectDetection(kind: .person, bounds: CGRect(x: point.x - 0.02, y: point.y - 0.02, width: 0.04, height: 0.04), confidence: confidence)
    }
    func testAcquisitionUsesAreaCenterPriorityAndEmptyFallback() {
        var s = CameraSettings(); s.focusArea.mode = .expanded
        var tracker = SubjectTracker()
        _ = tracker.update([subject(CGPoint(x: 0.5, y: 0.5), confidence: 0.4), subject(CGPoint(x: 0.55, y: 0.5)), subject(CGPoint(x: 0.8, y: 0.8))], at: 1, settings: s)
        tracker.acquire(settings: s, at: 1)
        XCTAssertTrue(tracker.result.locked)
        XCTAssertEqual(tracker.result.selected?.bounds.midX, 0.5)
        tracker.reset(); tracker.acquire(settings: s, at: 1)
        XCTAssertEqual(tracker.result.focusAction, .continuous(s.focusArea.center))
        s.autofocus = .single; tracker.reset(); tracker.acquire(settings: s, at: 1)
        XCTAssertEqual(tracker.result.focusAction, .single(s.focusArea.center))
        s.autofocus = .manual; tracker.acquire(settings: s, at: 1)
        XCTAssertEqual(tracker.result.focusAction, .none)
    }
    func testOutsideTouchRejectedAndTrackingSwitchControlsRegionExit() {
        for whole in [false, true] {
            var s = CameraSettings(); s.focusArea.mode = .flexible1; s.focusArea.wholeAreaTracking = whole
            var tracker = SubjectTracker()
            _ = tracker.update([subject(CGPoint(x: 0.64, y: 0.5))], at: 0, settings: s)
            tracker.select(at: CGPoint(x: 0.9, y: 0.9), area: s.focusArea)
            XCTAssertFalse(tracker.result.locked); XCTAssertNil(tracker.result.touchPoint)
            tracker.acquire(settings: s, at: 0)
            XCTAssertTrue(tracker.result.locked)
            let outside = subject(CGPoint(x: 0.67, y: 0.5))
            let result = tracker.update([outside], at: 0.1, settings: s)
            XCTAssertEqual(result.missing, !whole)
            if !whole {
                XCTAssertEqual(result.focusAction, .hold)
                let lost = tracker.update([outside], at: 2, settings: s)
                XCTAssertTrue(lost.lost); XCTAssertNil(lost.selected)
            }
        }
    }
    func testStaleAcquisitionFallsBackWithoutInventingAnObservationOrTouch() {
        var s = CameraSettings(); s.focusArea.mode = .flexible1
        var tracker = SubjectTracker()
        _ = tracker.update([subject(CGPoint(x: 0.5, y: 0.5))], at: 1, settings: s)
        tracker.acquire(settings: s, at: 2)
        XCTAssertFalse(tracker.result.locked); XCTAssertTrue(tracker.result.candidates.isEmpty)
        XCTAssertNil(tracker.result.observedAt); XCTAssertNil(tracker.result.touchPoint)
        XCTAssertEqual(tracker.result.areaFocusPoint, s.focusArea.center)
        XCTAssertEqual(tracker.result.focusAction, .continuous(s.focusArea.center))
        tracker.acquire(settings: s, at: 3)
        XCTAssertEqual(tracker.result.focusAction, .continuous(s.focusArea.center))
    }
    func testNewTouchCannotAcquireOutsideTargetAfterWholeAreaContinuation() {
        var s = CameraSettings(); s.focusArea.mode = .flexible1
        var tracker = SubjectTracker()
        _ = tracker.update([subject(CGPoint(x: 0.64, y: 0.5))], at: 0, settings: s)
        tracker.acquire(settings: s, at: 0)
        var outside = subject(CGPoint(x: 0.67, y: 0.5))
        outside.bounds = CGRect(x: 0.60, y: 0.4, width: 0.14, height: 0.2)
        _ = tracker.update([outside], at: 0.1, settings: s)
        tracker.select(at: CGPoint(x: 0.62, y: 0.5), area: s.focusArea)
        XCTAssertFalse(tracker.result.locked)
        XCTAssertEqual(tracker.result.touchPoint, CGPoint(x: 0.62, y: 0.5))
    }
    func testNewSelectionEpochCanReuseFreshObservationButNeverExpiredOne() {
        var gate = VisionFrameGate()
        var frame = TrackingResult(); frame.epoch = 1; frame.observedAt = 1
        XCTAssertTrue(gate.accept(frame, currentEpoch: 1, now: 1.01))
        frame.epoch = 2; frame.observedAt = 1.02
        XCTAssertTrue(gate.accept(frame, currentEpoch: 2, now: 1.03))
        var selection = frame; selection.epoch = 3
        XCTAssertTrue(gate.accept(selection, currentEpoch: 3, now: 1.04))
        XCTAssertFalse(gate.accept(frame, currentEpoch: 3, now: 1.04))
        selection.epoch = 4
        XCTAssertFalse(gate.accept(selection, currentEpoch: 4, now: 1.3))
    }
    func testAreaAndPolicyChangeInvalidateConfiguration() {
        var s = CameraSettings(); let initial = FocusConfiguration(s)
        s.focusArea.mode = .point; XCTAssertNotEqual(initial, FocusConfiguration(s))
        let point = FocusConfiguration(s)
        s.focusArea.move(to: CGPoint(x: 0.7, y: 0.5)); XCTAssertNotEqual(point, FocusConfiguration(s))
        let moved = FocusConfiguration(s)
        s.focusArea.wholeAreaTracking = false; XCTAssertNotEqual(moved, FocusConfiguration(s))
    }
}
