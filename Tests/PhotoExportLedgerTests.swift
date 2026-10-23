import XCTest
@testable import R6Camera

final class PhotoExportLedgerTests: XCTestCase {
    func testExportDeduplicatesPendingAndSuccessfulAndAllowsFailedRetry() {
        var ledger = PhotoExportLedger()
        XCTAssertTrue(ledger.enqueue("a")); XCTAssertTrue(ledger.isBusy("a"))
        XCTAssertFalse(ledger.enqueue("a", retry: true))
        ledger.start("a"); XCTAssertFalse(ledger.enqueue("a", retry: true))
        ledger.finish("a", error: "denied"); XCTAssertFalse(ledger.isBusy("a"))
        XCTAssertFalse(ledger.enqueue("a")); XCTAssertTrue(ledger.enqueue("a", retry: true))
        ledger.finish("a", error: nil); XCTAssertFalse(ledger.enqueue("a", retry: true))
    }
    func testCrashRecoveryRequiresExplicitRetryAndPersistsConfirmedSuccess() throws {
        var ledger = PhotoExportLedger()
        _ = ledger.enqueue("waiting"); _ = ledger.enqueue("active"); ledger.start("active")
        _ = ledger.enqueue("done"); ledger.finish("done", error: nil)
        var restored = try JSONDecoder().decode(PhotoExportLedger.self, from: JSONEncoder().encode(ledger))
        restored.recoverInterrupted()
        XCTAssertEqual(restored.entries["active"]?.state, .uncertain)
        XCTAssertEqual(restored.entries["waiting"]?.state, .uncertain)
        XCTAssertFalse(restored.enqueue("active")); XCTAssertTrue(restored.enqueue("active", retry: true))
        XCTAssertFalse(restored.enqueue("done", retry: true))
    }
}
