import Foundation

public enum ArchiveIndexStoreError: Error, Equatable {
    case invalidRunID(String)
}

public struct ArchiveIndexStore {
    public let destinationRoot: URL

    public init(destinationRoot: URL) {
        self.destinationRoot = destinationRoot
    }

    public var supportDirectory: URL {
        destinationRoot.appendingPathComponent("_photos_archive_exporter", isDirectory: true)
    }

    public var indexURL: URL {
        supportDirectory.appendingPathComponent("archive-index.json", isDirectory: false)
    }

    public var sqliteIndexURL: URL {
        supportDirectory.appendingPathComponent("archive-index.sqlite", isDirectory: false)
    }

    public func loadIndex() throws -> [ExportRecord] {
        let sqliteStore = SQLiteArchiveIndexStore(destinationRoot: destinationRoot)
        try migrateLegacyJSONIfNeeded(to: sqliteStore)
        return try sqliteStore.loadRecords()
    }

    public func loadIndex(for resources: [AssetResourceDescriptor]) throws -> [ExportRecord] {
        let sqliteStore = SQLiteArchiveIndexStore(destinationRoot: destinationRoot)
        try migrateLegacyJSONIfNeeded(to: sqliteStore)
        return try sqliteStore.loadRecords(for: resources)
    }

    public func loadDuplicateGroups() throws -> [DuplicateGroup] {
        let sqliteStore = SQLiteArchiveIndexStore(destinationRoot: destinationRoot)
        try migrateLegacyJSONIfNeeded(to: sqliteStore)
        return try sqliteStore.loadDuplicateGroups()
    }

    public func saveIndex(_ records: [ExportRecord]) throws {
        try SQLiteArchiveIndexStore(destinationRoot: destinationRoot).upsertRecords(records)
    }

    public func writeResourcesCSV(runID: String, records: [ExportRecord]) throws -> URL {
        let validRunID = try validateRunID(runID)
        let directory = runDirectory(validRunID: validRunID)
        try ensureRunDirectory(at: directory)
        let url = directory.appendingPathComponent("\(validRunID)-resources.csv", isDirectory: false)
        try writeCSV(to: url, header: resourceHeader) { handle in
            for record in records {
                try writeLine(resourceRow(record), to: handle)
            }
        }
        return url
    }

    public func writeErrorsCSV(runID: String, records: [ExportRecord]) throws -> URL {
        let validRunID = try validateRunID(runID)
        let directory = runDirectory(validRunID: validRunID)
        try ensureRunDirectory(at: directory)
        let url = directory.appendingPathComponent("\(validRunID)-errors.csv", isDirectory: false)
        let failed = records.filter { $0.status == .failed }
        try writeCSV(to: url, header: resourceHeader) { handle in
            for record in failed {
                try writeLine(resourceRow(record), to: handle)
            }
        }
        return url
    }

    public func writeDuplicatesCSV(runID: String, groups: [DuplicateGroup]) throws -> URL {
        let validRunID = try validateRunID(runID)
        let directory = runDirectory(validRunID: validRunID)
        try ensureRunDirectory(at: directory)
        let url = directory.appendingPathComponent("\(validRunID)-duplicates.csv", isDirectory: false)
        let header = csvRow(["sha256", "destinationPath", "originalFilename", "assetLocalIdentifier", "resourceIdentifier"])
        try writeCSV(to: url, header: header) { handle in
            for group in groups {
                for record in group.records {
                    try writeLine(csvRow([group.sha256, record.destinationPath, record.originalFilename, record.assetLocalIdentifier, record.resourceIdentifier]), to: handle)
                }
            }
        }
        return url
    }

    public func writeIncrementalPlanCSV(runID: String, entries: [IncrementalBackupPlanEntry]) throws -> URL {
        let validRunID = try validateRunID(runID)
        let directory = runDirectory(validRunID: validRunID)
        try ensureRunDirectory(at: directory)
        let url = directory.appendingPathComponent("\(validRunID)-incremental-plan.csv", isDirectory: false)
        let header = csvRow([
            "assetLocalIdentifier",
            "resourceIdentifier",
            "resourceType",
            "mediaType",
            "originalFilename",
            "action",
            "previousDestinationPath",
            "previousFileSize",
            "previousSha256",
            "note"
        ])
        try writeCSV(to: url, header: header) { handle in
            for entry in entries {
                try writeLine(
                    csvRow([
                        entry.resource.assetLocalIdentifier,
                        entry.resource.resourceIdentifier,
                        entry.resource.resourceType.rawValue,
                        entry.resource.mediaType.rawValue,
                        entry.resource.originalFilename,
                        entry.action.rawValue,
                        entry.previousRecord?.destinationPath ?? "",
                        entry.previousRecord.map { String($0.fileSize) } ?? "",
                        entry.previousRecord?.sha256 ?? "",
                        entry.note
                    ]),
                    to: handle
                )
            }
        }
        return url
    }

    private var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func loadLegacyJSONIndex() throws -> [ExportRecord] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return []
        }

        let data = try Data(contentsOf: indexURL)
        return ArchiveIndexCompactor.compact(try jsonDecoder.decode([ExportRecord].self, from: data))
    }

    private func migrateLegacyJSONIfNeeded(to sqliteStore: SQLiteArchiveIndexStore) throws {
        guard FileManager.default.fileExists(atPath: indexURL.path),
              try !sqliteStore.isLegacyJSONMigrationComplete()
        else {
            return
        }

        let legacyRecords = try loadLegacyJSONIndex()
        if !legacyRecords.isEmpty {
            try sqliteStore.upsertRecords(legacyRecords)
        }
        try sqliteStore.markLegacyJSONMigrationComplete()
    }

    private func ensureSupportDirectory() throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
    }

    private func ensureRunDirectory(at directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func writeCSV(to url: URL, header: String, rows: (FileHandle) throws -> Void) throws {
        let temporaryURL = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp", isDirectory: false)
        try Data().write(to: temporaryURL, options: [.atomic])
        let handle = try FileHandle(forWritingTo: temporaryURL)
        do {
            try writeLine(header, to: handle)
            try rows(handle)
            try handle.close()
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: url)
            }
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func writeLine(_ line: String, to handle: FileHandle) throws {
        try handle.write(contentsOf: Data("\(line)\n".utf8))
    }

    private func runDirectory(validRunID: String) -> URL {
        supportDirectory
            .appendingPathComponent("export-runs", isDirectory: true)
            .appendingPathComponent(validRunID, isDirectory: true)
    }

    private func validateRunID(_ runID: String) throws -> String {
        guard !runID.isEmpty,
              runID != ".",
              runID != "..",
              !runID.contains("/"),
              !runID.contains("\\"),
              !runID.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else {
            throw ArchiveIndexStoreError.invalidRunID(runID)
        }

        return runID
    }

    private var resourceHeader: String {
        csvRow([
            "runID",
            "assetLocalIdentifier",
            "resourceIdentifier",
            "resourceType",
            "mediaType",
            "originalFilename",
            "destinationPath",
            "captureDate",
            "captureDateSource",
            "fileSize",
            "sha256",
            "status",
            "warnings",
            "errorMessage"
        ])
    }

    private func resourceRow(_ record: ExportRecord) -> String {
        csvRow([
            record.runID,
            record.assetLocalIdentifier,
            record.resourceIdentifier,
            record.resourceType.rawValue,
            record.mediaType.rawValue,
            record.originalFilename,
            record.destinationPath,
            iso8601DateFormatter.string(from: record.captureDate),
            record.captureDateSource.rawValue,
            String(record.fileSize),
            record.sha256 ?? "",
            record.status.rawValue,
            record.warnings.joined(separator: "|"),
            record.errorMessage ?? ""
        ])
    }

    private var iso8601DateFormatter: ISO8601DateFormatter {
        ISO8601DateFormatter()
    }

    private func csvRow(_ values: [String]) -> String {
        values.map { value in
            let neutralized = neutralizeSpreadsheetFormula(value)
            let escaped = neutralized.replacingOccurrences(of: "\"", with: "\"\"")
            if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") || escaped.contains("\r") {
                return "\"\(escaped)\""
            }
            return escaped
        }.joined(separator: ",")
    }

    private func neutralizeSpreadsheetFormula(_ value: String) -> String {
        guard let first = value.first,
              first == "=" || first == "+" || first == "-" || first == "@" || first == "\t" || first == "\r"
        else {
            return value
        }

        return "'\(value)"
    }
}
