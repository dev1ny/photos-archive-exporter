import Foundation

public enum ArchiveIndexCompactor {
    public static func compact(_ records: [ExportRecord]) -> [ExportRecord] {
        var resourceOrder: [ResourceRecordKey] = []
        var recordByResource: [ResourceRecordKey: ExportRecord] = [:]

        for record in records {
            let key = ResourceRecordKey(record: record)
            if recordByResource[key] == nil {
                resourceOrder.append(key)
                recordByResource[key] = record
                continue
            }

            if shouldReplace(recordByResource[key], with: record) {
                recordByResource[key] = record
            }
        }

        return resourceOrder.compactMap { recordByResource[$0] }
    }

    private static func shouldReplace(_ existing: ExportRecord?, with candidate: ExportRecord) -> Bool {
        guard let existing else {
            return true
        }

        if candidate.status != .failed {
            return true
        }

        return existing.status == .failed
    }

    private struct ResourceRecordKey: Hashable {
        let assetLocalIdentifier: String
        let resourceIdentifier: String

        init(record: ExportRecord) {
            assetLocalIdentifier = record.assetLocalIdentifier
            resourceIdentifier = record.resourceIdentifier
        }
    }
}
