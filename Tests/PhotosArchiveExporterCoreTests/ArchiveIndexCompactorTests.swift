import XCTest
@testable import PhotosArchiveExporterCore

final class ArchiveIndexCompactorTests: XCTestCase {
    func testKeepsLatestSuccessfulRecordPerResourceIdentity() {
        let exported = ExportRecord.compactorSample(runID: "run-1", status: .exported, destinationPath: "/archive/IMG_0001.HEIC")
        let skipped = ExportRecord.compactorSample(runID: "run-2", status: .skippedExisting, destinationPath: "/archive/IMG_0001.HEIC")

        let compacted = ArchiveIndexCompactor.compact([exported, skipped])

        XCTAssertEqual(compacted, [skipped])
    }

    func testDoesNotLetFailedRecordErasePreviousSuccessfulArchiveRecord() {
        let exported = ExportRecord.compactorSample(runID: "run-1", status: .exported, destinationPath: "/archive/IMG_0001.HEIC")
        let failed = ExportRecord.compactorSample(runID: "run-2", status: .failed, destinationPath: "/archive/IMG_0001.HEIC", sha256: nil)

        let compacted = ArchiveIndexCompactor.compact([exported, failed])

        XCTAssertEqual(compacted, [exported])
    }

    func testKeepsLatestFailureWhenNoSuccessfulRecordExists() {
        let firstFailure = ExportRecord.compactorSample(runID: "run-1", status: .failed, destinationPath: "/archive/IMG_0001.HEIC", sha256: nil)
        let secondFailure = ExportRecord.compactorSample(runID: "run-2", status: .failed, destinationPath: "/archive/IMG_0001.HEIC", sha256: nil)

        let compacted = ArchiveIndexCompactor.compact([firstFailure, secondFailure])

        XCTAssertEqual(compacted, [secondFailure])
    }

    func testResourceIdentityDoesNotCollideWhenComponentsContainSeparatorCharacters() {
        let first = ExportRecord.compactorSample(
            runID: "run-1",
            status: .exported,
            destinationPath: "/archive/A.HEIC",
            assetLocalIdentifier: "asset|one",
            resourceIdentifier: "resource"
        )
        let second = ExportRecord.compactorSample(
            runID: "run-1",
            status: .exported,
            destinationPath: "/archive/B.HEIC",
            assetLocalIdentifier: "asset",
            resourceIdentifier: "one|resource"
        )

        let compacted = ArchiveIndexCompactor.compact([first, second])

        XCTAssertEqual(compacted.count, 2)
        XCTAssertEqual(compacted.map(\.destinationPath), ["/archive/A.HEIC", "/archive/B.HEIC"])
    }
}

private extension ExportRecord {
    static func compactorSample(
        runID: String,
        status: ExportStatus,
        destinationPath: String,
        sha256: String? = "hash",
        assetLocalIdentifier: String = "asset-1",
        resourceIdentifier: String = "resource-1"
    ) -> ExportRecord {
        ExportRecord(
            runID: runID,
            assetLocalIdentifier: assetLocalIdentifier,
            resourceIdentifier: resourceIdentifier,
            resourceType: .photo,
            mediaType: .image,
            originalFilename: "IMG_0001.HEIC",
            destinationPath: destinationPath,
            captureDate: Date(timeIntervalSince1970: 0),
            captureDateSource: .assetCreationDate,
            fileSize: sha256 == nil ? 0 : 12,
            sha256: sha256,
            status: status,
            warnings: [],
            errorMessage: status == .failed ? "failed" : nil
        )
    }
}
