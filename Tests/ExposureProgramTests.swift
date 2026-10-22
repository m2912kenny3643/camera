import XCTest
@testable import R6Camera

final class ExposureProgramTests: XCTestCase {
    func testAutoEffectiveOverridesDoNotErasePersonalSettings() {
        var s = CameraSettings(); s.program = .auto; s.autofocus = .manual
        s.whiteBalance = .tungsten; s.style = .mono; s.exposureBias = 2
        XCTAssertEqual(s.effective.autofocus, .servo)
        XCTAssertEqual(s.effective.whiteBalance, .automatic)
        XCTAssertEqual(s.effective.exposureBias, 0)
        XCTAssertEqual(s.whiteBalance, .tungsten)
        s.program = .program
        XCTAssertEqual(s.effective.whiteBalance, .tungsten)
        XCTAssertFalse(s.controlsShutter); XCTAssertFalse(s.controlsISO)
    }
    func testManualAutoISOStaysInManualAndAllowsCompensation() {
        var s = CameraSettings(); s.program = .manual
        XCTAssertTrue(s.controlsISO); XCTAssertTrue(s.controlsShutter)
        XCTAssertFalse(s.permitsExposureCompensation)
        s.useAutomaticISO()
        XCTAssertEqual(s.program, .manual)
        XCTAssertFalse(s.controlsISO); XCTAssertTrue(s.controlsShutter)
        XCTAssertTrue(s.permitsExposureCompensation)
        s.selectISO(400)
        XCTAssertEqual(s.program, .manual); XCTAssertTrue(s.controlsISO)
    }
    func testLegacyPresetDecodesWithNewDefaults() throws {
        let original = CameraSettings()
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(CameraSettings.self, from: data)
        XCTAssertEqual(restored.levelSize, .large)
        XCTAssertEqual(restored.timerCount, 3)
        XCTAssertFalse(restored.manualISOAutomatic)
        XCTAssertEqual(DriveMode(rawValue: "連拍"), .burst)
    }
    func testDriverRatesAndTimerLimits() {
        XCTAssertEqual(DriveMode.burstHighPlus.fps, 4)
        XCTAssertEqual(DriveMode.burst.fps, 2)
        XCTAssertEqual(DriveMode.burstLow.fps, 1)
        var s = CameraSettings(); s.timerCount = 99
        XCTAssertEqual(s.timerCount, 10)
        s.timerCount = 0; XCTAssertEqual(s.timerCount, 2)
    }
    func testSelectingISOInTvKeepsItsFixedShutter() {
        var s = CameraSettings(); s.program = .shutterPriority
        s.selectISO(400)
        XCTAssertEqual(s.program, .flexible)
        XCTAssertTrue(s.controlsShutter); XCTAssertTrue(s.controlsISO)
    }
}
