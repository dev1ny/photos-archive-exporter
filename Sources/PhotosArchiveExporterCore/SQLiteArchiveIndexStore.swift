import Foundation
import SQLite3

public enum SQLiteArchiveIndexStoreError: Error, Equatable {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
    case invalidStoredRecord(String)
}

public struct SQLiteArchiveIndexStore {
    public let destinationRoot: URL
    private static let legacyJSONMigrationKey = "legacy_json_migration_complete"

    public init(destinationRoot: URL) {
        self.destinationRoot = destinationRoot
    }

    public var supportDirectory: URL {
        destinationRoot.appendingPathComponent("_photos_archive_exporter", isDirectory: true)
    }

    public var databaseURL: URL {
        supportDirectory.appendingPathComponent("archive-index.sqlite", isDirectory: false)
    }

    public func loadRecords() throws -> [ExportRecord] {
        try withDatabase { database in
            try initialize(database)
            let sql = """
            SELECT run_id, asset_local_identifier, resource_identifier, resource_type, media_type,
                   original_filename, destination_path, capture_date, capture_date_source,
                   file_size, sha256, status, warnings_json, error_message
            FROM archive_records
            ORDER BY asset_local_identifier, resource_identifier
            """
            return try records(database: database, sql: sql, bindings: [])
        }
    }

    public func loadDuplicateGroups() throws -> [DuplicateGroup] {
        try withDatabase { database in
            try initialize(database)
            let sql = """
            WITH ranked_destinations AS (
                SELECT run_id, asset_local_identifier, resource_identifier, resource_type, media_type,
                       original_filename, destination_path, capture_date, capture_date_source,
                       file_size, sha256, status, warnings_json, error_message,
                       ROW_NUMBER() OVER (
                           PARTITION BY destination_path
                           ORDER BY updated_at DESC, asset_local_identifier, resource_identifier
                       ) AS destination_rank
                FROM archive_records
                WHERE status != ? AND sha256 IS NOT NULL AND sha256 != ''
            ),
            duplicate_hashes AS (
                SELECT sha256
                FROM ranked_destinations
                WHERE destination_rank = 1
                GROUP BY sha256
                HAVING COUNT(*) > 1
            )
            SELECT run_id, asset_local_identifier, resource_identifier, resource_type, media_type,
                   original_filename, destination_path, capture_date, capture_date_source,
                   file_size, sha256, status, warnings_json, error_message
            FROM ranked_destinations
            WHERE destination_rank = 1 AND sha256 IN (SELECT sha256 FROM duplicate_hashes)
            ORDER BY sha256, destination_path, asset_local_identifier, resource_identifier
            """
            return DuplicateReporter.strongDuplicateGroups(from: try records(database: database, sql: sql, bindings: [ExportStatus.failed.rawValue]))
        }
    }

    public func loadRecords(for resources: [AssetResourceDescriptor]) throws -> [ExportRecord] {
        try withDatabase { database in
            try initialize(database)
            let sql = """
            SELECT run_id, asset_local_identifier, resource_identifier, resource_type, media_type,
                   original_filename, destination_path, capture_date, capture_date_source,
                   file_size, sha256, status, warnings_json, error_message
            FROM archive_records
            WHERE asset_local_identifier = ? AND resource_identifier = ?
            """

            return try withStatement(sql, database: database) { statement in
                var records: [ExportRecord] = []
                for resource in resources {
                    guard sqlite3_reset(statement) == SQLITE_OK,
                          sqlite3_clear_bindings(statement) == SQLITE_OK
                    else {
                        throw SQLiteArchiveIndexStoreError.stepFailed(errorMessage(database))
                    }
                    try bind(resource.assetLocalIdentifier, at: 1, statement: statement)
                    try bind(resource.resourceIdentifier, at: 2, statement: statement)

                    while true {
                        let result = sqlite3_step(statement)
                        if result == SQLITE_ROW {
                            records.append(try record(from: statement))
                        } else if result == SQLITE_DONE {
                            break
                        } else {
                            throw SQLiteArchiveIndexStoreError.stepFailed(errorMessage(database))
                        }
                    }
                }
                return records
            }
        }
    }

    public func upsertRecords(_ records: [ExportRecord]) throws {
        try withDatabase { database in
            try initialize(database)
            try execute("BEGIN IMMEDIATE TRANSACTION", database: database)
            do {
                for record in ArchiveIndexCompactor.compact(records) {
                    if record.status == .failed,
                       let existing = try existingRecord(
                        database: database,
                        assetLocalIdentifier: record.assetLocalIdentifier,
                        resourceIdentifier: record.resourceIdentifier
                       ),
                       existing.status != .failed {
                        continue
                    }
                    try upsert(record, database: database)
                }
                try execute("COMMIT", database: database)
            } catch {
                try? execute("ROLLBACK", database: database)
                throw error
            }
        }
    }

    public func isLegacyJSONMigrationComplete() throws -> Bool {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return false
        }

        return try withDatabase { database in
            try initialize(database)
            return try metadataValue(for: Self.legacyJSONMigrationKey, database: database) == "true"
        }
    }

    public func markLegacyJSONMigrationComplete() throws {
        try withDatabase { database in
            try initialize(database)
            try setMetadataValue("true", for: Self.legacyJSONMigrationKey, database: database)
        }
    }

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite open error."
            if let database {
                sqlite3_close(database)
            }
            throw SQLiteArchiveIndexStoreError.openFailed(message)
        }
        defer {
            sqlite3_close(database)
        }

        return try body(database)
    }

    private func initialize(_ database: OpaquePointer) throws {
        try execute("PRAGMA journal_mode = WAL", database: database)
        try execute("PRAGMA synchronous = NORMAL", database: database)
        try execute("""
        CREATE TABLE IF NOT EXISTS schema_metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        )
        """, database: database)
        try execute("""
        CREATE TABLE IF NOT EXISTS archive_records (
            asset_local_identifier TEXT NOT NULL,
            resource_identifier TEXT NOT NULL,
            run_id TEXT NOT NULL,
            resource_type TEXT NOT NULL,
            media_type TEXT NOT NULL,
            original_filename TEXT NOT NULL,
            destination_path TEXT NOT NULL,
            capture_date TEXT NOT NULL,
            capture_date_source TEXT NOT NULL,
            file_size INTEGER NOT NULL,
            sha256 TEXT,
            status TEXT NOT NULL,
            warnings_json TEXT NOT NULL DEFAULT '[]',
            error_message TEXT,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (asset_local_identifier, resource_identifier)
        )
        """, database: database)
        try execute("CREATE INDEX IF NOT EXISTS idx_archive_records_sha256 ON archive_records(sha256) WHERE sha256 IS NOT NULL AND sha256 != ''", database: database)
        try execute("CREATE INDEX IF NOT EXISTS idx_archive_records_status ON archive_records(status)", database: database)
        try execute("CREATE INDEX IF NOT EXISTS idx_archive_records_destination_path ON archive_records(destination_path)", database: database)
        try execute("INSERT OR REPLACE INTO schema_metadata (key, value) VALUES ('schema_version', '1')", database: database)
    }

    private func upsert(_ record: ExportRecord, database: OpaquePointer) throws {
        let sql = """
        INSERT INTO archive_records (
            asset_local_identifier, resource_identifier, run_id, resource_type, media_type,
            original_filename, destination_path, capture_date, capture_date_source,
            file_size, sha256, status, warnings_json, error_message, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(asset_local_identifier, resource_identifier) DO UPDATE SET
            run_id = excluded.run_id,
            resource_type = excluded.resource_type,
            media_type = excluded.media_type,
            original_filename = excluded.original_filename,
            destination_path = excluded.destination_path,
            capture_date = excluded.capture_date,
            capture_date_source = excluded.capture_date_source,
            file_size = excluded.file_size,
            sha256 = excluded.sha256,
            status = excluded.status,
            warnings_json = excluded.warnings_json,
            error_message = excluded.error_message,
            updated_at = excluded.updated_at
        """
        try withStatement(sql, database: database) { statement in
            try bind(record.assetLocalIdentifier, at: 1, statement: statement)
            try bind(record.resourceIdentifier, at: 2, statement: statement)
            try bind(record.runID, at: 3, statement: statement)
            try bind(record.resourceType.rawValue, at: 4, statement: statement)
            try bind(record.mediaType.rawValue, at: 5, statement: statement)
            try bind(record.originalFilename, at: 6, statement: statement)
            try bind(record.destinationPath, at: 7, statement: statement)
            try bind(iso8601DateFormatter.string(from: record.captureDate), at: 8, statement: statement)
            try bind(record.captureDateSource.rawValue, at: 9, statement: statement)
            try bind(record.fileSize, at: 10, statement: statement)
            try bindOptional(record.sha256, at: 11, statement: statement)
            try bind(record.status.rawValue, at: 12, statement: statement)
            try bind(warningsJSON(record.warnings), at: 13, statement: statement)
            try bindOptional(record.errorMessage, at: 14, statement: statement)
            try bind(iso8601DateFormatter.string(from: Date()), at: 15, statement: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteArchiveIndexStoreError.stepFailed(errorMessage(database))
            }
        }
    }

    private func existingRecord(database: OpaquePointer, assetLocalIdentifier: String, resourceIdentifier: String) throws -> ExportRecord? {
        let sql = """
        SELECT run_id, asset_local_identifier, resource_identifier, resource_type, media_type,
               original_filename, destination_path, capture_date, capture_date_source,
               file_size, sha256, status, warnings_json, error_message
        FROM archive_records
        WHERE asset_local_identifier = ? AND resource_identifier = ?
        """
        return try records(database: database, sql: sql, bindings: [assetLocalIdentifier, resourceIdentifier]).first
    }

    private func records(database: OpaquePointer, sql: String, bindings: [String]) throws -> [ExportRecord] {
        try withStatement(sql, database: database) { statement in
            for (index, value) in bindings.enumerated() {
                try bind(value, at: Int32(index + 1), statement: statement)
            }

            var records: [ExportRecord] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_ROW {
                    records.append(try record(from: statement))
                } else if result == SQLITE_DONE {
                    return records
                } else {
                    throw SQLiteArchiveIndexStoreError.stepFailed(errorMessage(database))
                }
            }
        }
    }

    private func metadataValue(for key: String, database: OpaquePointer) throws -> String? {
        let sql = "SELECT value FROM schema_metadata WHERE key = ?"
        return try withStatement(sql, database: database) { statement in
            try bind(key, at: 1, statement: statement)
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                return optionalText(statement, 0)
            }
            if result == SQLITE_DONE {
                return nil
            }
            throw SQLiteArchiveIndexStoreError.stepFailed(errorMessage(database))
        }
    }

    private func setMetadataValue(_ value: String, for key: String, database: OpaquePointer) throws {
        let sql = "INSERT OR REPLACE INTO schema_metadata (key, value) VALUES (?, ?)"
        try withStatement(sql, database: database) { statement in
            try bind(key, at: 1, statement: statement)
            try bind(value, at: 2, statement: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteArchiveIndexStoreError.stepFailed(errorMessage(database))
            }
        }
    }

    private func record(from statement: OpaquePointer) throws -> ExportRecord {
        guard let resourceType = ResourceType(rawValue: text(statement, 3)),
              let mediaType = MediaType(rawValue: text(statement, 4)),
              let captureDate = iso8601DateFormatter.date(from: text(statement, 7)),
              let captureDateSource = CaptureDateSource(rawValue: text(statement, 8)),
              let status = ExportStatus(rawValue: text(statement, 11))
        else {
            throw SQLiteArchiveIndexStoreError.invalidStoredRecord("Stored archive record contains invalid enum or date values.")
        }

        return ExportRecord(
            runID: text(statement, 0),
            assetLocalIdentifier: text(statement, 1),
            resourceIdentifier: text(statement, 2),
            resourceType: resourceType,
            mediaType: mediaType,
            originalFilename: text(statement, 5),
            destinationPath: text(statement, 6),
            captureDate: captureDate,
            captureDateSource: captureDateSource,
            fileSize: sqlite3_column_int64(statement, 9),
            sha256: optionalText(statement, 10),
            status: status,
            warnings: warnings(fromJSON: text(statement, 12)),
            errorMessage: optionalText(statement, 13)
        )
    }

    private func withStatement<T>(_ sql: String, database: OpaquePointer, body: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteArchiveIndexStoreError.prepareFailed(errorMessage(database))
        }
        defer {
            sqlite3_finalize(statement)
        }
        return try body(statement)
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteArchiveIndexStoreError.stepFailed(errorMessage(database))
        }
    }

    private func bind(_ value: String, at index: Int32, statement: OpaquePointer) throws {
        guard sqlite3_bind_text(statement, index, value, -1, sqliteTransient) == SQLITE_OK else {
            throw SQLiteArchiveIndexStoreError.bindFailed("Could not bind text value.")
        }
    }

    private func bind(_ value: Int64, at index: Int32, statement: OpaquePointer) throws {
        guard sqlite3_bind_int64(statement, index, value) == SQLITE_OK else {
            throw SQLiteArchiveIndexStoreError.bindFailed("Could not bind integer value.")
        }
    }

    private func bindOptional(_ value: String?, at index: Int32, statement: OpaquePointer) throws {
        guard let value else {
            guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
                throw SQLiteArchiveIndexStoreError.bindFailed("Could not bind null value.")
            }
            return
        }
        try bind(value, at: index, statement: statement)
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        String(cString: sqlite3_column_text(statement, index))
    }

    private func optionalText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return text(statement, index)
    }

    private func warningsJSON(_ warnings: [String]) throws -> String {
        let data = try JSONEncoder().encode(warnings)
        return String(decoding: data, as: UTF8.self)
    }

    private func warnings(fromJSON json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let warnings = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return warnings
    }

    private var iso8601DateFormatter: ISO8601DateFormatter {
        ISO8601DateFormatter()
    }

    private func errorMessage(_ database: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(database))
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
