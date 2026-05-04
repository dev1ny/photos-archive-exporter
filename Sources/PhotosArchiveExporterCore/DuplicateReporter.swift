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
        var latestRecordByDestinationPath: [String: ExportRecord] = [:]
        for record in records {
            guard record.status != .failed,
                  let sha256 = record.sha256,
                  !sha256.isEmpty
            else {
                continue
            }
            latestRecordByDestinationPath[record.destinationPath] = record
        }

        let grouped = Dictionary(grouping: latestRecordByDestinationPath.values) { record in
            record.sha256 ?? ""
        }

        return grouped
            .compactMap { sha256, pairs -> DuplicateGroup? in
                return pairs.count > 1 ? DuplicateGroup(sha256: sha256, records: pairs) : nil
            }
            .sorted { $0.sha256 < $1.sha256 }
    }
}
