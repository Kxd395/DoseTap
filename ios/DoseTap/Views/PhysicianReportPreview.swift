import SwiftUI
import DoseCore

struct PhysicianReportPreview: View {
    let snapshot: PhysicianReportSnapshot
    @Environment(\.dismiss) private var dismiss
    @State private var recentDays = 28
    @State private var share: PhysicianShareFiles?
    @State private var shareDirectory: URL?
    @State private var failure: String?
    var body: some View {
        NavigationStack {
            List {
                Section("Captured report") {
                    Text(snapshot.period.label)
                    Text("\(date(snapshot.period.start)) – \(date(snapshot.period.endExclusive)) (end exclusive)")
                    Text("Timezone: \(snapshot.period.timeZoneIdentifier)")
                    Text("\(snapshot.period.calendarDayCount) calendar days; captured \(date(snapshot.generatedAt))")
                    Text(snapshot.coverageDescription).font(.caption)
                    Text(snapshot.includePartialMetrics == true ? "Partial values included by explicit selection." : "Partial values excluded from numeric summaries.").font(.caption)
                    Text("Not a diagnosis, treatment recommendation or clinical scale score.").font(.caption)
                }
                Section("Full-period overview") {
                    if snapshot.summaries.isEmpty { Text("No numeric metric summaries available. Missing information is not zero.") }
                    ForEach(snapshot.summaries) { summary in summaryRow(summary) }
                }
                ForEach(snapshot.contexts ?? []) { context in
                    Section(context.title) {
                        ForEach(Array(context.lines.enumerated()), id: \.offset) { _, line in Text(line) }
                        Text("\(context.source) • \(context.definitionVersion)").font(.caption)
                    }
                }
                Section("Monthly detail") {
                    ForEach(snapshot.monthlyCoverage) { coverage in
                        Text(coverage.description).font(.headline)
                        ForEach(snapshot.monthlySummaries.filter { $0.month == coverage.month }) { summary in summaryRow(summary) }
                    }
                }
                Section("Recent detail alongside the full period") {
                    Picker("Recent detail", selection: $recentDays) { Text("14 days").tag(14); Text("28 days").tag(28) }
                    ForEach(snapshot.recentDetail(days: recentDays).filter { $0.detailOnly != true }) { value in observationRow(value) }
                }
                Section("Reviewed visit notes and questions") {
                    ForEach(snapshot.notes) { note in
                        VStack(alignment: .leading) {
                            Text(note.activity).font(.headline)
                            Text(note.opportunity.label)
                            Text(note.comment)
                            Text("Examples: \(note.evidenceIDs.joined(separator: ", "))").font(.caption)
                            Text("Reviewed \(date(note.reviewedAt))").font(.caption)
                        }
                    }
                    ForEach(Array(snapshot.questions.enumerated()), id: \.offset) { _, question in Text(question) }
                }
                Section("All selected source detail") {
                    Text("Includes excluded, ambiguous and serious reported information. Unknown-time records remain unplaced and may fall outside this period.").font(.caption)
                    ForEach(snapshot.observations) { value in observationRow(value) }
                }
                Section("Snapshot provenance") {
                    Text("Snapshot \(snapshot.id.uuidString)").textSelection(.enabled)
                    Text("\(snapshot.version); \(snapshot.period.version); DoseTap \(snapshot.appVersion)").font(.caption)
                    Text("Later corrections require a new preview. JSON retains this captured report; CSV contains the same source detail.").font(.caption)
                }
            }.navigationTitle("Report preview")
                .accessibilityIdentifier("physician-report-preview")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) { Button("Share", action: prepareShare).accessibilityIdentifier("physician-share-report") }
                }
                .sheet(item: $share, onDismiss: cleanShare) { ActivityViewController(activityItems: $0.urls) }
                .alert("Report could not be shared", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                    Button("OK") { failure = nil }
                } message: { Text(failure ?? "") }
        }
    }
    private func date(_ value: Date) -> String {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: snapshot.period.timeZoneIdentifier)
        return formatter.string(from: value)
    }
    private func summaryRow(_ value: PhysicianMetricSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text([value.month, value.metricID].compactMap { $0 }.joined(separator: " • ")).font(.headline)
            if let label = value.comparisonLabel { Text(label).font(.subheadline) }
            Text("Median \(value.median.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "unavailable") \(value.unit)")
            if let lower = value.lowerQuartile, let upper = value.upperQuartile { Text("Middle 50%: \(lower.formatted())–\(upper.formatted()) \(value.unit)") }
            Text("\(value.availableCount)/\(value.eligibleCount) eligible observations available; \(value.assessedDays)/\(value.calendarDayCount) calendar days represented; \(value.availableDays) days with values")
            Text("\(value.numericContributionCount) numeric contributions, including \(value.includedPartialCount ?? 0) partial.").font(.caption)
            Text("Partial \(value.partialCount) • unavailable \(value.unavailableCount) • review \(value.reviewCount) • not applicable \(value.notApplicableCount) • not collected \(value.notCollectedCount) • unplaced \(value.unplacedCount)").font(.caption)
            Text("\(value.source) • \(value.definitionVersion)").font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
    private func observationRow(_ value: PhysicianReportObservation) -> some View {
        DisclosureGroup {
            Text(value.detail)
            Text("Source records: \(value.recordIDs.joined(separator: ", "))").font(.caption)
            Text("\(value.source) • \(value.definitionVersion)").font(.caption)
        } label: {
            VStack(alignment: .leading) {
                Text(value.metricID)
                Text("\(value.observedAt.map(date) ?? "Unknown occurrence time") • \(value.state.label)").font(.caption)
                if let amount = value.value { Text("\(amount.formatted()) \(value.unit)") }
                if value.requiresReview { Label("Retained for review", systemImage: "exclamationmark.triangle") }
            }
        }
    }
    private func prepareShare() {
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PhysicianReview-\(UUID().uuidString)", isDirectory: true)
            shareDirectory = directory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
            let json = directory.appendingPathComponent("DoseTap-physician-review.json"), csv = directory.appendingPathComponent("DoseTap-physician-detail.csv")
            try snapshot.jsonData().write(to: json, options: [.atomic, .completeFileProtection])
            try Data(snapshot.detailCSV.utf8).write(to: csv, options: [.atomic, .completeFileProtection])
            let pdf = directory.appendingPathComponent("DoseTap-physician-review.pdf")
            try PhysicianReportPDF.render(snapshot).write(to: pdf, options: [.atomic, .completeFileProtection])
            let summary = directory.appendingPathComponent("DoseTap-physician-summary.csv")
            try Data(snapshot.summaryCSV.utf8).write(to: summary, options: [.atomic, .completeFileProtection])
            share = PhysicianShareFiles(urls: [pdf, json, summary, csv])
        } catch { cleanShare(); failure = "The export files could not be prepared. Your saved preview is unchanged; retry sharing." }
    }
    private func cleanShare() {
        if let directory = shareDirectory { try? FileManager.default.removeItem(at: directory) }
        shareDirectory = nil
    }
}

private struct PhysicianShareFiles: Identifiable {
    let id = UUID()
    let urls: [URL]
}
