import XCTest
@testable import R6Camera

final class BurstDiagnosticsTests: XCTestCase {
    func testStartEndAndLongHoldStallsCannotPassUsingOnlyGoodMiddleIntervals() {
        for (offset, count, stopped) in [(0.0, 64, 10.0), (2.0, 64, 10.0), (0.0, 80, 60.0)] {
            var report = BurstDiagnostics(mode: "H+", format: "HEIF", requestedPixels: 12_000_000,
                                          exposure: 0.001, requestFPS: 8, device: "test", startedAt: 0)
            for id in 0..<count {
                let time = offset + Double(id)/8
                report.requested(id: Int64(id), at: time)
                report.captured(id: Int64(id), at: time)
                report.stored(id: Int64(id), at: time+0.1, succeeded: true, dimensions: nil)
            }
            report.stop(at: stopped)
            XCTAssertFalse(report.tenSecondCadencePassed)
        }
    }
    func testActualCallbacksNotRequestsDefineCadenceAndPendingWritesCannotPass() throws {
        var report = BurstDiagnostics(mode: "H+", format: "HEIF", requestedPixels: 12_000_000,
                                      exposure: 0.001, requestFPS: 12, device: "test", startedAt: 0)
        for id in Int64(0)..<120 {
            let t = Double(id) / 12
            report.requested(id: id, at: t)
            report.captured(id: id, at: t + 0.02)
            report.processed(id: id, at: t + 0.1)
            report.rendering(id: id, at: t + 0.2)
            if id < 119 { report.stored(id: id, at: t + 0.3, succeeded: true, dimensions: "4000x3000") }
        }
        report.stop(at: 10)
        XCTAssertFalse(report.tenSecondCadencePassed)
        report.stored(id: 119, at: 10.5, succeeded: true, dimensions: "4000x3000")
        XCTAssertTrue(report.tenSecondCadencePassed)
        XCTAssertEqual(report.measuredFPS ?? 0, 12, accuracy: 0.000001)
        XCTAssertLessThan(report.p95RelativeDeviation ?? 1, 0.000001)
        let json = try XCTUnwrap(report.reportText())
        XCTAssertTrue(json.contains("renderStartedAt"))
        XCTAssertTrue(json.contains("tenSecondCadencePassed"))
    }
    func testSlowCaptureFailedStorageAndTruncatedHoldCannotQualify() {
        var report = BurstDiagnostics(mode: "H+", format: "RAW", requestedPixels: 48_000_000,
                                      exposure: 0.001, requestFPS: 8, device: "test", startedAt: 0)
        for id in Int64(0)..<260 {
            report.requested(id: id, at: Double(id)/8)
            report.captured(id: id, at: Double(id)/4)
            report.stored(id: id, at: Double(id)/4+1, succeeded: id != 5, dimensions: nil)
        }
        report.blocked("處理緩衝已滿"); report.stop(at: 70)
        XCTAssertEqual(report.samples.count, 256)
        XCTAssertEqual(report.totalRequests, 260)
        XCTAssertEqual(report.blockedReasons["處理緩衝已滿"], 1)
        XCTAssertFalse(report.tenSecondCadencePassed)
        XCTAssertGreaterThan(report.p95RelativeDeviation ?? 0, 0.2)
    }
}
