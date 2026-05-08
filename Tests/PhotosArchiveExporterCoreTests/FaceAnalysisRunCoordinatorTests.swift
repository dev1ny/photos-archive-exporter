import XCTest
@testable import PhotosArchiveExporterCore

final class FaceAnalysisRunCoordinatorTests: XCTestCase {
    func testAnalyzesCurrentExportRecordsAndWritesReports() async throws {
        let destinationRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let imageURL = try writeTemporaryFile(named: "IMG_0001.HEIC", contents: Data("image-data".utf8))
        let exportRecord = ExportRecord.coordinatorSample(destinationPath: imageURL.path)
        let detector = CoordinatorFakeFaceDetector(results: [
            imageURL.path: StillImageFaceDetectionResult(
                imageWidth: 1200,
                imageHeight: 900,
                faces: [
                    DetectedFace(
                        boundingBox: NormalizedFaceBoundingBox(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
                        confidence: 0.9,
                        quality: nil,
                        roll: nil,
                        yaw: nil,
                        pitch: nil,
                        landmarks: []
                    )
                ]
            )
        ])
        let analyzer = FaceAnalysisPhotoAnalyzer(detector: detector)
        let coordinator = FaceAnalysisRunCoordinator(analyzer: analyzer)

        let result = try await coordinator.analyzeAndWriteReports(
            records: [exportRecord],
            destinationRoot: destinationRoot,
            runID: "face-run-1",
            settings: .defaultLowResource,
            analyzedAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(result.summary.analyzedAssetCount, 1)
        XCTAssertEqual(result.summary.failedAssetCount, 0)
        XCTAssertEqual(result.summary.facesDetectedCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.reportURLs.index.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.reportURLs.summary.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.reportURLs.assets.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.reportURLs.faces.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.reportURLs.errors.path))

        let store = FaceAnalysisReportStore(destinationRoot: destinationRoot)
        let index = try store.loadIndex()
        XCTAssertEqual(index.count, 1)
        XCTAssertEqual(index[0].facesDetected, 1)
    }

    private func writeTemporaryFile(named filename: String, contents: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(filename, isDirectory: false)
        try contents.write(to: url)
        return url
    }
}

private final class CoordinatorFakeFaceDetector: StillImageFaceDetectingWithLimit {
    private let results: [String: StillImageFaceDetectionResult]

    init(results: [String: StillImageFaceDetectionResult]) {
        self.results = results
    }

    func detectFaces(in imageURL: URL) async throws -> StillImageFaceDetectionResult {
        try await detectFaces(in: imageURL, imageLongEdgeLimit: FaceAnalysisSettings.defaultLowResource.imageLongEdgeLimit)
    }

    func detectFaces(in imageURL: URL, imageLongEdgeLimit: Int) async throws -> StillImageFaceDetectionResult {
        guard let result = results[imageURL.path] else {
            throw CoordinatorFakeFaceDetectorError.unexpectedPath
        }
        return result
    }
}

private enum CoordinatorFakeFaceDetectorError: Error {
    case unexpectedPath
}

private extension ExportRecord {
    static func coordinatorSample(destinationPath: String) -> ExportRecord {
        ExportRecord(
            runID: "export-run-1",
            assetLocalIdentifier: "asset-1",
            resourceIdentifier: "resource-1",
            resourceType: .photo,
            mediaType: .image,
            originalFilename: URL(fileURLWithPath: destinationPath).lastPathComponent,
            destinationPath: destinationPath,
            captureDate: Date(timeIntervalSince1970: 0),
            captureDateSource: .assetCreationDate,
            fileSize: 10,
            sha256: "hash",
            status: .exported,
            warnings: [],
            errorMessage: nil
        )
    }
}
