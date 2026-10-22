import XCTest
@testable import R6Camera

final class PhotoCaptureDataTests: XCTestCase {
    func testRawFailureStillPersistsSuccessfulJPEG() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let jpeg = Data([1, 2, 3])
        let photo = PhotoCaptureData(processed: jpeg, raw: nil, requiresRAW: true, error: "RAW processing failed")
        let files = try photo.persist(in: directory, stem: "partial", processedExtension: "jpg")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(files.processed)), jpeg)
        XCTAssertNil(files.raw)
        XCTAssertTrue(photo.warning?.contains("RAW processing failed") == true)
        XCTAssertTrue(photo.warning?.contains("缺少 RAW") == true)
        XCTAssertFalse(photo.isEmpty)
    }
    func testProcessedFailureStillPersistsSuccessfulDNG() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let raw = Data([4, 5, 6])
        let photo = PhotoCaptureData(processed: nil, raw: raw, requiresRAW: true, error: "JPEG failed")
        let files = try photo.persist(in: directory, stem: "partial", processedExtension: "jpg")
        XCTAssertNil(files.processed)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(files.raw)), raw)
        XCTAssertNotNil(photo.warning)
        let gallery = PhotoCaptureData.galleryItems(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
        XCTAssertEqual(gallery.map { $0.resolvingSymlinksInPath() }, [try XCTUnwrap(files.raw).resolvingSymlinksInPath()])
    }
    func testCompleteAndEmptyCaptureIntegrity() {
        let complete = PhotoCaptureData(processed: Data([1]), raw: Data([2]), requiresRAW: true, error: nil)
        XCTAssertNil(complete.warning)
        XCTAssertFalse(complete.isEmpty)
        let empty = PhotoCaptureData(processed: nil, raw: nil, requiresRAW: false, error: "Capture failed")
        XCTAssertTrue(empty.isEmpty)
        XCTAssertNotNil(empty.warning)
    }
    func testPairedRAWIsNotADuplicateGalleryEntry() {
        let root = URL(fileURLWithPath: "/photos")
        let jpeg = root.appendingPathComponent("paired.jpg")
        let paired = root.appendingPathComponent("paired.dng")
        let rawOnly = root.appendingPathComponent("raw.dng")
        let unrelated = root.appendingPathComponent("report.json")
        XCTAssertEqual(Set(PhotoCaptureData.galleryItems([jpeg, paired, rawOnly, unrelated])), Set([jpeg, rawOnly]))
    }
    func testWriteFailureForOneResourceDoesNotDiscardTheOther() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = PhotoCaptureData(processed: Data([1]), raw: Data([2]), requiresRAW: true, error: nil)
        // A directory at one destination makes just that resource unwritable.
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("first.jpg"), withIntermediateDirectories: false)
        let rawSaved = try photo.persist(in: directory, stem: "first", processedExtension: "jpg")
        XCTAssertNil(rawSaved.processed)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(rawSaved.raw)), Data([2]))
        XCTAssertNotNil(rawSaved.warning)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("second.dng"), withIntermediateDirectories: false)
        let jpegSaved = try photo.persist(in: directory, stem: "second", processedExtension: "jpg")
        XCTAssertNil(jpegSaved.raw)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(jpegSaved.processed)), Data([1]))
        XCTAssertNotNil(jpegSaved.warning)
    }
}
