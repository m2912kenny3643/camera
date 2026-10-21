import XCTest

final class CameraUITests: XCTestCase {
    func testQControlsAndMenuInBothOrientations() {
        let app = XCUIApplication()
        app.launchEnvironment["R6_UI_TESTING"] = "1"
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let quick = app.buttons["quick.open"]
        XCTAssertTrue(quick.waitForExistence(timeout: 10))
        quick.tap()
        XCTAssertTrue(app.buttons["quick.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quick.eye"].exists)
        capture("Q-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["quick.close"].waitForExistence(timeout: 5))
        capture("Q-landscape")
        app.buttons["quick.close"].tap()
        app.buttons["MENU"].tap()
        XCTAssertTrue(app.buttons["AF"].waitForExistence(timeout: 5))
        app.buttons["AF"].tap()
        capture("MENU-AF-landscape")
        XCUIDevice.shared.orientation = .portrait
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
