import Foundation

public enum FaceAnalysisResourceProfile: String, Codable, Equatable, CaseIterable {
    case lowResource
    case balanced
    case faster
}

public enum FaceAnalysisAssetStatus: String, Codable, Equatable, CaseIterable {
    case analyzed
    case skippedUnchanged
    case failed
    case canceled
}

public struct FaceAnalysisSettings: Codable, Equatable {
    public let includeVideos: Bool
    public let resourceProfile: FaceAnalysisResourceProfile
    public let imageLongEdgeLimit: Int
    public let videoFrameIntervalSeconds: Int
    public let maxFramesPerVideo: Int
    public let settingsVersion: Int

    public init(
        includeVideos: Bool,
        resourceProfile: FaceAnalysisResourceProfile,
        imageLongEdgeLimit: Int,
        videoFrameIntervalSeconds: Int,
        maxFramesPerVideo: Int,
        settingsVersion: Int
    ) {
        self.includeVideos = includeVideos
        self.resourceProfile = resourceProfile
        self.imageLongEdgeLimit = imageLongEdgeLimit
        self.videoFrameIntervalSeconds = videoFrameIntervalSeconds
        self.maxFramesPerVideo = maxFramesPerVideo
        self.settingsVersion = settingsVersion
    }

    public static let defaultLowResource = FaceAnalysisSettings(
        includeVideos: false,
        resourceProfile: .lowResource,
        imageLongEdgeLimit: 1600,
        videoFrameIntervalSeconds: 5,
        maxFramesPerVideo: 50,
        settingsVersion: 1
    )
}

public struct NormalizedFaceBoundingBox: Codable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct FaceLandmarkPoint: Codable, Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct FaceLandmarkRecord: Codable, Equatable {
    public let regionName: String
    public let normalizedPoints: [FaceLandmarkPoint]
    public let confidence: Double?

    public init(regionName: String, normalizedPoints: [FaceLandmarkPoint], confidence: Double?) {
        self.regionName = regionName
        self.normalizedPoints = normalizedPoints
        self.confidence = confidence
    }
}

public struct FaceAnalysisAssetRecord: Codable, Equatable, Identifiable {
    public var id: String { "\(assetLocalIdentifier)|\(resourceIdentifier)" }
    public let runID: String
    public let assetLocalIdentifier: String
    public let resourceIdentifier: String
    public let mediaType: MediaType
    public let originalFilename: String
    public let imageWidth: Int?
    public let imageHeight: Int?
    public let modificationDate: Date?
    public let fileSize: Int64?
    public let sha256: String?
    public let status: FaceAnalysisAssetStatus
    public let facesDetected: Int
    public let analyzedAt: Date?
    public let warningMessage: String?
    public let errorMessage: String?

    public init(
        runID: String,
        assetLocalIdentifier: String,
        resourceIdentifier: String,
        mediaType: MediaType,
        originalFilename: String,
        imageWidth: Int?,
        imageHeight: Int?,
        modificationDate: Date?,
        fileSize: Int64?,
        sha256: String?,
        status: FaceAnalysisAssetStatus,
        facesDetected: Int,
        analyzedAt: Date?,
        warningMessage: String?,
        errorMessage: String?
    ) {
        self.runID = runID
        self.assetLocalIdentifier = assetLocalIdentifier
        self.resourceIdentifier = resourceIdentifier
        self.mediaType = mediaType
        self.originalFilename = originalFilename
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.modificationDate = modificationDate
        self.fileSize = fileSize
        self.sha256 = sha256
        self.status = status
        self.facesDetected = facesDetected
        self.analyzedAt = analyzedAt
        self.warningMessage = warningMessage
        self.errorMessage = errorMessage
    }
}

public struct FaceObservationRecord: Codable, Equatable, Identifiable {
    public var id: String { faceObservationID }
    public let runID: String
    public let faceObservationID: String
    public let assetLocalIdentifier: String
    public let resourceIdentifier: String
    public let mediaType: MediaType
    public let videoTimestampSeconds: Double?
    public let faceIndex: Int
    public let boundingBox: NormalizedFaceBoundingBox
    public let confidence: Double?
    public let quality: Double?
    public let roll: Double?
    public let yaw: Double?
    public let pitch: Double?
    public let landmarks: [FaceLandmarkRecord]

    public init(
        runID: String,
        faceObservationID: String,
        assetLocalIdentifier: String,
        resourceIdentifier: String,
        mediaType: MediaType,
        videoTimestampSeconds: Double?,
        faceIndex: Int,
        boundingBox: NormalizedFaceBoundingBox,
        confidence: Double?,
        quality: Double?,
        roll: Double?,
        yaw: Double?,
        pitch: Double?,
        landmarks: [FaceLandmarkRecord]
    ) {
        self.runID = runID
        self.faceObservationID = faceObservationID
        self.assetLocalIdentifier = assetLocalIdentifier
        self.resourceIdentifier = resourceIdentifier
        self.mediaType = mediaType
        self.videoTimestampSeconds = videoTimestampSeconds
        self.faceIndex = faceIndex
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.quality = quality
        self.roll = roll
        self.yaw = yaw
        self.pitch = pitch
        self.landmarks = landmarks
    }
}

public struct FaceAnalysisRunSummary: Codable, Equatable {
    public let runID: String
    public let startedAt: Date
    public let finishedAt: Date?
    public let settings: FaceAnalysisSettings
    public let assetRecords: [FaceAnalysisAssetRecord]
    public let faceObservations: [FaceObservationRecord]

    public init(
        runID: String,
        startedAt: Date,
        finishedAt: Date?,
        settings: FaceAnalysisSettings,
        assetRecords: [FaceAnalysisAssetRecord],
        faceObservations: [FaceObservationRecord]
    ) {
        self.runID = runID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.settings = settings
        self.assetRecords = assetRecords
        self.faceObservations = faceObservations
    }

    public var totalAssetCount: Int { assetRecords.count }
    public var analyzedAssetCount: Int { assetRecords.filter { $0.status == .analyzed }.count }
    public var skippedAssetCount: Int { assetRecords.filter { $0.status == .skippedUnchanged }.count }
    public var failedAssetCount: Int { assetRecords.filter { $0.status == .failed }.count }
    public var canceledAssetCount: Int { assetRecords.filter { $0.status == .canceled }.count }
    public var photoAssetCount: Int { assetRecords.filter { $0.mediaType == .image }.count }
    public var videoAssetCount: Int { assetRecords.filter { $0.mediaType == .video }.count }
    public var facesDetectedCount: Int { assetRecords.reduce(0) { $0 + $1.facesDetected } }
    public var assetsWithFacesCount: Int { assetRecords.filter { $0.facesDetected > 0 }.count }
}
