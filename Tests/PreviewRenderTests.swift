#if os(iOS)
import XCTest
import CoreImage
@testable import R6Camera

final class PreviewRenderTests: XCTestCase {
    func testManualPeakingRetainsSceneInsteadOfBlackBackground() {
        let input = CIImage(color: CIColor(red: 0.45, green: 0.45, blue: 0.45)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 48))
        var settings = CameraSettings(); settings.autofocus = .manual; settings.peaking = true
        let result = PhotoRenderer.preview(input, settings: settings)
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { bytes in
            CIContext().render(result, toBitmap: bytes.baseAddress!, rowBytes: 4,
                               bounds: CGRect(x: 32, y: 24, width: 1, height: 1),
                               format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        }
        XCTAssertGreaterThan(pixel[0], 60)
        XCTAssertGreaterThan(pixel[1], 60)
        XCTAssertGreaterThan(pixel[2], 60)
        XCTAssertEqual(result.extent, input.extent)
    }
}
#endif
