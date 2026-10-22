import XCTest

final class CameraUITests: XCTestCase {
    func testLandscapeZoomMenusAndCaptureFeedback() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["R6_UI_TESTING"] = "1"
        app.launchEnvironment["R6_UI_HOLD_ZOOM"] = "1"
        app.launchEnvironment["R6_UI_FEEDBACK_TEST"] = "1"
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let quick = app.buttons["quick.open"]
        XCTAssertTrue(quick.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture("01-Candidate-landscape")
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait, .landscapeRight] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(quick.exists)
            XCTAssertGreaterThan(app.frame.width, app.frame.height)
        }
        app.buttons["zoom.open"].tap()
        let wheel = app.descendants(matching: .any)["zoom.wheel"]
        XCTAssertTrue(wheel.waitForExistence(timeout: 3))
        capture("02-Zoom-wheel")
        let originalZoom = Double(wheel.value as? String ?? "")!
        let start = wheel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let end = wheel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertGreaterThan(Double(wheel.value as? String ?? "")!, originalZoom)
        end.press(forDuration: 0.05, thenDragTo: start)
        XCTAssertLessThanOrEqual(Double(wheel.value as? String ?? "")!, originalZoom + 0.2)
        // Close by tapping the scene, away from the wheel and controls.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.45)).tap()
        quick.tap()
        XCTAssertTrue(app.buttons["quick.eye"].waitForExistence(timeout: 5))
        app.buttons["quick.eye"].tap()
        XCTAssertTrue(app.buttons["option.左眼優先"].waitForExistence(timeout: 5))
        capture("03-Q-Eye-options")
        app.buttons["option.右眼優先"].tap()
        app.buttons["editor.confirm"].tap()
        app.buttons["白平衡"].tap()
        XCTAssertTrue(app.buttons["option.日光"].waitForExistence(timeout: 5))
        capture("04-WB-palette")
        app.buttons["editor.confirm"].tap()
        app.buttons["MENU"].tap()
        XCTAssertTrue(app.buttons["menu.tab.1"].waitForExistence(timeout: 5))
        app.buttons["menu.tab.1"].tap()
        XCTAssertTrue(app.buttons["menu.要偵測的主體"].waitForExistence(timeout: 5))
        capture("05-MENU-AF")
        app.buttons["menu.眼睛偵測"].tap()
        XCTAssertTrue(app.buttons["option.關閉"].waitForExistence(timeout: 5))
        capture("06-MENU-eye-secondary")
        app.buttons["editor.confirm"].tap()
        app.buttons["menu.close"].tap()
        XCTAssertTrue(quick.waitForExistence(timeout: 5))
        // Center of synthetic subject vs blank scene: UI must expose unlock only after touch.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.45)).tap()
        XCTAssertTrue(app.buttons["focus.unlock"].waitForExistence(timeout: 5))
        capture("07-Touched-subject-blue")
        app.buttons["focus.unlock"].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.6)).tap()
        XCTAssertTrue(app.buttons["focus.unlock"].waitForExistence(timeout: 5))
        capture("08-Touch-point-single")
        verifyCaptureFeedbackLeavesLiveViewUncovered(app)
    }
    private func verifyCaptureFeedbackLeavesLiveViewUncovered(_ app: XCUIApplication) {
        let trigger = app.buttons["fixture.capture"]
        XCTAssertTrue(trigger.waitForExistence(timeout: 10))
        let viewfinder = app.descendants(matching: .any)["camera.viewfinder"]
        for count in 1...3 {
            trigger.tap()
            XCTAssertEqual(trigger.value as? String, String(count))
        }
        let returned = NSPredicate(format: "value == %@", "即時取景")
        expectation(for: returned, evaluatedWith: viewfinder)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(app.buttons["quick.open"].exists)
        app.buttons["MENU"].tap()
        app.buttons["menu.tab.2"].tap()
        XCTAssertFalse(app.buttons["menu.拍後檢視"].exists)
        app.buttons["menu.close"].tap()
        XCTAssertEqual(trigger.value as? String, "3")
        XCTAssertEqual(viewfinder.value as? String, "即時取景")
        capture("09-Live-view-after-capture-feedback")
    }
    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        // Also preserve PNGs outside xcresult: a crashed test runner may never finalize its result bundle.
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("R6CameraScreenshots")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: directory.appendingPathComponent(name).appendingPathExtension("png"), options: .atomic)
        } catch { XCTFail("Could not preserve screenshot: \(error)") }
    }
}
