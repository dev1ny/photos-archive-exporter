import XCTest
@testable import PhotosArchiveExporterCore

final class SQLiteArchiveIndexStoreTests: XCTestCase {
    func testMigratesLegacyJSONIndexToSQLiteOnLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ArchiveIndexStore(destinationRoot: directory)
        let legacyRecord = ExportRecord.sqliteSample(runID: "legacy-run", assetLocalIdentifier: "asset-1", resourceIdentifier: "resource-1", status: .exported)
        try FileManager.default.createDirectory(at: store.supportDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([legacyRecord]).write(to: store.indexURL)

        let loaded = try store.loadIndex()

        XCTAssertEqual(loaded, [legacyRecord])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.sqliteIndexURL.path))
    }

    func testRetriesLegacyJSONMigrationWhenSQLiteExistsWithoutMigrationMarker() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ArchiveIndexStore(destinationRoot: directory)
        let legacyRecord = ExportRecord.sqliteSample(runID: "legacy-run", assetLocalIdentifier: "asset-1", resourceIdentifier: "resource-1", status: .exported)
        try FileManager.default.createDirectory(at: store.supportDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([legacyRecord]).write(to: store.indexURL)
        _ = try SQLiteArchiveIndexStore(destinationRoot: directory).loadRecords()

        let loaded = try store.loadIndex()

        XCTAssertEqual(loaded, [legacyRecord])
    }

    func testSaveIndexPersistsCompactedRecordsToSQLite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ArchiveIndexStore(destinationRoot: directory)
        let exported = ExportRecord.sqliteSample(runID: "run-1", assetLocalIdentifier: "asset-1", resourceIdentifier: "resource-1", status: .exported)
        let skipped = ExportRecord.sqliteSample(runID: "run-2", assetLocalIdentifier: "asset-1", resourceIdentifier: "resource-1", status: .skippedExisting)

        try store.saveIndex([exported, skipped])
        let loaded = try store.loadIndex()

        XCTAssertEqual(loaded, [skipped])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.sqliteIndexURL.path))
    }

    func testLoadsOnlyRecordsForRequestedResources() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ArchiveIndexStore(destinationRoot: directory)
        let first = ExportRecord.sqliteSample(runID: "run-1", assetLocalIdentifier: "asset-1", resourceIdentifier: "resource-1", status: .exported)
        let second = ExportRecord.sqliteSample(runID: "run-1", assetLocalIdentifier: "asset-2", resourceIdentifier: "resource-2", status: .exported)
        try store.saveIndex([first, second])
        let resource = AssetResourceDescriptor(
            assetLocalIdentifier: "asset-2",
            resourceIdentifier: "resource-2",
            resourceType: .photo,
            mediaType: .image,
            originalFilename: "IMG_0002.HEIC",
            uniformTypeIdentifier: "public.heic",
            assetCreationDate: Date(timeIntervalSince1970: 0)
        )

        let loaded = try store.loadIndex(for: [resource])

        XCTAssertEqual(loaded, [second])
    }

    func testLoadsDuplicateGroupsFromSQLite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ArchiveIndexStore(destinationRoot: directory)
        let first = ExportRecord.sqliteSample(
            runID: "run-1",
            assetLocalIdentifier: "asset-1",
            resourceIdentifier: "resource-1",
            status: .exported,
            destinationPath: "/archive/a.heic",
            sha256: "shared"
        )
        let second = ExportRecord.sqliteSample(
            runID: "run-1",
            assetLocalIdentifier: "asset-2",
            resourceIdentifier: "resource-2",
            status: .exported,
            destinationPath: "/archive/b.heic",
            sha256: "shared"
        )
        let sameDestination = ExportRecord.sqliteSample(
            runID: "run-1",
            assetLocalIdentifier: "asset-3",
            resourceIdentifier: "resource-3",
            status: .exported,
            destinationPath: "/archive/b.heic",
            sha256: "shared"
        )
        let unique = ExportRecord.sqliteSample(
            runID: "run-1",
            assetLocalIdentifier: "asset-4",
            resourceIdentifier: "resource-4",
            status: .exported,
            destinationPath: "/archive/c.heic",
            sha256: "unique"
        )
        try store.saveIndex([first, second, sameDestination, unique])

        let groups = try store.loadDuplicateGroups()

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.sha256, "shared")
        XCTAssertEqual(Set(groups.first?.records.map(\.destinationPath) ?? []), ["/archive/a.heic", "/archive/b.heic"])
    }

    func testFailedBatchDoesNotOverwriteExistingSuccessfulSQLiteRecord() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ArchiveIndexStore(destinationRoot: directory)
        let exported = ExportRecord.sqliteSample(runID: "run-1", assetLocalIdentifier: "asset-1", resourceIdentifier: "resource-1", status: .exported)
        let failed = ExportRecord.sqliteSample(runID: "run-2", assetLocalIdentifier: "asset-1", resourceIdentifier: "resource-1", status: .failed)

        try store.saveIndex([exported])
        try store.saveIndex([failed])

        let loaded = try store.loadIndex()
        XCTAssertEqual(loaded, [exported])
    }
}

private extension ExportRecord {
    static func sqliteSample(
        runID: String,
        assetLocalIdentifier: String,
        resourceIdentifier: String,
        status: ExportStatus,
        destinationPath: String? = nil,
        sha256: String? = nil
    ) -> ExportRecord {
        ExportRecord(
            runID: runID,
            assetLocalIdentifier: assetLocalIdentifier,
            resourceIdentifier: resourceIdentifier,
            resourceType: .photo,
            mediaType: .image,
            originalFilename: "\(resourceIdentifier).HEIC",
            destinationPath: destinationPath ?? "/archive/\(resourceIdentifier).HEIC",
            captureDate: Date(timeIntervalSince1970: 0),
            captureDateSource: .assetCreationDate,
            fileSize: status == .failed ? 0 : 12,
            sha256: status == .failed ? nil : (sha256 ?? "hash-\(resourceIdentifier)"),
            status: status,
            warnings: [],
            errorMessage: status == .failed ? "failed" : nil
        )
    }
}
