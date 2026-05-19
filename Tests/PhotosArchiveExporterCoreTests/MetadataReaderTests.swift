import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
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

    func testDoesNotUseTiffDateTimeAsExifOriginal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("sample.jpg")

        var pixels: [UInt8] = [255, 0, 0, 255]
        guard let context = CGContext(
            data: &pixels,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage(),
           let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            XCTFail("Failed to create test JPEG")
            return
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFDateTime: "2024:01:02 03:04:05",
                kCGImagePropertyTIFFMake: "TestMake"
            ]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let metadata = MetadataReader.readCaptureDates(from: file)

        XCTAssertNil(metadata.exifOriginal)
    }

    func testExifOriginalDateIsParsedInUTC() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("sample.jpg")

        var pixels: [UInt8] = [255, 0, 0, 255]
        guard let context = CGContext(
            data: &pixels,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage(),
           let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            XCTFail("Failed to create test JPEG")
            return
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2024:06:15 12:30:45"
            ]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let metadata = MetadataReader.readCaptureDates(from: file)
        let parsed = try XCTUnwrap(metadata.exifOriginal)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = MetadataReader.exifAssumedTimeZone
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: parsed
        )
        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 6)
        XCTAssertEqual(components.day, 15)
        XCTAssertEqual(components.hour, 12)
        XCTAssertEqual(components.minute, 30)
        XCTAssertEqual(components.second, 45)
        XCTAssertEqual(MetadataReader.exifAssumedTimeZone.secondsFromGMT(), 0)
    }
}
