#if os(iOS)
import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import R6Camera

final class PhotoLibraryStoreTests: XCTestCase {
    private final class Exporter: PhotoLibraryExporting {
        private let lock = NSLock()
        private var callback: ((String?) -> Void)?
        private var count = 0
        var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
        func export(_ url: URL, raw: URL?, completion: @escaping (String?) -> Void) {
            lock.lock(); count += 1; callback = completion; lock.unlock()
        }
        func finish(_ error: String?) {
            lock.lock(); let completion = callback; callback = nil; lock.unlock(); completion?(error)
        }
    }
    @MainActor func testStorageKeepsOriginalAndDeletionCannotRaceExport() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let exporter = Exporter(), store = PhotoLibraryStore(directory: folder, exporter: exporter)
        let saved = expectation(description: "stored")
        let bytes = Data([1,2,3]) // Invalid style input: the successful original must survive.
        let output = PhotoJob.Output(data: PhotoCaptureData(processed: bytes, raw: nil, requiresRAW: false, error: nil),
                                     settings: CameraSettings(), type: .jpeg, dimensions: "test")
        store.store(.success(output), id: 1, rendering: {}) { result in
            if case .success(let photo) = result { XCTAssertFalse(photo.complete); XCTAssertNotNil(photo.warning) }
            else { XCTFail("Original was not preserved") }
            saved.fulfill()
        }
        await fulfillment(of: [saved], timeout: 3)
        let url = try XCTUnwrap(store.items.first?.url)
        XCTAssertEqual(try Data(contentsOf: url), bytes); XCTAssertEqual(exporter.calls, 1)
        XCTAssertEqual(store.bytes, Int64(bytes.count))
        let rejected = expectation(description: "delete blocked")
        store.delete(url) { XCTAssertNotNil($0); rejected.fulfill() }
        await fulfillment(of: [rejected], timeout: 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        exporter.finish(nil)
        let exported = expectation(for: NSPredicate { _, _ in store.items.first?.exportState == .exported }, evaluatedWith: nil)
        await fulfillment(of: [exported], timeout: 3)
        store.retryExport(url)
        let deleted = expectation(description: "delete after export")
        store.delete(url) { XCTAssertNil($0); deleted.fulfill() }
        await fulfillment(of: [deleted], timeout: 3)
        XCTAssertEqual(exporter.calls, 1); XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    @MainActor func testLedgerWriteFailureNeverStartsPhotosExport() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(".r6-exports.json"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let exporter = Exporter(), store = PhotoLibraryStore(directory: folder, exporter: exporter)
        let saved = expectation(description: "original persisted")
        let output = PhotoJob.Output(data: PhotoCaptureData(processed: Data([1]), raw: nil, requiresRAW: false, error: nil),
                                     settings: CameraSettings(), type: .jpeg, dimensions: nil)
        store.store(.success(output), id: 2, rendering: {}) { _ in saved.fulfill() }
        await fulfillment(of: [saved], timeout: 3)
        XCTAssertEqual(exporter.calls, 0)
        XCTAssertEqual(store.items.first?.exportState, .failed)
        XCTAssertNotNil(store.message)
    }
    func testGalleryThumbnailAndExifAreBoundedAndCancelledLoadsAreDiscarded() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        }
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage),
            [kCGImagePropertyExifDictionary: [kCGImagePropertyExifExposureTime: 0.008]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let loaded = await GalleryLoader.shared.load(url, maxPixels: 300)
        XCTAssertLessThanOrEqual(try XCTUnwrap(loaded?.image?.cgImage).width, 300)
        XCTAssertTrue(loaded?.metadata.contains("1/125") == true)
        let task = Task {
            try? await Task.sleep(nanoseconds: 1_000_000)
            return await GalleryLoader.shared.load(url, maxPixels: 4096)
        }
        task.cancel()
        let cancelled = await task.value
        XCTAssertNil(cancelled)
    }
}
#endif
