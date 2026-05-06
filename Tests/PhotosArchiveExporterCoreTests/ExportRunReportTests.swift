import XCTest
@testable import PhotosArchiveExporterCore

final class ExportRunReportTests: XCTestCase {
    func testSummarizesRunIssuesForUI() {
        let exported = ExportRecord.reportSample(
            originalFilename: "IMG_0001.HEIC",
            destinationPath: "/archive/IMG_0001.HEIC",
            status: .exported,
            warnings: []
        )
        let failed = ExportRecord.reportSample(
            originalFilename: "IMG_0002.HEIC",
            destinationPath: "/archive/IMG_0002.HEIC",
            status: .failed,
            warnings: [],
            errorMessage: "The resource could not be read."
        )
        let warning = ExportRecord.reportSample(
            originalFilename: "IMG_0003.HEIC",
            destinationPath: "/archive/IMG_0003.HEIC",
            status: .exported,
            warnings: ["No embedded capture date; used Photos creation date."]
        )
        let renamed = ExportRecord.reportSample(
            originalFilename: "IMG_0004.HEIC",
            destinationPath: "/archive/IMG_0004 2.HEIC",
            status: .renamedConflict,
            warnings: []
        )
        let duplicateGroup = DuplicateGroup(sha256: "same-hash", records: [exported, warning])

        let report = ExportRunReport(
            runID: "run-1",
            currentRunRecords: [exported, failed, warning, renamed],
            duplicateGroups: [duplicateGroup]
        )

        XCTAssertEqual(report.totalCount, 4)
        XCTAssertEqual(report.failedRecords.map(\.originalFilename), ["IMG_0002.HEIC"])
        XCTAssertEqual(report.warningRecords.map(\.originalFilename), ["IMG_0003.HEIC"])
        XCTAssertEqual(report.renamedConflictRecords.map(\.originalFilename), ["IMG_0004.HEIC"])
        XCTAssertEqual(report.duplicateResourceCount, 2)
        XCTAssertTrue(report.hasIssues)
    }

    func testCleanRunHasNoIssues() {
        let report = ExportRunReport(
            runID: "run-1",
            currentRunRecords: [
                .reportSample(
                    originalFilename: "IMG_0001.HEIC",
                    destinationPath: "/archive/IMG_0001.HEIC",
                    status: .exported,
                    warnings: []
                )
            ],
            duplicateGroups: []
        )

        XCTAssertFalse(report.hasIssues)
        XCTAssertEqual(report.duplicateResourceCount, 0)
    }
}

private extension ExportRecord {
    static func reportSample(
        originalFilename: String,
        destinationPath: String,
        status: ExportStatus,
        warnings: [String],
        errorMessage: String? = nil
    ) -> ExportRecord {
        ExportRecord(
            runID: "run-1",
            assetLocalIdentifier: UUID().uuidString,
            resourceIdentifier: UUID().uuidString,
            resourceType: .photo,
            mediaType: .image,
            originalFilename: originalFilename,
            destinationPath: destinationPath,
            captureDate: Date(timeIntervalSince1970: 0),
            captureDateSource: .assetCreationDate,
            fileSize: 12,
            sha256: status == .failed ? nil : "same-hash",
            status: status,
            warnings: warnings,
            errorMessage: errorMessage
        )
    }
}
