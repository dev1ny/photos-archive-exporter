import Foundation

public enum ResourceType: String, Codable, Equatable, CaseIterable {
    case photo
    case video
    case pairedVideo
    case fullSizePhoto
    case fullSizeVideo
    case fullSizePairedVideo
    case alternatePhoto
    case other
}

public enum MediaType: String, Codable, Equatable, CaseIterable {
    case image
    case video
    case other
}

public enum ResourceMediaTypeResolver {
    public static func mediaType(for resourceType: ResourceType, assetMediaType: MediaType) -> MediaType {
        switch resourceType {
        case .video, .pairedVideo, .fullSizeVideo, .fullSizePairedVideo:
            return .video
        case .photo, .fullSizePhoto, .alternatePhoto:
            return .image
        case .other:
            return assetMediaType
        }
    }
}

public struct ArchiveProgress: Equatable {
    public let title: String
    public let completedUnitCount: Int
    public let totalUnitCount: Int?
    public let detail: String?

    public init(
        title: String,
        completedUnitCount: Int,
        totalUnitCount: Int?,
        detail: String? = nil
    ) {
        self.title = title
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.detail = detail
    }

    public static func indeterminate(title: String, detail: String? = nil) -> ArchiveProgress {
        ArchiveProgress(
            title: title,
            completedUnitCount: 0,
            totalUnitCount: nil,
            detail: detail
        )
    }

    public var isDeterminate: Bool {
        guard let totalUnitCount else {
            return false
        }
        return totalUnitCount > 0
    }

    public var fractionCompleted: Double? {
        guard let totalUnitCount, totalUnitCount > 0 else {
            return nil
        }
        let fraction = Double(completedUnitCount) / Double(totalUnitCount)
        return min(1, max(0, fraction))
    }

    public var countText: String? {
        guard let totalUnitCount else {
            return nil
        }
        return "\(completedUnitCount.formatted()) / \(totalUnitCount.formatted())"
    }

    public var percentText: String? {
        guard let fractionCompleted else {
            return nil
        }
        return fractionCompleted.formatted(.percent.precision(.fractionLength(0)))
    }
}

public enum CaptureDateSource: String, Codable, Equatable, CaseIterable {
    case exifOriginal
    case quickTimeCreation
    case assetCreationDate
    case exportRunDate
}

public enum ExportStatus: String, Codable, Equatable, CaseIterable {
    case planned
    case exported
    case skippedExisting
    case renamedConflict
    case failed
}

public struct PhotoAssetDescriptor: Codable, Equatable, Identifiable {
    public var id: String { localIdentifier }
    public let localIdentifier: String
    public let mediaType: MediaType
    public let creationDate: Date?
    public let modificationDate: Date?
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(localIdentifier: String, mediaType: MediaType, creationDate: Date?, modificationDate: Date?, pixelWidth: Int, pixelHeight: Int) {
        self.localIdentifier = localIdentifier
        self.mediaType = mediaType
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public struct AssetResourceDescriptor: Codable, Equatable, Identifiable {
    public var id: String { resourceIdentifier }
    public let assetLocalIdentifier: String
    public let resourceIdentifier: String
    public let resourceType: ResourceType
    public let mediaType: MediaType
    public let originalFilename: String
    public let uniformTypeIdentifier: String?
    public let assetCreationDate: Date?

    public init(assetLocalIdentifier: String, resourceIdentifier: String, resourceType: ResourceType, mediaType: MediaType, originalFilename: String, uniformTypeIdentifier: String?, assetCreationDate: Date?) {
        self.assetLocalIdentifier = assetLocalIdentifier
        self.resourceIdentifier = resourceIdentifier
        self.resourceType = resourceType
        self.mediaType = mediaType
        self.originalFilename = originalFilename
        self.uniformTypeIdentifier = uniformTypeIdentifier
        self.assetCreationDate = assetCreationDate
    }
}

public struct CaptureDateDecision: Codable, Equatable {
    public let date: Date
    public let source: CaptureDateSource
    public let warnings: [String]

    public init(date: Date, source: CaptureDateSource, warnings: [String]) {
        self.date = date
        self.source = source
        self.warnings = warnings
    }
}

public struct ExportRecord: Codable, Equatable, Identifiable {
    public var id: String { "\(assetLocalIdentifier)|\(resourceIdentifier)|\(originalFilename)" }
    public let runID: String
    public let assetLocalIdentifier: String
    public let resourceIdentifier: String
    public let resourceType: ResourceType
    public let mediaType: MediaType
    public let originalFilename: String
    public let destinationPath: String
    public let captureDate: Date
    public let captureDateSource: CaptureDateSource
    public let fileSize: Int64
    public let sha256: String?
    public let status: ExportStatus
    public let warnings: [String]
    public let errorMessage: String?

    public init(runID: String, assetLocalIdentifier: String, resourceIdentifier: String, resourceType: ResourceType, mediaType: MediaType, originalFilename: String, destinationPath: String, captureDate: Date, captureDateSource: CaptureDateSource, fileSize: Int64, sha256: String?, status: ExportStatus, warnings: [String], errorMessage: String?) {
        self.runID = runID
        self.assetLocalIdentifier = assetLocalIdentifier
        self.resourceIdentifier = resourceIdentifier
        self.resourceType = resourceType
        self.mediaType = mediaType
        self.originalFilename = originalFilename
        self.destinationPath = destinationPath
        self.captureDate = captureDate
        self.captureDateSource = captureDateSource
        self.fileSize = fileSize
        self.sha256 = sha256
        self.status = status
        self.warnings = warnings
        self.errorMessage = errorMessage
    }
}

public struct RunSummary: Codable, Equatable {
    public let runID: String
    public let startedAt: Date
    public let finishedAt: Date?
    public let records: [ExportRecord]

    public init(runID: String, startedAt: Date, finishedAt: Date?, records: [ExportRecord]) {
        self.runID = runID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.records = records
    }

    public var exportedCount: Int { records.filter { $0.status == .exported }.count }
    public var skippedCount: Int { records.filter { $0.status == .skippedExisting }.count }
    public var failedCount: Int { records.filter { $0.status == .failed }.count }
    public var renamedConflictCount: Int { records.filter { $0.status == .renamedConflict }.count }
}
