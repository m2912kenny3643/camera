#if canImport(UIKit)
import XCTest
import AVFoundation
import ImageIO
@testable import R6Camera

/// Real bundled ONNX inference. Functional fixtures do not stand in for 100-image accuracy.
final class BirdONNXTests: XCTestCase {
    private func fixture(_ name: String, ext: String = "jpg") throws -> CVPixelBuffer {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "BirdFixture-\(name)", withExtension: ext))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return try BirdDiagnosticsView.makeBuffer(image)
    }
    func testBundledPinnedModelProducesActualEyeHeadAndBodyObservations() throws {
        let model = try BirdONNXModel() // Constructor verifies the full bundled ONNX digest.
        for (name, ext, expected) in [("eagle", "png", "eye"), ("head", "jpg", "head"), ("body", "jpg", "body")] {
            let poses = try model.observations(fixture(name, ext: ext), at: 42, region: nil, padding: 1)
            let pose = try XCTUnwrap(poses.first, "No actual model observation for \(name)")
            XCTAssertEqual(pose.timestamp, 42)
            let detection = pose.detection
            switch expected {
            case "eye":
                let eye = try XCTUnwrap(detection.eye(.automatic))
                XCTAssertEqual(eye.x, 0.4927, accuracy: 0.01)
                XCTAssertEqual(eye.y, 0.2631, accuracy: 0.01)
            case "head": XCTAssertNil(detection.eye(.automatic)); XCTAssertNotNil(detection.headBounds)
            default: XCTAssertNil(detection.eye(.automatic)); XCTAssertNil(detection.headBounds)
            }
            XCTAssertTrue(pose.body.minX.isFinite && pose.body.minY.isFinite)
            XCTAssertGreaterThan(pose.body.area, 0)
            XCTAssertTrue(pose.keypoints.values.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite && $0.confidence.isFinite })
        }
    }
    func testExplicitWholeImageRegionMatchesDefaultDecodedOutput() throws {
        let model = try BirdONNXModel()
        let buffer = try fixture("eagle", ext: "png")
        let implicit = try model.observations(buffer, at: 1, region: nil, padding: 1)
        let explicit = try model.observations(buffer, at: 1, region: CGRect(x: 0, y: 0, width: 1, height: 1), padding: 1)
        XCTAssertEqual(implicit.count, explicit.count)
        for (a, b) in zip(implicit, explicit) {
            XCTAssertEqual(a.body.minX, b.body.minX, accuracy: 0.000001)
            XCTAssertEqual(a.body.minY, b.body.minY, accuracy: 0.000001)
            XCTAssertEqual(a.body.width, b.body.width, accuracy: 0.000001)
            XCTAssertEqual(a.body.height, b.body.height, accuracy: 0.000001)
            XCTAssertEqual(a.confidence, b.confidence, accuracy: 0.000001)
        }
    }
    func testFrontalROIAndNoBirdFixturesUseActualModel() throws {
        let model = try BirdONNXModel()
        let frontal = try XCTUnwrap(model.observations(fixture("frontal"), at: 1).first)
        XCTAssertNotNil(frontal.detection.leftEye); XCTAssertNotNil(frontal.detection.rightEye)
        XCTAssertTrue(try model.observations(fixture("background", ext: "png"), at: 1).isEmpty)
        XCTAssertTrue(try model.observations(fixture("distant"), at: 1).isEmpty) // Retains known distant-flock miss.
        let roi = try XCTUnwrap(model.observations(fixture("eagle", ext: "png"), at: 2,
                              region: CGRect(x: 0.2,y: 0.15,width: 0.6,height: 0.75), padding: 1.2).first)
        let eye = try XCTUnwrap(roi.detection.eye(.automatic))
        XCTAssertEqual(eye.x, 0.4927, accuracy: 0.05)
        XCTAssertEqual(eye.y, 0.2631, accuracy: 0.05)
    }
    func testNativeBGRAProducesRGBNCHWAnd114LetterboxWithoutRowStrideAssumption() throws {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 320, 160, kCVPixelFormatType_32BGRA,
                                          nil, &buffer), kCVReturnSuccess)
        let image = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(image, [])
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(image)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(image)
        for y in 0..<160 {
            for x in 0..<320 {
                let i = y*stride+x*4
                base[i] = UInt8(x % 256); base[i+1] = UInt8(y); base[i+2] = 17; base[i+3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(image, [])
        let data = try BirdONNXModel().preparedInputData(image)
        let floats = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        XCTAssertEqual(floats.count, 3*320*320)
        XCTAssertEqual(floats[160*320+20], 17.0/255, accuracy: 0.000001)
        XCTAssertEqual(floats[320*320+160*320+20], 80.0/255, accuracy: 0.000001)
        XCTAssertEqual(floats[2*320*320+160*320+20], 20.0/255, accuracy: 0.000001)
        for channel in 0..<3 { XCTAssertEqual(floats[channel*320*320+20*320+20], 114.0/255, accuracy: 0.000001) }
    }
}
#endif
