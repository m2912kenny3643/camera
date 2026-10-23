import XCTest
@testable import R6Camera

final class BurstCalibrationTests: XCTestCase {
    private func report(fps: Double, reduced: Bool = false) -> BurstDiagnostics {
        var r = BurstDiagnostics(mode: "H+", format: "HEIF", requestedPixels: 12_000_000, exposure: 0.001, requestFPS: fps, device: "test", startedAt: 0)
        for i in 0..<Int(fps*10) {
            r.requested(id: Int64(i), at: Double(i)/fps)
            r.captured(id: Int64(i), at: Double(i)/fps+0.02)
            r.stored(id: Int64(i), at: Double(i)/fps+0.1, succeeded: true, dimensions: "4000x3000")
        }
        if reduced { r.reduced(to: fps/2) }
        r.stop(at: 10)
        return r
    }
    func testThreePassesRequiredAndFailureMovesDownWithoutRecovery() {
        var c = BurstCalibration(key: "test", drive: .burstHighPlus, maximum: 12)
        c.consume(report(fps: 12)); c.consume(report(fps: 12))
        XCTAssertNil(c.verifiedFPS)
        c.consume(report(fps: 12, reduced: true))
        XCTAssertEqual(c.rate, 10); XCTAssertEqual(c.consecutivePasses, 0)
        for _ in 0..<3 { c.consume(report(fps: 10)) }
        XCTAssertEqual(c.verifiedFPS, 10)
    }
    func testConfigurationChangesInvalidateAndStorePersistsOnlyConcreteRate() {
        var s = CameraSettings(); s.drive = .burstHighPlus
        func key(_ settings: CameraSettings, lens: String = "wide", model: String = "hash") -> String {
            BurstCalibrationKey.make(lens: lens, os: "27", settings: settings, pixels: 48_771_072, exposure: 0.01, model: model)
        }
        let original = key(s)
        s.burstRateTrial = .fastest; XCTAssertEqual(original, key(s))
        s.format = .raw; XCTAssertNotEqual(original, key(s))
        XCTAssertNotEqual(original, key(CameraSettings(), lens: "tele"))
        XCTAssertNotEqual(original, key(CameraSettings(), model: "newHash"))
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = BurstCalibrationStore(defaults: defaults)
        XCTAssertNil(store.rate(for: original))
        store.save(8, for: original); XCTAssertEqual(store.rate(for: original), 8)
        store.save(.nan, for: original); XCTAssertEqual(store.rate(for: original), 8)
    }
    func testIncompleteStorageShortHoldAndDegradedHoldNeverQualify() {
        var c = BurstCalibration(key: "x", drive: .burstHighPlus, maximum: 12)
        var pending = BurstDiagnostics(mode: "H+", format: "HEIF", requestedPixels: 12, exposure: 0.001, requestFPS: 12, device: "test", startedAt: 0)
        pending.requested(id: 1, at: 0); pending.stop(at: 10)
        c.consume(pending); XCTAssertEqual(c.consecutivePasses, 0); XCTAssertEqual(c.rate, 12)
        var short = report(fps: 12); short.stop(at: 9)
        c.consume(short); XCTAssertEqual(c.consecutivePasses, 0); XCTAssertEqual(c.rate, 12)
        c.consume(report(fps: 12, reduced: true)); XCTAssertEqual(c.rate, 10)
    }
    func testPressureCannotRecoverOnNextHoldOrRelaunchWithoutNewCalibration() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = BurstCalibrationStore(defaults: defaults)
        store.save(10, for: "bird")
        XCTAssertEqual(store.requestRate(conservative: 4, for: "bird"), 10)
        store.restrict(to: 8, for: "bird")
        XCTAssertNil(store.rate(for: "bird"))
        XCTAssertEqual(store.requestRate(conservative: 4, for: "bird"), 4)
        store.restrict(to: 2, for: "bird")
        XCTAssertEqual(BurstCalibrationStore(defaults: defaults).requestRate(conservative: 4, for: "bird"), 2)
        for i in 0..<60 { store.restrict(to: 4, for: "other-\(i)") }
        XCTAssertEqual(store.requestRate(conservative: 4, for: "bird"), 2)
        store.save(8, for: "bird") // Only a completed three-pass calibration calls save in the controller.
        XCTAssertEqual(store.requestRate(conservative: 4, for: "bird"), 8)
    }
    func testExposureFloorAndHighDriveCeiling() {
        XCTAssertEqual(BurstCalibration(key: "x", drive: .burst, maximum: 12).rates, [6,4,2,1])
        XCTAssertEqual(BurstCalibration(key: "x", drive: .burstHighPlus, maximum: 0.49).rate, 0.49)
    }
}
