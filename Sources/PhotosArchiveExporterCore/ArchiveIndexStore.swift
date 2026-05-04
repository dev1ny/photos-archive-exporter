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

    public func loadIndex() throws -> [ExportRecord] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return []
        }

        let data = try Data(contentsOf: indexURL)
        return try jsonDecoder.decode([ExportRecord].self, from: data)
    }

    public func saveIndex(_ records: [ExportRecord]) throws {
        try ensureSupportDirectory()
        let data = try jsonEncoder.encode(records)
        try data.write(to: indexURL, options: [.atomic])
    }

    public func writeResourcesCSV(runID: String, records: [ExportRecord]) throws -> URL {
        let validRunID = try validateRunID(runID)
        let directory = runDirectory(validRunID: validRunID)
        try ensureRunDirectory(at: directory)
        let url = directory.appendingPathComponent("\(validRunID)-resources.csv", isDirectory: false)
        let rows = [resourceHeader] + records.map(resourceRow)
        try rows.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public func writeErrorsCSV(runID: String, records: [ExportRecord]) throws -> URL {
        let validRunID = try validateRunID(runID)
        let directory = runDirectory(validRunID: validRunID)
        try ensureRunDirectory(at: directory)
        let url = directory.appendingPathComponent("\(validRunID)-errors.csv", isDirectory: false)
        let failed = records.filter { $0.status == .failed }
        let rows = [resourceHeader] + failed.map(resourceRow)
        try rows.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public func writeDuplicatesCSV(runID: String, groups: [DuplicateGroup]) throws -> URL {
        let validRunID = try validateRunID(runID)
        let directory = runDirectory(validRunID: validRunID)
        try ensureRunDirectory(at: directory)
        let url = directory.appendingPathComponent("\(validRunID)-duplicates.csv", isDirectory: false)
        let header = csvRow(["sha256", "destinationPath", "originalFilename", "assetLocalIdentifier", "resourceIdentifier"])
        let rows = groups.flatMap { group in
            group.records.map { record in
                csvRow([group.sha256, record.destinationPath, record.originalFilename, record.assetLocalIdentifier, record.resourceIdentifier])
            }
        }
        try ([header] + rows).joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
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

    private func ensureSupportDirectory() throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
    }

    private func ensureRunDirectory(at directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
