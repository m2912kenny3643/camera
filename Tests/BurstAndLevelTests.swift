import XCTest
@testable import R6Camera

final class BurstAndLevelTests: XCTestCase {
    func testTenSecondCadenceAndNoCatchUpAfterBackpressure() {
        var cadence = BurstCadence(fps: 4, exposure: 0.001, now: 0)
        for i in 0..<40 { XCTAssertTrue(cadence.admit(at: Double(i) * 0.25, ready: true)) }
        XCTAssertEqual(cadence.measuredFPS ?? 0, 4, accuracy: 0.00001)
        XCTAssertFalse(cadence.admit(at: 10, ready: false))
        XCTAssertTrue(cadence.admit(at: 12, ready: true))
        XCTAssertFalse(cadence.admit(at: 12, ready: true))
        XCTAssertGreaterThan(cadence.interval, 0.25)
        XCTAssertEqual(cadence.blocked, 1)
    }
    func testExposureLimitsCadenceWithoutChangingExposure() {
        let cadence = BurstCadence(fps: 4, exposure: 2, now: 0)
        XCTAssertEqual(cadence.interval, 2.03, accuracy: 0.00001)
    }
    func testFasterTenSecondCadenceToleratesBoundedSchedulerJitter() {
        var cadence = BurstCadence(fps: 8, exposure: 0.001, now: 0)
        var count = 0
        while cadence.nextDeadline < 10 {
            let jitter = count.isMultiple(of: 3) ? 0.008 : 0.002
            XCTAssertTrue(cadence.admit(at: cadence.nextDeadline + jitter, ready: true))
            count += 1
        }
        XCTAssertGreaterThan(count, 70)
        let deviations = cadence.intervals.map { abs($0 - 0.125) / 0.125 }.sorted()
        XCTAssertLessThanOrEqual(deviations[Int(Double(deviations.count - 1) * 0.95)], 0.2)
    }
    func testBackpressureDoesNotQueueOrCompensateWithFastRequests() {
        var cadence = BurstCadence(fps: 8, exposure: 0.001, now: 0)
        XCTAssertTrue(cadence.admit(at: 0, ready: true))
        XCTAssertFalse(cadence.admit(at: 0.125, ready: false))
        XCTAssertTrue(cadence.admit(at: 1, ready: true))
        XCTAssertEqual(cadence.accepted, 2)
        XCTAssertEqual(cadence.nextDeadline, 2)
        XCTAssertFalse(cadence.admit(at: 1.01, ready: true))
    }
    func testFixedLandscapeGravityAndInvalidSensorData() {
        var filter = LevelFilter()
        XCTAssertEqual(filter.update(x: -1, y: 0, z: 0, at: 0), LevelReading(roll: 0, pitch: 0))
        XCTAssertTrue(filter.reading?.isLevel == true)
        let rightTilt = filter.update(x: -cos(0.1), y: sin(0.1), z: 0, at: 1)
        XCTAssertGreaterThan(rightTilt?.roll ?? 0, 5)
        XCTAssertNil(filter.update(x: 0, y: 0, z: 1, at: 2))
        XCTAssertNil(filter.update(x: .nan, y: 0, z: 0, at: 3))
    }
}
