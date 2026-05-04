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
