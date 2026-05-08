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
    @Published var statusMessage = "Choose a destination and authorize Photos access to begin."
    @Published var lastError: String?

    let libraryClient: PhotoKitLibraryClient
    private let resourceWriter: any ResourceWriting
    private let faceAnalysisCoordinator: FaceAnalysisRunCoordinator
    private static let exportBatchSize = 500

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
        statusMessage = "Scanning the current Photos library..."

        do {
            resources = try await libraryClient.scanResources()
            phase = .ready
            statusMessage = "Found \(resources.count) exportable resources."
        } catch {
            resources = []
            setRecords([])
            clearRunReport()
            clearFaceAnalysisReport()
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
        statusMessage = "Analyzing \(faceAnalysisEligibleImageCount) exported photos..."

        let startedAt = Date()
        let runID = Self.makeRunID(date: startedAt)

        do {
            let result = try await faceAnalysisCoordinator.analyzeAndWriteReports(
                records: records,
                destinationRoot: destinationRoot,
                runID: runID,
                settings: .defaultLowResource,
                analyzedAt: startedAt
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
            statusMessage = "Face analysis finished for run \(runID)."
        } catch {
            clearFaceAnalysisReport()
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
        statusMessage = mode.startMessage(resourceCount: resources.count)

        let startedAt = Date()
        let runID = Self.makeRunID(date: startedAt)
        let runner = ExportRunner(resourceWriter: resourceWriter)
        let indexStore = ArchiveIndexStore(destinationRoot: destinationRoot)

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
            statusMessage = mode.finishedMessage(runID: runID)
        } catch {
            clearRunReport()
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

        try await forEachResourceBatch { batch in
            let previousRecords = try indexStore.loadIndex(for: batch)
            let batchRecords = await runner.export(
                resources: batch,
                destinationRoot: destinationRoot,
                runID: runID,
                exportRunDate: startedAt,
                existingRecords: previousRecords
            )
            try indexStore.saveIndex(batchRecords)
            currentRunRecords.append(contentsOf: batchRecords)
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
            statusMessage = "Incremental backup verified \(skippedCount) existing resources and queued \(queuedCount) resources."

            let exportedRecords = await runner.export(
                resources: plan.resourcesToExport,
                destinationRoot: destinationRoot,
                runID: runID,
                exportRunDate: startedAt,
                existingRecords: previousRecords + plan.skippedRecords
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

    private func forEachResourceBatch(_ body: ([AssetResourceDescriptor]) async throws -> Void) async rethrows {
        var startIndex = resources.startIndex

        while startIndex < resources.endIndex {
            let endIndex = resources.index(startIndex, offsetBy: Self.exportBatchSize, limitedBy: resources.endIndex) ?? resources.endIndex
            try await body(Array(resources[startIndex..<endIndex]))
            startIndex = endIndex
        }
    }
}

private enum ExportMode {
    case full
    case incremental

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

            if record.mediaType == .image && record.status != .failed {
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
