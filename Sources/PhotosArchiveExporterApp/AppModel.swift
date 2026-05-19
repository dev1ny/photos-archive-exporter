import AppKit
import Combine
import Foundation
import PhotosArchiveExporterCore

@MainActor
final class AppModel: ObservableObject {
    enum Phase: String, CaseIterable {
        case idle = "Idle"
        case scanning = "Scanning"
        case ready = "Ready"
        case exporting = "Exporting"
        case analyzingFaces = "Analyzing Faces"
        case finished = "Finished"
        case failed = "Failed"
    }

    @Published var phase: Phase = .idle
    @Published var destinationRoot: URL?
    @Published var resources: [AssetResourceDescriptor] = []
    @Published var records: [ExportRecord] = []
    @Published private var recordCounts = ExportRecordCounts()
    @Published var lastRunReport: ExportRunReport?
    @Published var reportFiles: [ExportReportFile] = []
    @Published var lastFaceAnalysisSummary: FaceAnalysisRunSummary?
    @Published var faceAnalysisReportFiles: [FaceAnalysisReportFile] = []
    @Published var progress: ArchiveProgress?
    @Published var statusMessage = "Choose a destination and authorize Photos access to begin."
    @Published var lastError: String?

    let libraryClient: PhotoKitLibraryClient
    private let resourceWriter: any ResourceWriting
    private let faceAnalysisCoordinator: FaceAnalysisRunCoordinator
    private static let exportBatchSize = 500
    private static let progressUpdateInterval = 25

    init(
        libraryClient: PhotoKitLibraryClient? = nil,
        resourceWriter: any ResourceWriting = PhotoKitResourceWriter(),
        faceAnalysisCoordinator: FaceAnalysisRunCoordinator = FaceAnalysisRunCoordinator()
    ) {
        self.libraryClient = libraryClient ?? PhotoKitLibraryClient()
        self.resourceWriter = resourceWriter
        self.faceAnalysisCoordinator = faceAnalysisCoordinator
        self.libraryClient.refreshAuthorizationState()
    }

    var isBusy: Bool {
        phase == .scanning || phase == .exporting || phase == .analyzingFaces
    }

    var canScan: Bool {
        libraryClient.authorizationState.canRead && !isBusy
    }

    var canExport: Bool {
        libraryClient.authorizationState.canRead
            && destinationRoot != nil
            && !resources.isEmpty
            && (phase == .ready || phase == .finished)
    }

    var canIncrementalBackup: Bool {
        canExport
    }

    var faceAnalysisEligibleImageCount: Int {
        recordCounts.faceAnalysisEligibleImageCount
    }

    var canAnalyzeFaces: Bool {
        destinationRoot != nil && faceAnalysisEligibleImageCount > 0 && !isBusy
    }

    var faceAnalyzedCount: Int {
        lastFaceAnalysisSummary?.analyzedAssetCount ?? 0
    }

    var faceAnalysisFailedCount: Int {
        lastFaceAnalysisSummary?.failedAssetCount ?? 0
    }

    var facesDetectedCount: Int {
        lastFaceAnalysisSummary?.facesDetectedCount ?? 0
    }

    var exportedCount: Int {
        recordCounts.exported
    }

    var skippedCount: Int {
        recordCounts.skipped
    }

    var failedCount: Int {
        recordCounts.failed
    }

    var renamedCount: Int {
        recordCounts.renamed
    }

    var duplicateCount: Int {
        recordCounts.duplicates
    }

    func requestPhotosAccess() async {
        lastError = nil
        clearProgress()
        let authorizationState = await libraryClient.requestAuthorization()
        if authorizationState.canRead {
            statusMessage = "Photos access authorized."
        } else {
            resources = []
            setRecords([])
            clearRunReport()
            clearFaceAnalysisReport()
            phase = .failed
            lastError = "Photos access is \(authorizationState.displayName.lowercased())."
            statusMessage = "Photos access is required before scanning."
        }
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose Photos Archive Destination"
        panel.prompt = "Choose Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        destinationRoot = url
        lastError = nil
        clearProgress()
        clearFaceAnalysisReport()
        statusMessage = "Destination set to \(url.path)."
    }

    func scanLibrary() async {
        guard canScan else {
            return
        }

        phase = .scanning
        lastError = nil
        resources = []
        setRecords([])
        clearRunReport()
        clearFaceAnalysisReport()
        updateIndeterminateProgress(
            title: "Scanning Library",
            detail: "Scanning the current Photos library..."
        )

        do {
            resources = try await libraryClient.scanResources()
            phase = .ready
            updateProgress(
                title: "Scanning Library",
                completed: resources.count,
                total: resources.count,
                detail: "Found \(resources.count.formatted()) exportable resources."
            )
        } catch {
            resources = []
            setRecords([])
            clearRunReport()
            clearFaceAnalysisReport()
            clearProgress()
            phase = .failed
            lastError = error.localizedDescription
            statusMessage = "Scan failed."
        }
    }

    func startExport() async {
        await runExport(mode: .full)
    }

    func startIncrementalBackup() async {
        await runExport(mode: .incremental)
    }

    func startFaceAnalysis() async {
        guard canAnalyzeFaces, let destinationRoot else {
            return
        }

        phase = .analyzingFaces
        lastError = nil
        clearFaceAnalysisReport()
        updateProgress(
            title: "Face Analysis",
            completed: 0,
            total: faceAnalysisEligibleImageCount,
            detail: "Analyzing \(faceAnalysisEligibleImageCount.formatted()) exported photos..."
        )

        let startedAt = Date()
        let runID = Self.makeRunID(date: startedAt)

        do {
            let result = try await faceAnalysisCoordinator.analyzeAndWriteReports(
                records: records,
                destinationRoot: destinationRoot,
                runID: runID,
                settings: .defaultLowResource,
                analyzedAt: startedAt,
                progressHandler: { [weak self] completed, total in
                    await MainActor.run {
                        self?.updateProgress(
                            title: "Face Analysis",
                            completed: completed,
                            total: total,
                            detail: "Analyzed \(completed.formatted()) of \(total.formatted()) exported photos."
                        )
                    }
                }
            )

            lastFaceAnalysisSummary = result.summary
            faceAnalysisReportFiles = [
                FaceAnalysisReportFile(kind: .index, url: result.reportURLs.index),
                FaceAnalysisReportFile(kind: .summary, url: result.reportURLs.summary),
                FaceAnalysisReportFile(kind: .assets, url: result.reportURLs.assets),
                FaceAnalysisReportFile(kind: .faces, url: result.reportURLs.faces),
                FaceAnalysisReportFile(kind: .errors, url: result.reportURLs.errors)
            ]

            phase = .finished
            updateProgress(
                title: "Face Analysis",
                completed: result.summary.totalAssetCount,
                total: result.summary.totalAssetCount,
                detail: "Face analysis finished for run \(runID)."
            )
        } catch {
            clearFaceAnalysisReport()
            clearProgress()
            phase = .failed
            lastError = error.localizedDescription
            statusMessage = "Face analysis failed."
        }
    }

    func revealDestination() {
        guard let destinationRoot else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([destinationRoot])
    }

    func revealReports() {
        guard !reportFiles.isEmpty else {
            revealDestination()
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting(reportFiles.map(\.url))
    }

    func openReportFile(_ file: ExportReportFile) {
        NSWorkspace.shared.open(file.url)
    }

    func revealFaceAnalysisReports() {
        guard !faceAnalysisReportFiles.isEmpty else {
            revealDestination()
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting(faceAnalysisReportFiles.map(\.url))
    }

    func openFaceAnalysisReportFile(_ file: FaceAnalysisReportFile) {
        NSWorkspace.shared.open(file.url)
    }

    static func makeRunID(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return formatter.string(from: date)
    }

    private func clearRunReport() {
        lastRunReport = nil
        reportFiles = []
    }

    private func clearFaceAnalysisReport() {
        lastFaceAnalysisSummary = nil
        faceAnalysisReportFiles = []
    }

    private func clearProgress() {
        progress = nil
    }

    private func updateProgress(
        title: String,
        completed: Int,
        total: Int?,
        detail: String
    ) {
        progress = ArchiveProgress(
            title: title,
            completedUnitCount: completed,
            totalUnitCount: total,
            detail: detail
        )
        statusMessage = detail
    }

    private func updateIndeterminateProgress(title: String, detail: String) {
        progress = .indeterminate(title: title, detail: detail)
        statusMessage = detail
    }

    private func setRecords(_ records: [ExportRecord], duplicateGroups: [DuplicateGroup] = []) {
        self.records = records
        recordCounts = ExportRecordCounts(records: records, duplicateGroups: duplicateGroups)
    }

    private func runExport(mode: ExportMode) async {
        guard canExport, let destinationRoot else {
            return
        }

        phase = .exporting
        lastError = nil
        setRecords([])
        clearRunReport()
        clearFaceAnalysisReport()
        updateProgress(
            title: mode.progressTitle,
            completed: 0,
            total: resources.count,
            detail: mode.startMessage(resourceCount: resources.count)
        )

        let startedAt = Date()
        let runID = Self.makeRunID(date: startedAt)
        let runner = ExportRunner(resourceWriter: resourceWriter)
        let indexStore = ArchiveIndexStore(destinationRoot: destinationRoot)

        // GC orphaned tmp/<UUID> files from any previously crashed / cancelled
        // run before we start writing new ones. Best-effort — never blocks.
        let purged = runner.purgeOrphanedTemporaryFiles(at: destinationRoot)
        if purged > 0 {
            updateProgress(
                title: mode.progressTitle,
                completed: 0,
                total: resources.count,
                detail: "Cleaned up \(purged) leftover temporary file\(purged == 1 ? "" : "s") from a previous run."
            )
        }

        do {
            let exportResult = try await makeExportRecords(
                mode: mode,
                runner: runner,
                indexStore: indexStore,
                destinationRoot: destinationRoot,
                runID: runID,
                startedAt: startedAt
            )
            let duplicateGroups = try indexStore.loadDuplicateGroups()
            let currentRunDuplicateGroups = DuplicateReporter.strongDuplicateGroups(from: exportResult.records)
            setRecords(exportResult.records, duplicateGroups: currentRunDuplicateGroups)
            updateProgress(
                title: mode.progressTitle,
                completed: exportResult.records.count,
                total: resources.count,
                detail: "Writing export reports..."
            )
            let resourcesCSV = try indexStore.writeResourcesCSV(runID: runID, records: exportResult.records)
            let errorsCSV = try indexStore.writeErrorsCSV(runID: runID, records: exportResult.records)
            let duplicatesCSV = try indexStore.writeDuplicatesCSV(runID: runID, groups: duplicateGroups)

            lastRunReport = ExportRunReport(
                runID: runID,
                currentRunRecords: exportResult.records,
                duplicateGroups: duplicateGroups
            )

            var files = [
                ExportReportFile(kind: .archiveIndex, url: indexStore.sqliteIndexURL),
                ExportReportFile(kind: .resources, url: resourcesCSV),
                ExportReportFile(kind: .errors, url: errorsCSV),
                ExportReportFile(kind: .duplicates, url: duplicatesCSV)
            ]
            if let incrementalPlanURL = exportResult.incrementalPlanURL {
                files.append(ExportReportFile(kind: .incrementalPlan, url: incrementalPlanURL))
            }
            reportFiles = files

            phase = .finished
            updateProgress(
                title: mode.progressTitle,
                completed: exportResult.records.count,
                total: resources.count,
                detail: mode.finishedMessage(runID: runID)
            )
        } catch {
            clearRunReport()
            clearProgress()
            phase = .failed
            lastError = error.localizedDescription
            statusMessage = mode.failedMessage
        }
    }

    private func makeExportRecords(
        mode: ExportMode,
        runner: ExportRunner,
        indexStore: ArchiveIndexStore,
        destinationRoot: URL,
        runID: String,
        startedAt: Date
    ) async throws -> ExportResult {
        switch mode {
        case .full:
            let exportedRecords = try await exportResourcesInBatches(
                runner: runner,
                indexStore: indexStore,
                destinationRoot: destinationRoot,
                runID: runID,
                startedAt: startedAt
            )
            return ExportResult(records: exportedRecords, incrementalPlanURL: nil)

        case .incremental:
            return try await exportIncrementalResourcesInBatches(
                runner: runner,
                indexStore: indexStore,
                destinationRoot: destinationRoot,
                runID: runID,
                startedAt: startedAt
            )
        }
    }

    private func exportResourcesInBatches(
        runner: ExportRunner,
        indexStore: ArchiveIndexStore,
        destinationRoot: URL,
        runID: String,
        startedAt: Date
    ) async throws -> [ExportRecord] {
        var currentRunRecords: [ExportRecord] = []
        var completedCount = 0

        try await forEachResourceBatch { batch in
            let previousRecords = try indexStore.loadIndex(for: batch)
            _ = try await runner.exportInBatches(
                resources: batch,
                destinationRoot: destinationRoot,
                runID: runID,
                exportRunDate: startedAt,
                existingRecords: previousRecords,
                batchSize: Self.progressUpdateInterval,
                didPlanRecord: { plannedRecord in
                    try indexStore.saveIndex([plannedRecord])
                },
                didExportBatch: { batchRecords in
                    try indexStore.saveIndex(batchRecords)
                    currentRunRecords.append(contentsOf: batchRecords)
                    completedCount += batchRecords.count
                    updateProgress(
                        title: ExportMode.full.progressTitle,
                        completed: completedCount,
                        total: resources.count,
                        detail: "Exported \(completedCount.formatted()) of \(resources.count.formatted()) resources."
                    )
                }
            )
        }

        return currentRunRecords
    }

    private func exportIncrementalResourcesInBatches(
        runner: ExportRunner,
        indexStore: ArchiveIndexStore,
        destinationRoot: URL,
        runID: String,
        startedAt: Date
    ) async throws -> ExportResult {
        let planner = IncrementalBackupPlanner()
        var currentRunRecords: [ExportRecord] = []
        var planEntries: [IncrementalBackupPlanEntry] = []
        var skippedCount = 0
        var queuedCount = 0
        var completedCount = 0

        try await forEachResourceBatch { batch in
            let previousRecords = try indexStore.loadIndex(for: batch)
            let plan = try await makeIncrementalPlan(
                planner: planner,
                resources: batch,
                previousRecords: previousRecords,
                runID: runID,
                exportRunDate: startedAt
            )
            skippedCount += plan.skippedRecords.count
            queuedCount += plan.resourcesToExport.count
            completedCount += plan.skippedRecords.count
            updateProgress(
                title: ExportMode.incremental.progressTitle,
                completed: completedCount,
                total: resources.count,
                detail: "Incremental backup verified \(skippedCount.formatted()) existing resources and queued \(queuedCount.formatted()) resources."
            )

            let exportedRecords = try await runner.exportInBatches(
                resources: plan.resourcesToExport,
                destinationRoot: destinationRoot,
                runID: runID,
                exportRunDate: startedAt,
                existingRecords: previousRecords + plan.skippedRecords,
                batchSize: Self.progressUpdateInterval,
                didPlanRecord: { plannedRecord in
                    try indexStore.saveIndex([plannedRecord])
                },
                didExportBatch: { exportedBatch in
                    completedCount += exportedBatch.count
                    updateProgress(
                        title: ExportMode.incremental.progressTitle,
                        completed: completedCount,
                        total: resources.count,
                        detail: "Incremental backup processed \(completedCount.formatted()) of \(resources.count.formatted()) resources."
                    )
                }
            )
            let batchRecords = plan.currentRunRecords(exportedRecords: exportedRecords)
            try indexStore.saveIndex(batchRecords)
            currentRunRecords.append(contentsOf: batchRecords)
            planEntries.append(contentsOf: plan.entries)
        }

        let incrementalPlanCSV = try indexStore.writeIncrementalPlanCSV(runID: runID, entries: planEntries)
        return ExportResult(records: currentRunRecords, incrementalPlanURL: incrementalPlanCSV)
    }

    private nonisolated func makeIncrementalPlan(
        planner: IncrementalBackupPlanner,
        resources: [AssetResourceDescriptor],
        previousRecords: [ExportRecord],
        runID: String,
        exportRunDate: Date
    ) async throws -> IncrementalBackupPlan {
        try await Task.detached(priority: .utility) {
            try planner.plan(
                resources: resources,
                previousRecords: previousRecords,
                runID: runID,
                exportRunDate: exportRunDate
            )
        }.value
    }

    private func forEachResourceBatch(_ body: ([AssetResourceDescriptor]) async throws -> Void) async throws {
        var startIndex = resources.startIndex

        while startIndex < resources.endIndex {
            try Task.checkCancellation()
            let endIndex = resources.index(startIndex, offsetBy: Self.exportBatchSize, limitedBy: resources.endIndex) ?? resources.endIndex
            try await body(Array(resources[startIndex..<endIndex]))
            // Release the per-batch PHAssetResource cache so memory stays bounded
            // when exporting tens of thousands of resources.
            (resourceWriter as? PhotoKitResourceWriter)?.resetBatchCache()
            startIndex = endIndex
        }
    }
}

private enum ExportMode {
    case full
    case incremental

    var progressTitle: String {
        switch self {
        case .full:
            return "Full Export"
        case .incremental:
            return "Incremental Backup"
        }
    }

    func startMessage(resourceCount: Int) -> String {
        switch self {
        case .full:
            return "Exporting \(resourceCount) resources..."
        case .incremental:
            return "Planning incremental backup for \(resourceCount) resources..."
        }
    }

    func finishedMessage(runID: String) -> String {
        switch self {
        case .full:
            return "Export finished for run \(runID)."
        case .incremental:
            return "Incremental backup finished for run \(runID)."
        }
    }

    var failedMessage: String {
        switch self {
        case .full:
            return "Export failed."
        case .incremental:
            return "Incremental backup failed."
        }
    }
}

private struct ExportResult {
    let records: [ExportRecord]
    let incrementalPlanURL: URL?
}

private struct ExportRecordCounts {
    let exported: Int
    let skipped: Int
    let failed: Int
    let renamed: Int
    let duplicates: Int
    let faceAnalysisEligibleImageCount: Int

    init(
        exported: Int = 0,
        skipped: Int = 0,
        failed: Int = 0,
        renamed: Int = 0,
        duplicates: Int = 0,
        faceAnalysisEligibleImageCount: Int = 0
    ) {
        self.exported = exported
        self.skipped = skipped
        self.failed = failed
        self.renamed = renamed
        self.duplicates = duplicates
        self.faceAnalysisEligibleImageCount = faceAnalysisEligibleImageCount
    }

    init(records: [ExportRecord], duplicateGroups: [DuplicateGroup]) {
        var exported = 0
        var skipped = 0
        var failed = 0
        var renamed = 0
        var faceAnalysisEligibleImageCount = 0

        for record in records {
            switch record.status {
            case .exported:
                exported += 1
            case .skippedExisting:
                skipped += 1
            case .failed:
                failed += 1
            case .renamedConflict:
                renamed += 1
            case .planned:
                break
            }

            let effectiveMediaType = ResourceMediaTypeResolver.mediaType(
                for: record.resourceType,
                assetMediaType: record.mediaType
            )
            if effectiveMediaType == .image && record.status != .failed {
                faceAnalysisEligibleImageCount += 1
            }
        }

        self.exported = exported
        self.skipped = skipped
        self.failed = failed
        self.renamed = renamed
        self.duplicates = duplicateGroups.reduce(0) { $0 + $1.records.count }
        self.faceAnalysisEligibleImageCount = faceAnalysisEligibleImageCount
    }
}

extension PhotosAuthorizationState {
    var displayName: String {
        switch self {
        case .notDetermined:
            return "Not Determined"
        case .authorized:
            return "Authorized"
        case .limited:
            return "Limited"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        }
    }
}

struct ExportReportFile: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case archiveIndex
        case resources
        case errors
        case duplicates
        case incrementalPlan

        var displayName: String {
            switch self {
            case .archiveIndex:
                return "Index SQLite"
            case .resources:
                return "Resources CSV"
            case .errors:
                return "Errors CSV"
            case .duplicates:
                return "Duplicates CSV"
            case .incrementalPlan:
                return "Incremental Plan CSV"
            }
        }

        var systemImage: String {
            switch self {
            case .archiveIndex:
                return "doc.text"
            case .resources:
                return "tablecells"
            case .errors:
                return "exclamationmark.triangle"
            case .duplicates:
                return "doc.on.doc"
            case .incrementalPlan:
                return "arrow.triangle.2.circlepath"
            }
        }
    }

    let kind: Kind
    let url: URL

    var id: Kind {
        kind
    }
}

struct FaceAnalysisReportFile: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case index
        case summary
        case assets
        case faces
        case errors

        var displayName: String {
            switch self {
            case .index:
                return "Index JSON"
            case .summary:
                return "Summary JSON"
            case .assets:
                return "Assets CSV"
            case .faces:
                return "Faces CSV"
            case .errors:
                return "Errors CSV"
            }
        }

        var systemImage: String {
            switch self {
            case .index, .summary:
                return "doc.text"
            case .assets, .faces:
                return "tablecells"
            case .errors:
                return "exclamationmark.triangle"
            }
        }
    }

    let kind: Kind
    let url: URL

    var id: Kind {
        kind
    }
}
