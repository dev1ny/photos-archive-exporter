import XCTest
@testable import PhotosArchiveExporterCore

final class PathPlannerTests: XCTestCase {
    func testCaptureDatePriorityUsesExifBeforeAssetCreation() {
        let exif = Date(timeIntervalSince1970: 100)
        let asset = Date(timeIntervalSince1970: 200)

        let decision = CaptureDateResolver.resolve(exifOriginal: exif, quickTimeCreation: nil, assetCreationDate: asset, exportRunDate: Date(timeIntervalSince1970: 300))

        XCTAssertEqual(decision.date, exif)
        XCTAssertEqual(decision.source, .exifOriginal)
        XCTAssertEqual(decision.warnings, [])
    }

    func testCaptureDateFallsBackToRunDateWithWarning() {
        let runDate = Date(timeIntervalSince1970: 300)

        let decision = CaptureDateResolver.resolve(exifOriginal: nil, quickTimeCreation: nil, assetCreationDate: nil, exportRunDate: runDate)

        XCTAssertEqual(decision.date, runDate)
        XCTAssertEqual(decision.source, .exportRunDate)
        XCTAssertEqual(decision.warnings, ["missing_capture_date"])
    }

    func testBuildsYearMonthDayPathWithTimestampPrefix() throws {
        let root = URL(fileURLWithPath: "/Archive")
        let date = ISO8601DateFormatter().date(from: "2024-08-16T14:22:10Z")!
        let planner = PathPlanner(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0)!)

        let url = planner.preferredDestination(root: root, captureDate: date, originalFilename: "IMG_1234.HEIC")

        XCTAssertEqual(url.path, "/Archive/2024/2024-08/2024-08-16/2024-08-16_14-22-10_IMG_1234.HEIC")
    }

    func testSanitizesUnsafeFilenameCharacters() {
        XCTAssertEqual(FilenameSanitizer.sanitize("IMG/12:34?.HEIC"), "IMG_12_34_.HEIC")
        XCTAssertEqual(FilenameSanitizer.sanitize("   "), "unnamed")
    }

    func testConflictSuffixesIncrementUntilAvailable() {
        let root = URL(fileURLWithPath: "/Archive")
        let preferred = root.appendingPathComponent("file.HEIC")
        let existing: Set<String> = [
            "/Archive/file.HEIC",
            "/Archive/file__2.HEIC"
        ]

        let resolved = PathPlanner.resolveConflict(for: preferred) { existing.contains($0.path) }

        XCTAssertEqual(resolved.path, "/Archive/file__3.HEIC")
    }
}
