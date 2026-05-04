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
