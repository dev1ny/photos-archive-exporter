import XCTest
@testable import PhotosArchiveExporterCore

final class FilenameSanitizerTests: XCTestCase {
    func testReplacesInvalidCharacters() {
        XCTAssertEqual(FilenameSanitizer.sanitize("foo/bar:baz?.jpg"), "foo_bar_baz_.jpg")
    }

    func testReturnsUnnamedForEmptyInput() {
        XCTAssertEqual(FilenameSanitizer.sanitize(""), "unnamed")
        XCTAssertEqual(FilenameSanitizer.sanitize("   "), "unnamed")
    }

    func testStripsTrailingDotsAndSpaces() {
        XCTAssertEqual(FilenameSanitizer.sanitize("photo. "), "photo")
        XCTAssertEqual(FilenameSanitizer.sanitize("photo..."), "photo")
        XCTAssertEqual(FilenameSanitizer.sanitize("photo.jpg.."), "photo.jpg")
    }

    func testNeutralizesWindowsReservedNames() {
        XCTAssertEqual(FilenameSanitizer.sanitize("CON"), "_CON")
        XCTAssertEqual(FilenameSanitizer.sanitize("con.txt"), "_con.txt")
        XCTAssertEqual(FilenameSanitizer.sanitize("LPT3.JPG"), "_LPT3.JPG")
        // Names that merely contain a reserved word should be left alone.
        XCTAssertEqual(FilenameSanitizer.sanitize("CONcert.jpg"), "CONcert.jpg")
    }

    func testTruncatesOverlongFilenamesPreservingExtension() {
        let stem = String(repeating: "a", count: 300)
        let result = FilenameSanitizer.sanitize("\(stem).heic")
        XCTAssertLessThanOrEqual(result.utf8.count, 200)
        XCTAssertTrue(result.hasSuffix(".heic"))
    }

    func testTruncatesByteAwareForMultiByteScalars() {
        // Each 한 takes 3 UTF-8 bytes; 100 chars = 300 bytes.
        let stem = String(repeating: "한", count: 100)
        let result = FilenameSanitizer.sanitize("\(stem).jpg")
        XCTAssertLessThanOrEqual(result.utf8.count, 200)
        XCTAssertTrue(result.hasSuffix(".jpg"))
    }

    func testKeepsUnicodeAndEmojiUntouchedWhenWithinBudget() {
        XCTAssertEqual(FilenameSanitizer.sanitize("夏威夷🌴.jpg"), "夏威夷🌴.jpg")
    }
}
