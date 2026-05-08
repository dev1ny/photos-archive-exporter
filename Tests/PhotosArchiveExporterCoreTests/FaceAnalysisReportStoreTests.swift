import XCTest
@testable import PhotosArchiveExporterCore

final class FaceAnalysisReportStoreTests: XCTestCase {
    func testSettingsRoundTripThroughJSON() throws {
        let settings = FaceAnalysisSettings(
            includeVideos: true,
            resourceProfile: .balanced,
            imageLongEdgeLimit: 1600,
            videoFrameIntervalSeconds: 3,
            maxFramesPerVideo: 100,
            settingsVersion: 1
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(settings)
        let decoded = try JSONDecoder().decode(FaceAnalysisSettings.self, from: data)

        XCTAssertEqual(decoded, settings)
    }

    func testRunSummaryAggregatesAssetsAndFaces() {
        let records = [
            FaceAnalysisAssetRecord.analysisSample(
                assetLocalIdentifier: "asset-photo-faces",
                mediaType: .image,
                status: .analyzed,
                facesDetected: 3
            ),
            FaceAnalysisAssetRecord.analysisSample(
                assetLocalIdentifier: "asset-photo-empty",
                mediaType: .image,
                status: .analyzed,
                facesDetected: 0
            ),
            FaceAnalysisAssetRecord.analysisSample(
                assetLocalIdentifier: "asset-video-skipped",
                mediaType: .video,
                status: .skippedUnchanged,
                facesDetected: 0
            ),
            FaceAnalysisAssetRecord.analysisSample(
                assetLocalIdentifier: "asset-video-failed",
                mediaType: .video,
                status: .failed,
                facesDetected: 0,
                errorMessage: "Vision request failed."
            )
        ]
        let summary = FaceAnalysisRunSummary(
            runID: "run-1",
            startedAt: Date(timeIntervalSince1970: 0),
            finishedAt: Date(timeIntervalSince1970: 10),
            settings: .defaultLowResource,
            assetRecords: records,
            faceObservations: []
        )

        XCTAssertEqual(summary.totalAssetCount, 4)
        XCTAssertEqual(summary.analyzedAssetCount, 2)
        XCTAssertEqual(summary.skippedAssetCount, 1)
        XCTAssertEqual(summary.failedAssetCount, 1)
        XCTAssertEqual(summary.photoAssetCount, 2)
        XCTAssertEqual(summary.videoAssetCount, 2)
        XCTAssertEqual(summary.facesDetectedCount, 3)
        XCTAssertEqual(summary.assetsWithFacesCount, 1)
    }

    func testWritesIndexSummaryAndCSVReports() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = FaceAnalysisReportStore(destinationRoot: directory)
        let records = [
            FaceAnalysisAssetRecord.analysisSample(
                assetLocalIdentifier: "asset-1",
                mediaType: .image,
                status: .analyzed,
                facesDetected: 1
            ),
            FaceAnalysisAssetRecord.analysisSample(
                assetLocalIdentifier: "asset-2",
                mediaType: .image,
                status: .failed,
                facesDetected: 0,
                errorMessage: "Image request failed."
            )
        ]
        let face = FaceObservationRecord.analysisSample(
            faceObservationID: "face-1",
            assetLocalIdentifier: "asset-1",
            boundingBox: NormalizedFaceBoundingBox(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        )
        let summary = FaceAnalysisRunSummary(
            runID: "run-1",
            startedAt: Date(timeIntervalSince1970: 0),
            finishedAt: Date(timeIntervalSince1970: 10),
            settings: .defaultLowResource,
            assetRecords: records,
            faceObservations: [face]
        )

        try store.saveIndex(records)
        let loadedIndex = try store.loadIndex()
        let summaryURL = try store.writeRunSummary(summary)
        let assetsURL = try store.writeAssetsCSV(runID: "run-1", records: records)
        let facesURL = try store.writeFacesCSV(runID: "run-1", faces: [face])
        let errorsURL = try store.writeErrorsCSV(runID: "run-1", records: records)

        XCTAssertEqual(loadedIndex, records)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.indexURL.path))
        XCTAssertEqual(summaryURL.path, store.supportDirectory.appendingPathComponent("face-analysis-runs/run-1/run-1-summary.json").path)
        XCTAssertEqual(assetsURL.path, store.supportDirectory.appendingPathComponent("face-analysis-runs/run-1/run-1-assets.csv").path)
        XCTAssertEqual(facesURL.path, store.supportDirectory.appendingPathComponent("face-analysis-runs/run-1/run-1-faces.csv").path)
        XCTAssertEqual(errorsURL.path, store.supportDirectory.appendingPathComponent("face-analysis-runs/run-1/run-1-errors.csv").path)

        let assetsCSV = try String(contentsOf: assetsURL)
        let facesCSV = try String(contentsOf: facesURL)
        let errorsCSV = try String(contentsOf: errorsURL)
        XCTAssertTrue(assetsCSV.contains("assetLocalIdentifier"))
        XCTAssertTrue(facesCSV.contains("boundingBoxX"))
        XCTAssertTrue(errorsCSV.contains("Image request failed."))
        XCTAssertFalse(errorsCSV.contains("asset-1"))
    }

    func testFaceAnalysisIndexKeepsLatestRecordPerResource() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = FaceAnalysisReportStore(destinationRoot: directory)
        let firstRun = FaceAnalysisAssetRecord.analysisSample(
            runID: "run-1",
            assetLocalIdentifier: "asset-1",
            mediaType: .image,
            status: .analyzed,
            facesDetected: 1
        )
        let secondRun = FaceAnalysisAssetRecord.analysisSample(
            runID: "run-2",
            assetLocalIdentifier: "asset-1",
            mediaType: .image,
            status: .analyzed,
            facesDetected: 2
        )

        try store.saveIndex([firstRun, secondRun])

        let loaded = try store.loadIndex()
        XCTAssertEqual(loaded, [secondRun])
    }

    func testFaceAnalysisCSVNeutralizesSpreadsheetFormulas() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = FaceAnalysisReportStore(destinationRoot: directory)
        let dangerousValue = "=HYPERLINK(\"http://example.com\")"
        let record = FaceAnalysisAssetRecord.analysisSample(
            assetLocalIdentifier: "asset-1",
            mediaType: .image,
            originalFilename: dangerousValue,
            status: .failed,
            facesDetected: 0,
            errorMessage: dangerousValue
        )

        let csvURL = try store.writeAssetsCSV(runID: "run-1", records: [record])
        let csv = try String(contentsOf: csvURL)

        XCTAssertTrue(csv.contains("\"'=HYPERLINK(\"\"http://example.com\"\")\""))
    }

    func testRejectsInvalidFaceAnalysisRunIDs() throws {
        let invalidRunIDs = ["../escape", ".", "..", "bad/name", "bad\\name", ""]
        let record = FaceAnalysisAssetRecord.analysisSample(
            assetLocalIdentifier: "asset-1",
            mediaType: .image,
            status: .failed,
            facesDetected: 0,
            errorMessage: "Image request failed."
        )
        let face = FaceObservationRecord.analysisSample(
            faceObservationID: "face-1",
            assetLocalIdentifier: "asset-1",
            boundingBox: NormalizedFaceBoundingBox(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        )

        for runID in invalidRunIDs {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let store = FaceAnalysisReportStore(destinationRoot: directory)
            let summary = FaceAnalysisRunSummary(
                runID: runID,
                startedAt: Date(timeIntervalSince1970: 0),
                finishedAt: nil,
                settings: .defaultLowResource,
                assetRecords: [record],
                faceObservations: [face]
            )

            XCTAssertThrowsError(try store.writeRunSummary(summary))
            XCTAssertThrowsError(try store.writeAssetsCSV(runID: runID, records: [record]))
            XCTAssertThrowsError(try store.writeFacesCSV(runID: runID, faces: [face]))
            XCTAssertThrowsError(try store.writeErrorsCSV(runID: runID, records: [record]))
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.supportDirectory.path))
        }
    }
}

private extension FaceAnalysisAssetRecord {
    static func analysisSample(
        runID: String = "run-1",
        assetLocalIdentifier: String,
        mediaType: MediaType,
        originalFilename: String = "IMG_0001.HEIC",
        status: FaceAnalysisAssetStatus,
        facesDetected: Int,
        errorMessage: String? = nil
    ) -> FaceAnalysisAssetRecord {
        FaceAnalysisAssetRecord(
            runID: runID,
            assetLocalIdentifier: assetLocalIdentifier,
            resourceIdentifier: "\(assetLocalIdentifier)-resource",
            mediaType: mediaType,
            originalFilename: originalFilename,
            imageWidth: mediaType == .image ? 4000 : 1920,
            imageHeight: mediaType == .image ? 3000 : 1080,
            modificationDate: Date(timeIntervalSince1970: 0),
            fileSize: 12,
            sha256: "hash-\(assetLocalIdentifier)",
            status: status,
            facesDetected: facesDetected,
            analyzedAt: status == .analyzed ? Date(timeIntervalSince1970: 10) : nil,
            warningMessage: nil,
            errorMessage: errorMessage
        )
    }
}

private extension FaceObservationRecord {
    static func analysisSample(
        faceObservationID: String,
        assetLocalIdentifier: String,
        boundingBox: NormalizedFaceBoundingBox
    ) -> FaceObservationRecord {
        FaceObservationRecord(
            runID: "run-1",
            faceObservationID: faceObservationID,
            assetLocalIdentifier: assetLocalIdentifier,
            resourceIdentifier: "\(assetLocalIdentifier)-resource",
            mediaType: .image,
            videoTimestampSeconds: nil,
            faceIndex: 0,
            boundingBox: boundingBox,
            confidence: 0.9,
            quality: 0.8,
            roll: nil,
            yaw: nil,
            pitch: nil,
            landmarks: [
                FaceLandmarkRecord(
                    regionName: "leftEye",
                    normalizedPoints: [
                        FaceLandmarkPoint(x: 0.2, y: 0.3),
                        FaceLandmarkPoint(x: 0.25, y: 0.35)
                    ],
                    confidence: 0.7
                )
            ]
        )
    }
}
