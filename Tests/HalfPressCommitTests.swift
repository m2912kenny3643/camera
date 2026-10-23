#if os(iOS)
import XCTest
import AVFoundation
@testable import R6Camera

final class HalfPressCommitTests: XCTestCase {
    func testHardwareControlHasOnlyOneFixedItem() {
        let queue = DispatchQueue(label: "fixed-control-test")
        queue.sync {
            let control = HardwareShutterControl.make(queue: queue)
            XCTAssertEqual(control.numberOfIndexes, 1)
            XCTAssertEqual(control.selectedIndex, 0)
            XCTAssertEqual(control.localizedIndexTitles, ["對焦／返回"])
            XCTAssertTrue(control.isEnabled)
        }
    }
    @MainActor func testCommitThenImmediatelyQueuedFullClickUsesOriginalEventBoundary() async throws {
        let name = UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let camera = CameraController(store: SettingsStore(defaults: defaults))
        defer { camera.stop() }
        camera.settings.program = .manual; camera.isRunning = true; camera.captureEnabled = false
        camera.publishHardwareControls(true, status: "Unit injection, no hardware proof")
        let supported = expectation(for: NSPredicate { _, _ in camera.hardwareControlsSupported }, evaluatedWith: nil)
        await fulfillment(of: [supported], timeout: 2)
        let draft = CameraEditSession(control: .area, settings: camera.settings)
        draft.draft.focusArea.mode = .flexible2; camera.editorSessions.register(draft)
        let eventTime = CACurrentMediaTime()
        camera.hardwareInput(.controlsActive, at: eventTime)
        XCTAssertEqual(camera.settings.focusArea.mode, .flexible2)
        camera.hardwareInput(.primaryBegan, at: eventTime + 0.000001)
        camera.hardwareInput(.primaryEnded, at: eventTime + 0.000002)
        let request = camera.capturePageReturnRequest
        XCTAssertTrue(camera.hardwareReturningToCapture)
        camera.capturePageDidReturn(request: request)
        let records = try JSONDecoder().decode([HardwareShutterRecord].self, from: Data(camera.hardwareShutterReport.utf8))
        XCTAssertTrue(records.contains { $0.reason == "waiting-for-capture-page" })
        XCTAssertEqual(records.filter { $0.actions.contains("photo") }.count, 1)
        XCTAssertFalse(records.contains { $0.reason == "stale-input-before-reset" })
        XCTAssertFalse(camera.commitEditor(draft.id))
        XCTAssertEqual(camera.hardwareReceiver.receivedEvents, 0)
    }
    @MainActor func testStopRejectsOldHalfPressWithoutConsumingDraftOrLeavingBlueFrame() throws {
        let name = UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let camera = CameraController(store: SettingsStore(defaults: defaults))
        let draft = CameraEditSession(control: .eye, settings: camera.settings)
        draft.draft.eyes = .left; camera.editorSessions.register(draft)
        let old = CACurrentMediaTime(); camera.tracking.areaFocusPoint = CGPoint(x: 0.5, y: 0.5)
        camera.stop(); camera.hardwareInput(.controlsActive, at: old)
        XCTAssertEqual(camera.settings.eyes, .automatic)
        XCTAssertNotNil(camera.editorSessions.take(draft.id))
        XCTAssertNil(camera.tracking.areaFocusPoint)
    }
    @MainActor func testNewDriveAndFocusSettingsUseSameReturnAndReleaseRules() async throws {
        let name = UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        for releaseBeforeReturn in [false, true] {
            let camera = CameraController(store: SettingsStore(defaults: defaults))
            camera.settings = CameraSettings(); camera.isRunning = true; camera.captureEnabled = false
            camera.publishHardwareControls(true, status: "Unit injection, no hardware proof")
            let supported = expectation(for: NSPredicate { _, _ in camera.hardwareControlsSupported }, evaluatedWith: nil)
            await fulfillment(of: [supported], timeout: 2)
            let draft = CameraEditSession(control: .drive, settings: camera.settings)
            draft.draft.drive = .burstLow; camera.editorSessions.register(draft)
            let time = CACurrentMediaTime()
            camera.hardwareInput(.controlsActive, at: time)
            camera.hardwareInput(.primaryBegan, at: time + 0.000001)
            if releaseBeforeReturn { camera.hardwareInput(.primaryEnded) }
            camera.capturePageDidReturn(request: camera.capturePageReturnRequest)
            let records = try JSONDecoder().decode([HardwareShutterRecord].self, from: Data(camera.hardwareShutterReport.utf8))
            XCTAssertEqual(records.filter { $0.actions.contains("beginBurst") }.count, releaseBeforeReturn ? 0 : 1)
            camera.hardwareInput(.primaryEnded)
            camera.hardwareInput(.primaryCancelled)
            XCTAssertFalse(camera.hardwareReturningToCapture)
            camera.stop()
        }
        let camera = CameraController(store: SettingsStore(defaults: defaults))
        let mf = CameraEditSession(control: .manualFocus, settings: camera.settings)
        mf.draft.autofocus = .manual; mf.draft.manualFocus = 0.7; camera.editorSessions.register(mf)
        XCTAssertTrue(camera.commitEditor(mf.id))
        XCTAssertEqual(camera.settings.autofocus, .manual); XCTAssertEqual(camera.settings.manualFocus, 0.7)
        XCTAssertNil(FocusIndicator.resolve(camera.tracking, settings: camera.settings))
        camera.stop()
    }
}
#endif
