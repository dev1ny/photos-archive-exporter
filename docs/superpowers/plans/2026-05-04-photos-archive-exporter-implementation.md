# Photos Archive Exporter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS SwiftUI app that exports original resources from the current Photos library into a year/month/day archive with reports and safe reruns.

**Architecture:** Create a Swift Package with a testable `PhotosArchiveExporterCore` library and a `PhotosArchiveExporterApp` SwiftUI executable. Keep PhotoKit access in the app target behind small adapters, while archive path planning, metadata reading, hashing, indexing, and CSV/JSON reporting live in the core target. Package the executable into a `.app` bundle with Photos privacy usage strings.

**Tech Stack:** Swift 5.9+, SwiftUI, PhotoKit, ImageIO, AVFoundation, CryptoKit, XCTest, shell build script.

---

## File Structure

- Create `Package.swift`: SwiftPM package definition for the core library, app executable, and tests.
- Create `Sources/PhotosArchiveExporterCore/ExportTypes.swift`: shared domain types for assets, resources, export records, statuses, and summaries.
- Create `Sources/PhotosArchiveExporterApp/main.swift`: temporary executable entry point until the SwiftUI app replaces it.
- Create `Sources/PhotosArchiveExporterCore/FilenameSanitizer.swift`: filesystem-safe filename cleanup.
- Create `Sources/PhotosArchiveExporterCore/CaptureDateResolver.swift`: date priority logic.
- Create `Sources/PhotosArchiveExporterCore/PathPlanner.swift`: year/month/day destination path generation and conflict suffix generation.
- Create `Sources/PhotosArchiveExporterCore/MetadataReader.swift`: EXIF and QuickTime date extraction from exported temporary files.
- Create `Sources/PhotosArchiveExporterCore/FileHasher.swift`: SHA-256 file hashing.
- Create `Sources/PhotosArchiveExporterCore/ArchiveIndexStore.swift`: JSON index and CSV report read/write.
- Create `Sources/PhotosArchiveExporterCore/DuplicateReporter.swift`: SHA-256 duplicate grouping.
- Create `Sources/PhotosArchiveExporterCore/ExportRunner.swift`: temporary export orchestration, hash verification, path conflict handling, and progress events using an injected resource writer.
- Create `Sources/PhotosArchiveExporterApp/PhotosArchiveExporterApp.swift`: SwiftUI entry point.
- Create `Sources/PhotosArchiveExporterApp/AppModel.swift`: app state, scan/export actions, and UI-facing progress.
- Create `Sources/PhotosArchiveExporterApp/ContentView.swift`: main exporter interface.
- Create `Sources/PhotosArchiveExporterApp/PhotoKitLibraryClient.swift`: PhotoKit authorization, asset scanning, resource enumeration, and `PHAssetResourceManager` writer.
- Create `scripts/build_app.sh`: release build and `.app` bundle assembly with `NSPhotoLibraryUsageDescription`.
- Create `Tests/PhotosArchiveExporterCoreTests/*.swift`: focused tests for core behavior.

## Task 1: Swift Package Skeleton And Core Types

**Files:**
- Create: `Package.swift`
- Create: `Sources/PhotosArchiveExporterCore/ExportTypes.swift`
- Create: `Sources/PhotosArchiveExporterApp/main.swift`
- Create: `Tests/PhotosArchiveExporterCoreTests/ExportTypesTests.swift`

- [ ] **Step 1: Create the Swift package definition**

Create `Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PhotosArchiveExporter",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "PhotosArchiveExporterCore",
            targets: ["PhotosArchiveExporterCore"]
        ),
        .executable(
            name: "PhotosArchiveExporterApp",
            targets: ["PhotosArchiveExporterApp"]
        )
    ],
    targets: [
        .target(
            name: "PhotosArchiveExporterCore"
        ),
        .executableTarget(
            name: "PhotosArchiveExporterApp",
            dependencies: ["PhotosArchiveExporterCore"]
        ),
        .testTarget(
            name: "PhotosArchiveExporterCoreTests",
            dependencies: ["PhotosArchiveExporterCore"]
        )
    ]
)
```

- [ ] **Step 2: Write the first failing model test**

Create `Tests/PhotosArchiveExporterCoreTests/ExportTypesTests.swift`:

```swift
import XCTest
@testable import PhotosArchiveExporterCore

final class ExportTypesTests: XCTestCase {
    func testRunSummaryCountsStatuses() {
        let records = [
            ExportRecord.sample(status: .exported, sha256: "aaa"),
            ExportRecord.sample(status: .skippedExisting, sha256: "aaa"),
            ExportRecord.sample(status: .failed, sha256: nil),
            ExportRecord.sample(status: .renamedConflict, sha256: "bbb")
        ]

        let summary = RunSummary(runID: "run-1", startedAt: .init(timeIntervalSince1970: 0), finishedAt: .init(timeIntervalSince1970: 10), records: records)

        XCTAssertEqual(summary.exportedCount, 1)
        XCTAssertEqual(summary.skippedCount, 1)
        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertEqual(summary.renamedConflictCount, 1)
    }
}

private extension ExportRecord {
    static func sample(status: ExportStatus, sha256: String?) -> ExportRecord {
        ExportRecord(
            runID: "run-1",
            assetLocalIdentifier: "asset-1",
            resourceIdentifier: "resource-1",
            resourceType: .photo,
            mediaType: .image,
            originalFilename: "IMG_0001.HEIC",
            destinationPath: "/Archive/2024/2024-08/2024-08-16/2024-08-16_12-00-00_IMG_0001.HEIC",
            captureDate: .init(timeIntervalSince1970: 0),
            captureDateSource: .assetCreationDate,
            fileSize: 12,
            sha256: sha256,
            status: status,
            warnings: [],
            errorMessage: nil
        )
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run:

```bash
swift test --filter ExportTypesTests
```

Expected: FAIL because `ExportRecord`, `ExportStatus`, and `RunSummary` do not exist.

- [ ] **Step 4: Add the core domain types**

Create `Sources/PhotosArchiveExporterCore/ExportTypes.swift`:

```swift
import Foundation

public enum ResourceType: String, Codable, Equatable, CaseIterable {
    case photo
    case video
    case pairedVideo
    case fullSizePhoto
    case fullSizeVideo
    case fullSizePairedVideo
    case alternatePhoto
    case other
}

public enum MediaType: String, Codable, Equatable, CaseIterable {
    case image
    case video
    case other
}

public enum CaptureDateSource: String, Codable, Equatable, CaseIterable {
    case exifOriginal
    case quickTimeCreation
    case assetCreationDate
    case exportRunDate
}

public enum ExportStatus: String, Codable, Equatable, CaseIterable {
    case planned
    case exported
    case skippedExisting
    case renamedConflict
    case failed
}

public struct PhotoAssetDescriptor: Codable, Equatable, Identifiable {
    public var id: String { localIdentifier }
    public let localIdentifier: String
    public let mediaType: MediaType
    public let creationDate: Date?
    public let modificationDate: Date?
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(localIdentifier: String, mediaType: MediaType, creationDate: Date?, modificationDate: Date?, pixelWidth: Int, pixelHeight: Int) {
        self.localIdentifier = localIdentifier
        self.mediaType = mediaType
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public struct AssetResourceDescriptor: Codable, Equatable, Identifiable {
    public var id: String { resourceIdentifier }
    public let assetLocalIdentifier: String
    public let resourceIdentifier: String
    public let resourceType: ResourceType
    public let mediaType: MediaType
    public let originalFilename: String
    public let uniformTypeIdentifier: String?
    public let assetCreationDate: Date?

    public init(assetLocalIdentifier: String, resourceIdentifier: String, resourceType: ResourceType, mediaType: MediaType, originalFilename: String, uniformTypeIdentifier: String?, assetCreationDate: Date?) {
        self.assetLocalIdentifier = assetLocalIdentifier
        self.resourceIdentifier = resourceIdentifier
        self.resourceType = resourceType
        self.mediaType = mediaType
        self.originalFilename = originalFilename
        self.uniformTypeIdentifier = uniformTypeIdentifier
        self.assetCreationDate = assetCreationDate
    }
}

public struct CaptureDateDecision: Codable, Equatable {
    public let date: Date
    public let source: CaptureDateSource
    public let warnings: [String]

    public init(date: Date, source: CaptureDateSource, warnings: [String]) {
        self.date = date
        self.source = source
        self.warnings = warnings
    }
}

public struct ExportRecord: Codable, Equatable, Identifiable {
    public var id: String { "\(assetLocalIdentifier)|\(resourceIdentifier)|\(originalFilename)" }
    public let runID: String
    public let assetLocalIdentifier: String
    public let resourceIdentifier: String
    public let resourceType: ResourceType
    public let mediaType: MediaType
    public let originalFilename: String
    public let destinationPath: String
    public let captureDate: Date
    public let captureDateSource: CaptureDateSource
    public let fileSize: Int64
    public let sha256: String?
    public let status: ExportStatus
    public let warnings: [String]
    public let errorMessage: String?

    public init(runID: String, assetLocalIdentifier: String, resourceIdentifier: String, resourceType: ResourceType, mediaType: MediaType, originalFilename: String, destinationPath: String, captureDate: Date, captureDateSource: CaptureDateSource, fileSize: Int64, sha256: String?, status: ExportStatus, warnings: [String], errorMessage: String?) {
        self.runID = runID
        self.assetLocalIdentifier = assetLocalIdentifier
        self.resourceIdentifier = resourceIdentifier
        self.resourceType = resourceType
        self.mediaType = mediaType
        self.originalFilename = originalFilename
        self.destinationPath = destinationPath
        self.captureDate = captureDate
        self.captureDateSource = captureDateSource
        self.fileSize = fileSize
        self.sha256 = sha256
        self.status = status
        self.warnings = warnings
        self.errorMessage = errorMessage
    }
}

public struct RunSummary: Codable, Equatable {
    public let runID: String
    public let startedAt: Date
    public let finishedAt: Date?
    public let records: [ExportRecord]

    public init(runID: String, startedAt: Date, finishedAt: Date?, records: [ExportRecord]) {
        self.runID = runID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.records = records
    }

    public var exportedCount: Int { records.filter { $0.status == .exported }.count }
    public var skippedCount: Int { records.filter { $0.status == .skippedExisting }.count }
    public var failedCount: Int { records.filter { $0.status == .failed }.count }
    public var renamedConflictCount: Int { records.filter { $0.status == .renamedConflict }.count }
}
```

- [ ] **Step 5: Add a temporary executable entry point**

Create `Sources/PhotosArchiveExporterApp/main.swift` so SwiftPM can build the executable target before the SwiftUI app is added in Task 7:

```swift
print("Photos Archive Exporter")
```

- [ ] **Step 6: Run the model test to verify it passes**

Run:

```bash
swift test --filter ExportTypesTests
```

Expected: PASS.

- [ ] **Step 7: Commit Task 1**

Run:

```bash
git add Package.swift Sources/PhotosArchiveExporterCore/ExportTypes.swift Sources/PhotosArchiveExporterApp/main.swift Tests/PhotosArchiveExporterCoreTests/ExportTypesTests.swift docs/superpowers/plans/2026-05-04-photos-archive-exporter-implementation.md
git commit -m "feat: add photos exporter core models"
```

## Task 2: Filename, Capture Date, And Path Planning

**Files:**
- Create: `Sources/PhotosArchiveExporterCore/FilenameSanitizer.swift`
- Create: `Sources/PhotosArchiveExporterCore/CaptureDateResolver.swift`
- Create: `Sources/PhotosArchiveExporterCore/PathPlanner.swift`
- Create: `Tests/PhotosArchiveExporterCoreTests/PathPlannerTests.swift`

- [ ] **Step 1: Write failing path and date tests**

Create `Tests/PhotosArchiveExporterCoreTests/PathPlannerTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
swift test --filter PathPlannerTests
```

Expected: FAIL because the planner and resolver types do not exist.

- [ ] **Step 3: Implement filename sanitizing**

Create `Sources/PhotosArchiveExporterCore/FilenameSanitizer.swift`:

```swift
import Foundation

public enum FilenameSanitizer {
    public static func sanitize(_ filename: String) -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "unnamed"
        }

        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let scalars = trimmed.unicodeScalars.map { scalar in
            invalidCharacters.contains(scalar) || scalar.properties.isControl ? "_" : Character(scalar)
        }
        let cleaned = String(scalars)
        return cleaned.isEmpty ? "unnamed" : cleaned
    }
}
```

- [ ] **Step 4: Implement capture date priority**

Create `Sources/PhotosArchiveExporterCore/CaptureDateResolver.swift`:

```swift
import Foundation

public enum CaptureDateResolver {
    public static func resolve(exifOriginal: Date?, quickTimeCreation: Date?, assetCreationDate: Date?, exportRunDate: Date) -> CaptureDateDecision {
        if let exifOriginal {
            return CaptureDateDecision(date: exifOriginal, source: .exifOriginal, warnings: [])
        }

        if let quickTimeCreation {
            return CaptureDateDecision(date: quickTimeCreation, source: .quickTimeCreation, warnings: [])
        }

        if let assetCreationDate {
            return CaptureDateDecision(date: assetCreationDate, source: .assetCreationDate, warnings: [])
        }

        return CaptureDateDecision(date: exportRunDate, source: .exportRunDate, warnings: ["missing_capture_date"])
    }
}
```

- [ ] **Step 5: Implement path planning and conflict suffixes**

Create `Sources/PhotosArchiveExporterCore/PathPlanner.swift`:

```swift
import Foundation

public struct PathPlanner {
    private let calendar: Calendar
    private let timeZone: TimeZone

    public init(calendar: Calendar = Calendar(identifier: .gregorian), timeZone: TimeZone = .current) {
        var configured = calendar
        configured.timeZone = timeZone
        self.calendar = configured
        self.timeZone = timeZone
    }

    public func preferredDestination(root: URL, captureDate: Date, originalFilename: String) -> URL {
        let year = format(captureDate, "yyyy")
        let month = format(captureDate, "yyyy-MM")
        let day = format(captureDate, "yyyy-MM-dd")
        let timePrefix = format(captureDate, "yyyy-MM-dd_HH-mm-ss")
        let safeFilename = FilenameSanitizer.sanitize(originalFilename)
        return root
            .appendingPathComponent(year, isDirectory: true)
            .appendingPathComponent(month, isDirectory: true)
            .appendingPathComponent(day, isDirectory: true)
            .appendingPathComponent("\(timePrefix)_\(safeFilename)", isDirectory: false)
    }

    public static func resolveConflict(for preferred: URL, exists: (URL) -> Bool) -> URL {
        if !exists(preferred) {
            return preferred
        }

        let directory = preferred.deletingLastPathComponent()
        let base = preferred.deletingPathExtension().lastPathComponent
        let ext = preferred.pathExtension
        var counter = 2

        while true {
            let filename = ext.isEmpty ? "\(base)__\(counter)" : "\(base)__\(counter).\(ext)"
            let candidate = directory.appendingPathComponent(filename, isDirectory: false)
            if !exists(candidate) {
                return candidate
            }
            counter += 1
        }
    }

    private func format(_ date: Date, _ template: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = template
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run:

```bash
swift test --filter PathPlannerTests
```

Expected: PASS.

- [ ] **Step 7: Commit Task 2**

Run:

```bash
git add Sources/PhotosArchiveExporterCore/FilenameSanitizer.swift Sources/PhotosArchiveExporterCore/CaptureDateResolver.swift Sources/PhotosArchiveExporterCore/PathPlanner.swift Tests/PhotosArchiveExporterCoreTests/PathPlannerTests.swift
git commit -m "feat: add archive path planning"
```

## Task 3: Metadata Reader And File Hasher

**Files:**
- Create: `Sources/PhotosArchiveExporterCore/MetadataReader.swift`
- Create: `Sources/PhotosArchiveExporterCore/FileHasher.swift`
- Create: `Tests/PhotosArchiveExporterCoreTests/MetadataReaderTests.swift`
- Create: `Tests/PhotosArchiveExporterCoreTests/FileHasherTests.swift`

- [ ] **Step 1: Write failing metadata and hashing tests**

Create `Tests/PhotosArchiveExporterCoreTests/FileHasherTests.swift`:

```swift
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
```

Create `Tests/PhotosArchiveExporterCoreTests/MetadataReaderTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter FileHasherTests
swift test --filter MetadataReaderTests
```

Expected: FAIL because `FileHasher` and `MetadataReader` do not exist.

- [ ] **Step 3: Implement SHA-256 hashing**

Create `Sources/PhotosArchiveExporterCore/FileHasher.swift`:

```swift
import CryptoKit
import Foundation

public enum FileHasher {
    public static func sha256Hex(for url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 4: Implement image and QuickTime date extraction**

Create `Sources/PhotosArchiveExporterCore/MetadataReader.swift`:

```swift
import AVFoundation
import Foundation
import ImageIO

public struct ResourceMetadataDates: Equatable {
    public let exifOriginal: Date?
    public let quickTimeCreation: Date?

    public init(exifOriginal: Date?, quickTimeCreation: Date?) {
        self.exifOriginal = exifOriginal
        self.quickTimeCreation = quickTimeCreation
    }
}

public enum MetadataReader {
    public static func readCaptureDates(from url: URL) -> ResourceMetadataDates {
        ResourceMetadataDates(
            exifOriginal: readExifOriginalDate(from: url),
            quickTimeCreation: readQuickTimeCreationDate(from: url)
        )
    }

    private static func readExifOriginalDate(from url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let rawDate = exif?[kCGImagePropertyExifDateTimeOriginal] as? String
            ?? exif?[kCGImagePropertyExifDateTimeDigitized] as? String
            ?? tiff?[kCGImagePropertyTIFFDateTime] as? String

        guard let rawDate else {
            return nil
        }

        return parseExifDate(rawDate)
    }

    private static func readQuickTimeCreationDate(from url: URL) -> Date? {
        let asset = AVURLAsset(url: url)
        let metadataItems = asset.commonMetadata + asset.metadata
        for item in metadataItems {
            if item.commonKey?.rawValue == "creationDate", let date = item.dateValue {
                return date
            }

            if item.identifier?.rawValue.lowercased().contains("creationdate") == true, let date = item.dateValue {
                return date
            }

            if item.identifier?.rawValue.lowercased().contains("creationdate") == true, let string = item.stringValue {
                return ISO8601DateFormatter().date(from: string)
            }
        }

        return nil
    }

    private static func parseExifDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: value)
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run:

```bash
swift test --filter FileHasherTests
swift test --filter MetadataReaderTests
```

Expected: PASS.

- [ ] **Step 6: Commit Task 3**

Run:

```bash
git add Sources/PhotosArchiveExporterCore/MetadataReader.swift Sources/PhotosArchiveExporterCore/FileHasher.swift Tests/PhotosArchiveExporterCoreTests/MetadataReaderTests.swift Tests/PhotosArchiveExporterCoreTests/FileHasherTests.swift
git commit -m "feat: read media metadata and hashes"
```

## Task 4: Archive Index And Duplicate Reports

**Files:**
- Create: `Sources/PhotosArchiveExporterCore/ArchiveIndexStore.swift`
- Create: `Sources/PhotosArchiveExporterCore/DuplicateReporter.swift`
- Create: `Tests/PhotosArchiveExporterCoreTests/ArchiveIndexStoreTests.swift`
- Create: `Tests/PhotosArchiveExporterCoreTests/DuplicateReporterTests.swift`

- [ ] **Step 1: Write failing index and duplicate tests**

Create `Tests/PhotosArchiveExporterCoreTests/ArchiveIndexStoreTests.swift`:

```swift
import XCTest
@testable import PhotosArchiveExporterCore

final class ArchiveIndexStoreTests: XCTestCase {
    func testWritesAndReadsIndexJSON() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ArchiveIndexStore(destinationRoot: directory)
        let record = ExportRecord.indexSample(status: .exported, sha256: "aaa")

        try store.saveIndex([record])
        let loaded = try store.loadIndex()

        XCTAssertEqual(loaded, [record])
    }

    func testWritesCSVWithEscapedValues() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ArchiveIndexStore(destinationRoot: directory)
        let record = ExportRecord.indexSample(status: .failed, sha256: nil, errorMessage: "bad, value")

        let csvURL = try store.writeResourcesCSV(runID: "run-1", records: [record])
        let csv = try String(contentsOf: csvURL)

        XCTAssertTrue(csv.contains("\"bad, value\""))
        XCTAssertTrue(csv.contains("originalFilename"))
    }
}

private extension ExportRecord {
    static func indexSample(status: ExportStatus, sha256: String?, errorMessage: String? = nil) -> ExportRecord {
        ExportRecord(
            runID: "run-1",
            assetLocalIdentifier: "asset-1",
            resourceIdentifier: "resource-1",
            resourceType: .photo,
            mediaType: .image,
            originalFilename: "IMG_0001.HEIC",
            destinationPath: "/Archive/IMG_0001.HEIC",
            captureDate: Date(timeIntervalSince1970: 0),
            captureDateSource: .assetCreationDate,
            fileSize: 12,
            sha256: sha256,
            status: status,
            warnings: [],
            errorMessage: errorMessage
        )
    }
}
```

Create `Tests/PhotosArchiveExporterCoreTests/DuplicateReporterTests.swift`:

```swift
import XCTest
@testable import PhotosArchiveExporterCore

final class DuplicateReporterTests: XCTestCase {
    func testGroupsOnlyMatchingHashesWithMultipleRecords() {
        let records = [
            ExportRecord.duplicateSample(path: "/a.heic", sha256: "same"),
            ExportRecord.duplicateSample(path: "/b.heic", sha256: "same"),
            ExportRecord.duplicateSample(path: "/c.heic", sha256: "unique"),
            ExportRecord.duplicateSample(path: "/d.heic", sha256: nil)
        ]

        let groups = DuplicateReporter.strongDuplicateGroups(from: records)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].sha256, "same")
        XCTAssertEqual(groups[0].records.map(\.destinationPath).sorted(), ["/a.heic", "/b.heic"])
    }
}

private extension ExportRecord {
    static func duplicateSample(path: String, sha256: String?) -> ExportRecord {
        ExportRecord(
            runID: "run-1",
            assetLocalIdentifier: UUID().uuidString,
            resourceIdentifier: UUID().uuidString,
            resourceType: .photo,
            mediaType: .image,
            originalFilename: URL(fileURLWithPath: path).lastPathComponent,
            destinationPath: path,
            captureDate: Date(timeIntervalSince1970: 0),
            captureDateSource: .assetCreationDate,
            fileSize: 12,
            sha256: sha256,
            status: .exported,
            warnings: [],
            errorMessage: nil
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter ArchiveIndexStoreTests
swift test --filter DuplicateReporterTests
```

Expected: FAIL because index and duplicate types do not exist.

- [ ] **Step 3: Implement duplicate grouping**

Create `Sources/PhotosArchiveExporterCore/DuplicateReporter.swift`:

```swift
import Foundation

public struct DuplicateGroup: Codable, Equatable {
    public let sha256: String
    public let records: [ExportRecord]

    public init(sha256: String, records: [ExportRecord]) {
        self.sha256 = sha256
        self.records = records
    }
}

public enum DuplicateReporter {
    public static func strongDuplicateGroups(from records: [ExportRecord]) -> [DuplicateGroup] {
        let grouped = Dictionary(grouping: records.compactMap { record -> (String, ExportRecord)? in
            guard let sha256 = record.sha256, !sha256.isEmpty else {
                return nil
            }
            return (sha256, record)
        }, by: { $0.0 })

        return grouped
            .compactMap { sha256, pairs -> DuplicateGroup? in
                let records = pairs.map(\.1)
                return records.count > 1 ? DuplicateGroup(sha256: sha256, records: records) : nil
            }
            .sorted { $0.sha256 < $1.sha256 }
    }
}
```

- [ ] **Step 4: Implement JSON and CSV report storage**

Create `Sources/PhotosArchiveExporterCore/ArchiveIndexStore.swift`:

```swift
import Foundation

public struct ArchiveIndexStore {
    public let destinationRoot: URL

    public init(destinationRoot: URL) {
        self.destinationRoot = destinationRoot
    }

    public var supportDirectory: URL {
        destinationRoot.appendingPathComponent("_photos_archive_exporter", isDirectory: true)
    }

    public var indexURL: URL {
        supportDirectory.appendingPathComponent("archive-index.json", isDirectory: false)
    }

    public func loadIndex() throws -> [ExportRecord] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return []
        }

        let data = try Data(contentsOf: indexURL)
        return try jsonDecoder.decode([ExportRecord].self, from: data)
    }

    public func saveIndex(_ records: [ExportRecord]) throws {
        try ensureSupportDirectory()
        let data = try jsonEncoder.encode(records)
        try data.write(to: indexURL, options: [.atomic])
    }

    public func writeResourcesCSV(runID: String, records: [ExportRecord]) throws -> URL {
        try ensureRunDirectory(runID: runID)
        let url = runDirectory(runID: runID).appendingPathComponent("\(runID)-resources.csv", isDirectory: false)
        let rows = [resourceHeader] + records.map(resourceRow)
        try rows.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public func writeErrorsCSV(runID: String, records: [ExportRecord]) throws -> URL {
        try ensureRunDirectory(runID: runID)
        let url = runDirectory(runID: runID).appendingPathComponent("\(runID)-errors.csv", isDirectory: false)
        let failed = records.filter { $0.status == .failed }
        let rows = [resourceHeader] + failed.map(resourceRow)
        try rows.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public func writeDuplicatesCSV(runID: String, groups: [DuplicateGroup]) throws -> URL {
        try ensureRunDirectory(runID: runID)
        let url = runDirectory(runID: runID).appendingPathComponent("\(runID)-duplicates.csv", isDirectory: false)
        let header = csvRow(["sha256", "destinationPath", "originalFilename", "assetLocalIdentifier", "resourceIdentifier"])
        let rows = groups.flatMap { group in
            group.records.map { record in
                csvRow([group.sha256, record.destinationPath, record.originalFilename, record.assetLocalIdentifier, record.resourceIdentifier])
            }
        }
        try ([header] + rows).joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func ensureSupportDirectory() throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
    }

    private func ensureRunDirectory(runID: String) throws {
        try FileManager.default.createDirectory(at: runDirectory(runID: runID), withIntermediateDirectories: true)
    }

    private func runDirectory(runID: String) -> URL {
        supportDirectory.appendingPathComponent("export-runs", isDirectory: true).appendingPathComponent(runID, isDirectory: true)
    }

    private var resourceHeader: String {
        csvRow(["runID", "assetLocalIdentifier", "resourceIdentifier", "resourceType", "mediaType", "originalFilename", "destinationPath", "captureDate", "captureDateSource", "fileSize", "sha256", "status", "warnings", "errorMessage"])
    }

    private func resourceRow(_ record: ExportRecord) -> String {
        csvRow([
            record.runID,
            record.assetLocalIdentifier,
            record.resourceIdentifier,
            record.resourceType.rawValue,
            record.mediaType.rawValue,
            record.originalFilename,
            record.destinationPath,
            ISO8601DateFormatter().string(from: record.captureDate),
            record.captureDateSource.rawValue,
            String(record.fileSize),
            record.sha256 ?? "",
            record.status.rawValue,
            record.warnings.joined(separator: "|"),
            record.errorMessage ?? ""
        ])
    }

    private func csvRow(_ values: [String]) -> String {
        values.map { value in
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
                return "\"\(escaped)\""
            }
            return escaped
        }.joined(separator: ",")
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run:

```bash
swift test --filter ArchiveIndexStoreTests
swift test --filter DuplicateReporterTests
```

Expected: PASS.

- [ ] **Step 6: Commit Task 4**

Run:

```bash
git add Sources/PhotosArchiveExporterCore/ArchiveIndexStore.swift Sources/PhotosArchiveExporterCore/DuplicateReporter.swift Tests/PhotosArchiveExporterCoreTests/ArchiveIndexStoreTests.swift Tests/PhotosArchiveExporterCoreTests/DuplicateReporterTests.swift
git commit -m "feat: add archive reports"
```

## Task 5: Export Runner With Injected Resource Writer

**Files:**
- Create: `Sources/PhotosArchiveExporterCore/ExportRunner.swift`
- Create: `Tests/PhotosArchiveExporterCoreTests/ExportRunnerTests.swift`

- [ ] **Step 1: Write failing export runner tests**

Create `Tests/PhotosArchiveExporterCoreTests/ExportRunnerTests.swift`:

```swift
import XCTest
@testable import PhotosArchiveExporterCore

final class ExportRunnerTests: XCTestCase {
    func testExportsResourceToDatePathAndRecordsHash() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resource = AssetResourceDescriptor(
            assetLocalIdentifier: "asset-1",
            resourceIdentifier: "resource-1",
            resourceType: .photo,
            mediaType: .image,
            originalFilename: "IMG_0001.HEIC",
            uniformTypeIdentifier: "public.heic",
            assetCreationDate: Date(timeIntervalSince1970: 0)
        )
        let writer = FakeResourceWriter(data: Data("hello".utf8))
        let runner = ExportRunner(resourceWriter: writer, pathPlanner: PathPlanner(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0)!))

        let records = await runner.export(resources: [resource], destinationRoot: directory, runID: "run-1", exportRunDate: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].status, .exported)
        XCTAssertEqual(records[0].sha256, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        XCTAssertTrue(FileManager.default.fileExists(atPath: records[0].destinationPath))
        XCTAssertTrue(records[0].destinationPath.contains("/1970/1970-01/1970-01-01/1970-01-01_00-00-00_IMG_0001.HEIC"))
    }

    func testRecordsFailureAndContinues() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resources = [
            AssetResourceDescriptor(assetLocalIdentifier: "asset-1", resourceIdentifier: "fail", resourceType: .photo, mediaType: .image, originalFilename: "A.HEIC", uniformTypeIdentifier: nil, assetCreationDate: Date(timeIntervalSince1970: 0)),
            AssetResourceDescriptor(assetLocalIdentifier: "asset-2", resourceIdentifier: "ok", resourceType: .photo, mediaType: .image, originalFilename: "B.HEIC", uniformTypeIdentifier: nil, assetCreationDate: Date(timeIntervalSince1970: 0))
        ]
        let writer = FakeResourceWriter(data: Data("hello".utf8), failingResourceID: "fail")
        let runner = ExportRunner(resourceWriter: writer, pathPlanner: PathPlanner(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0)!))

        let records = await runner.export(resources: resources, destinationRoot: directory, runID: "run-1", exportRunDate: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(records.map(\.status), [.failed, .exported])
    }

    func testSkipsExistingFileWhenHashMatches() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let planner = PathPlanner(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0)!)
        let preferred = planner.preferredDestination(root: directory, captureDate: Date(timeIntervalSince1970: 0), originalFilename: "IMG_0001.HEIC")
        try FileManager.default.createDirectory(at: preferred.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: preferred)
        let resource = AssetResourceDescriptor(
            assetLocalIdentifier: "asset-1",
            resourceIdentifier: "resource-1",
            resourceType: .photo,
            mediaType: .image,
            originalFilename: "IMG_0001.HEIC",
            uniformTypeIdentifier: "public.heic",
            assetCreationDate: Date(timeIntervalSince1970: 0)
        )
        let runner = ExportRunner(resourceWriter: FakeResourceWriter(data: Data("hello".utf8)), pathPlanner: planner)

        let records = await runner.export(resources: [resource], destinationRoot: directory, runID: "run-1", exportRunDate: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(records[0].status, .skippedExisting)
        XCTAssertEqual(records[0].destinationPath, preferred.path)
    }
}

private struct FakeResourceWriter: ResourceWriting {
    let data: Data
    var failingResourceID: String?

    func write(resource: AssetResourceDescriptor, to temporaryURL: URL) async throws {
        if resource.resourceIdentifier == failingResourceID {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: temporaryURL)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter ExportRunnerTests
```

Expected: FAIL because `ExportRunner` and `ResourceWriting` do not exist.

- [ ] **Step 3: Implement the export runner**

Create `Sources/PhotosArchiveExporterCore/ExportRunner.swift`:

```swift
import Foundation

public protocol ResourceWriting {
    func write(resource: AssetResourceDescriptor, to temporaryURL: URL) async throws
}

public struct ExportRunner {
    private let resourceWriter: ResourceWriting
    private let pathPlanner: PathPlanner
    private let fileManager: FileManager

    public init(resourceWriter: ResourceWriting, pathPlanner: PathPlanner = PathPlanner(), fileManager: FileManager = .default) {
        self.resourceWriter = resourceWriter
        self.pathPlanner = pathPlanner
        self.fileManager = fileManager
    }

    public func export(resources: [AssetResourceDescriptor], destinationRoot: URL, runID: String, exportRunDate: Date) async -> [ExportRecord] {
        var records: [ExportRecord] = []

        for resource in resources {
            let record = await exportOne(resource: resource, destinationRoot: destinationRoot, runID: runID, exportRunDate: exportRunDate)
            records.append(record)
        }

        return records
    }

    private func exportOne(resource: AssetResourceDescriptor, destinationRoot: URL, runID: String, exportRunDate: Date) async -> ExportRecord {
        let temporaryDirectory = destinationRoot
            .appendingPathComponent("_photos_archive_exporter", isDirectory: true)
            .appendingPathComponent("tmp", isDirectory: true)
        let temporaryURL = temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: false)

        do {
            try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            try await resourceWriter.write(resource: resource, to: temporaryURL)

            let metadata = MetadataReader.readCaptureDates(from: temporaryURL)
            let capture = CaptureDateResolver.resolve(
                exifOriginal: metadata.exifOriginal,
                quickTimeCreation: metadata.quickTimeCreation,
                assetCreationDate: resource.assetCreationDate,
                exportRunDate: exportRunDate
            )
            let preferred = pathPlanner.preferredDestination(root: destinationRoot, captureDate: capture.date, originalFilename: resource.originalFilename)

            let hash = try FileHasher.sha256Hex(for: temporaryURL)
            let size = try Int64(fileManager.attributesOfItem(atPath: temporaryURL.path)[.size] as? UInt64 ?? 0)

            if fileManager.fileExists(atPath: preferred.path) {
                let existingHash = try FileHasher.sha256Hex(for: preferred)
                if existingHash == hash {
                    try? fileManager.removeItem(at: temporaryURL)
                    return makeRecord(resource: resource, runID: runID, destination: preferred, capture: capture, fileSize: size, sha256: hash, status: .skippedExisting, errorMessage: nil)
                }
            }

            let finalURL = PathPlanner.resolveConflict(for: preferred) { fileManager.fileExists(atPath: $0.path) }
            let renamed = finalURL != preferred
            try fileManager.createDirectory(at: finalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: temporaryURL, to: finalURL)
            return makeRecord(resource: resource, runID: runID, destination: finalURL, capture: capture, fileSize: size, sha256: hash, status: renamed ? .renamedConflict : .exported, errorMessage: nil)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            let fallbackCapture = CaptureDateResolver.resolve(exifOriginal: nil, quickTimeCreation: nil, assetCreationDate: resource.assetCreationDate, exportRunDate: exportRunDate)
            let fallbackURL = pathPlanner.preferredDestination(root: destinationRoot, captureDate: fallbackCapture.date, originalFilename: resource.originalFilename)
            return makeRecord(resource: resource, runID: runID, destination: fallbackURL, capture: fallbackCapture, fileSize: 0, sha256: nil, status: .failed, errorMessage: String(describing: error))
        }
    }

    private func makeRecord(resource: AssetResourceDescriptor, runID: String, destination: URL, capture: CaptureDateDecision, fileSize: Int64, sha256: String?, status: ExportStatus, errorMessage: String?) -> ExportRecord {
        ExportRecord(
            runID: runID,
            assetLocalIdentifier: resource.assetLocalIdentifier,
            resourceIdentifier: resource.resourceIdentifier,
            resourceType: resource.resourceType,
            mediaType: resource.mediaType,
            originalFilename: resource.originalFilename,
            destinationPath: destination.path,
            captureDate: capture.date,
            captureDateSource: capture.source,
            fileSize: fileSize,
            sha256: sha256,
            status: status,
            warnings: capture.warnings,
            errorMessage: errorMessage
        )
    }
}
```

- [ ] **Step 4: Run export runner tests**

Run:

```bash
swift test --filter ExportRunnerTests
```

Expected: PASS.

- [ ] **Step 5: Run all core tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 6: Commit Task 5**

Run:

```bash
git add Sources/PhotosArchiveExporterCore/ExportRunner.swift Tests/PhotosArchiveExporterCoreTests/ExportRunnerTests.swift
git commit -m "feat: add safe export runner"
```

## Task 6: PhotoKit Adapter

**Files:**
- Create: `Sources/PhotosArchiveExporterApp/PhotoKitLibraryClient.swift`

- [ ] **Step 1: Add PhotoKit client and resource writer**

Create `Sources/PhotosArchiveExporterApp/PhotoKitLibraryClient.swift`:

```swift
import Foundation
import Photos
import PhotosArchiveExporterCore

enum PhotosAuthorizationState: Equatable {
    case notDetermined
    case authorized
    case limited
    case denied
    case restricted

    var canRead: Bool {
        self == .authorized || self == .limited
    }
}

@MainActor
final class PhotoKitLibraryClient: ObservableObject {
    @Published private(set) var authorizationState: PhotosAuthorizationState = .notDetermined

    func refreshAuthorizationState() {
        authorizationState = Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestAuthorization() async -> PhotosAuthorizationState {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        let mapped = Self.map(status)
        authorizationState = mapped
        return mapped
    }

    func scanResources() async throws -> [AssetResourceDescriptor] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard Self.map(status).canRead else {
            throw PhotoKitError.notAuthorized
        }

        return try await Task.detached(priority: .userInitiated) {
            var resources: [AssetResourceDescriptor] = []
            let fetch = PHAsset.fetchAssets(with: nil)
            fetch.enumerateObjects { asset, _, _ in
                let assetMediaType = Self.mapMediaType(asset.mediaType)
                let assetResources = PHAssetResource.assetResources(for: asset)
                for resource in assetResources where Self.shouldExport(resource) {
                    resources.append(
                        AssetResourceDescriptor(
                            assetLocalIdentifier: asset.localIdentifier,
                            resourceIdentifier: "\(asset.localIdentifier)|\(resource.type.rawValue)|\(resource.originalFilename)",
                            resourceType: Self.mapResourceType(resource.type),
                            mediaType: assetMediaType,
                            originalFilename: resource.originalFilename,
                            uniformTypeIdentifier: resource.uniformTypeIdentifier,
                            assetCreationDate: asset.creationDate
                        )
                    )
                }
            }
            return resources
        }.value
    }

    private static func map(_ status: PHAuthorizationStatus) -> PhotosAuthorizationState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .limited:
            return .limited
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }

    private static func mapMediaType(_ mediaType: PHAssetMediaType) -> PhotosArchiveExporterCore.MediaType {
        switch mediaType {
        case .image:
            return .image
        case .video:
            return .video
        default:
            return .other
        }
    }

    private static func mapResourceType(_ type: PHAssetResourceType) -> ResourceType {
        switch type {
        case .photo:
            return .photo
        case .video:
            return .video
        case .pairedVideo:
            return .pairedVideo
        case .fullSizePhoto:
            return .fullSizePhoto
        case .fullSizeVideo:
            return .fullSizeVideo
        case .fullSizePairedVideo:
            return .fullSizePairedVideo
        case .alternatePhoto:
            return .alternatePhoto
        default:
            return .other
        }
    }

    private static func shouldExport(_ resource: PHAssetResource) -> Bool {
        switch resource.type {
        case .photo, .video, .pairedVideo, .fullSizePhoto, .fullSizeVideo, .fullSizePairedVideo, .alternatePhoto:
            return true
        default:
            return false
        }
    }
}

enum PhotoKitError: LocalizedError {
    case notAuthorized
    case resourceNotFound(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Photos access is not authorized."
        case .resourceNotFound(let identifier):
            return "Could not find Photos resource \(identifier)."
        }
    }
}

struct PhotoKitResourceWriter: ResourceWriting {
    func write(resource: AssetResourceDescriptor, to temporaryURL: URL) async throws {
        guard let phResource = findResource(for: resource) else {
            throw PhotoKitError.resourceNotFound(resource.resourceIdentifier)
        }

        try await withCheckedThrowingContinuation { continuation in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = false
            PHAssetResourceManager.default().writeData(for: phResource, toFile: temporaryURL, options: options) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func findResource(for descriptor: AssetResourceDescriptor) -> PHAssetResource? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [descriptor.assetLocalIdentifier], options: nil)
        guard let asset = assets.firstObject else {
            return nil
        }

        return PHAssetResource.assetResources(for: asset).first { resource in
            "\(asset.localIdentifier)|\(resource.type.rawValue)|\(resource.originalFilename)" == descriptor.resourceIdentifier
        }
    }
}
```

- [ ] **Step 2: Build to catch PhotoKit API issues**

Run:

```bash
swift build
```

Expected: PASS. If `PHAssetResourceType.fullSizePairedVideo` is unavailable on the installed SDK, remove only that enum case mapping and keep `.pairedVideo`.

- [ ] **Step 3: Commit Task 6**

Run:

```bash
git add Sources/PhotosArchiveExporterApp/PhotoKitLibraryClient.swift
git commit -m "feat: add photokit library client"
```

## Task 7: SwiftUI App State And Interface

**Files:**
- Create: `Sources/PhotosArchiveExporterApp/PhotosArchiveExporterApp.swift`
- Create: `Sources/PhotosArchiveExporterApp/AppModel.swift`
- Create: `Sources/PhotosArchiveExporterApp/ContentView.swift`

- [ ] **Step 1: Create app state model**

Create `Sources/PhotosArchiveExporterApp/AppModel.swift`:

```swift
import AppKit
import Foundation
import PhotosArchiveExporterCore

@MainActor
final class AppModel: ObservableObject {
    enum Phase: String {
        case idle = "Idle"
        case scanning = "Scanning"
        case ready = "Ready"
        case exporting = "Exporting"
        case finished = "Finished"
        case failed = "Failed"
    }

    @Published var phase: Phase = .idle
    @Published var destinationRoot: URL?
    @Published var resources: [AssetResourceDescriptor] = []
    @Published var records: [ExportRecord] = []
    @Published var statusMessage = "Select a destination folder, authorize Photos access, then scan the current library."
    @Published var lastError: String?

    let libraryClient: PhotoKitLibraryClient
    private let resourceWriter: ResourceWriting

    init(libraryClient: PhotoKitLibraryClient = PhotoKitLibraryClient(), resourceWriter: ResourceWriting = PhotoKitResourceWriter()) {
        self.libraryClient = libraryClient
        self.resourceWriter = resourceWriter
        self.libraryClient.refreshAuthorizationState()
    }

    var canScan: Bool {
        libraryClient.authorizationState.canRead
    }

    var canExport: Bool {
        destinationRoot != nil && !resources.isEmpty && phase != .exporting
    }

    var exportedCount: Int { records.filter { $0.status == .exported }.count }
    var skippedCount: Int { records.filter { $0.status == .skippedExisting }.count }
    var failedCount: Int { records.filter { $0.status == .failed }.count }
    var renamedCount: Int { records.filter { $0.status == .renamedConflict }.count }
    var duplicateCount: Int { DuplicateReporter.strongDuplicateGroups(from: records).reduce(0) { $0 + $1.records.count } }

    func requestPhotosAccess() {
        Task {
            let state = await libraryClient.requestAuthorization()
            statusMessage = state.canRead ? "Photos access granted." : "Photos access is not available."
        }
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Archive Folder"
        if panel.runModal() == .OK {
            destinationRoot = panel.url
            statusMessage = "Destination selected: \(panel.url?.path ?? "")"
        }
    }

    func scanLibrary() {
        phase = .scanning
        lastError = nil
        statusMessage = "Scanning current Photos library..."
        Task {
            do {
                resources = try await libraryClient.scanResources()
                phase = .ready
                statusMessage = "Scan complete. Found \(resources.count) original resources."
            } catch {
                phase = .failed
                lastError = error.localizedDescription
                statusMessage = "Scan failed."
            }
        }
    }

    func startExport() {
        guard let destinationRoot else {
            return
        }

        phase = .exporting
        lastError = nil
        statusMessage = "Exporting original resources..."
        let runID = Self.makeRunID(date: Date())
        let runner = ExportRunner(resourceWriter: resourceWriter)

        Task {
            let newRecords = await runner.export(resources: resources, destinationRoot: destinationRoot, runID: runID, exportRunDate: Date())
            records = newRecords

            do {
                let store = ArchiveIndexStore(destinationRoot: destinationRoot)
                let previous = try store.loadIndex()
                let combined = previous + newRecords
                try store.saveIndex(combined)
                try store.writeResourcesCSV(runID: runID, records: newRecords)
                try store.writeErrorsCSV(runID: runID, records: newRecords)
                try store.writeDuplicatesCSV(runID: runID, groups: DuplicateReporter.strongDuplicateGroups(from: combined))
                phase = .finished
                statusMessage = "Export finished. Reports saved in _photos_archive_exporter."
            } catch {
                phase = .failed
                lastError = error.localizedDescription
                statusMessage = "Export finished, but report writing failed."
            }
        }
    }

    func revealDestination() {
        guard let destinationRoot else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([destinationRoot])
    }

    private static func makeRunID(date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
    }
}
```

- [ ] **Step 2: Create SwiftUI entry point**

Create `Sources/PhotosArchiveExporterApp/PhotosArchiveExporterApp.swift`:

```swift
import SwiftUI

@main
struct PhotosArchiveExporterApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 920, minHeight: 620)
        }
    }
}
```

- [ ] **Step 3: Create the main exporter view**

Create `Sources/PhotosArchiveExporterApp/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            controls
            summary
            progressAndResults
            Spacer(minLength: 0)
        }
        .padding(24)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Photos Archive Exporter")
                .font(.system(size: 28, weight: .semibold))
            Text("Read-only original export from the current Photos library. To export an old .photoslibrary, open it in Photos first, then return here.")
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
            GridRow {
                Text("Photos Access")
                    .fontWeight(.medium)
                HStack {
                    Text(String(describing: model.libraryClient.authorizationState))
                        .monospaced()
                    Button("Authorize", action: model.requestPhotosAccess)
                }
            }

            GridRow {
                Text("Destination")
                    .fontWeight(.medium)
                HStack {
                    Text(model.destinationRoot?.path ?? "No folder selected")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose Folder", action: model.chooseDestination)
                }
            }

            GridRow {
                Text("Run")
                    .fontWeight(.medium)
                HStack {
                    Button("Scan Library", action: model.scanLibrary)
                        .disabled(!model.canScan || model.phase == .scanning || model.phase == .exporting)
                    Button("Start Full Export", action: model.startExport)
                        .disabled(!model.canExport)
                    Button("Reveal Destination", action: model.revealDestination)
                        .disabled(model.destinationRoot == nil)
                }
            }
        }
        .buttonStyle(.bordered)
    }

    private var summary: some View {
        HStack(spacing: 12) {
            metric("Resources", model.resources.count)
            metric("Exported", model.exportedCount)
            metric("Skipped", model.skippedCount)
            metric("Renamed", model.renamedCount)
            metric("Failed", model.failedCount)
            metric("Duplicates", model.duplicateCount)
        }
    }

    private func metric(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 130, alignment: .leading)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var progressAndResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.phase.rawValue)
                .font(.headline)
            Text(model.statusMessage)
                .foregroundStyle(.secondary)
            if let lastError = model.lastError {
                Text(lastError)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            if model.phase == .exporting || model.phase == .scanning {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        )
    }
}
```

- [ ] **Step 4: Build the app target**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 5: Commit Task 7**

Run:

```bash
git add Sources/PhotosArchiveExporterApp/PhotosArchiveExporterApp.swift Sources/PhotosArchiveExporterApp/AppModel.swift Sources/PhotosArchiveExporterApp/ContentView.swift
git commit -m "feat: add photos exporter mac app"
```

## Task 8: App Bundle Build Script

**Files:**
- Create: `scripts/build_app.sh`

- [ ] **Step 1: Create app bundle script**

Create `scripts/build_app.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Photos Archive Exporter"
BINARY_NAME="PhotosArchiveExporterApp"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp ".build/release/$BINARY_NAME" "$MACOS_DIR/$BINARY_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>PhotosArchiveExporterApp</string>
    <key>CFBundleIdentifier</key>
    <string>local.photos-archive-exporter</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Photos Archive Exporter</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPhotoLibraryUsageDescription</key>
    <string>Photos Archive Exporter needs read access to export original photos and videos into your chosen archive folder.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
```

- [ ] **Step 2: Make the script executable**

Run:

```bash
chmod +x scripts/build_app.sh
```

- [ ] **Step 3: Build the app bundle**

Run:

```bash
scripts/build_app.sh
```

Expected: PASS and prints `dist/Photos Archive Exporter.app`.

- [ ] **Step 4: Commit Task 8**

Run:

```bash
git add scripts/build_app.sh
git commit -m "build: add mac app bundle script"
```

## Task 9: Verification And First Manual Run

**Files:**
- Modify if needed: files from earlier tasks only when verification exposes a concrete issue.

- [ ] **Step 1: Run all tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 2: Build release app bundle**

Run:

```bash
scripts/build_app.sh
```

Expected: PASS and `dist/Photos Archive Exporter.app` exists.

- [ ] **Step 3: Launch the app**

Run:

```bash
open "dist/Photos Archive Exporter.app"
```

Expected: App opens, shows Photos authorization state, destination picker, scan button, and export button.

- [ ] **Step 4: Perform a small-library manual check**

Use the current Photos library only if it is safe to scan. Select a temporary archive destination such as `/private/tmp/photos-archive-export-test`, authorize Photos access, scan, then export a small library or cancel quickly after confirming the export begins.

Expected:

- App requests Photos access with the usage string.
- Scan produces a nonnegative resource count.
- Destination folder contains year/month/day folders when export completes for at least one resource.
- `_photos_archive_exporter/archive-index.json` exists after export completion.
- CSV reports exist under `_photos_archive_exporter/export-runs/<run-id>/`.
- Rerunning against the same destination records matching resources as skipped or conflict-renamed rather than overwritten.

- [ ] **Step 5: Commit verification fixes**

If verification required changes, run:

```bash
git add Package.swift Sources Tests scripts
git commit -m "fix: polish photos exporter verification"
```

If no changes were needed, skip this commit.
