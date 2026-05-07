import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                controls
                metrics
                progressPanel
                faceAnalysisPanel
                resultPanel
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Photos Archive Exporter")
                .font(.largeTitle.weight(.semibold))
            Text("Reads the current Photos library and exports originals into a dated archive without modifying the library.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
            GridRow {
                controlLabel("Photos Access")
                Text(model.libraryClient.authorizationState.displayName)
                    .foregroundStyle(model.libraryClient.authorizationState.canRead ? .primary : .secondary)
                Button("Authorize") {
                    Task { await model.requestPhotosAccess() }
                }
                .disabled(model.isBusy)
            }

            GridRow {
                controlLabel("Destination")
                Text(model.destinationRoot?.path ?? "No folder selected")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(model.destinationRoot == nil ? .secondary : .primary)
                HStack(spacing: 10) {
                    Button("Choose Folder") {
                        model.chooseDestination()
                    }
                    .disabled(model.isBusy)

                    Button("Reveal Destination") {
                        model.revealDestination()
                    }
                    .disabled(model.destinationRoot == nil)
                }
            }

            GridRow {
                controlLabel("Run")
                Text(model.phase.rawValue)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("Scan Library") {
                        Task { await model.scanLibrary() }
                    }
                    .disabled(!model.canScan)

                    Button("Start Full Export") {
                        Task { await model.startExport() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canExport)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var metrics: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 14) {
            GridRow {
                metric("Resources", value: model.resources.count)
                metric("Exported", value: model.exportedCount)
                metric("Skipped", value: model.skippedCount)
            }
            GridRow {
                metric("Renamed", value: model.renamedCount)
                metric("Failed", value: model.failedCount)
                metric("Duplicates", value: model.duplicateCount)
            }
        }
    }

    private var progressPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if model.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(model.phase.rawValue)
                    .font(.headline)

                Spacer()
            }

            Text(model.statusMessage)
                .foregroundStyle(.secondary)

            if let lastError = model.lastError {
                Text(lastError)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor))
        )
    }

    private var faceAnalysisPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Face Analysis")
                        .font(.title3.weight(.semibold))
                    Text(faceAnalysisStatusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 12)

                HStack(spacing: 10) {
                    Button {
                        Task { await model.startFaceAnalysis() }
                    } label: {
                        Label("Analyze Exported Photos", systemImage: "face.smiling")
                    }
                    .disabled(!model.canAnalyzeFaces)

                    Button {
                        model.revealFaceAnalysisReports()
                    } label: {
                        Label("Reveal Reports", systemImage: "folder")
                    }
                    .disabled(model.faceAnalysisReportFiles.isEmpty)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    metric("Analyzed", value: model.faceAnalyzedCount)
                    metric("Failed", value: model.faceAnalysisFailedCount)
                    metric("Faces Detected", value: model.facesDetectedCount)
                }
            }

            if !model.faceAnalysisReportFiles.isEmpty {
                HStack(spacing: 10) {
                    ForEach(model.faceAnalysisReportFiles) { file in
                        Button {
                            model.openFaceAnalysisReportFile(file)
                        } label: {
                            Label(file.kind.displayName, systemImage: file.kind.systemImage)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor))
        )
    }

    private var faceAnalysisStatusText: String {
        if let summary = model.lastFaceAnalysisSummary {
            return "Run \(summary.runID). Reports are written under the archive support folder."
        }

        if model.faceAnalysisEligibleImageCount > 0 {
            return "\(model.faceAnalysisEligibleImageCount) exported photos are ready for local analysis."
        }

        return "Export photos first, then run local face analysis on this run."
    }

    @ViewBuilder
    private var resultPanel: some View {
        if let report = model.lastRunReport {
            ExportResultsView(
                report: report,
                reportFiles: model.reportFiles,
                revealReports: model.revealReports,
                openReportFile: model.openReportFile
            )
        }
    }

    private func controlLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 120, alignment: .leading)
    }

    private func metric(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.formatted())
                .font(.title2.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

}
