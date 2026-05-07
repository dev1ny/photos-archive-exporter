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
    @Published var lastRunReport: ExportRunReport?
    @Published var reportFiles: [ExportReportFile] = []
    @Published var lastFaceAnalysisSummary: FaceAnalysisRunSummary?
    @Published var faceAnalysisReportFiles: [FaceAnalysisReportFile] = []
    @Published var statusMessage = "Choose a destination and authorize Photos access to begin."
    @Published var lastError: String?

    let libraryClient: PhotoKitLibraryClient
    private let resourceWriter: any ResourceWriting
    private let faceAnalysisCoordinator: FaceAnalysisRunCoordinator

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

    var faceAnalysisEligibleImageCount: Int {
        records.filter { $0.mediaType == .image && $0.status != .failed }.count
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
        records.filter { $0.status == .exported }.count
    }

    var skippedCount: Int {
        records.filter { $0.status == .skippedExisting }.count
    }

    var failedCount: Int {
        records.filter { $0.status == .failed }.count
    }

    var renamedCount: Int {
        records.filter { $0.status == .renamedConflict }.count
    }

    var duplicateCount: Int {
        DuplicateReporter.strongDuplicateGroups(from: records)
            .reduce(0) { $0 + $1.records.count }
    }

    func requestPhotosAccess() async {
        lastError = nil
        let authorizationState = await libraryClient.requestAuthorization()
        if authorizationState.canRead {
            statusMessage = "Photos access authorized."
        } else {
            resources = []
            records = []
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
        records = []
        clearRunReport()
        clearFaceAnalysisReport()
        statusMessage = "Scanning the current Photos library..."

        do {
            resources = try await libraryClient.scanResources()
            phase = .ready
            statusMessage = "Found \(resources.count) exportable resources."
        } catch {
            resources = []
            records = []
            clearRunReport()
            clearFaceAnalysisReport()
            phase = .failed
            lastError = error.localizedDescription
            statusMessage = "Scan failed."
        }
    }

    func startExport() async {
        guard canExport, let destinationRoot else {
            return
        }

        phase = .exporting
        lastError = nil
        records = []
        clearRunReport()
        clearFaceAnalysisReport()
        statusMessage = "Exporting \(resources.count) resources..."

        let startedAt = Date()
        let runID = Self.makeRunID(date: startedAt)
        let runner = ExportRunner(resourceWriter: resourceWriter)
        let indexStore = ArchiveIndexStore(destinationRoot: destinationRoot)

        do {
            let previousRecords = try indexStore.loadIndex()
            let newRecords = await runner.export(
                resources: resources,
                destinationRoot: destinationRoot,
                runID: runID,
                exportRunDate: startedAt,
                existingRecords: previousRecords
            )
            records = newRecords

            let combinedRecords = previousRecords + newRecords
            let duplicateGroups = DuplicateReporter.strongDuplicateGroups(from: combinedRecords)
            try indexStore.saveIndex(combinedRecords)
            let resourcesCSV = try indexStore.writeResourcesCSV(runID: runID, records: newRecords)
            let errorsCSV = try indexStore.writeErrorsCSV(runID: runID, records: newRecords)
            let duplicatesCSV = try indexStore.writeDuplicatesCSV(runID: runID, groups: duplicateGroups)

            lastRunReport = ExportRunReport(
                runID: runID,
                currentRunRecords: newRecords,
                duplicateGroups: duplicateGroups
            )
            reportFiles = [
                ExportReportFile(kind: .archiveIndex, url: indexStore.indexURL),
                ExportReportFile(kind: .resources, url: resourcesCSV),
                ExportReportFile(kind: .errors, url: errorsCSV),
                ExportReportFile(kind: .duplicates, url: duplicatesCSV)
            ]

            phase = .finished
            statusMessage = "Export finished for run \(runID)."
        } catch {
            clearRunReport()
            phase = .failed
            lastError = error.localizedDescription
            statusMessage = "Export failed."
        }
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

        var displayName: String {
            switch self {
            case .archiveIndex:
                return "Index JSON"
            case .resources:
                return "Resources CSV"
            case .errors:
                return "Errors CSV"
            case .duplicates:
                return "Duplicates CSV"
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
