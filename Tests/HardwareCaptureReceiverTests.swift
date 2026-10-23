#if canImport(UIKit) && canImport(AVKit)
import XCTest
import UIKit
import AVKit
@testable import R6Camera

final class HardwareCaptureReceiverTests: XCTestCase {
    @MainActor func testReceiverFollowsContentAcrossFullScreenAndNestedPages() async {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 844, height: 390))
        let root = UIViewController()
        window.rootViewController = root; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let preview = UIView(frame: root.view.bounds); root.view.addSubview(preview)
        let receiver = HardwareCaptureReceiver()
        XCTAssertFalse(receiver.bind(window), "A UIWindow is not a capture content host")
        XCTAssertTrue(receiver.bind(preview)); receiver.setEnabled(true)
        XCTAssertTrue(preview.interactions.contains { $0 is AVCaptureEventInteraction })
        let menu = UIViewController(); menu.modalPresentationStyle = .fullScreen
        let shown = expectation(description: "MENU presented")
        root.present(menu, animated: false) { shown.fulfill() }
        await fulfillment(of: [shown], timeout: 3)
        XCTAssertFalse(receiver.bind(menu.view), "Same scene preserves authorization")
        XCTAssertTrue(receiver.enabled)
        XCTAssertEqual(menu.view.interactions.filter { $0 is AVCaptureEventInteraction }.count, 1)
        XCTAssertFalse(preview.interactions.contains { $0 is AVCaptureEventInteraction })
        XCTAssertFalse(window.interactions.contains { $0 is AVCaptureEventInteraction })
        let nested = UIViewController(); nested.modalPresentationStyle = .fullScreen
        let nestedShown = expectation(description: "Nested presented")
        menu.present(nested, animated: false) { nestedShown.fulfill() }
        await fulfillment(of: [nestedShown], timeout: 3)
        receiver.bind(nested.view)
        XCTAssertTrue(receiver.enabled)
        XCTAssertFalse(menu.view.interactions.contains { $0 is AVCaptureEventInteraction })
        XCTAssertEqual(nested.view.interactions.filter { $0 is AVCaptureEventInteraction }.count, 1)
        let dismissed = expectation(description: "Return")
        root.dismiss(animated: false) { dismissed.fulfill() }
        await fulfillment(of: [dismissed], timeout: 3)
        receiver.unbind(nested.view); receiver.unbind(menu.view); receiver.bind(preview)
        XCTAssertTrue(receiver.enabled)
        XCTAssertTrue(preview.interactions.contains { $0 is AVCaptureEventInteraction })
        XCTAssertEqual(receiver.receivedEvents, 0, "Installing an interaction is not evidence of OS delivery")
        receiver.setEnabled(false)
        XCTAssertFalse(receiver.attached); XCTAssertFalse(receiver.enabled)
        XCTAssertFalse(preview.interactions.contains { $0 is AVCaptureEventInteraction })
    }
    @MainActor func testControllerInstallsCaptureContentInBothSettingsAndDetachesInBackground() {
        let window = UIWindow(); let root = UIViewController()
        window.rootViewController = root; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let camera = CameraController()
        camera.captureEnabled = true; camera.isRunning = true
        for twoStage in [false, true] {
            camera.settings.experimentalHardwareShutter = twoStage
            camera.bindHardwareView(root.view)
            XCTAssertTrue(camera.hardwareReceiver.enabled)
            XCTAssertTrue(root.view.interactions.contains { $0 is AVCaptureEventInteraction })
            XCTAssertFalse(window.interactions.contains { $0 is AVCaptureEventInteraction })
        }
        camera.sceneIsActive = false
        XCTAssertFalse(camera.hardwareReceiver.enabled)
        camera.sceneIsActive = true
        XCTAssertTrue(camera.hardwareReceiver.enabled)
        camera.stop()
        XCTAssertFalse(camera.hardwareReceiver.enabled)
        XCTAssertEqual(camera.hardwareReceiver.receivedEvents, 0)
    }
    @MainActor func testDestructionRemovesContentOwnedInteraction() {
        let window = UIWindow(); let root = UIViewController()
        window.rootViewController = root; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        var receiver: HardwareCaptureReceiver? = HardwareCaptureReceiver()
        receiver?.bind(root.view); receiver?.setEnabled(true)
        XCTAssertEqual(root.view.interactions.filter { $0 is AVCaptureEventInteraction }.count, 1)
        receiver = nil
        XCTAssertFalse(root.view.interactions.contains { $0 is AVCaptureEventInteraction })
    }
    @MainActor func testReenableSceneChangeAndDetachedHostNeverDuplicateReceiver() {
        let first = UIWindow(), second = UIWindow()
        let root1 = UIViewController(), root2 = UIViewController()
        first.rootViewController = root1; first.makeKeyAndVisible()
        second.rootViewController = root2; second.makeKeyAndVisible()
        defer { first.isHidden = true; second.isHidden = true }
        let view1 = UIView(), view2 = UIView()
        root1.view.addSubview(view1); root2.view.addSubview(view2)
        let receiver = HardwareCaptureReceiver()
        XCTAssertTrue(receiver.bind(view1)); receiver.setEnabled(true); receiver.setEnabled(true)
        XCTAssertFalse(receiver.bind(view1))
        XCTAssertEqual(view1.interactions.filter { $0 is AVCaptureEventInteraction }.count, 1)
        receiver.setEnabled(false); receiver.setEnabled(true)
        XCTAssertEqual(view1.interactions.filter { $0 is AVCaptureEventInteraction }.count, 1)
        XCTAssertTrue(receiver.bind(view2))
        XCTAssertFalse(view1.interactions.contains { $0 is AVCaptureEventInteraction })
        XCTAssertTrue(receiver.enabled)
        view2.removeFromSuperview(); receiver.unbind(view2)
        XCTAssertFalse(receiver.enabled)
        receiver.bind(view1)
        XCTAssertTrue(receiver.enabled)
        XCTAssertFalse(first.interactions.contains { $0 is AVCaptureEventInteraction })
        receiver.setEnabled(false)
    }
}
#endif
