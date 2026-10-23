import XCTest

final class CameraUITests: XCTestCase {
    func testEightFocusAreasDraftSizingMovementAndProgramOverride() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment["R6_UI_TESTING"] = "1"; app.launch()
        let area = app.buttons["hud.area"]
        XCTAssertTrue(area.waitForExistence(timeout: 10))
        XCTAssertEqual(area.value as? String, "全區域自動對焦")
        area.tap()
        let names = ["重點自動對焦", "單點自動對焦", "擴展自動對焦區域：四點", "擴展自動對焦區域：環繞", "彈性區域自動對焦1", "彈性區域自動對焦2", "彈性區域自動對焦3", "全區域自動對焦"]
        for name in names { XCTAssertTrue(app.buttons["option.\(name)"].exists) }
        app.buttons["option.彈性區域自動對焦2"].tap()
        XCTAssertTrue(app.sliders["area.width"].exists)
        app.sliders["area.width"].adjust(toNormalizedSliderPosition: 0.4)
        app.buttons["editor.back"].tap()
        XCTAssertEqual(area.value as? String, "全區域自動對焦")
        area.tap(); app.buttons["option.彈性區域自動對焦2"].tap()
        app.sliders["area.width"].adjust(toNormalizedSliderPosition: 0.4)
        app.buttons["editor.confirm"].tap()
        XCTAssertEqual(area.value as? String, "彈性區域自動對焦2")
        capture("10-Flexible-area-applied")
        let frame = app.descendants(matching: .any)["focus.areaFrame"]
        XCTAssertTrue(frame.exists)
        let before = frame.value as? String
        let photo = app.descendants(matching: .any)["camera.viewfinder"]
        let center = photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.15, thenDragTo: photo.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)))
        XCTAssertNotEqual(frame.value as? String, before)
        capture("11-Flexible-area-moved")
        app.buttons["hud.mode"].tap(); app.buttons["option.A+"].tap(); app.buttons["editor.confirm"].tap()
        XCTAssertEqual(area.value as? String, "全區域自動對焦")
        app.buttons["hud.mode"].tap(); app.buttons["option.M"].tap(); app.buttons["editor.confirm"].tap()
        XCTAssertEqual(area.value as? String, "彈性區域自動對焦2")
        app.buttons["MENU"].tap(); app.buttons["menu.tab.1"].tap()
        app.buttons["menu.自動對焦區域"].tap()
        XCTAssertTrue(app.switches["area.wholeTracking"].exists)
        capture("12-MENU-eight-focus-areas")
        app.buttons["editor.back"].tap(); app.buttons["menu.close"].tap()
    }
    func testHardwareLightPressReturnsFromQuickMenuNestedPageAndPlayback() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["R6_UI_TESTING"] = "1"
        app.launchEnvironment["R6_UI_FEEDBACK_TEST"] = "1"
        app.launchEnvironment["R6_UI_HARDWARE_RETURN_TEST"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["quick.open"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["fixture.hardwareReturn"].frame.intersects(app.buttons["quick.open"].frame))
        XCTAssertEqual(app.buttons["fixture.capture"].value as? String, "0")
        var returnedShots = 0
        func lightPressAndImmediateFullPress() {
            let triggers = app.buttons.matching(identifier: "fixture.hardwareReturn").allElementsBoundByIndex
            guard let trigger = triggers.first(where: { $0.isHittable }) else { XCTFail("Missing visible hardware injection"); return }
            XCTAssertEqual(trigger.value as? String, "window-enabled", "Actual window receiver must remain attached and enabled before injection")
            trigger.tap()
            returnedShots += 1
            let feedback = app.buttons["fixture.capture"]
            let returned = NSPredicate(format: "value == %@", String(returnedShots))
            expectation(for: returned, evaluatedWith: feedback)
            waitForExpectations(timeout: 8)
            XCTAssertTrue(app.buttons["quick.open"].isHittable)
            XCTAssertFalse(app.buttons["menu.close"].exists)
            XCTAssertFalse(app.buttons["editor.confirm"].exists)
            XCTAssertFalse(app.buttons["gallery.close"].exists)
        }
        app.buttons["quick.open"].tap()
        XCTAssertTrue(app.buttons["quick.eye"].waitForExistence(timeout: 5))
        app.buttons["quick.eye"].tap()
        app.buttons["option.右眼優先"].tap() // The unconfirmed draft must be discarded.
        lightPressAndImmediateFullPress()
        app.buttons["quick.open"].tap(); app.buttons["quick.eye"].tap()
        XCTAssertEqual(app.buttons["option.自動"].value as? String, "已選取")
        lightPressAndImmediateFullPress()
        app.buttons["MENU"].tap(); app.buttons["menu.tab.1"].tap()
        app.buttons["menu.眼睛偵測"].tap()
        lightPressAndImmediateFullPress()
        app.buttons["MENU"].tap(); app.buttons["menu.tab.1"].tap()
        app.buttons["bird.test.open"].tap()
        XCTAssertTrue(app.buttons["bird.test.close"].waitForExistence(timeout: 5))
        lightPressAndImmediateFullPress()
        XCTAssertFalse(app.buttons["bird.test.close"].exists)
        app.buttons["gallery.open"].tap()
        XCTAssertTrue(app.buttons["gallery.close"].waitForExistence(timeout: 5))
        lightPressAndImmediateFullPress()
        app.buttons["zoom.open"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["zoom.wheel"].waitForExistence(timeout: 5))
        lightPressAndImmediateFullPress()
        XCTAssertFalse(app.descendants(matching: .any)["zoom.wheel"].exists)
        capture("Hardware-return-to-shooting-page")
    }
    func testExperimentalHardwareShutterDefaultsOffAndCanBeRestored() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["R6_UI_TESTING"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["MENU"].waitForExistence(timeout: 10))
        app.buttons["MENU"].tap()
        app.buttons["menu.tab.3"].tap()
        let setting = app.buttons["hardwareShutter.experimental"]
        XCTAssertTrue(setting.waitForExistence(timeout: 5))
        XCTAssertEqual(setting.value as? String, "關閉")
        setting.tap()
        XCTAssertEqual(setting.value as? String, "開啟")
        XCTAssertTrue(app.buttons["hardwareShutter.shareReport"].exists)
        capture("Hardware-shutter-experimental-settings")
        setting.tap()
        XCTAssertEqual(setting.value as? String, "關閉")
        app.buttons["menu.close"].tap()
        XCTAssertTrue(app.buttons["MENU"].waitForExistence(timeout: 5))
    }
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
        let viewfinder = app.descendants(matching: .any)["camera.viewfinder"]
        XCTAssertEqual(viewfinder.frame.width / viewfinder.frame.height, 4.0 / 3, accuracy: 0.01)
        XCTAssertGreaterThan(viewfinder.frame.minX, app.frame.minX + 40)
        XCTAssertLessThan(viewfinder.frame.maxX, app.frame.maxX - 40)
        let leftBlank = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: viewfinder.frame.minX - app.frame.minX - 5, dy: viewfinder.frame.midY - app.frame.minY))
        leftBlank.tap()
        XCTAssertFalse(app.buttons["focus.unlock"].exists)
        capture("01-Candidate-landscape")
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait, .landscapeRight] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(quick.exists)
            XCTAssertGreaterThan(app.frame.width, app.frame.height)
        }
        app.buttons["zoom.open"].tap()
        let wheel = app.descendants(matching: .any)["zoom.wheel"]
        XCTAssertTrue(wheel.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(wheel.frame.minX, viewfinder.frame.maxX - 1)
        XCTAssertGreaterThanOrEqual(wheel.frame.minY, quick.frame.maxY)
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
        capture("03-Q-live-palette")
        XCTAssertEqual(viewfinder.frame.width / viewfinder.frame.height, 4.0 / 3, accuracy: 0.01)
        app.buttons["quick.eye"].tap()
        XCTAssertTrue(app.buttons["option.左眼優先"].waitForExistence(timeout: 5))
        capture("03-Q-Eye-options")
        app.buttons["option.右眼優先"].tap()
        // A pending choice must not survive Back.
        app.buttons["editor.back"].tap()
        quick.tap(); app.buttons["quick.eye"].tap()
        XCTAssertEqual(app.buttons["option.自動"].value as? String, "已選取")
        app.buttons["option.右眼優先"].tap()
        app.buttons["editor.confirm"].tap()
        app.buttons["hud.af"].tap()
        XCTAssertTrue(app.buttons["option.ONE SHOT"].exists)
        capture("04-AF-operation")
        app.buttons["editor.back"].tap()
        verifyDriveAndExposureEditors(app)
        app.buttons["hud.format"].tap()
        app.buttons["option.JPEG"].tap()
        capture("09-Quality-two-groups")
        app.buttons["editor.confirm"].tap()
        XCTAssertEqual(app.buttons["hud.format"].value as? String, "JPEG")
        app.buttons["白平衡"].tap()
        XCTAssertTrue(app.buttons["option.日光"].waitForExistence(timeout: 5))
        capture("04-WB-palette")
        app.buttons["option.日光"].tap()
        app.buttons["editor.confirm"].tap()
        verifyLevelDisplay(app)
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
        verifyProgramRestrictionsPreserveWhiteBalance(app)
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
    func testActualBundledBirdFunctionalScreens() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment["R6_UI_TESTING"] = "1"; app.launch()
        XCTAssertTrue(app.buttons["MENU"].waitForExistence(timeout: 10)); app.buttons["MENU"].tap()
        app.buttons["menu.tab.1"].tap()
        let open = app.buttons["bird.test.open"]
        if !open.isHittable { app.swipeUp() }
        XCTAssertTrue(open.waitForExistence(timeout: 5)); open.tap()
        let state = app.staticTexts["bird.test.status"]
        for (sample, expected) in [("eagle","眼睛"),("head","頭部"),("body","身體"),("frontal","眼睛"),("distant","未辨識"),("background","未辨識")] {
            let button = app.buttons["bird.test.case.\(sample)"]
            let ready = NSPredicate(format: "enabled == true")
            expectation(for: ready, evaluatedWith: button); waitForExpectations(timeout: 30)
            button.tap()
            let complete = NSPredicate(format: "value == %@", expected)
            expectation(for: complete, evaluatedWith: state); waitForExpectations(timeout: 30)
            capture("Bird-\(sample)-actual-ONNX")
        }
        app.buttons["bird.test.close"].tap()
        XCTAssertTrue(app.buttons["menu.close"].waitForExistence(timeout: 5))
    }
    private func verifyDriveAndExposureEditors(_ app: XCUIApplication) {
        let drive = app.buttons["hud.drive"]
        drive.tap()
        app.buttons["option.高速連拍 H+"].tap()
        XCTAssertTrue(app.staticTexts["drive.calibrationHint"].exists)
        capture("05-Drive-Hplus-pending")
        app.buttons["editor.confirm"].tap()
        XCTAssertEqual(drive.value as? String, "高速連拍 H+")
        drive.tap()
        XCTAssertTrue(app.staticTexts["drive.calibrationHint"].exists)
        app.buttons["option.高速連拍 H"].tap()
        app.buttons["editor.back"].tap()
        XCTAssertEqual(drive.value as? String, "高速連拍 H+")
        drive.tap()
        XCTAssertTrue(app.staticTexts["drive.calibrationHint"].exists)
        XCTAssertTrue(app.buttons["option.自拍連拍"].isHittable)
        app.buttons["option.自拍連拍"].tap()
        let count = app.steppers["drive.timerCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 3))
        XCTAssertEqual(count.value as? String, "3")
        count.buttons.element(boundBy: 1).tap()
        XCTAssertEqual(count.value as? String, "4")
        capture("06-Timer-continuous")
        app.buttons["editor.confirm"].tap()
        drive.tap()
        XCTAssertEqual(app.steppers["drive.timerCount"].value as? String, "4")
        app.buttons["editor.back"].tap()
        let iso = app.buttons["hud.iso"]
        iso.tap(); app.buttons["option.AUTO"].tap(); app.buttons["editor.confirm"].tap()
        XCTAssertEqual(iso.value as? String, "AUTO")
        XCTAssertEqual(app.buttons["hud.mode"].label, "M")
        iso.tap(); app.buttons["option.400"].tap(); app.buttons["editor.confirm"].tap()
        XCTAssertEqual(iso.value as? String, "400")
    }
    private func verifyLevelDisplay(_ app: XCUIApplication) {
        let info = app.buttons["fixture.capture"]
        info.tap()
        XCTAssertTrue(app.descendants(matching: .any)["camera.level"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.descendants(matching: .any)["camera.level"].value as? String, "水平")
        assertLevelCentered(app)
        capture("07-Level-large")
        info.tap(); info.tap() // clean -> full; one launch preserves all other test state.
        app.buttons["MENU"].tap()
        app.buttons["menu.水平儀顯示大小"].tap()
        app.buttons["option.小"].tap(); app.buttons["editor.confirm"].tap()
        app.buttons["menu.close"].tap()
        info.tap()
        XCTAssertTrue(app.descendants(matching: .any)["camera.level"].waitForExistence(timeout: 3))
        assertLevelCentered(app)
        capture("08-Level-small")
        info.tap(); info.tap()
    }
    private func assertLevelCentered(_ app: XCUIApplication) {
        let level = app.descendants(matching: .any)["camera.level"].frame
        let photo = app.descendants(matching: .any)["camera.viewfinder"].frame
        XCTAssertEqual(level.midX, photo.midX, accuracy: 1)
        XCTAssertEqual(level.midY, photo.midY, accuracy: 1)
    }
    private func verifyProgramRestrictionsPreserveWhiteBalance(_ app: XCUIApplication) {
        app.buttons["hud.mode"].tap(); app.buttons["option.A+"].tap(); app.buttons["editor.confirm"].tap()
        app.buttons["白平衡"].tap()
        XCTAssertFalse(app.buttons["option.日光"].exists)
        app.buttons["editor.back"].tap()
        app.buttons["hud.mode"].tap(); app.buttons["option.P"].tap(); app.buttons["editor.confirm"].tap()
        app.buttons["白平衡"].tap()
        XCTAssertEqual(app.buttons["option.日光"].value as? String, "已選取")
        app.buttons["editor.back"].tap()
        app.buttons["hud.mode"].tap(); app.buttons["option.M"].tap(); app.buttons["editor.confirm"].tap()
    }
    private func verifyCaptureFeedbackLeavesLiveViewUncovered(_ app: XCUIApplication) {
        let trigger = app.buttons["fixture.capture"]
        XCTAssertTrue(trigger.waitForExistence(timeout: 10))
        let previous = Int(trigger.value as? String ?? "0")!
        let viewfinder = app.descendants(matching: .any)["camera.viewfinder"]
        for count in 1...3 {
            trigger.tap()
            XCTAssertEqual(trigger.value as? String, String(previous + count))
        }
        let returned = NSPredicate(format: "value == %@", "即時取景")
        expectation(for: returned, evaluatedWith: viewfinder)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(app.buttons["quick.open"].exists)
        app.buttons["MENU"].tap()
        app.buttons["menu.tab.2"].tap()
        XCTAssertFalse(app.buttons["menu.拍後檢視"].exists)
        app.buttons["menu.close"].tap()
        XCTAssertEqual(trigger.value as? String, String(previous + 3))
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
