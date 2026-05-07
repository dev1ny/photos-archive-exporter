import Foundation
import ImageIO
import Vision

public enum FaceAnalysisImageDetectorError: Error, Equatable {
    case unsupportedImage(URL)
}

public struct DetectedFace: Equatable {
    public let boundingBox: NormalizedFaceBoundingBox
    public let confidence: Double?
    public let quality: Double?
    public let roll: Double?
    public let yaw: Double?
    public let pitch: Double?
    public let landmarks: [FaceLandmarkRecord]

    public init(
        boundingBox: NormalizedFaceBoundingBox,
        confidence: Double?,
        quality: Double?,
        roll: Double?,
        yaw: Double?,
        pitch: Double?,
        landmarks: [FaceLandmarkRecord]
    ) {
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.quality = quality
        self.roll = roll
        self.yaw = yaw
        self.pitch = pitch
        self.landmarks = landmarks
    }
}

public struct StillImageFaceDetectionResult: Equatable {
    public let imageWidth: Int
    public let imageHeight: Int
    public let faces: [DetectedFace]

    public init(imageWidth: Int, imageHeight: Int, faces: [DetectedFace]) {
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.faces = faces
    }
}

public protocol StillImageFaceDetecting {
    func detectFaces(in imageURL: URL) async throws -> StillImageFaceDetectionResult
}

public struct FaceAnalysisPhotoAnalyzerResult: Equatable {
    public let summary: FaceAnalysisRunSummary
    public let assetRecords: [FaceAnalysisAssetRecord]
    public let faceObservations: [FaceObservationRecord]

    public init(
        summary: FaceAnalysisRunSummary,
        assetRecords: [FaceAnalysisAssetRecord],
        faceObservations: [FaceObservationRecord]
    ) {
        self.summary = summary
        self.assetRecords = assetRecords
        self.faceObservations = faceObservations
    }
}

public struct FaceAnalysisPhotoAnalyzer {
    private let detector: any StillImageFaceDetecting

    public init(detector: any StillImageFaceDetecting = VisionStillImageFaceDetector()) {
        self.detector = detector
    }

    public func analyze(
        records: [ExportRecord],
        runID: String,
        settings: FaceAnalysisSettings,
        analyzedAt: Date = Date()
    ) async -> FaceAnalysisPhotoAnalyzerResult {
        var assetRecords: [FaceAnalysisAssetRecord] = []
        var faceObservations: [FaceObservationRecord] = []

        for record in records where shouldAnalyze(record) {
            let imageURL = URL(fileURLWithPath: record.destinationPath)
            do {
                let detection = try await detector.detectFaces(in: imageURL)
                assetRecords.append(
                    makeAssetRecord(
                        from: record,
                        runID: runID,
                        imageWidth: detection.imageWidth,
                        imageHeight: detection.imageHeight,
                        facesDetected: detection.faces.count,
                        status: .analyzed,
                        analyzedAt: analyzedAt,
                        errorMessage: nil
                    )
                )
                faceObservations.append(
                    contentsOf: detection.faces.enumerated().map { faceIndex, face in
                        makeFaceObservation(from: face, exportRecord: record, runID: runID, faceIndex: faceIndex)
                    }
                )
            } catch {
                assetRecords.append(
                    makeAssetRecord(
                        from: record,
                        runID: runID,
                        imageWidth: nil,
                        imageHeight: nil,
                        facesDetected: 0,
                        status: .failed,
                        analyzedAt: analyzedAt,
                        errorMessage: String(describing: error)
                    )
                )
            }
        }

        let summary = FaceAnalysisRunSummary(
            runID: runID,
            startedAt: analyzedAt,
            finishedAt: analyzedAt,
            settings: settings,
            assetRecords: assetRecords,
            faceObservations: faceObservations
        )

        return FaceAnalysisPhotoAnalyzerResult(
            summary: summary,
            assetRecords: assetRecords,
            faceObservations: faceObservations
        )
    }

    private func shouldAnalyze(_ record: ExportRecord) -> Bool {
        record.mediaType == .image && record.status != .failed
    }

    private func makeAssetRecord(
        from record: ExportRecord,
        runID: String,
        imageWidth: Int?,
        imageHeight: Int?,
        facesDetected: Int,
        status: FaceAnalysisAssetStatus,
        analyzedAt: Date,
        errorMessage: String?
    ) -> FaceAnalysisAssetRecord {
        FaceAnalysisAssetRecord(
            runID: runID,
            assetLocalIdentifier: record.assetLocalIdentifier,
            resourceIdentifier: record.resourceIdentifier,
            mediaType: record.mediaType,
            originalFilename: record.originalFilename,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            modificationDate: nil,
            fileSize: record.fileSize,
            sha256: record.sha256,
            status: status,
            facesDetected: facesDetected,
            analyzedAt: analyzedAt,
            warningMessage: nil,
            errorMessage: errorMessage
        )
    }

    private func makeFaceObservation(
        from face: DetectedFace,
        exportRecord: ExportRecord,
        runID: String,
        faceIndex: Int
    ) -> FaceObservationRecord {
        FaceObservationRecord(
            runID: runID,
            faceObservationID: "\(runID)|\(exportRecord.assetLocalIdentifier)|\(exportRecord.resourceIdentifier)|\(faceIndex)",
            assetLocalIdentifier: exportRecord.assetLocalIdentifier,
            resourceIdentifier: exportRecord.resourceIdentifier,
            mediaType: exportRecord.mediaType,
            videoTimestampSeconds: nil,
            faceIndex: faceIndex,
            boundingBox: face.boundingBox,
            confidence: face.confidence,
            quality: face.quality,
            roll: face.roll,
            yaw: face.yaw,
            pitch: face.pitch,
            landmarks: face.landmarks
        )
    }
}

public struct VisionStillImageFaceDetector: StillImageFaceDetecting {
    public init() {}

    public func detectFaces(in imageURL: URL) async throws -> StillImageFaceDetectionResult {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                throw FaceAnalysisImageDetectorError.unsupportedImage(imageURL)
            }

            let request = VNDetectFaceLandmarksRequest()
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])

            let faces = (request.results ?? []).map { observation in
                DetectedFace(
                    boundingBox: NormalizedFaceBoundingBox(
                        x: observation.boundingBox.origin.x,
                        y: observation.boundingBox.origin.y,
                        width: observation.boundingBox.width,
                        height: observation.boundingBox.height
                    ),
                    confidence: Double(observation.confidence),
                    quality: nil,
                    roll: observation.roll?.doubleValue,
                    yaw: observation.yaw?.doubleValue,
                    pitch: observation.pitch?.doubleValue,
                    landmarks: Self.landmarkRecords(from: observation.landmarks)
                )
            }

            return StillImageFaceDetectionResult(
                imageWidth: image.width,
                imageHeight: image.height,
                faces: faces
            )
        }.value
    }

    private static func landmarkRecords(from landmarks: VNFaceLandmarks2D?) -> [FaceLandmarkRecord] {
        guard let landmarks else {
            return []
        }

        return [
            landmarkRecord(name: "faceContour", region: landmarks.faceContour),
            landmarkRecord(name: "leftEye", region: landmarks.leftEye),
            landmarkRecord(name: "rightEye", region: landmarks.rightEye),
            landmarkRecord(name: "leftEyebrow", region: landmarks.leftEyebrow),
            landmarkRecord(name: "rightEyebrow", region: landmarks.rightEyebrow),
            landmarkRecord(name: "nose", region: landmarks.nose),
            landmarkRecord(name: "noseCrest", region: landmarks.noseCrest),
            landmarkRecord(name: "medianLine", region: landmarks.medianLine),
            landmarkRecord(name: "outerLips", region: landmarks.outerLips),
            landmarkRecord(name: "innerLips", region: landmarks.innerLips),
            landmarkRecord(name: "leftPupil", region: landmarks.leftPupil),
            landmarkRecord(name: "rightPupil", region: landmarks.rightPupil)
        ].compactMap { $0 }
    }

    private static func landmarkRecord(name: String, region: VNFaceLandmarkRegion2D?) -> FaceLandmarkRecord? {
        guard let region else {
            return nil
        }

        return FaceLandmarkRecord(
            regionName: name,
            normalizedPoints: region.normalizedPoints.map { point in
                FaceLandmarkPoint(x: point.x, y: point.y)
            },
            confidence: nil
        )
    }
}
