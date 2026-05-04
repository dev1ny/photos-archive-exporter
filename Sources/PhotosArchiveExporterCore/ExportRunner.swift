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
        var records: [ExportRecord] = []

        for resource in resources {
            records.append(await export(
                resource: resource,
                destinationRoot: destinationRoot,
                runID: runID,
                exportRunDate: exportRunDate,
                knownRecords: existingRecords + records
            ))
        }

        return records
    }

    private func export(resource: AssetResourceDescriptor, destinationRoot: URL, runID: String, exportRunDate: Date, knownRecords: [ExportRecord]) async -> ExportRecord {
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
                knownRecords: knownRecords
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

    private func resolveExportDestination(preferred: URL, temporaryHash: String, resource: AssetResourceDescriptor, knownRecords: [ExportRecord]) throws -> (url: URL, isExistingMatch: Bool) {
        var existingCandidates: Set<String> = []
        var candidate = preferred

        while true {
            guard fileManager.fileExists(atPath: candidate.path) else {
                return (candidate, false)
            }

            let existingHash = try FileHasher.sha256Hex(for: candidate)
            if existingHash == temporaryHash {
                if hasKnownMatchingRecord(for: resource, destination: candidate, sha256: temporaryHash, in: knownRecords) {
                    return (candidate, true)
                }
            }

            existingCandidates.insert(candidate.path)
            candidate = PathPlanner.resolveConflict(for: preferred) { candidate in
                candidate == preferred || existingCandidates.contains(candidate.path)
            }
        }
    }

    private func hasKnownMatchingRecord(for resource: AssetResourceDescriptor, destination: URL, sha256: String, in knownRecords: [ExportRecord]) -> Bool {
        knownRecords.contains { record in
            record.assetLocalIdentifier == resource.assetLocalIdentifier
                && record.resourceIdentifier == resource.resourceIdentifier
                && record.destinationPath == destination.path
                && record.sha256 == sha256
                && record.status != .failed
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
