import PhotosArchiveExporterCore
import SwiftUI

struct ExportResultsView: View {
    let report: ExportRunReport
    let reportFiles: [ExportReportFile]
    let revealReports: () -> Void
    let openReportFile: (ExportReportFile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            reportFileButtons
            summaryGrid

            if report.hasIssues {
                issueSections
            } else {
                cleanRunMessage
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor))
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Export Results")
                    .font(.title3.weight(.semibold))
                Text("Run \(report.runID). These details match the JSON index and CSV reports written for this export.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 12)

            Button {
                revealReports()
            } label: {
                Label("Reveal Reports", systemImage: "folder")
            }
        }
    }

    private var reportFileButtons: some View {
        HStack(spacing: 10) {
            ForEach(reportFiles) { file in
                Button {
                    openReportFile(file)
                } label: {
                    Label(file.kind.displayName, systemImage: file.kind.systemImage)
                }
            }
        }
    }

    private var summaryGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 14) {
            GridRow {
                resultMetric("Current Run", value: report.totalCount)
                resultMetric("Failed", value: report.failedRecords.count)
                resultMetric("Warnings", value: report.warningRecords.count)
            }
            GridRow {
                resultMetric("Skipped", value: report.skippedExistingRecords.count)
                resultMetric("Renamed", value: report.renamedConflictRecords.count)
                resultMetric("Duplicates", value: report.duplicateResourceCount)
            }
        }
    }

    private var issueSections: some View {
        VStack(alignment: .leading, spacing: 14) {
            recordSection(
                title: "Failed Exports",
                subtitle: "These resources were not copied and need attention.",
                records: report.failedRecords,
                systemImage: "xmark.octagon",
                tint: .red,
                detail: { record in record.errorMessage ?? "No error message was recorded." }
            )

            duplicateSection(groups: report.duplicateGroups)

            recordSection(
                title: "Warnings",
                subtitle: "These files exported, but metadata fallback or other warnings were recorded.",
                records: report.warningRecords,
                systemImage: "exclamationmark.triangle",
                tint: .orange,
                detail: { record in record.warnings.joined(separator: " ") }
            )

            recordSection(
                title: "Renamed Conflicts",
                subtitle: "These files exported to conflict-safe names because a destination path already existed.",
                records: report.renamedConflictRecords,
                systemImage: "textformat.abc.dottedunderline",
                tint: .blue,
                detail: { record in record.destinationPath }
            )
        }
    }

    private var cleanRunMessage: some View {
        Label("No failures, duplicate resources, warnings, or renamed conflicts found in this run.", systemImage: "checkmark.seal")
            .foregroundStyle(.green)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.green.opacity(0.08))
            )
    }

    @ViewBuilder
    private func recordSection(
        title: String,
        subtitle: String,
        records: [ExportRecord],
        systemImage: String,
        tint: Color,
        detail: @escaping (ExportRecord) -> String
    ) -> some View {
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(title: title, subtitle: subtitle, count: records.count, systemImage: systemImage, tint: tint)

                ForEach(Array(records.prefix(8))) { record in
                    recordRow(record, detail: detail(record), tint: tint)
                }

                if records.count > 8 {
                    Text("\(records.count - 8) more rows are available in the CSV report.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }

    @ViewBuilder
    private func duplicateSection(groups: [DuplicateGroup]) -> some View {
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(
                    title: "Duplicate Resources",
                    subtitle: "These records share the same SHA-256 hash. Files are preserved; nothing is deleted automatically.",
                    count: groups.reduce(0) { $0 + $1.records.count },
                    systemImage: "doc.on.doc",
                    tint: .purple
                )

                ForEach(groups.prefix(6), id: \.sha256) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.sha256)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        ForEach(group.records.prefix(4), id: \.destinationPath) { record in
                            recordRow(record, detail: record.destinationPath, tint: .purple)
                        }

                        if group.records.count > 4 {
                            Text("\(group.records.count - 4) more matching resources are available in the duplicates CSV.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor))
                    )
                }

                if groups.count > 6 {
                    Text("\(groups.count - 6) more duplicate groups are available in the duplicates CSV.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }

    private func sectionHeader(title: String, subtitle: String, count: Int, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                    Text(count.formatted())
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func recordRow(_ record: ExportRecord, detail: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.originalFilename)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Text(record.destinationPath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }

    private func resultMetric(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.formatted())
                .font(.title3.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
