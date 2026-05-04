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
