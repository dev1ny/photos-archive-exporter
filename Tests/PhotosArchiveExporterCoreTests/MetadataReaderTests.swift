import XCTest
@testable import PhotosArchiveExporterCore

final class MetadataReaderTests: XCTestCase {
    func testReturnsNilDatesForPlainTextFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("sample.txt")
        try Data("not media".utf8).write(to: file)

        let metadata = MetadataReader.readCaptureDates(from: file)

        XCTAssertNil(metadata.exifOriginal)
        XCTAssertNil(metadata.quickTimeCreation)
    }
}
