import XCTest
@testable import R6Camera

final class HardwareShutterTests: XCTestCase {
    func testOldSettingsDecodeWithExperimentOffAndNewSettingRoundTrips() throws {
        let encoder = JSONEncoder()
        var settings = CameraSettings()
        XCTAssertFalse(settings.experimentalHardwareShutter)
        settings.experimentalHardwareShutter = true
        let data = try encoder.encode(settings)
        XCTAssertTrue(try JSONDecoder().decode(CameraSettings.self, from: data).experimentalHardwareShutter)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "storedExperimentalHardwareShutter")
        let oldData = try JSONSerialization.data(withJSONObject: object)
        XCTAssertFalse(try JSONDecoder().decode(CameraSettings.self, from: oldData).experimentalHardwareShutter)
    }
    private func send(_ gate: inout HardwareShutter, _ input: HardwareShutter.Input,
                      _ time: Double, burst: Bool = false, available: Bool = true,
                      experimental: Bool = true, captureAllowed: Bool = true) -> [HardwareShutter.Action] {
        gate.receive(input, at: time, experimental: experimental, available: available, burst: burst,
                     captureAllowed: captureAllowed, returningToCapture: !captureAllowed).actions
    }
    func testDirectPressAndSecondaryCannotCapture() {
        var gate = HardwareShutter()
        XCTAssertEqual(send(&gate, .primaryBegan, 0), [])
        XCTAssertEqual(send(&gate, .primaryEnded, 0.1), [])
        XCTAssertEqual(send(&gate, .controlsActive, 1), [.focus])
        XCTAssertEqual(send(&gate, .secondaryBegan, 1.1), [])
        XCTAssertEqual(send(&gate, .secondaryEnded, 1.2), [])
        XCTAssertEqual(send(&gate, .primaryBegan, 1.3), [.photo])
    }
    func testQueuedPressBeforeAuthorizationCannotCapture() {
        var gate = HardwareShutter()
        _ = send(&gate, .controlsActive, 10)
        XCTAssertEqual(send(&gate, .primaryBegan, 9.9), [])
        _ = send(&gate, .primaryEnded, 10.1)
        XCTAssertEqual(send(&gate, .primaryBegan, 10.2), [.photo])
    }
    func testActiveOverlayAllowsRepeatedPressesWithoutTwoSecondExpiry() {
        var gate = HardwareShutter()
        XCTAssertEqual(send(&gate, .controlsActive, 0), [.focus])
        XCTAssertEqual(send(&gate, .controlsActive, 1), [])
        XCTAssertNil(gate.deadline)
        XCTAssertEqual(send(&gate, .primaryBegan, 2.284), [.photo])
        XCTAssertEqual(send(&gate, .primaryBegan, 2.3), [])
        _ = send(&gate, .primaryEnded, 3)
        XCTAssertEqual(send(&gate, .controlsActive, 3.1), [])
        XCTAssertEqual(send(&gate, .primaryBegan, 15), [.photo])
    }
    func testExactExpiryAndDismissalGraceBoundaries() {
        var gate = HardwareShutter()
        _ = send(&gate, .controlsActive, 10)
        _ = send(&gate, .controlsInactive, 10.5)
        _ = send(&gate, .controlsInactive, 10.7)
        XCTAssertEqual(gate.deadline!, 10.8, accuracy: 0.00001)
        XCTAssertEqual(send(&gate, .primaryBegan, 10.799), [.photo])
        gate = HardwareShutter()
        _ = send(&gate, .controlsActive, 10)
        _ = send(&gate, .controlsInactive, 20)
        XCTAssertEqual(gate.deadline!, 20.3, accuracy: 0.00001)
        XCTAssertEqual(send(&gate, .primaryBegan, 20.3), [])
    }
    func testDismissalGraceIsConsumedButActiveOverlayIsNot() {
        var gate = HardwareShutter()
        _ = send(&gate, .controlsActive, 0)
        _ = send(&gate, .controlsInactive, 10)
        XCTAssertEqual(send(&gate, .primaryBegan, 10.1), [.photo])
        _ = send(&gate, .primaryEnded, 10.15)
        XCTAssertEqual(send(&gate, .primaryBegan, 10.2), [])
    }
    func testDeviceLogSequenceNoLongerRejectsFiveFullPresses() {
        var gate = HardwareShutter()
        _ = send(&gate, .controlsActive, 39080.036483375006)
        for (began, ended) in [(39082.32026487501, 39083.67955954168),
                               (39084.42962408334, 39085.12953995834),
                               (39085.430341833344, 39085.58136579167),
                               (39086.03004166667, 39086.14671283334),
                               (39086.330320833345, 39086.46334891667)] {
            XCTAssertEqual(send(&gate, .primaryBegan, began), [.photo])
            _ = send(&gate, .primaryEnded, ended)
        }
    }
    func testMenuReturnDefersSingleShotUntilCapturePageIsReady() {
        var gate = HardwareShutter()
        XCTAssertEqual(send(&gate, .controlsActive, 0, captureAllowed: false), [.focus])
        XCTAssertEqual(send(&gate, .primaryBegan, 0.1, captureAllowed: false), [])
        XCTAssertEqual(gate.pendingCapture, .photo)
        _ = send(&gate, .primaryEnded, 0.2, captureAllowed: false)
        XCTAssertEqual(send(&gate, .capturePageReady, 0.3), [.photo])
        XCTAssertEqual(send(&gate, .capturePageReady, 0.4), [])
    }
    func testCoveredPageCannotQueueCaptureWithoutLightPressReturn() {
        var gate = HardwareShutter()
        _ = send(&gate, .controlsActive, 0)
        let result = gate.receive(.primaryBegan, at: 1, experimental: true, available: true,
                                  burst: false, captureAllowed: false, returningToCapture: false)
        XCTAssertTrue(result.actions.isEmpty)
        XCTAssertNil(gate.pendingCapture)
        XCTAssertEqual(send(&gate, .capturePageReady, 2), [])
    }
    func testMenuReturnBurstRequiresStillHeldAndResetRevokesPendingPhoto() {
        var gate = HardwareShutter()
        _ = send(&gate, .controlsActive, 0, captureAllowed: false)
        _ = send(&gate, .primaryBegan, 0.1, burst: true, captureAllowed: false)
        XCTAssertEqual(send(&gate, .capturePageReady, 0.2), [.beginBurst])
        XCTAssertEqual(send(&gate, .primaryEnded, 1), [.stopBurst])
        gate = HardwareShutter()
        _ = send(&gate, .controlsActive, 0, captureAllowed: false)
        _ = send(&gate, .primaryBegan, 0.1, burst: true, captureAllowed: false)
        _ = send(&gate, .primaryEnded, 0.2, captureAllowed: false)
        XCTAssertEqual(send(&gate, .capturePageReady, 0.3), [])
        gate = HardwareShutter()
        _ = send(&gate, .controlsActive, 0, captureAllowed: false)
        _ = send(&gate, .primaryBegan, 0.1, captureAllowed: false)
        _ = send(&gate, .reset, 0.2)
        XCTAssertEqual(send(&gate, .capturePageReady, 0.3), [])
    }
    func testBurstSurvivesExpiryUntilRelease() {
        var gate = HardwareShutter()
        _ = send(&gate, .controlsActive, 0)
        XCTAssertEqual(send(&gate, .primaryBegan, 1, burst: true), [.beginBurst])
        XCTAssertEqual(send(&gate, .controlsInactive, 5), [])
        XCTAssertEqual(send(&gate, .primaryEnded, 10), [.stopBurst])
        XCTAssertEqual(send(&gate, .primaryEnded, 11), [])
    }
    func testInterruptionCancellationAndSettingsResetRevokeAuthorization() {
        for input in [HardwareShutter.Input.reset, .primaryCancelled, .secondaryCancelled] {
            var gate = HardwareShutter()
            _ = send(&gate, .controlsActive, 0)
            _ = send(&gate, input, 0.5)
            XCTAssertEqual(send(&gate, .primaryBegan, 1), [])
            gate = HardwareShutter()
            _ = send(&gate, .controlsActive, 0)
            _ = send(&gate, .primaryBegan, 0.2, burst: true)
            XCTAssertEqual(send(&gate, input, 0.5), [.stopBurst])
            XCTAssertFalse(gate.bursting)
        }
        var gate = HardwareShutter()
        _ = send(&gate, .controlsActive, 0)
        XCTAssertEqual(send(&gate, .primaryBegan, 0.1, available: false), [])
        XCTAssertEqual(send(&gate, .primaryBegan, 0.2), [])
    }
    func testHeldUnpreparedPressIsRejectedButNextFreshPressCanCapture() {
        var gate = HardwareShutter()
        _ = send(&gate, .primaryBegan, 0)
        XCTAssertEqual(send(&gate, .controlsActive, 0.1), [])
        XCTAssertEqual(send(&gate, .primaryBegan, 0.2), [])
        _ = send(&gate, .primaryEnded, 0.3)
        XCTAssertEqual(send(&gate, .primaryBegan, 0.4), [.photo])
    }
    func testLegacyModeRetainsBothButtonsAndDoesNotFocusOnOverlay() {
        var gate = HardwareShutter()
        XCTAssertEqual(send(&gate, .controlsActive, 0, experimental: false), [])
        XCTAssertEqual(send(&gate, .primaryBegan, 1, experimental: false), [.photo])
        _ = send(&gate, .primaryEnded, 1.1, experimental: false)
        XCTAssertEqual(send(&gate, .secondaryBegan, 2, burst: true, experimental: false), [.beginBurst])
        XCTAssertEqual(send(&gate, .secondaryEnded, 4, experimental: false), [.stopBurst])
    }
}
