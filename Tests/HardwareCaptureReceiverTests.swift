#if canImport(UIKit) && canImport(AVKit)
import XCTest
import UIKit
import AVKit
@testable import R6Camera

final class HardwareCaptureReceiverTests: XCTestCase {
    @MainActor func testReceiverSurvivesFullScreenAndNestedPresentation() async {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 844, height: 390))
        let root = UIViewController()
        window.rootViewController = root; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let preview = UIView(frame: root.view.bounds); root.view.addSubview(preview)
        let receiver = HardwareCaptureReceiver()
        XCTAssertTrue(receiver.bind(window)); receiver.setEnabled(true)
        let menu = UIViewController(); menu.modalPresentationStyle = .fullScreen
        let shown = expectation(description: "MENU presented")
        root.present(menu, animated: false) { shown.fulfill() }
        await fulfillment(of: [shown], timeout: 3)
        XCTAssertTrue(receiver.attached); XCTAssertTrue(receiver.enabled)
        XCTAssertEqual(window.interactions.filter { $0 is AVCaptureEventInteraction }.count, 1)
        XCTAssertFalse(preview.interactions.contains { $0 is AVCaptureEventInteraction })
        let nested = UIViewController(); nested.modalPresentationStyle = .fullScreen
        let nestedShown = expectation(description: "Nested presented")
        menu.present(nested, animated: false) { nestedShown.fulfill() }
        await fulfillment(of: [nestedShown], timeout: 3)
        XCTAssertTrue(receiver.attached); XCTAssertTrue(receiver.enabled)
        let dismissed = expectation(description: "Return")
        root.dismiss(animated: false) { dismissed.fulfill() }
        await fulfillment(of: [dismissed], timeout: 3)
        XCTAssertTrue(receiver.enabled)
        receiver.setEnabled(false)
        XCTAssertFalse(receiver.attached); XCTAssertFalse(receiver.enabled)
        XCTAssertFalse(window.interactions.contains { $0 is AVCaptureEventInteraction })
    }
    @MainActor func testDestructionRemovesWindowOwnedInteraction() {
        let window = UIWindow()
        var receiver: HardwareCaptureReceiver? = HardwareCaptureReceiver()
        _ = receiver?.bind(window); receiver?.setEnabled(true)
        XCTAssertEqual(window.interactions.filter { $0 is AVCaptureEventInteraction }.count, 1)
        receiver = nil
        XCTAssertFalse(window.interactions.contains { $0 is AVCaptureEventInteraction })
    }
    @MainActor func testReenableAndWindowRebindNeverDuplicateReceiver() {
        let first = UIWindow(), second = UIWindow()
        let receiver = HardwareCaptureReceiver()
        XCTAssertTrue(receiver.bind(first)); receiver.setEnabled(true); receiver.setEnabled(true)
        XCTAssertFalse(receiver.bind(first))
        XCTAssertEqual(first.interactions.filter { $0 is AVCaptureEventInteraction }.count, 1)
        receiver.setEnabled(false); receiver.setEnabled(true)
        XCTAssertEqual(first.interactions.filter { $0 is AVCaptureEventInteraction }.count, 1)
        XCTAssertTrue(receiver.bind(second))
        XCTAssertFalse(first.interactions.contains { $0 is AVCaptureEventInteraction })
        XCTAssertFalse(receiver.enabled)
        receiver.setEnabled(true)
        XCTAssertEqual(second.interactions.filter { $0 is AVCaptureEventInteraction }.count, 1)
        receiver.setEnabled(false)
    }
}
#endif
