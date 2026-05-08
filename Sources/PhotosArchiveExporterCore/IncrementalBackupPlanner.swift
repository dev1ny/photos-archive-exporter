import Foundation

public enum IncrementalBackupAction: String, Codable, Equatable, CaseIterable {
    case skipExisting
    case exportNew
    case exportMissingDestination
    case exportChanged
    case exportUnverified
}

public struct IncrementalBackupPlanEntry: Codable, Equatable {
    public let resource: AssetResourceDescriptor
    public let action: IncrementalBackupAction
    public let previousRecord: ExportRecord?
    public let note: String

    public init(resource: AssetResourceDescriptor, action: IncrementalBackupAction, previousRecord: ExportRecord?, note: String) {
        self.resource = resource
        self.action = action
        self.previousRecord = previousRecord
        self.note = note
    }
}

public struct IncrementalBackupPlan: Equatable {
    public let entries: [IncrementalBackupPlanEntry]
    public let resourcesToExport: [AssetResourceDescriptor]
    public let skippedRecords: [ExportRecord]

    public init(entries: [IncrementalBackupPlanEntry], resourcesToExport: [AssetResourceDescriptor], skippedRecords: [ExportRecord]) {
        self.entries = entries
        self.resourcesToExport = resourcesToExport
        self.skippedRecords = skippedRecords
    }

    public func currentRunRecords(exportedRecords: [ExportRecord]) -> [ExportRecord] {
        var skippedByResource: [ResourceRecordKey: ExportRecord] = [:]
        for record in skippedRecords {
            skippedByResource[ResourceRecordKey(record: record)] = record
        }

        var exportedByResource: [ResourceRecordKey: ExportRecord] = [:]
        for record in exportedRecords {
            exportedByResource[ResourceRecordKey(record: record)] = record
        }

        return entries.compactMap { entry in
            let key = ResourceRecordKey(resource: entry.resource)
            if entry.action == .skipExisting {
                return skippedByResource[key]
            }
            return exportedByResource[key]
        }
    }
}

public struct IncrementalBackupPlanner {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func plan(resources: [AssetResourceDescriptor], previousRecords: [ExportRecord], runID: String, exportRunDate: Date) throws -> IncrementalBackupPlan {
        let latestRecords = latestSuccessfulRecordsByResourceIdentity(from: previousRecords)
        var entries: [IncrementalBackupPlanEntry] = []
        var resourcesToExport: [AssetResourceDescriptor] = []
        var skippedRecords: [ExportRecord] = []

        for resource in resources {
            guard let previousRecord = latestRecords[ResourceRecordKey(resource: resource)] else {
                entries.append(.init(resource: resource, action: .exportNew, previousRecord: nil, note: "No previous successful archive record exists."))
                resourcesToExport.append(resource)
                continue
            }

            let decision = decision(for: previousRecord)
            entries.append(.init(resource: resource, action: decision.action, previousRecord: previousRecord, note: decision.note))

            if decision.action == .skipExisting {
                skippedRecords.append(makeSkippedRecord(from: previousRecord, resource: resource, runID: runID, exportRunDate: exportRunDate))
            } else {
                resourcesToExport.append(resource)
            }
        }

        return IncrementalBackupPlan(entries: entries, resourcesToExport: resourcesToExport, skippedRecords: skippedRecords)
    }

    private func latestSuccessfulRecordsByResourceIdentity(from records: [ExportRecord]) -> [ResourceRecordKey: ExportRecord] {
        var latest: [ResourceRecordKey: ExportRecord] = [:]
        for record in records where record.status != .failed {
            latest[ResourceRecordKey(record: record)] = record
        }
        return latest
    }

    private func decision(for record: ExportRecord) -> (action: IncrementalBackupAction, note: String) {
        guard let expectedHash = record.sha256, !expectedHash.isEmpty, record.fileSize > 0 else {
            return (.exportUnverified, "Previous record has no usable hash or file size.")
        }

        guard fileManager.fileExists(atPath: record.destinationPath) else {
            return (.exportMissingDestination, "Previous destination file is missing.")
        }

        do {
            let actualSize = try fileSize(atPath: record.destinationPath)
            guard actualSize == record.fileSize else {
                return (.exportChanged, "Previous destination file size changed.")
            }

            let actualHash = try FileHasher.sha256Hex(for: URL(fileURLWithPath: record.destinationPath))
            guard actualHash == expectedHash else {
                return (.exportChanged, "Previous destination file hash changed.")
            }

            return (.skipExisting, "Previous destination file still matches the archive index.")
        } catch {
            return (.exportUnverified, "Previous destination file could not be verified: \(String(describing: error))")
        }
    }

    private func makeSkippedRecord(from previousRecord: ExportRecord, resource: AssetResourceDescriptor, runID: String, exportRunDate: Date) -> ExportRecord {
        ExportRecord(
            runID: runID,
            assetLocalIdentifier: resource.assetLocalIdentifier,
            resourceIdentifier: resource.resourceIdentifier,
            resourceType: resource.resourceType,
            mediaType: resource.mediaType,
            originalFilename: resource.originalFilename,
            destinationPath: previousRecord.destinationPath,
            captureDate: previousRecord.captureDate,
            captureDateSource: previousRecord.captureDateSource,
            fileSize: previousRecord.fileSize,
            sha256: previousRecord.sha256,
            status: .skippedExisting,
            warnings: previousRecord.warnings,
            errorMessage: nil
        )
    }

    private func fileSize(atPath path: String) throws -> Int64 {
        let attributes = try fileManager.attributesOfItem(atPath: path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

}

private struct ResourceRecordKey: Hashable {
    let assetLocalIdentifier: String
    let resourceIdentifier: String

    init(resource: AssetResourceDescriptor) {
        assetLocalIdentifier = resource.assetLocalIdentifier
        resourceIdentifier = resource.resourceIdentifier
    }

    init(record: ExportRecord) {
        assetLocalIdentifier = record.assetLocalIdentifier
        resourceIdentifier = record.resourceIdentifier
    }
}
