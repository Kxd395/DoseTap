import SwiftUI
import UniformTypeIdentifiers
import UIKit
import DoseCore

/// Read-only review of one immutable received source. The parent owns scrolling.
struct CompanionPhysicianView: View {
    let snapshot: CloudDashboardSnapshot
    let report: DashboardCompanionProjection
    let nights: [DashboardCompanionProjection.Night]
    let period: PhysicianReportPeriod?
    let inspection: DashboardInspectionState
    let filterDescription: String
    @State private var captured: DashboardCompanionPhysicianReport?
    @State private var recentDays = 28
    @State private var document = CompanionReportDocument()
    @State private var exporting = false
    @State private var filename = "DoseTap-physician-review"
    @State private var failure: String?

    init(snapshot: CloudDashboardSnapshot, report: DashboardCompanionProjection,
         nights: [DashboardCompanionProjection.Night], period: PhysicianReportPeriod?,
         inspection: DashboardInspectionState, filterDescription: String) {
        self.snapshot = snapshot; self.report = report; self.nights = nights; self.period = period
        self.inspection = inspection; self.filterDescription = filterDescription
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Physician review").font(.title2.bold())
            Text("Review timing and reported experience with your clinician. This report does not calculate a clinical scale score or recommend treatment.")
            if period == nil {
                Text("Report period unavailable. Choose a valid report range; a completed visit is required for Since completed visit.")
            }
            Button(captured == nil ? "Prepare captured report" : "Prepare new captured report", action: prepare)
                .disabled(period == nil)
                .accessibilityIdentifier("companion-physician-prepare")
            if let captured {
                if !captured.matches(snapshot: snapshot, nights: nights, period: period, inspection: inspection, filterDescription: filterDescription) {
                    Label("The source or inspection settings changed. This preview and its exports retain the earlier capture. Prepare a new report to use the current selection.", systemImage: "clock.arrow.circlepath")
                }
                preview(captured.preview)
            } else {
                Text("Preparation freezes the received source, selected nights, period and shared filters. No report is sent automatically.").foregroundStyle(.secondary)
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: document.contentType, defaultFilename: filename) { result in
            if case .failure = result { failure = "The report could not be saved. The captured preview is retained; retry the export." }
        }
        .alert("Report unavailable", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") { failure = nil }
        } message: { Text(failure ?? "") }
        .accessibilityIdentifier("companion-physician-review")
    }

    private func preview(_ value: PhysicianReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(value.period.label).font(.headline)
            Text("\(date(value.period.start, value)) – \(date(value.period.endExclusive, value)) (end exclusive)")
            Text("\(value.period.timeZoneIdentifier) • \(value.period.calendarDayCount) calendar days")
            Text(value.coverageDescription).font(.caption)
            Text(value.includePartialMetrics == true ? "Finite, dated partial measurements included by explicit selection." : "Partial measurements excluded from numeric summaries.").font(.caption)
            Menu("Export captured report") {
                Button("JSON with provenance") { export(value, kind: .json) }
                Button("Full and monthly summary CSV") { export(value, kind: .summary) }
                Button("All source detail CSV") { export(value, kind: .detail) }
                Button("Printable review text") { export(value, kind: .text) }
                Button("Print captured review") { printReview(value) }
            }.accessibilityIdentifier("companion-physician-export")
            Divider()
            Text("Full-period overview").font(.headline)
            if value.summaries.isEmpty { Text("No eligible metric summaries. Missing observations are not zero.") }
            ForEach(value.summaries) { summary($0) }
            ForEach(value.contexts ?? []) { context in
                DisclosureGroup(context.title) {
                    ForEach(Array(context.lines.enumerated()), id: \.offset) { _, line in Text(line).textSelection(.enabled) }
                    Text("\(context.source) • \(context.definitionVersion)").font(.caption)
                    Text("Records: \(context.recordIDs.joined(separator: ", "))").font(.caption)
                }
            }
            DisclosureGroup("Every calendar month") {
                ForEach(value.monthlyCoverage) { month in
                    Text(month.description).font(.headline)
                    ForEach(value.monthlySummaries.filter { $0.month == month.month }) { summary($0) }
                }
            }
            DisclosureGroup("Recent detail alongside the full period") {
                Picker("Recent detail", selection: $recentDays) { Text("14 days").tag(14); Text("28 days").tag(28) }.pickerStyle(.segmented)
                let recent = value.recentDetail(days: recentDays)
                if recent.isEmpty { Text("No dated observations in this recent interval.") }
                ForEach(recent) { observation($0, value) }
            }
            DisclosureGroup("All selected source detail and review appendix") {
                Text("Unknown occurrence times remain unplaced and may fall outside the report period. Serious and ambiguous reports remain visible.").font(.caption)
                ForEach(value.observations) { observation($0, value) }
            }
            Text("Captured \(date(value.generatedAt, value)) • \(value.id.uuidString)").font(.caption).textSelection(.enabled)
            Text("\(value.version) • \(value.period.version) • app \(value.appVersion)").font(.caption)
        }
    }
    private func summary(_ value: PhysicianMetricSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metricTitle(value.metricID)).font(.subheadline.bold())
            if let label = value.comparisonLabel { Text(label).font(.caption) }
            Text("Median \(value.median.map { $0.formatted() } ?? "unavailable") \(value.unit)")
            if let lower = value.lowerQuartile, let upper = value.upperQuartile { Text("Middle 50%: \(lower.formatted())–\(upper.formatted()) \(value.unit)") }
            Text("\(value.availableCount)/\(value.eligibleCount) available; \(value.assessedDays)/\(value.calendarDayCount) calendar days represented; \(value.availableDays) days with values").font(.caption)
            Text("\(value.numericContributionCount) numeric contributions; \(value.includedPartialCount ?? 0) partial included. Partial \(value.partialCount), unavailable \(value.unavailableCount), review \(value.reviewCount), not applicable \(value.notApplicableCount), not collected \(value.notCollectedCount), unplaced \(value.unplacedCount).").font(.caption)
            Text("\(value.source) • \(value.definitionVersion)").font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
    private func observation(_ value: PhysicianReportObservation, _ report: PhysicianReportSnapshot) -> some View {
        DisclosureGroup {
            Text(value.detail).textSelection(.enabled)
            Text("Records: \(value.recordIDs.joined(separator: ", "))").font(.caption)
            Text("\(value.source) • \(value.definitionVersion)").font(.caption)
        } label: {
            VStack(alignment: .leading) {
                Text(metricTitle(value.metricID))
                Text("\(value.observedAt.map { date($0, report) } ?? "Unknown occurrence time") • \(value.state.label)").font(.caption)
                if let amount = value.value { Text("\(amount.formatted()) \(value.unit)") }
                if value.requiresReview { Label("Retained for review", systemImage: "exclamationmark.triangle") }
            }
        }
    }
    private func prepare() {
        do {
            let info = Bundle.main.infoDictionary ?? [:]
            captured = try .init(snapshot: snapshot, report: report, nights: nights, period: period, inspection: inspection,
                filterDescription: filterDescription, appVersion: "\(info["CFBundleShortVersionString"] ?? "unknown") (\(info["CFBundleVersion"] ?? "unknown"))")
        } catch { failure = error.localizedDescription }
    }
    private enum ExportKind { case json, summary, detail, text }
    private func export(_ value: PhysicianReportSnapshot, kind: ExportKind) {
        do {
            try value.validate()
            switch kind {
            case .json: document = .init(data: try value.jsonData(), contentType: .json); filename = "DoseTap-physician-review.json"
            case .summary: document = .init(data: Data(value.summaryCSV.utf8)); filename = "DoseTap-physician-summary.csv"
            case .detail: document = .init(data: Data(value.detailCSV.utf8)); filename = "DoseTap-physician-detail.csv"
            case .text: document = .init(data: Data(value.reviewText.utf8), contentType: .plainText); filename = "DoseTap-physician-review.txt"
            }
            exporting = true
        } catch { failure = "The captured report failed validation. Prepare a new report before exporting." }
    }
    static func printFormatter(for value: PhysicianReportSnapshot) throws -> UISimpleTextPrintFormatter {
        try value.validate()
        let formatter = UISimpleTextPrintFormatter(text: value.reviewText)
        formatter.font = .systemFont(ofSize: 11)
        formatter.perPageContentInsets = UIEdgeInsets(top: 36, left: 36, bottom: 36, right: 36)
        return formatter
    }
    private func printReview(_ value: PhysicianReportSnapshot) {
        do {
            let formatter = try Self.printFormatter(for: value)
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
                  let view = scene.windows.first(where: \.isKeyWindow)?.rootViewController?.view else {
                failure = "The print preview cannot open without an active window. Retry when the app is visible."; return
            }
            let printer = UIPrintInteractionController.shared
            let info = UIPrintInfo(dictionary: nil); info.jobName = "DoseTap physician review"; info.outputType = .general
            printer.printInfo = info; printer.printFormatter = formatter
            let opened = printer.present(from: CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1), in: view, animated: true) { controller, _, error in
                controller.printFormatter = nil; controller.printInfo = nil
                if error != nil { failure = "The print operation failed. The captured report is retained." }
            }
            if !opened {
                printer.printFormatter = nil; printer.printInfo = nil
                failure = "The print preview could not open. Retry when the app is visible."
            }
        } catch { failure = "The report failed validation. Prepare a new report before printing." }
    }
    private func metricTitle(_ id: String) -> String {
        let names = ["dose.interval": "Actual interval between doses", "dose.reported-count": "Confirmed reported dose count",
            "sleep.mainProviderEpisode": "Main provider episode sleep", "sleep.observedAfterDose2": "Observed sleep after Dose 2",
            "night.outcome.source": "Reported night outcome", "dosetap.custom-current-sleepiness": "Current sleepiness — custom diary",
            "nap.patient-estimated-sleep": "Patient-estimated nap sleep"]
        if id.hasPrefix("daytime.event.") { return "Reported daytime event: " + id.dropFirst("daytime.event.".count) }
        return names[id] ?? id
    }
    private func date(_ value: Date, _ report: PhysicianReportSnapshot) -> String {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: report.period.timeZoneIdentifier)
        return formatter.string(from: value)
    }
}
