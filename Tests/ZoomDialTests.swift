import XCTest
@testable import R6Camera

final class ZoomDialTests: XCTestCase {
    func testHubIsOutsideScreenAndAllTickEndpointsAreConcentric() {
        let dial = ZoomDialGeometry(size: CGSize(width: 852, height: 360))
        XCTAssertGreaterThan(dial.center.x, dial.size.width)
        XCTAssertEqual(dial.point(angle: .pi).x, 852 * 0.85, accuracy: 0.001)
        for value: CGFloat in [0.5, 0.7, 1, 2, 4, 10] {
            let angle = dial.angle(for: value, selected: 1)
            let point = dial.point(angle: angle)
            XCTAssertEqual(hypot(point.x - dial.center.x, point.y - dial.center.y), dial.radius, accuracy: 0.001)
            let inner = dial.point(angle: angle, inset: 12)
            let cross = (point.x - dial.center.x) * (inner.y - dial.center.y) - (point.y - dial.center.y) * (inner.x - dial.center.x)
            XCTAssertEqual(cross, 0, accuracy: 0.001)
        }
    }
    func testLogarithmicDragAndLimits() {
        let dial = ZoomDialGeometry(size: CGSize(width: 852, height: 360))
        XCTAssertEqual(dial.zoom(start: 1, rotation: -0.46, range: 0.5...10), 2, accuracy: 0.001)
        XCTAssertEqual(dial.zoom(start: 1, rotation: 0.46, range: 0.5...10), 0.5, accuracy: 0.001)
        XCTAssertEqual(dial.zoom(start: 1, rotation: 100, range: 0.5...10), 0.5)
        XCTAssertEqual(dial.zoom(start: 1, rotation: -100, range: 0.5...10), 10)
    }
    func testHigherZoomIsAbovePointerAndLowerZoomBelow() {
        let dial = ZoomDialGeometry(size: CGSize(width: 852, height: 360))
        XCTAssertGreaterThan(dial.point(angle: dial.angle(for: 0.5, selected: 1)).y, dial.center.y)
        XCTAssertLessThan(dial.point(angle: dial.angle(for: 2, selected: 1)).y, dial.center.y)
    }
    func testDialFollowsFingerAcrossPiBoundary() {
        let dial = ZoomDialGeometry(size: CGSize(width: 852, height: 360))
        let before = dial.point(angle: .pi - 0.05)
        let after = dial.point(angle: .pi + 0.05)
        XCTAssertEqual(dial.rotation(from: before, to: after), 0.1, accuracy: 0.00001)
        let start = dial.point(angle: .pi)
        let finger = dial.point(angle: .pi - 0.2)
        let zoom = dial.zoom(start: 1, rotation: dial.rotation(from: start, to: finger), range: 0.5...10)
        XCTAssertGreaterThan(zoom, 1)
        // The 1x tick rotates to exactly the same angle as the finger.
        XCTAssertEqual(dial.angle(for: 1, selected: zoom), .pi - 0.2, accuracy: 0.00001)
    }
}
