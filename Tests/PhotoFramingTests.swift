import XCTest
@testable import R6Camera

final class PhotoFramingTests: XCTestCase {
    func testFourThirdsFrameCenteredWithSeparateSideRails() {
        let frame = ViewfinderGeometry.photoRect(in: CGSize(width: 1600, height: 648))
        XCTAssertEqual(frame, CGRect(x: 368, y: 0, width: 864, height: 648))
        XCTAssertNil(ViewfinderGeometry.normalizedIfInside(CGPoint(x: 50, y: 300), imageAspect: 4.0/3, size: CGSize(width: 1600, height: 648)))
        XCTAssertNil(ViewfinderGeometry.normalizedIfInside(CGPoint(x: 1400, y: 300), imageAspect: 4.0/3, size: CGSize(width: 1600, height: 648)))
    }
    func testAllImageEdgesRemainVisibleWithoutStretching() {
        for aspect: CGFloat in [4.0/3, 16.0/9, 3.0/4] {
            let size = CGSize(width: 864, height: 648)
            let image = ViewfinderGeometry.imageRect(imageAspect: aspect, in: size)
            XCTAssertGreaterThanOrEqual(image.minX, 0)
            XCTAssertGreaterThanOrEqual(image.minY, 0)
            XCTAssertLessThanOrEqual(image.maxX, size.width)
            XCTAssertLessThanOrEqual(image.maxY, size.height)
            XCTAssertEqual(image.width/image.height, aspect, accuracy: 0.000001)
            for point in [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0.2, y: 0.7)] {
                let display = ViewfinderGeometry.display(point, imageAspect: aspect, size: size)
                let roundTrip = ViewfinderGeometry.normalized(display, imageAspect: aspect, size: size)
                XCTAssertEqual(roundTrip.x, point.x, accuracy: 0.000001)
                XCTAssertEqual(roundTrip.y, point.y, accuracy: 0.000001)
            }
        }
    }
    func testLetterboxDoesNotCreateFocusPoint() {
        XCTAssertNil(ViewfinderGeometry.normalizedIfInside(CGPoint(x: 432, y: 5), imageAspect: 16.0/9, size: CGSize(width: 864, height: 648)))
        XCTAssertEqual(ViewfinderGeometry.normalizedIfInside(CGPoint(x: 432, y: 324), imageAspect: 16.0/9, size: CGSize(width: 864, height: 648)), CGPoint(x: 0.5, y: 0.5))
    }
}
