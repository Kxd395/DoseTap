import SwiftUI
import AppKit

struct ExportView: View {
    @ObservedObject var dataStore: DataStore
    @State private var exportStatus: String?
    @State private var recommendationMode: InsightRecommendationMode = .restfulSleep
    @State private var redactClinicianExport = false
    @State private var encryptSavedExports = false

    private let reportBuilder = InsightReportBuilder()
    private let encryptionService = ExportEncryptionService()

    private var redaction: InsightExportRedactionOptions {
        redactClinicianExport ? .clinicianSafe : .none
    }

    private var sessions: [InsightSession] {
        dataStore.insightSessions
    }

    private var providerPreview: String {
        reportBuilder.buildProviderSummary(
            sessions: sessions,
            bundle: dataStore.importedInsightsBundle,
            redaction: redaction
        )
    }

    private var recommendationPreview: String {
        reportBuilder.buildRecommendationPackage(
            sessions: sessions,
            mode: recommendationMode,
            bundle: dataStore.importedInsightsBundle,
            redaction: redaction
        )
    }

    private var metricFactsCSV: String {
        reportBuilder.buildMetricFactsCSV(
            sessions: sessions,
            redaction: redaction
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Export & Reports")
                    .font(.largeTitle.bold())

                Text("Generate provider-facing summaries, matched-night review exports, and raw night-level CSV from the imported DoseTap bundle.")
                    .foregroundColor(.secondary)

                Toggle("Redact free text, exact timestamps, and bundle fingerprint for clinician exports", isOn: $redactClinicianExport)
                    .toggleStyle(.switch)

                Toggle("Encrypt saved exports with a passphrase", isOn: $encryptSavedExports)
                    .toggleStyle(.switch)

                actionRow
                bundleMetadataCard
                availabilityCard
                previewCard
                recommendationPreviewCard
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
                    content: reportBuilder.buildSessionCSV(
                        sessions: sessions,
                        redaction: redaction
                    )
                )
            }
            .disabled(sessions.isEmpty)

            Button("Save Metric Facts CSV") {
                saveFile(
                    suggestedName: redactClinicianExport ? "DoseTap-Metric-Facts-Redacted.csv" : "DoseTap-Metric-Facts.csv",
                    content: metricFactsCSV
                )
            }
            .disabled(sessions.isEmpty)

            Button("Save Timing Insight Package") {
                saveFile(
                    suggestedName: "DoseTap-Timing-Insight-Package.txt",
                    content: recommendationPreview
                )
            }
            .disabled(sessions.isEmpty)

            Button("Save Timing Comparison CSV") {
                saveFile(
                    suggestedName: "DoseTap-Timing-Comparison.csv",
                    content: reportBuilder.buildRecommendationComparisonCSV(
                        sessions: sessions,
                        mode: recommendationMode
                    )
                )
            }
            .disabled(sessions.isEmpty)

            Button("Save Imported Bundle Copy") {
                guard let data = dataStore.importedInsightsBundleData else { return }
                saveData(
                    suggestedName: dataStore.importedInsightsBundle?.importMetadata?.fileName ?? "insights_bundle.json",
                    data: data
                )
            }
            .disabled(dataStore.importedInsightsBundleData == nil)

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
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 150)),
                GridItem(.flexible(minimum: 150)),
                GridItem(.flexible(minimum: 150))
            ],
            alignment: .leading,
            spacing: 12
        ) {
            availabilityMetric(title: "Imported Nights", value: "\(sessions.count)", color: .blue)
            availabilityMetric(title: "Morning Check-Ins", value: "\(sessions.filter { $0.morning != nil }.count)", color: .teal)
            availabilityMetric(title: "Pre-Sleep Logs", value: "\(sessions.filter { $0.preSleep != nil }.count)", color: .pink)
            availabilityMetric(title: "Apple Health Nights", value: "\(sessions.filter { $0.healthKit != nil }.count)", color: .green)
            availabilityMetric(title: "WHOOP Nights", value: "\(sessions.filter { $0.whoop != nil }.count)", color: .indigo)
            availabilityMetric(title: "Other Meds Logged", value: "\(sessions.reduce(0) { $0 + $1.medicationCount })", color: .orange)
        }
    }

    @ViewBuilder
    private var bundleMetadataCard: some View {
        if let bundle = dataStore.importedInsightsBundle {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 150)),
                    GridItem(.flexible(minimum: 150)),
                    GridItem(.flexible(minimum: 150))
                ],
                alignment: .leading,
                spacing: 12
            ) {
                availabilityMetric(title: "Schema", value: "\(bundle.schemaVersion)", color: .secondary)
                availabilityMetric(title: "Export Version", value: bundle.exportVersion ?? "—", color: .secondary)
                availabilityMetric(title: "App Version", value: bundle.appVersion ?? "—", color: .secondary)
                availabilityMetric(title: "Timezone", value: bundle.timeZoneIdentifier ?? "—", color: .secondary)
                availabilityMetric(
                    title: "UTC Offset",
                    value: bundle.localOffsetMinutes.map { "\($0)m" } ?? "—",
                    color: .secondary
                )
                availabilityMetric(
                    title: "Apple Health Export",
                    value: consentLabel(
                        enabled: bundle.consent?.appleHealthEnabled,
                        available: bundle.consent?.appleHealthAvailable,
                        authorizedOrConnected: bundle.consent?.appleHealthAuthorized
                    ),
                    color: .secondary
                )
                availabilityMetric(
                    title: "WHOOP Export",
                    value: consentLabel(
                        enabled: bundle.consent?.whoopEnabled,
                        available: true,
                        authorizedOrConnected: bundle.consent?.whoopConnected
                    ),
                    color: .secondary
                )
                availabilityMetric(
                    title: "Bundle Warnings",
                    value: "\(bundle.exportWarnings?.count ?? 0)",
                    color: (bundle.exportWarnings?.isEmpty ?? true) ? .green : .orange
                )
                availabilityMetric(
                    title: "Bundle Size",
                    value: bundle.importMetadata.map { ByteCountFormatter.string(fromByteCount: Int64($0.byteCount), countStyle: .file) } ?? "—",
                    color: .secondary
                )
            }

            if let exportWarnings = bundle.exportWarnings, !exportWarnings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Export Warnings")
                        .font(.headline)
                    ForEach(exportWarnings, id: \.self) { warning in
                        Text("• \(warning)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 8)
            }

            if let importMetadata = bundle.importMetadata {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bundle Fingerprint")
                        .font(.headline)
                    Text(importMetadata.sha256Hex)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Text("Imported \(importMetadata.importedAtUTC.formatted(date: .abbreviated, time: .shortened)) from \(importMetadata.fileName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
            }
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

    private var recommendationPreviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Timing Insight Package Preview")
                    .font(.headline)
                Spacer()
                Picker("Mode", selection: $recommendationMode) {
                    ForEach(InsightRecommendationMode.allCases) { item in
                        Text(item.displayTitle).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 240)
            }

            if sessions.isEmpty {
                Text("Import a DoseTap Studio bundle to enable recommendation package export.")
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    Text(recommendationPreview)
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

    private func consentLabel(enabled: Bool?, available: Bool?, authorizedOrConnected: Bool?) -> String {
        guard let enabled else { return "—" }
        guard enabled else { return "Disabled" }
        if let available, !available {
            return "Unavailable"
        }
        guard let authorizedOrConnected else { return "Enabled"
        }
        return authorizedOrConnected ? "Connected" : "Missing Access"
    }

    private func saveFile(suggestedName: String, content: String) {
        let fileData = Data(content.utf8)
        saveData(suggestedName: suggestedName, data: fileData)
    }

    private func saveData(suggestedName: String, data: Data) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = encryptSavedExports ? encryptedFileName(for: suggestedName) : suggestedName

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let payload: Data
                if encryptSavedExports {
                    guard let passphrase = requestPassphrase() else { return }
                    payload = try encryptionService.encrypt(
                        data: data,
                        fileName: suggestedName,
                        passphrase: passphrase
                    )
                } else {
                    payload = data
                }

                try payload.write(to: url)
                exportStatus = "Saved \(url.lastPathComponent)."
            } catch {
                exportStatus = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    private func encryptedFileName(for suggestedName: String) -> String {
        "\(suggestedName).dtenc"
    }

    private func requestPassphrase() -> String? {
        let alert = NSAlert()
        alert.messageText = "Encrypt Export"
        alert.informativeText = "Enter a passphrase to encrypt this export package. You will need the same passphrase to decrypt it later."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Encrypt")
        alert.addButton(withTitle: "Cancel")

        let passphraseField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        passphraseField.placeholderString = "Passphrase"
        let confirmField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        confirmField.placeholderString = "Confirm passphrase"

        let stack = NSStackView(views: [passphraseField, confirmField])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else {
            exportStatus = "Encrypted export cancelled."
            return nil
        }

        let passphrase = passphraseField.stringValue
        let confirmation = confirmField.stringValue

        guard passphrase.count >= 8 else {
            exportStatus = "Encryption requires a passphrase of at least 8 characters."
            return nil
        }

        guard passphrase == confirmation else {
            exportStatus = "Passphrase confirmation did not match."
            return nil
        }

        return passphrase
    }
}

#Preview {
    ExportView(dataStore: DataStore())
}
