import XCTest
@testable import PhotosArchiveExporterCore

final class ArchiveIndexStoreTests: XCTestCase {
    func testWritesAndReadsSQLiteIndex() throws {
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

    func testRejectsInvalidRunIDsBeforeWritingReports() throws {
        let invalidRunIDs = ["../escape", ".", "..", "bad/name", "bad\\name", ""]
        let record = ExportRecord.indexSample(status: .failed, sha256: "aaa")
        let duplicateGroup = DuplicateGroup(sha256: "aaa", records: [record, record])

        for runID in invalidRunIDs {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let store = ArchiveIndexStore(destinationRoot: directory)

            XCTAssertThrowsError(try store.writeResourcesCSV(runID: runID, records: [record]))
            XCTAssertThrowsError(try store.writeErrorsCSV(runID: runID, records: [record]))
            XCTAssertThrowsError(try store.writeDuplicatesCSV(runID: runID, groups: [duplicateGroup]))
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.supportDirectory.path))
        }
    }

    func testNeutralizesFormulaLeadingCSVValues() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ArchiveIndexStore(destinationRoot: directory)
        let dangerousValue = "=HYPERLINK(\"http://example.com\")"
        let record = ExportRecord.indexSample(
            status: .failed,
            sha256: nil,
            originalFilename: dangerousValue,
            errorMessage: dangerousValue
        )

        let csvURL = try store.writeResourcesCSV(runID: "run-1", records: [record])
        let csv = try String(contentsOf: csvURL)

        XCTAssertTrue(csv.contains("\"'=HYPERLINK(\"\"http://example.com\"\")\""))
    }

    func testWritesIncrementalPlanCSV() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ArchiveIndexStore(destinationRoot: directory)
        let resource = AssetResourceDescriptor(
            assetLocalIdentifier: "asset-1",
            resourceIdentifier: "resource-1",
            resourceType: .photo,
            mediaType: .image,
            originalFilename: "IMG_0001.HEIC",
            uniformTypeIdentifier: "public.heic",
            assetCreationDate: Date(timeIntervalSince1970: 0)
        )
        let entry = IncrementalBackupPlanEntry(
            resource: resource,
            action: .skipExisting,
            previousRecord: ExportRecord.indexSample(status: .exported, sha256: "aaa"),
            note: "Previous destination file still matches the archive index."
        )

        let csvURL = try store.writeIncrementalPlanCSV(runID: "run-1", entries: [entry])
        let csv = try String(contentsOf: csvURL)

        XCTAssertTrue(csv.contains("action"))
        XCTAssertTrue(csv.contains("skipExisting"))
        XCTAssertTrue(csv.contains("Previous destination file still matches"))
    }

    func testRepeatedSkippedIncrementalRunsDoNotGrowArchiveIndex() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ArchiveIndexStore(destinationRoot: directory)
        let resourceCount = 100

        for run in 1...5 {
            let previous = try store.loadIndex()
            let currentRunRecords = (0..<resourceCount).map { index in
                ExportRecord.indexSample(
                    runID: "run-\(run)",
                    status: .skippedExisting,
                    sha256: "hash-\(index)",
                    assetLocalIdentifier: "asset-\(index)",
                    resourceIdentifier: "resource-\(index)"
                )
            }

            try store.saveIndex(previous + currentRunRecords)
            let loaded = try store.loadIndex()

            XCTAssertEqual(loaded.count, resourceCount)
            XCTAssertEqual(Set(loaded.map { "\($0.assetLocalIdentifier)|\($0.resourceIdentifier)" }).count, resourceCount)
            XCTAssertTrue(loaded.allSatisfy { $0.runID == "run-\(run)" })
        }
    }

    func testResourcesCSVStillWritesEveryCurrentRunRecordAfterIndexCompaction() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ArchiveIndexStore(destinationRoot: directory)
        try store.saveIndex([
            ExportRecord.indexSample(runID: "old-run", status: .exported, sha256: "aaa", resourceIdentifier: "resource-1"),
            ExportRecord.indexSample(runID: "new-run", status: .skippedExisting, sha256: "aaa", resourceIdentifier: "resource-1")
        ])
        let currentRunRecords = [
            ExportRecord.indexSample(runID: "run-1", status: .exported, sha256: "a", resourceIdentifier: "resource-a"),
            ExportRecord.indexSample(runID: "run-1", status: .skippedExisting, sha256: "b", resourceIdentifier: "resource-b"),
            ExportRecord.indexSample(runID: "run-1", status: .renamedConflict, sha256: "c", resourceIdentifier: "resource-c")
        ]

        let csvURL = try store.writeResourcesCSV(runID: "run-1", records: currentRunRecords)
        let csv = try String(contentsOf: csvURL)
        let lines = csv.split(separator: "\n")

        XCTAssertEqual(lines.count, currentRunRecords.count + 1)
        XCTAssertTrue(csv.contains("resource-a"))
        XCTAssertTrue(csv.contains("resource-b"))
        XCTAssertTrue(csv.contains("resource-c"))
        XCTAssertTrue(csv.contains("skippedExisting"))
        XCTAssertTrue(csv.contains("renamedConflict"))
        XCTAssertFalse(csv.contains("old-run"))
    }
}

private extension ExportRecord {
    static func indexSample(
        runID: String = "run-1",
        status: ExportStatus,
        sha256: String?,
        originalFilename: String = "IMG_0001.HEIC",
        errorMessage: String? = nil,
        assetLocalIdentifier: String = "asset-1",
        resourceIdentifier: String = "resource-1"
    ) -> ExportRecord {
        ExportRecord(
            runID: runID,
            assetLocalIdentifier: assetLocalIdentifier,
            resourceIdentifier: resourceIdentifier,
            resourceType: .photo,
            mediaType: .image,
            originalFilename: originalFilename,
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
