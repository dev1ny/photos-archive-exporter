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
        case finished = "Finished"
        case failed = "Failed"
    }

    @Published var phase: Phase = .idle
    @Published var destinationRoot: URL?
    @Published var resources: [AssetResourceDescriptor] = []
    @Published var records: [ExportRecord] = []
    @Published var statusMessage = "Choose a destination and authorize Photos access to begin."
    @Published var lastError: String?

    let libraryClient: PhotoKitLibraryClient
    private let resourceWriter: any ResourceWriting

    init(
        libraryClient: PhotoKitLibraryClient? = nil,
        resourceWriter: any ResourceWriting = PhotoKitResourceWriter()
    ) {
        self.libraryClient = libraryClient ?? PhotoKitLibraryClient()
        self.resourceWriter = resourceWriter
        self.libraryClient.refreshAuthorizationState()
    }

    var canScan: Bool {
        libraryClient.authorizationState.canRead && phase != .scanning && phase != .exporting
    }

    var canExport: Bool {
        libraryClient.authorizationState.canRead
            && destinationRoot != nil
            && !resources.isEmpty
            && (phase == .ready || phase == .finished)
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
        statusMessage = "Scanning the current Photos library..."

        do {
            resources = try await libraryClient.scanResources()
            phase = .ready
            statusMessage = "Found \(resources.count) exportable resources."
        } catch {
            resources = []
            records = []
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
        statusMessage = "Exporting \(resources.count) resources..."

        let startedAt = Date()
        let runID = Self.makeRunID(date: startedAt)
        let runner = ExportRunner(resourceWriter: resourceWriter)
        let indexStore = ArchiveIndexStore(destinationRoot: destinationRoot)

        do {
            let newRecords = await runner.export(
                resources: resources,
                destinationRoot: destinationRoot,
                runID: runID,
                exportRunDate: startedAt
            )
            let combinedRecords = try indexStore.loadIndex() + newRecords
            try indexStore.saveIndex(combinedRecords)
            _ = try indexStore.writeResourcesCSV(runID: runID, records: newRecords)
            _ = try indexStore.writeErrorsCSV(runID: runID, records: newRecords)
            _ = try indexStore.writeDuplicatesCSV(
                runID: runID,
                groups: DuplicateReporter.strongDuplicateGroups(from: combinedRecords)
            )

            records = newRecords
            phase = .finished
            statusMessage = "Export finished for run \(runID)."
        } catch {
            phase = .failed
            lastError = error.localizedDescription
            statusMessage = "Export failed."
        }
    }

    func revealDestination() {
        guard let destinationRoot else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([destinationRoot])
    }

    static func makeRunID(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return formatter.string(from: date)
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
