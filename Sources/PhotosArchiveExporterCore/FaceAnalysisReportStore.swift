import Foundation

public enum FaceAnalysisReportStoreError: Error, Equatable {
    case invalidRunID(String)
}

public struct FaceAnalysisReportStore {
    public let destinationRoot: URL

    public init(destinationRoot: URL) {
        self.destinationRoot = destinationRoot
    }

    public var supportDirectory: URL {
        destinationRoot.appendingPathComponent("_photos_archive_exporter", isDirectory: true)
    }

    public var indexURL: URL {
        supportDirectory.appendingPathComponent("face-analysis-index.json", isDirectory: false)
    }

    public func loadIndex() throws -> [FaceAnalysisAssetRecord] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return []
        }

        let data = try Data(contentsOf: indexURL)
        return compactIndex(try jsonDecoder.decode([FaceAnalysisAssetRecord].self, from: data))
    }

    public func saveIndex(_ records: [FaceAnalysisAssetRecord]) throws {
        try ensureSupportDirectory()
        let data = try jsonEncoder.encode(compactIndex(records))
        try data.write(to: indexURL, options: [.atomic])
    }

    public func writeRunSummary(_ summary: FaceAnalysisRunSummary) throws -> URL {
        let validRunID = try validateRunID(summary.runID)
        let directory = runDirectory(validRunID: validRunID)
        try ensureRunDirectory(at: directory)
        let url = directory.appendingPathComponent("\(validRunID)-summary.json", isDirectory: false)
        let data = try jsonEncoder.encode(summary)
        try data.write(to: url, options: [.atomic])
        return url
    }

    public func writeAssetsCSV(runID: String, records: [FaceAnalysisAssetRecord]) throws -> URL {
        let validRunID = try validateRunID(runID)
        let directory = runDirectory(validRunID: validRunID)
        try ensureRunDirectory(at: directory)
        let url = directory.appendingPathComponent("\(validRunID)-assets.csv", isDirectory: false)
        try writeCSV(to: url, header: assetHeader) { handle in
            for record in records {
                try writeLine(assetRow(record), to: handle)
            }
        }
        return url
    }

    public func writeFacesCSV(runID: String, faces: [FaceObservationRecord]) throws -> URL {
        let validRunID = try validateRunID(runID)
        let directory = runDirectory(validRunID: validRunID)
        try ensureRunDirectory(at: directory)
        let url = directory.appendingPathComponent("\(validRunID)-faces.csv", isDirectory: false)
        try writeCSV(to: url, header: faceHeader) { handle in
            for face in faces {
                try writeLine(faceRow(face), to: handle)
            }
        }
        return url
    }

    public func writeErrorsCSV(runID: String, records: [FaceAnalysisAssetRecord]) throws -> URL {
        let validRunID = try validateRunID(runID)
        let directory = runDirectory(validRunID: validRunID)
        try ensureRunDirectory(at: directory)
        let url = directory.appendingPathComponent("\(validRunID)-errors.csv", isDirectory: false)
        let failed = records.filter { $0.status == .failed }
        try writeCSV(to: url, header: assetHeader) { handle in
            for record in failed {
                try writeLine(assetRow(record), to: handle)
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

    private func compactIndex(_ records: [FaceAnalysisAssetRecord]) -> [FaceAnalysisAssetRecord] {
        var resourceOrder: [FaceAnalysisRecordKey] = []
        var recordByResource: [FaceAnalysisRecordKey: FaceAnalysisAssetRecord] = [:]

        for record in records {
            let key = FaceAnalysisRecordKey(record: record)
            if recordByResource[key] == nil {
                resourceOrder.append(key)
            }
            recordByResource[key] = record
        }

        return resourceOrder.compactMap { recordByResource[$0] }
    }

    private func runDirectory(validRunID: String) -> URL {
        supportDirectory
            .appendingPathComponent("face-analysis-runs", isDirectory: true)
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
            throw FaceAnalysisReportStoreError.invalidRunID(runID)
        }

        return runID
    }

    private var assetHeader: String {
        csvRow([
            "runID",
            "assetLocalIdentifier",
            "resourceIdentifier",
            "mediaType",
            "originalFilename",
            "imageWidth",
            "imageHeight",
            "modificationDate",
            "fileSize",
            "sha256",
            "status",
            "facesDetected",
            "analyzedAt",
            "warningMessage",
            "errorMessage"
        ])
    }

    private func assetRow(_ record: FaceAnalysisAssetRecord) -> String {
        csvRow([
            record.runID,
            record.assetLocalIdentifier,
            record.resourceIdentifier,
            record.mediaType.rawValue,
            record.originalFilename,
            optionalString(record.imageWidth),
            optionalString(record.imageHeight),
            optionalDateString(record.modificationDate),
            optionalString(record.fileSize),
            record.sha256 ?? "",
            record.status.rawValue,
            String(record.facesDetected),
            optionalDateString(record.analyzedAt),
            record.warningMessage ?? "",
            record.errorMessage ?? ""
        ])
    }

    private var faceHeader: String {
        csvRow([
            "runID",
            "faceObservationID",
            "assetLocalIdentifier",
            "resourceIdentifier",
            "mediaType",
            "videoTimestampSeconds",
            "faceIndex",
            "boundingBoxX",
            "boundingBoxY",
            "boundingBoxWidth",
            "boundingBoxHeight",
            "confidence",
            "quality",
            "roll",
            "yaw",
            "pitch",
            "landmarkRegionNames"
        ])
    }

    private func faceRow(_ face: FaceObservationRecord) -> String {
        csvRow([
            face.runID,
            face.faceObservationID,
            face.assetLocalIdentifier,
            face.resourceIdentifier,
            face.mediaType.rawValue,
            optionalString(face.videoTimestampSeconds),
            String(face.faceIndex),
            String(face.boundingBox.x),
            String(face.boundingBox.y),
            String(face.boundingBox.width),
            String(face.boundingBox.height),
            optionalString(face.confidence),
            optionalString(face.quality),
            optionalString(face.roll),
            optionalString(face.yaw),
            optionalString(face.pitch),
            face.landmarks.map(\.regionName).joined(separator: "|")
        ])
    }

    private func optionalString<T>(_ value: T?) -> String {
        value.map { String(describing: $0) } ?? ""
    }

    private func optionalDateString(_ date: Date?) -> String {
        date.map { iso8601DateFormatter.string(from: $0) } ?? ""
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

private struct FaceAnalysisRecordKey: Hashable {
    let assetLocalIdentifier: String
    let resourceIdentifier: String

    init(record: FaceAnalysisAssetRecord) {
        assetLocalIdentifier = record.assetLocalIdentifier
        resourceIdentifier = record.resourceIdentifier
    }
}
