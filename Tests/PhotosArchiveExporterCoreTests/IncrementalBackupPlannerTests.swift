import XCTest
@testable import PhotosArchiveExporterCore

final class IncrementalBackupPlannerTests: XCTestCase {
    func testSkipsPreviouslyExportedResourceWhenDestinationStillMatches() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = directory.appendingPathComponent("Archive/IMG_0001.HEIC")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: destination)
        let resource = AssetResourceDescriptor.incrementalSample(assetID: "asset-1", resourceID: "resource-1")
        let previousRecord = ExportRecord.incrementalSample(
            runID: "old-run",
            resource: resource,
            destinationPath: destination.path,
            fileSize: 5,
            sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
            status: .exported
        )

        let plan = try IncrementalBackupPlanner().plan(
            resources: [resource],
            previousRecords: [previousRecord],
            runID: "new-run",
            exportRunDate: Date(timeIntervalSince1970: 100)
        )

        XCTAssertTrue(plan.resourcesToExport.isEmpty)
        XCTAssertEqual(plan.skippedRecords.count, 1)
        XCTAssertEqual(plan.skippedRecords[0].runID, "new-run")
        XCTAssertEqual(plan.skippedRecords[0].status, .skippedExisting)
        XCTAssertEqual(plan.skippedRecords[0].destinationPath, destination.path)
        XCTAssertEqual(plan.entries.map(\.action), [.skipExisting])
    }

    func testExportsWhenPriorDestinationIsMissingOrChanged() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let missingDestination = directory.appendingPathComponent("Archive/MISSING.HEIC")
        let changedDestination = directory.appendingPathComponent("Archive/CHANGED.HEIC")
        try FileManager.default.createDirectory(at: changedDestination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("changed".utf8).write(to: changedDestination)

        let missingResource = AssetResourceDescriptor.incrementalSample(assetID: "asset-missing", resourceID: "resource-missing", filename: "MISSING.HEIC")
        let changedResource = AssetResourceDescriptor.incrementalSample(assetID: "asset-changed", resourceID: "resource-changed", filename: "CHANGED.HEIC")
        let previousRecords = [
            ExportRecord.incrementalSample(
                resource: missingResource,
                destinationPath: missingDestination.path,
                fileSize: 5,
                sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
            ),
            ExportRecord.incrementalSample(
                resource: changedResource,
                destinationPath: changedDestination.path,
                fileSize: 5,
                sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
            )
        ]

        let plan = try IncrementalBackupPlanner().plan(
            resources: [missingResource, changedResource],
            previousRecords: previousRecords,
            runID: "new-run",
            exportRunDate: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(plan.resourcesToExport.map(\.resourceIdentifier), ["resource-missing", "resource-changed"])
        XCTAssertTrue(plan.skippedRecords.isEmpty)
        XCTAssertEqual(plan.entries.map(\.action), [.exportMissingDestination, .exportChanged])
    }

    func testExportsWhenPreviousRecordCannotBeVerified() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = directory.appendingPathComponent("Archive/IMG_0001.HEIC")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: destination)
        let resource = AssetResourceDescriptor.incrementalSample(assetID: "asset-1", resourceID: "resource-1")
        let previousRecord = ExportRecord.incrementalSample(
            resource: resource,
            destinationPath: destination.path,
            fileSize: 5,
            sha256: nil
        )

        let plan = try IncrementalBackupPlanner().plan(
            resources: [resource],
            previousRecords: [previousRecord],
            runID: "new-run",
            exportRunDate: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(plan.resourcesToExport, [resource])
        XCTAssertTrue(plan.skippedRecords.isEmpty)
        XCTAssertEqual(plan.entries.map(\.action), [.exportUnverified])
    }

    func testRecoversCompletedPlannedCheckpointWhenDestinationStillMatches() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = directory.appendingPathComponent("Archive/IMG_0001.HEIC")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: destination)
        let resource = AssetResourceDescriptor.incrementalSample(assetID: "asset-1", resourceID: "resource-1")
        let plannedRecord = ExportRecord.incrementalSample(
            runID: "interrupted-run",
            resource: resource,
            destinationPath: destination.path,
            fileSize: 5,
            sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
            status: .planned
        )

        let plan = try IncrementalBackupPlanner().plan(
            resources: [resource],
            previousRecords: [plannedRecord],
            runID: "recovery-run",
            exportRunDate: Date(timeIntervalSince1970: 100)
        )

        XCTAssertTrue(plan.resourcesToExport.isEmpty)
        XCTAssertEqual(plan.entries.map(\.action), [.recoverPlannedCheckpoint])
        XCTAssertEqual(plan.skippedRecords.count, 1)
        XCTAssertEqual(plan.skippedRecords[0].status, .skippedExisting)
        XCTAssertEqual(plan.skippedRecords[0].sha256, plannedRecord.sha256)
    }

    func testExportsWhenPreviousDestinationCannotBeReadForVerification() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = directory.appendingPathComponent("Archive/IMG_0001.HEIC")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let directorySize = try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber
        let resource = AssetResourceDescriptor.incrementalSample(assetID: "asset-1", resourceID: "resource-1")
        let previousRecord = ExportRecord.incrementalSample(
            resource: resource,
            destinationPath: destination.path,
            fileSize: directorySize?.int64Value ?? 0,
            sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )

        let plan = try IncrementalBackupPlanner().plan(
            resources: [resource],
            previousRecords: [previousRecord],
            runID: "new-run",
            exportRunDate: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(plan.resourcesToExport, [resource])
        XCTAssertTrue(plan.skippedRecords.isEmpty)
        XCTAssertEqual(plan.entries.map(\.action), [.exportUnverified])
        XCTAssertTrue(plan.entries[0].note.contains("could not be verified"))
    }

    func testCurrentRunRecordsPreservePlannedResourceOrder() throws {
        let skippedResource = AssetResourceDescriptor.incrementalSample(assetID: "asset-skip", resourceID: "resource-skip", filename: "SKIP.HEIC")
        let exportedResource = AssetResourceDescriptor.incrementalSample(assetID: "asset-export", resourceID: "resource-export", filename: "EXPORT.HEIC")
        let skippedRecord = ExportRecord.incrementalSample(resource: skippedResource, destinationPath: "/archive/SKIP.HEIC", fileSize: 5, sha256: "aaa", status: .skippedExisting)
        let exportedRecord = ExportRecord.incrementalSample(resource: exportedResource, destinationPath: "/archive/EXPORT.HEIC", fileSize: 5, sha256: "bbb", status: .exported)
        let plan = IncrementalBackupPlan(
            entries: [
                .init(resource: skippedResource, action: .skipExisting, previousRecord: skippedRecord, note: "skip"),
                .init(resource: exportedResource, action: .exportNew, previousRecord: nil, note: "export")
            ],
            resourcesToExport: [exportedResource],
            skippedRecords: [skippedRecord]
        )

        let currentRunRecords = plan.currentRunRecords(exportedRecords: [exportedRecord])

        XCTAssertEqual(currentRunRecords.map(\.resourceIdentifier), ["resource-skip", "resource-export"])
        XCTAssertEqual(currentRunRecords.map(\.status), [.skippedExisting, .exported])
    }
}

private extension AssetResourceDescriptor {
    static func incrementalSample(assetID: String, resourceID: String, filename: String = "IMG_0001.HEIC") -> AssetResourceDescriptor {
        AssetResourceDescriptor(
            assetLocalIdentifier: assetID,
            resourceIdentifier: resourceID,
            resourceType: .photo,
            mediaType: .image,
            originalFilename: filename,
            uniformTypeIdentifier: "public.heic",
            assetCreationDate: Date(timeIntervalSince1970: 0)
        )
    }
}

private extension ExportRecord {
    static func incrementalSample(
        runID: String = "old-run",
        resource: AssetResourceDescriptor,
        destinationPath: String,
        fileSize: Int64,
        sha256: String?,
        status: ExportStatus = .exported
    ) -> ExportRecord {
        ExportRecord(
            runID: runID,
            assetLocalIdentifier: resource.assetLocalIdentifier,
            resourceIdentifier: resource.resourceIdentifier,
            resourceType: resource.resourceType,
            mediaType: resource.mediaType,
            originalFilename: resource.originalFilename,
            destinationPath: destinationPath,
            captureDate: Date(timeIntervalSince1970: 0),
            captureDateSource: .assetCreationDate,
            fileSize: fileSize,
            sha256: sha256,
            status: status,
            warnings: [],
            errorMessage: nil
        )
    }
}
