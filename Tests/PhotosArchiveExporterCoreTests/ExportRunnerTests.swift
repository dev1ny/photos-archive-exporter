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
        let existingRecord = ExportRecord.runnerSample(
            assetLocalIdentifier: "asset-1",
            resourceIdentifier: "resource-1",
            destinationPath: preferred.path,
            sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )

        let records = await runner.export(
            resources: [resource],
            destinationRoot: directory,
            runID: "run-1",
            exportRunDate: Date(timeIntervalSince1970: 10),
            existingRecords: [existingRecord]
        )

        XCTAssertEqual(records[0].status, .skippedExisting)
        XCTAssertEqual(records[0].destinationPath, preferred.path)
    }

    func testSkipsExistingConflictFileWhenHashMatchesOnRerun() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let planner = PathPlanner(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0)!)
        let preferred = planner.preferredDestination(root: directory, captureDate: Date(timeIntervalSince1970: 0), originalFilename: "IMG_0001.HEIC")
        let conflict = PathPlanner.resolveConflict(for: preferred) { candidate in
            candidate == preferred
        }
        let nextConflict = PathPlanner.resolveConflict(for: preferred) { candidate in
            candidate == preferred || candidate == conflict
        }
        try FileManager.default.createDirectory(at: preferred.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("different".utf8).write(to: preferred)
        try Data("hello".utf8).write(to: conflict)
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
        let existingRecord = ExportRecord.runnerSample(
            assetLocalIdentifier: "asset-1",
            resourceIdentifier: "resource-1",
            destinationPath: conflict.path,
            sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )

        let records = await runner.export(
            resources: [resource],
            destinationRoot: directory,
            runID: "run-1",
            exportRunDate: Date(timeIntervalSince1970: 10),
            existingRecords: [existingRecord]
        )

        XCTAssertEqual(records[0].status, .skippedExisting)
        XCTAssertEqual(records[0].destinationPath, conflict.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: nextConflict.path))
    }

    func testExportsSameHashDifferentResourceToConflictPathWhenIndexDoesNotMatchIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let planner = PathPlanner(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0)!)
        let preferred = planner.preferredDestination(root: directory, captureDate: Date(timeIntervalSince1970: 0), originalFilename: "IMG_0001.HEIC")
        let conflict = PathPlanner.resolveConflict(for: preferred) { candidate in
            candidate == preferred
        }
        try FileManager.default.createDirectory(at: preferred.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: preferred)
        let resource = AssetResourceDescriptor(
            assetLocalIdentifier: "asset-2",
            resourceIdentifier: "resource-2",
            resourceType: .photo,
            mediaType: .image,
            originalFilename: "IMG_0001.HEIC",
            uniformTypeIdentifier: "public.heic",
            assetCreationDate: Date(timeIntervalSince1970: 0)
        )
        let runner = ExportRunner(resourceWriter: FakeResourceWriter(data: Data("hello".utf8)), pathPlanner: planner)
        let differentResourceRecord = ExportRecord.runnerSample(
            assetLocalIdentifier: "asset-1",
            resourceIdentifier: "resource-1",
            destinationPath: preferred.path,
            sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )

        let records = await runner.export(
            resources: [resource],
            destinationRoot: directory,
            runID: "run-1",
            exportRunDate: Date(timeIntervalSince1970: 10),
            existingRecords: [differentResourceRecord]
        )

        XCTAssertEqual(records[0].status, .renamedConflict)
        XCTAssertEqual(records[0].destinationPath, conflict.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: conflict.path))
    }

    func testLargeKnownRecordsPreserveExactIdentityDestinationHashMatching() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let planner = PathPlanner(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0)!)
        let preferred = planner.preferredDestination(root: directory, captureDate: Date(timeIntervalSince1970: 0), originalFilename: "IMG_0001.HEIC")
        let conflict = PathPlanner.resolveConflict(for: preferred) { candidate in
            candidate == preferred
        }
        try FileManager.default.createDirectory(at: preferred.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: preferred)
        let resource = AssetResourceDescriptor(
            assetLocalIdentifier: "asset-target",
            resourceIdentifier: "resource-target",
            resourceType: .photo,
            mediaType: .image,
            originalFilename: "IMG_0001.HEIC",
            uniformTypeIdentifier: "public.heic",
            assetCreationDate: Date(timeIntervalSince1970: 0)
        )
        let matchingHash = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        var existingRecords: [ExportRecord] = (0..<2_000).flatMap { index in
            [
                ExportRecord.runnerSample(
                    assetLocalIdentifier: "noise-asset-\(index)",
                    resourceIdentifier: "noise-resource-\(index)",
                    destinationPath: preferred.path,
                    sha256: matchingHash
                ),
                ExportRecord.runnerSample(
                    assetLocalIdentifier: "asset-target",
                    resourceIdentifier: "resource-target",
                    destinationPath: "/archive/other-\(index).HEIC",
                    sha256: matchingHash
                ),
                ExportRecord.runnerSample(
                    assetLocalIdentifier: "asset-target",
                    resourceIdentifier: "resource-target",
                    destinationPath: preferred.path,
                    sha256: "different-\(index)"
                )
            ]
        }
        existingRecords.append(
            ExportRecord.runnerSample(
                assetLocalIdentifier: "asset-target",
                resourceIdentifier: "resource-target",
                destinationPath: preferred.path,
                sha256: matchingHash
            )
        )
        let runner = ExportRunner(resourceWriter: FakeResourceWriter(data: Data("hello".utf8)), pathPlanner: planner)

        let records = await runner.export(
            resources: [resource],
            destinationRoot: directory,
            runID: "run-1",
            exportRunDate: Date(timeIntervalSince1970: 10),
            existingRecords: existingRecords
        )

        XCTAssertEqual(records[0].status, .skippedExisting)
        XCTAssertEqual(records[0].destinationPath, preferred.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: conflict.path))
    }

    func testExportsInBatchesAndCallsCompletionForEachBatch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resources = (0..<5).map { index in
            AssetResourceDescriptor(
                assetLocalIdentifier: "asset-\(index)",
                resourceIdentifier: "resource-\(index)",
                resourceType: .photo,
                mediaType: .image,
                originalFilename: "IMG_\(index).HEIC",
                uniformTypeIdentifier: "public.heic",
                assetCreationDate: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let runner = ExportRunner(resourceWriter: PerResourceFakeWriter())
        var batchSizes: [Int] = []

        let records = try await runner.exportInBatches(
            resources: resources,
            destinationRoot: directory,
            runID: "run-1",
            exportRunDate: Date(timeIntervalSince1970: 10),
            existingRecords: [],
            batchSize: 2
        ) { batch in
            batchSizes.append(batch.count)
        }

        XCTAssertEqual(records.count, 5)
        XCTAssertEqual(batchSizes, [2, 2, 1])
        XCTAssertEqual(records.map(\.status), Array(repeating: .exported, count: 5))
    }

    func testWritesPlannedCheckpointBeforeMovingCommittedFile() async throws {
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
        let runner = ExportRunner(
            resourceWriter: FakeResourceWriter(data: Data("hello".utf8)),
            pathPlanner: PathPlanner(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0)!)
        )
        var plannedRecords: [ExportRecord] = []

        let records = try await runner.exportInBatches(
            resources: [resource],
            destinationRoot: directory,
            runID: "run-1",
            exportRunDate: Date(timeIntervalSince1970: 10),
            existingRecords: [],
            batchSize: 1,
            didPlanRecord: { plannedRecord in
                try validatePlannedCheckpoint(plannedRecord, plannedRecords: &plannedRecords)
            }
        ) { _ in }

        XCTAssertEqual(plannedRecords.count, 1)
        XCTAssertEqual(records[0].status, .exported)
        XCTAssertEqual(records[0].destinationPath, plannedRecords[0].destinationPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: plannedRecords[0].destinationPath))
    }

    private func validatePlannedCheckpoint(_ plannedRecord: ExportRecord, plannedRecords: inout [ExportRecord]) throws {
        XCTAssertEqual(plannedRecord.status, .planned)
        XCTAssertEqual(plannedRecord.fileSize, 5)
        XCTAssertEqual(plannedRecord.sha256, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plannedRecord.destinationPath))
        plannedRecords.append(plannedRecord)
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

private struct PerResourceFakeWriter: ResourceWriting {
    func write(resource: AssetResourceDescriptor, to temporaryURL: URL) async throws {
        try Data(resource.resourceIdentifier.utf8).write(to: temporaryURL)
    }
}

private extension ExportRecord {
    static func runnerSample(
        assetLocalIdentifier: String,
        resourceIdentifier: String,
        destinationPath: String,
        sha256: String?,
        status: ExportStatus = .exported
    ) -> ExportRecord {
        ExportRecord(
            runID: "prior-run",
            assetLocalIdentifier: assetLocalIdentifier,
            resourceIdentifier: resourceIdentifier,
            resourceType: .photo,
            mediaType: .image,
            originalFilename: URL(fileURLWithPath: destinationPath).lastPathComponent,
            destinationPath: destinationPath,
            captureDate: Date(timeIntervalSince1970: 0),
            captureDateSource: .assetCreationDate,
            fileSize: 5,
            sha256: sha256,
            status: status,
            warnings: [],
            errorMessage: nil
        )
    }
}
