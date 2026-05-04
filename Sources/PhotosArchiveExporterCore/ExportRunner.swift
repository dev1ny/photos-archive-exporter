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

    public func export(resources: [AssetResourceDescriptor], destinationRoot: URL, runID: String, exportRunDate: Date) async -> [ExportRecord] {
        var records: [ExportRecord] = []

        for resource in resources {
            records.append(await export(resource: resource, destinationRoot: destinationRoot, runID: runID, exportRunDate: exportRunDate))
        }

        return records
    }

    private func export(resource: AssetResourceDescriptor, destinationRoot: URL, runID: String, exportRunDate: Date) async -> ExportRecord {
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

            if fileManager.fileExists(atPath: fallbackDestination.path) {
                let existingHash = try FileHasher.sha256Hex(for: fallbackDestination)
                if existingHash == temporaryHash {
                    try? fileManager.removeItem(at: temporaryURL)
                    return makeRecord(
                        resource: resource,
                        runID: runID,
                        destination: fallbackDestination,
                        captureDateDecision: captureDateDecision,
                        fileSize: temporarySize,
                        sha256: temporaryHash,
                        status: .skippedExisting,
                        errorMessage: nil
                    )
                }

                let conflictDestination = PathPlanner.resolveConflict(for: fallbackDestination) { candidate in
                    fileManager.fileExists(atPath: candidate.path)
                }
                try moveTemporaryFile(from: temporaryURL, to: conflictDestination)
                return makeRecord(
                    resource: resource,
                    runID: runID,
                    destination: conflictDestination,
                    captureDateDecision: captureDateDecision,
                    fileSize: temporarySize,
                    sha256: temporaryHash,
                    status: .renamedConflict,
                    errorMessage: nil
                )
            }

            try moveTemporaryFile(from: temporaryURL, to: fallbackDestination)
            return makeRecord(
                resource: resource,
                runID: runID,
                destination: fallbackDestination,
                captureDateDecision: captureDateDecision,
                fileSize: temporarySize,
                sha256: temporaryHash,
                status: .exported,
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
