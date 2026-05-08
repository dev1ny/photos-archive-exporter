import XCTest
@testable import PhotosArchiveExporterCore

final class FaceAnalysisPhotoAnalyzerTests: XCTestCase {
    func testAnalyzesExportedImageRecordsWithInjectedDetector() async throws {
        let imageURL = try writeTemporaryFile(named: "IMG_0001.HEIC", contents: Data("image-data".utf8))
        let record = ExportRecord.photoAnalysisSample(
            assetLocalIdentifier: "asset-1",
            resourceIdentifier: "resource-1",
            destinationPath: imageURL.path,
            mediaType: .image,
            status: .exported,
            fileSize: 10,
            sha256: "image-hash"
        )
        let detector = FakeStillImageFaceDetector(results: [
            imageURL.path: .success(
                StillImageFaceDetectionResult(
                    imageWidth: 4000,
                    imageHeight: 3000,
                    faces: [
                        DetectedFace(
                            boundingBox: NormalizedFaceBoundingBox(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
                            confidence: 0.95,
                            quality: nil,
                            roll: nil,
                            yaw: nil,
                            pitch: nil,
                            landmarks: [
                                FaceLandmarkRecord(
                                    regionName: "leftEye",
                                    normalizedPoints: [FaceLandmarkPoint(x: 0.2, y: 0.3)],
                                    confidence: nil
                                )
                            ]
                        ),
                        DetectedFace(
                            boundingBox: NormalizedFaceBoundingBox(x: 0.5, y: 0.6, width: 0.2, height: 0.2),
                            confidence: 0.8,
                            quality: 0.7,
                            roll: 0.1,
                            yaw: 0.2,
                            pitch: nil,
                            landmarks: []
                        )
                    ]
                )
            )
        ])
        let analyzer = FaceAnalysisPhotoAnalyzer(detector: detector)

        let result = await analyzer.analyze(
            records: [record],
            runID: "run-1",
            settings: .defaultLowResource,
            analyzedAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(detector.requestedPaths, [imageURL.path])
        XCTAssertEqual(detector.requestedImageLongEdgeLimits, [FaceAnalysisSettings.defaultLowResource.imageLongEdgeLimit])
        XCTAssertEqual(result.assetRecords.count, 1)
        XCTAssertEqual(result.assetRecords[0].status, .analyzed)
        XCTAssertEqual(result.assetRecords[0].facesDetected, 2)
        XCTAssertEqual(result.assetRecords[0].imageWidth, 4000)
        XCTAssertEqual(result.assetRecords[0].imageHeight, 3000)
        XCTAssertEqual(result.assetRecords[0].fileSize, 10)
        XCTAssertEqual(result.assetRecords[0].sha256, "image-hash")
        XCTAssertNil(result.assetRecords[0].errorMessage)
        XCTAssertEqual(result.faceObservations.count, 2)
        XCTAssertEqual(result.faceObservations[0].faceObservationID, "run-1|asset-1|resource-1|0")
        XCTAssertEqual(result.faceObservations[0].landmarks.map(\.regionName), ["leftEye"])
        XCTAssertEqual(result.summary.facesDetectedCount, 2)
    }

    func testPassesConfiguredImageLongEdgeLimitToDetector() async throws {
        let imageURL = try writeTemporaryFile(named: "IMG_0001.HEIC", contents: Data("image-data".utf8))
        let record = ExportRecord.photoAnalysisSample(
            assetLocalIdentifier: "asset-1",
            resourceIdentifier: "resource-1",
            destinationPath: imageURL.path,
            mediaType: .image,
            status: .exported
        )
        let detector = FakeStillImageFaceDetector(results: [
            imageURL.path: .success(StillImageFaceDetectionResult(imageWidth: 900, imageHeight: 600, faces: []))
        ])
        let analyzer = FaceAnalysisPhotoAnalyzer(detector: detector)
        let settings = FaceAnalysisSettings(
            includeVideos: false,
            resourceProfile: .lowResource,
            imageLongEdgeLimit: 900,
            videoFrameIntervalSeconds: 5,
            maxFramesPerVideo: 50,
            settingsVersion: 1
        )

        _ = await analyzer.analyze(
            records: [record],
            runID: "run-1",
            settings: settings,
            analyzedAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(detector.requestedImageLongEdgeLimits, [900])
    }

    func testReportsProgressForEligibleImageRecords() async throws {
        let firstURL = try writeTemporaryFile(named: "IMG_0001.HEIC", contents: Data("one".utf8))
        let secondURL = try writeTemporaryFile(named: "IMG_0002.HEIC", contents: Data("two".utf8))
        let records = [
            ExportRecord.photoAnalysisSample(
                assetLocalIdentifier: "asset-1",
                resourceIdentifier: "resource-1",
                destinationPath: firstURL.path,
                mediaType: .image,
                status: .exported
            ),
            ExportRecord.photoAnalysisSample(
                assetLocalIdentifier: "asset-video",
                resourceIdentifier: "resource-video",
                destinationPath: "/tmp/video.mov",
                mediaType: .video,
                status: .exported
            ),
            ExportRecord.photoAnalysisSample(
                assetLocalIdentifier: "asset-2",
                resourceIdentifier: "resource-2",
                destinationPath: secondURL.path,
                mediaType: .image,
                status: .exported
            )
        ]
        let detector = FakeStillImageFaceDetector(results: [
            firstURL.path: .success(StillImageFaceDetectionResult(imageWidth: 100, imageHeight: 80, faces: [])),
            secondURL.path: .success(StillImageFaceDetectionResult(imageWidth: 120, imageHeight: 90, faces: []))
        ])
        let analyzer = FaceAnalysisPhotoAnalyzer(detector: detector)
        let progressRecorder = ProgressRecorder()

        _ = await analyzer.analyze(
            records: records,
            runID: "run-1",
            settings: .defaultLowResource,
            analyzedAt: Date(timeIntervalSince1970: 20),
            progressHandler: { completed, total in
                await progressRecorder.record(completed: completed, total: total)
            }
        )

        let events = await progressRecorder.events
        XCTAssertEqual(events, [
            ProgressEvent(completed: 1, total: 2),
            ProgressEvent(completed: 2, total: 2)
        ])
    }

    func testRecordsFailedAnalysisWithoutStoppingRun() async throws {
        let failingURL = try writeTemporaryFile(named: "IMG_fail.HEIC", contents: Data("bad".utf8))
        let succeedingURL = try writeTemporaryFile(named: "IMG_ok.HEIC", contents: Data("ok".utf8))
        let failingRecord = ExportRecord.photoAnalysisSample(
            assetLocalIdentifier: "asset-fail",
            resourceIdentifier: "resource-fail",
            destinationPath: failingURL.path,
            mediaType: .image,
            status: .exported
        )
        let succeedingRecord = ExportRecord.photoAnalysisSample(
            assetLocalIdentifier: "asset-ok",
            resourceIdentifier: "resource-ok",
            destinationPath: succeedingURL.path,
            mediaType: .image,
            status: .exported
        )
        let detector = FakeStillImageFaceDetector(results: [
            failingURL.path: .failure(FakeDetectorError.failed),
            succeedingURL.path: .success(StillImageFaceDetectionResult(imageWidth: 100, imageHeight: 80, faces: []))
        ])
        let analyzer = FaceAnalysisPhotoAnalyzer(detector: detector)

        let result = await analyzer.analyze(
            records: [failingRecord, succeedingRecord],
            runID: "run-1",
            settings: .defaultLowResource,
            analyzedAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(result.assetRecords.map(\.status), [.failed, .analyzed])
        XCTAssertEqual(result.assetRecords[0].errorMessage, "failed")
        XCTAssertEqual(result.assetRecords[1].facesDetected, 0)
        XCTAssertTrue(result.faceObservations.isEmpty)
        XCTAssertEqual(result.summary.failedAssetCount, 1)
        XCTAssertEqual(result.summary.analyzedAssetCount, 1)
    }

    func testSkipsNonImageAndFailedExportRecords() async throws {
        let videoRecord = ExportRecord.photoAnalysisSample(
            assetLocalIdentifier: "asset-video",
            resourceIdentifier: "resource-video",
            destinationPath: "/tmp/video.mov",
            mediaType: .video,
            status: .exported
        )
        let failedExportRecord = ExportRecord.photoAnalysisSample(
            assetLocalIdentifier: "asset-failed",
            resourceIdentifier: "resource-failed",
            destinationPath: "/tmp/failed.heic",
            mediaType: .image,
            status: .failed
        )
        let detector = FakeStillImageFaceDetector(results: [:])
        let analyzer = FaceAnalysisPhotoAnalyzer(detector: detector)

        let result = await analyzer.analyze(
            records: [videoRecord, failedExportRecord],
            runID: "run-1",
            settings: .defaultLowResource,
            analyzedAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertTrue(detector.requestedPaths.isEmpty)
        XCTAssertTrue(result.assetRecords.isEmpty)
        XCTAssertTrue(result.faceObservations.isEmpty)
        XCTAssertEqual(result.summary.totalAssetCount, 0)
    }

    func testSkipsLivePhotoPairedVideoEvenWhenLegacyRecordSaysImage() async throws {
        let pairedVideoRecord = ExportRecord.photoAnalysisSample(
            assetLocalIdentifier: "asset-live",
            resourceIdentifier: "resource-paired-video",
            destinationPath: "/tmp/live.mov",
            resourceType: .pairedVideo,
            mediaType: .image,
            status: .exported
        )
        let detector = FakeStillImageFaceDetector(results: [:])
        let analyzer = FaceAnalysisPhotoAnalyzer(detector: detector)

        let result = await analyzer.analyze(
            records: [pairedVideoRecord],
            runID: "run-1",
            settings: .defaultLowResource,
            analyzedAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertTrue(detector.requestedPaths.isEmpty)
        XCTAssertTrue(result.assetRecords.isEmpty)
        XCTAssertEqual(result.summary.totalAssetCount, 0)
    }

    func testVisionDetectorThrowsForUnsupportedImageFile() async throws {
        let url = try writeTemporaryFile(named: "not-image.txt", contents: Data("not an image".utf8))
        let detector = VisionStillImageFaceDetector()

        do {
            _ = try await detector.detectFaces(in: url, imageLongEdgeLimit: 1600)
            XCTFail("Expected unsupported image to throw.")
        } catch FaceAnalysisImageDetectorError.unsupportedImage(let thrownURL) {
            XCTAssertEqual(thrownURL.path, url.path)
        } catch {
            XCTFail("Expected unsupportedImage, got \(error).")
        }
    }

    private func writeTemporaryFile(named filename: String, contents: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(filename, isDirectory: false)
        try contents.write(to: url)
        return url
    }
}

private struct ProgressEvent: Equatable {
    let completed: Int
    let total: Int
}

private actor ProgressRecorder {
    private var recordedEvents: [ProgressEvent] = []

    var events: [ProgressEvent] {
        recordedEvents
    }

    func record(completed: Int, total: Int) {
        recordedEvents.append(ProgressEvent(completed: completed, total: total))
    }
}

private final class FakeStillImageFaceDetector: StillImageFaceDetectingWithLimit {
    private let results: [String: Result<StillImageFaceDetectionResult, Error>]
    private(set) var requestedPaths: [String] = []
    private(set) var requestedImageLongEdgeLimits: [Int] = []

    init(results: [String: Result<StillImageFaceDetectionResult, Error>]) {
        self.results = results
    }

    func detectFaces(in imageURL: URL) async throws -> StillImageFaceDetectionResult {
        try await detectFaces(in: imageURL, imageLongEdgeLimit: FaceAnalysisSettings.defaultLowResource.imageLongEdgeLimit)
    }

    func detectFaces(in imageURL: URL, imageLongEdgeLimit: Int) async throws -> StillImageFaceDetectionResult {
        requestedPaths.append(imageURL.path)
        requestedImageLongEdgeLimits.append(imageLongEdgeLimit)
        guard let result = results[imageURL.path] else {
            throw FakeDetectorError.unexpectedPath
        }
        return try result.get()
    }
}

private enum FakeDetectorError: Error, CustomStringConvertible {
    case failed
    case unexpectedPath

    var description: String {
        switch self {
        case .failed:
            return "failed"
        case .unexpectedPath:
            return "unexpected path"
        }
    }
}

private extension ExportRecord {
    static func photoAnalysisSample(
        assetLocalIdentifier: String,
        resourceIdentifier: String,
        destinationPath: String,
        resourceType: ResourceType? = nil,
        mediaType: MediaType,
        status: ExportStatus,
        fileSize: Int64 = 12,
        sha256: String? = "hash"
    ) -> ExportRecord {
        ExportRecord(
            runID: "export-run-1",
            assetLocalIdentifier: assetLocalIdentifier,
            resourceIdentifier: resourceIdentifier,
            resourceType: resourceType ?? (mediaType == .video ? .video : .photo),
            mediaType: mediaType,
            originalFilename: URL(fileURLWithPath: destinationPath).lastPathComponent,
            destinationPath: destinationPath,
            captureDate: Date(timeIntervalSince1970: 0),
            captureDateSource: .assetCreationDate,
            fileSize: fileSize,
            sha256: sha256,
            status: status,
            warnings: [],
            errorMessage: status == .failed ? "Export failed." : nil
        )
    }
}
