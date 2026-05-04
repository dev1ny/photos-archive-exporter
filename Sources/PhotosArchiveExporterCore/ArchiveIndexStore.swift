import Foundation

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
        try ensureRunDirectory(runID: runID)
        let url = runDirectory(runID: runID).appendingPathComponent("\(runID)-resources.csv", isDirectory: false)
        let rows = [resourceHeader] + records.map(resourceRow)
        try rows.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public func writeErrorsCSV(runID: String, records: [ExportRecord]) throws -> URL {
        try ensureRunDirectory(runID: runID)
        let url = runDirectory(runID: runID).appendingPathComponent("\(runID)-errors.csv", isDirectory: false)
        let failed = records.filter { $0.status == .failed }
        let rows = [resourceHeader] + failed.map(resourceRow)
        try rows.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public func writeDuplicatesCSV(runID: String, groups: [DuplicateGroup]) throws -> URL {
        try ensureRunDirectory(runID: runID)
        let url = runDirectory(runID: runID).appendingPathComponent("\(runID)-duplicates.csv", isDirectory: false)
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

    private func ensureRunDirectory(runID: String) throws {
        try FileManager.default.createDirectory(at: runDirectory(runID: runID), withIntermediateDirectories: true)
    }

    private func runDirectory(runID: String) -> URL {
        supportDirectory
            .appendingPathComponent("export-runs", isDirectory: true)
            .appendingPathComponent(runID, isDirectory: true)
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
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
                return "\"\(escaped)\""
            }
            return escaped
        }.joined(separator: ",")
    }
}
