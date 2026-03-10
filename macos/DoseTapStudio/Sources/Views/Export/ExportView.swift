import SwiftUI
import AppKit

struct ExportView: View {
    @ObservedObject var dataStore: DataStore
    @State private var exportStatus: String?

    private let reportBuilder = InsightReportBuilder()

    private var sessions: [InsightSession] {
        dataStore.insightSessions
    }

    private var providerPreview: String {
        reportBuilder.buildProviderSummary(sessions: sessions)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Export & Reports")
                    .font(.largeTitle.bold())

                Text("Generate a provider summary or raw night-level CSV from the imported DoseTap bundle.")
                    .foregroundColor(.secondary)

                actionRow
                availabilityCard
                previewCard
            }
            .padding()
        }
        .navigationTitle("Export")
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button("Save Provider Summary") {
                saveFile(
                    suggestedName: "DoseTap-Provider-Summary.txt",
                    content: providerPreview
                )
            }
            .disabled(sessions.isEmpty)

            Button("Save Night CSV") {
                saveFile(
                    suggestedName: "DoseTap-Night-Summary.csv",
                    content: reportBuilder.buildSessionCSV(sessions: sessions)
                )
            }
            .disabled(sessions.isEmpty)

            Button("Copy Summary") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(providerPreview, forType: .string)
                exportStatus = "Provider summary copied to clipboard."
            }
            .disabled(sessions.isEmpty)

            Spacer()

            if let exportStatus {
                Text(exportStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var availabilityCard: some View {
        HStack(spacing: 12) {
            availabilityMetric(title: "Imported Nights", value: "\(sessions.count)", color: .blue)
            availabilityMetric(title: "Morning Check-Ins", value: "\(sessions.filter { $0.morning != nil }.count)", color: .teal)
            availabilityMetric(title: "Pre-Sleep Logs", value: "\(sessions.filter { $0.preSleep != nil }.count)", color: .pink)
            availabilityMetric(title: "Other Meds Logged", value: "\(sessions.reduce(0) { $0 + $1.medicationCount })", color: .orange)
            Spacer()
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Provider Summary Preview")
                .font(.headline)

            if sessions.isEmpty {
                Text("Import a DoseTap Studio bundle to enable report export.")
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    Text(providerPreview)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 320)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func availabilityMetric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title2.bold())
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 150, alignment: .leading)
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func saveFile(suggestedName: String, content: String) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedName

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                exportStatus = "Saved \(url.lastPathComponent)."
            } catch {
                exportStatus = "Save failed: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    ExportView(dataStore: DataStore())
}
