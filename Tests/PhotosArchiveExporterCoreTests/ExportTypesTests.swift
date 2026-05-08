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

    func testResourceMediaTypeResolverTreatsLivePhotoPairedVideoAsVideo() {
        XCTAssertEqual(ResourceMediaTypeResolver.mediaType(for: .pairedVideo, assetMediaType: .image), .video)
        XCTAssertEqual(ResourceMediaTypeResolver.mediaType(for: .fullSizePairedVideo, assetMediaType: .image), .video)
        XCTAssertEqual(ResourceMediaTypeResolver.mediaType(for: .video, assetMediaType: .image), .video)
        XCTAssertEqual(ResourceMediaTypeResolver.mediaType(for: .fullSizeVideo, assetMediaType: .image), .video)
    }

    func testResourceMediaTypeResolverPreservesPhotoResourcesAsImage() {
        XCTAssertEqual(ResourceMediaTypeResolver.mediaType(for: .photo, assetMediaType: .image), .image)
        XCTAssertEqual(ResourceMediaTypeResolver.mediaType(for: .fullSizePhoto, assetMediaType: .image), .image)
        XCTAssertEqual(ResourceMediaTypeResolver.mediaType(for: .alternatePhoto, assetMediaType: .image), .image)
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
