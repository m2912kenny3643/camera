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
        // Screen coordinates increase downward: dragging down must zoom in.
        XCTAssertEqual(dial.zoom(start: 1, verticalTranslation: 100, range: 0.5...10), 2, accuracy: 0.001)
        XCTAssertEqual(dial.zoom(start: 1, verticalTranslation: -100, range: 0.5...10), 0.5, accuracy: 0.001)
        XCTAssertEqual(dial.zoom(start: 1, verticalTranslation: -1000, range: 0.5...10), 0.5)
        XCTAssertEqual(dial.zoom(start: 1, verticalTranslation: 1000, range: 0.5...10), 10)
    }
    func testLowerZoomIsAbovePointerAndHigherZoomBelow() {
        let dial = ZoomDialGeometry(size: CGSize(width: 852, height: 360))
        XCTAssertLessThan(dial.point(angle: dial.angle(for: 0.5, selected: 1)).y, dial.center.y)
        XCTAssertGreaterThan(dial.point(angle: dial.angle(for: 2, selected: 1)).y, dial.center.y)
    }
}
