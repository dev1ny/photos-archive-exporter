import XCTest
@testable import PhotosArchiveExporterCore

final class FileHasherTests: XCTestCase {
    func testSHA256ForSmallFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("sample.txt")
        try Data("hello".utf8).write(to: file)

        let hash = try FileHasher.sha256Hex(for: file)

        XCTAssertEqual(hash, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }
}
