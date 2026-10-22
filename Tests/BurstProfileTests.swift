import XCTest
@testable import R6Camera

final class BurstProfileTests: XCTestCase {
    func testTrialLadderPreservesQualityAndConservativeFallbacks() throws {
        var settings = CameraSettings(); settings.drive = .burstHighPlus
        for trial in BurstRateTrial.allCases {
            settings.burstRateTrial = trial
            let snapshot = settings
            XCTAssertEqual(BurstProfile(settings: settings, responsive: true, photoPixels: 12_000_000, exposure: 0.001).requestFPS, Double(trial.rawValue))
            XCTAssertEqual(BurstProfile(settings: settings, responsive: true, photoPixels: 48_000_000, exposure: 0.001).requestFPS, 4)
            XCTAssertEqual(settings, snapshot)
            settings.drive = .burst
            XCTAssertEqual(BurstProfile(settings: settings, responsive: true, photoPixels: 12_000_000, exposure: 0.001).requestFPS, trial.highFPS)
            settings.drive = .burstHighPlus
        }
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(CameraSettings.self, from: data).burstRateTrial, .fastest)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "storedBurstRateTrial")
        XCTAssertEqual(try JSONDecoder().decode(CameraSettings.self, from: JSONSerialization.data(withJSONObject: legacy)).burstRateTrial, .standard)
    }
    func testFasterRequestsRequireCompatibleProcessedCapture() {
        var settings = CameraSettings(); settings.drive = .burstHighPlus
        let fast = BurstProfile(settings: settings, responsive: true, photoPixels: 12_000_000, exposure: 0.001)
        XCTAssertEqual(fast.requestFPS, 8)
        XCTAssertNil(fast.reason)
        settings.drive = .burst
        XCTAssertEqual(BurstProfile(settings: settings, responsive: true, photoPixels: 12_000_000, exposure: 0.001).requestFPS, 4)
        settings.drive = .burstLow
        XCTAssertEqual(BurstProfile(settings: settings, responsive: true, photoPixels: 12_000_000, exposure: 0.001).requestFPS, 1)
    }
    func testRAWHighResolutionExactExposureAndUnsupportedHardwareStayConservative() {
        var settings = CameraSettings(); settings.drive = .burstHighPlus
        for pixels: Int64 in [0, 48_000_000] {
            XCTAssertEqual(BurstProfile(settings: settings, responsive: true, photoPixels: pixels, exposure: 0.001).requestFPS, 4)
        }
        XCTAssertEqual(BurstProfile(settings: settings, responsive: false, photoPixels: 12_000_000, exposure: 0.001).requestFPS, 4)
        settings.format = .raw
        XCTAssertEqual(BurstProfile(settings: settings, responsive: true, photoPixels: 12_000_000, exposure: 0.001).requestFPS, 4)
        settings.format = .jpeg; settings.program = .manual
        XCTAssertEqual(BurstProfile(settings: settings, responsive: true, photoPixels: 12_000_000, exposure: 0.001).requestFPS, 4)
    }
    func testLongExposureLimitsRequestsWithoutChangingSettings() {
        var settings = CameraSettings(); settings.drive = .burstHighPlus
        let original = settings
        let profile = BurstProfile(settings: settings, responsive: true, photoPixels: 12_000_000, exposure: 2)
        XCTAssertEqual(profile.requestFPS, 1 / 2.03, accuracy: 0.000001)
        XCTAssertEqual(profile.reason, "曝光時間限制")
        XCTAssertEqual(settings, original)
    }
}
