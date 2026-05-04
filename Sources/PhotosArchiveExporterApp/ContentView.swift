import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            controls
            metrics
            progressPanel
            Spacer(minLength: 0)
        }
        .padding(28)
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
                .disabled(model.phase == .scanning || model.phase == .exporting)
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
                    .disabled(model.phase == .scanning || model.phase == .exporting)

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
                if model.phase == .scanning || model.phase == .exporting {
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
