import Foundation

public struct DuplicateGroup: Codable, Equatable {
    public let sha256: String
    public let records: [ExportRecord]

    public init(sha256: String, records: [ExportRecord]) {
        self.sha256 = sha256
        self.records = records
    }
}

public enum DuplicateReporter {
    public static func strongDuplicateGroups(from records: [ExportRecord]) -> [DuplicateGroup] {
        let grouped = Dictionary(grouping: records.compactMap { record -> (String, ExportRecord)? in
            guard let sha256 = record.sha256, !sha256.isEmpty else {
                return nil
            }
            return (sha256, record)
        }, by: { $0.0 })

        return grouped
            .compactMap { sha256, pairs -> DuplicateGroup? in
                let records = pairs.map(\.1)
                return records.count > 1 ? DuplicateGroup(sha256: sha256, records: records) : nil
            }
            .sorted { $0.sha256 < $1.sha256 }
    }
}
