import XCTest

final class CameraUITests: XCTestCase {
    func testLandscapeCameraZoomAndSecondaryMenus() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["R6_UI_TESTING"] = "1"
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
        let wheel = app.otherElements["zoom.wheel"]
        XCTAssertTrue(wheel.waitForExistence(timeout: 3))
        capture("02-Zoom-wheel")
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
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
