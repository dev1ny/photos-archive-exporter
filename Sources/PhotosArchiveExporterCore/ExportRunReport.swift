import Foundation

public struct ExportRunReport: Equatable {
    public let runID: String
    public let currentRunRecords: [ExportRecord]
    public let duplicateGroups: [DuplicateGroup]

    public init(runID: String, currentRunRecords: [ExportRecord], duplicateGroups: [DuplicateGroup]) {
        self.runID = runID
        self.currentRunRecords = currentRunRecords
        self.duplicateGroups = duplicateGroups
    }

    public var totalCount: Int {
        currentRunRecords.count
    }

    public var exportedRecords: [ExportRecord] {
        currentRunRecords.filter { $0.status == .exported }
    }

    public var skippedExistingRecords: [ExportRecord] {
        currentRunRecords.filter { $0.status == .skippedExisting }
    }

    public var failedRecords: [ExportRecord] {
        currentRunRecords.filter { $0.status == .failed }
    }

    public var renamedConflictRecords: [ExportRecord] {
        currentRunRecords.filter { $0.status == .renamedConflict }
    }

    public var warningRecords: [ExportRecord] {
        currentRunRecords.filter { !$0.warnings.isEmpty }
    }

    public var duplicateResourceCount: Int {
        duplicateGroups.reduce(0) { $0 + $1.records.count }
    }

    public var hasIssues: Bool {
        !failedRecords.isEmpty
            || !warningRecords.isEmpty
            || !renamedConflictRecords.isEmpty
            || !duplicateGroups.isEmpty
    }
}
