import Foundation

public protocol ResourceWriting {
    func write(resource: AssetResourceDescriptor, to temporaryURL: URL) async throws
}

public struct ExportRunner {
    private let resourceWriter: any ResourceWriting
    private let pathPlanner: PathPlanner
    private let fileManager: FileManager

    public init(resourceWriter: any ResourceWriting, pathPlanner: PathPlanner = PathPlanner(), fileManager: FileManager = .default) {
        self.resourceWriter = resourceWriter
        self.pathPlanner = pathPlanner
        self.fileManager = fileManager
    }

    public func export(resources: [AssetResourceDescriptor], destinationRoot: URL, runID: String, exportRunDate: Date, existingRecords: [ExportRecord] = []) async -> [ExportRecord] {
        return await exportInBatches(
            resources: resources,
            destinationRoot: destinationRoot,
            runID: runID,
            exportRunDate: exportRunDate,
            existingRecords: existingRecords,
            batchSize: max(resources.count, 1),
            didExportBatch: { _ in }
        )
    }

    public func exportInBatches(
        resources: [AssetResourceDescriptor],
        destinationRoot: URL,
        runID: String,
        exportRunDate: Date,
        existingRecords: [ExportRecord] = [],
        batchSize: Int,
        didExportBatch: ([ExportRecord]) throws -> Void
    ) async rethrows -> [ExportRecord] {
        var records: [ExportRecord] = []
        var batchRecords: [ExportRecord] = []
        var knownRecordKeys = KnownExportRecordKeys(records: existingRecords)
        let effectiveBatchSize = max(1, batchSize)

        for resource in resources {
            let record = await export(
                resource: resource,
                destinationRoot: destinationRoot,
                runID: runID,
                exportRunDate: exportRunDate,
                knownRecordKeys: knownRecordKeys
            )
            records.append(record)
            batchRecords.append(record)
            knownRecordKeys.insert(record)

            if batchRecords.count == effectiveBatchSize {
                try didExportBatch(batchRecords)
                batchRecords.removeAll(keepingCapacity: true)
            }
        }

        if !batchRecords.isEmpty {
            try didExportBatch(batchRecords)
        }

        return records
    }

    private func export(resource: AssetResourceDescriptor, destinationRoot: URL, runID: String, exportRunDate: Date, knownRecordKeys: KnownExportRecordKeys) async -> ExportRecord {
        let temporaryURL = temporaryDirectory(root: destinationRoot).appendingPathComponent(UUID().uuidString, isDirectory: false)
        var fallbackDecision = fallbackCaptureDateDecision(for: resource, exportRunDate: exportRunDate)
        var fallbackDestination = pathPlanner.preferredDestination(root: destinationRoot, captureDate: fallbackDecision.date, originalFilename: resource.originalFilename)

        do {
            try fileManager.createDirectory(at: temporaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await resourceWriter.write(resource: resource, to: temporaryURL)

            let metadataDates = MetadataReader.readCaptureDates(from: temporaryURL)
            let captureDateDecision = CaptureDateResolver.resolve(
                exifOriginal: metadataDates.exifOriginal,
                quickTimeCreation: metadataDates.quickTimeCreation,
                assetCreationDate: resource.assetCreationDate,
                exportRunDate: exportRunDate
            )
            fallbackDecision = captureDateDecision
            fallbackDestination = pathPlanner.preferredDestination(root: destinationRoot, captureDate: captureDateDecision.date, originalFilename: resource.originalFilename)

            let temporaryHash = try FileHasher.sha256Hex(for: temporaryURL)
            let temporarySize = try fileSize(at: temporaryURL)

            let exportDestination = try resolveExportDestination(
                preferred: fallbackDestination,
                temporaryHash: temporaryHash,
                resource: resource,
                knownRecordKeys: knownRecordKeys
            )
            if exportDestination.isExistingMatch {
                try? fileManager.removeItem(at: temporaryURL)
                return makeRecord(
                    resource: resource,
                    runID: runID,
                    destination: exportDestination.url,
                    captureDateDecision: captureDateDecision,
                    fileSize: temporarySize,
                    sha256: temporaryHash,
                    status: .skippedExisting,
                    errorMessage: nil
                )
            }

            try moveTemporaryFile(from: temporaryURL, to: exportDestination.url)
            return makeRecord(
                resource: resource,
                runID: runID,
                destination: exportDestination.url,
                captureDateDecision: captureDateDecision,
                fileSize: temporarySize,
                sha256: temporaryHash,
                status: exportDestination.url == fallbackDestination ? .exported : .renamedConflict,
                errorMessage: nil
            )
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            return makeRecord(
                resource: resource,
                runID: runID,
                destination: fallbackDestination,
                captureDateDecision: fallbackDecision,
                fileSize: 0,
                sha256: nil,
                status: .failed,
                errorMessage: String(describing: error)
            )
        }
    }

    private func temporaryDirectory(root: URL) -> URL {
        root
            .appendingPathComponent("_photos_archive_exporter", isDirectory: true)
            .appendingPathComponent("tmp", isDirectory: true)
    }

    private func fallbackCaptureDateDecision(for resource: AssetResourceDescriptor, exportRunDate: Date) -> CaptureDateDecision {
        CaptureDateResolver.resolve(
            exifOriginal: nil,
            quickTimeCreation: nil,
            assetCreationDate: resource.assetCreationDate,
            exportRunDate: exportRunDate
        )
    }

    private func moveTemporaryFile(from temporaryURL: URL, to destination: URL) throws {
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: temporaryURL, to: destination)
    }

    private func resolveExportDestination(preferred: URL, temporaryHash: String, resource: AssetResourceDescriptor, knownRecordKeys: KnownExportRecordKeys) throws -> (url: URL, isExistingMatch: Bool) {
        var existingCandidates: Set<String> = []
        var candidate = preferred

        while true {
            guard fileManager.fileExists(atPath: candidate.path) else {
                return (candidate, false)
            }

            let existingHash = try FileHasher.sha256Hex(for: candidate)
            if existingHash == temporaryHash {
                if knownRecordKeys.contains(resource: resource, destination: candidate, sha256: temporaryHash) {
                    return (candidate, true)
                }
            }

            existingCandidates.insert(candidate.path)
            candidate = PathPlanner.resolveConflict(for: preferred) { candidate in
                candidate == preferred || existingCandidates.contains(candidate.path)
            }
        }
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func makeRecord(
        resource: AssetResourceDescriptor,
        runID: String,
        destination: URL,
        captureDateDecision: CaptureDateDecision,
        fileSize: Int64,
        sha256: String?,
        status: ExportStatus,
        errorMessage: String?
    ) -> ExportRecord {
        ExportRecord(
            runID: runID,
            assetLocalIdentifier: resource.assetLocalIdentifier,
            resourceIdentifier: resource.resourceIdentifier,
            resourceType: resource.resourceType,
            mediaType: resource.mediaType,
            originalFilename: resource.originalFilename,
            destinationPath: destination.path,
            captureDate: captureDateDecision.date,
            captureDateSource: captureDateDecision.source,
            fileSize: fileSize,
            sha256: sha256,
            status: status,
            warnings: captureDateDecision.warnings,
            errorMessage: errorMessage
        )
    }
}

private struct KnownExportRecordKeys {
    private var keys: Set<KnownExportRecordKey> = []

    init(records: [ExportRecord]) {
        for record in records {
            insert(record)
        }
    }

    mutating func insert(_ record: ExportRecord) {
        guard record.status != .failed,
              let sha256 = record.sha256,
              !sha256.isEmpty
        else {
            return
        }

        keys.insert(KnownExportRecordKey(
            assetLocalIdentifier: record.assetLocalIdentifier,
            resourceIdentifier: record.resourceIdentifier,
            destinationPath: record.destinationPath,
            sha256: sha256
        ))
    }

    func contains(resource: AssetResourceDescriptor, destination: URL, sha256: String) -> Bool {
        keys.contains(KnownExportRecordKey(
            assetLocalIdentifier: resource.assetLocalIdentifier,
            resourceIdentifier: resource.resourceIdentifier,
            destinationPath: destination.path,
            sha256: sha256
        ))
    }
}

private struct KnownExportRecordKey: Hashable {
    let assetLocalIdentifier: String
    let resourceIdentifier: String
    let destinationPath: String
    let sha256: String
}
