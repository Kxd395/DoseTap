import SwiftUI
import Charts
import DoseCore

struct CompanionSleepPatterns: View {
    let report: DashboardCompanionProjection
    let nights: [DashboardCompanionProjection.Night]
    @Binding var inspection: DashboardInspectionState
    @State private var definition: DashboardSleepMetricProjection.Definition = .mainProviderEpisode
    @State private var mode = "By date"
    @Environment(\.dynamicTypeSize) private var typeSize
    private var chartHeight: CGFloat { typeSize.isAccessibilitySize ? 520 : 280 }
    private let modes = ["By date", "Dose pattern", "Paired interval"]
    private var rows: [SleepRow] {
        let context = try? report.contextTimeline()
        return nights.map { night in
            SleepRow(night: night, metric: report.sleepMetric(for: night, definition: definition),
                     context: report.contextStratum(for: night, timeline: context))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Sleep & dose pattern").font(.title2.bold()).accessibilityIdentifier("companion-sleep-patterns")
            Text("Apple Health primary episodes retain their source and exact match to a local session. Provider-only episodes remain independent observations. WHOOP evidence is unavailable in this reporting copy.")
                .font(.footnote)
            Picker("Sleep definition", selection: $definition) {
                Text("Main provider episode").tag(DashboardSleepMetricProjection.Definition.mainProviderEpisode)
                Text("Observed after Dose 2").tag(DashboardSleepMetricProjection.Definition.observedAfterDose2)
            }.pickerStyle(.menu).accessibilityIdentifier("companion-sleep-definition")
            Picker("Plot", selection: $mode) { ForEach(modes, id: \.self) { Text($0).tag($0) } }
                .pickerStyle(.menu).accessibilityIdentifier("companion-sleep-mode")
            Toggle("Include partial values in summaries", isOn: $inspection.includePartialMetrics)
            Text("\(rows.count) observations · \(rows.filter { $0.metric.metric.value != nil }.count) with a plotted value · \(rows.filter { $0.metric.metric.value == nil }.count) unavailable or not applicable")
                .font(.caption)
            if mode == "By date" { dateChart }
            else if mode == "Dose pattern" { categoryChart(rows) }
            else {
                Chart(rows.filter { $0.night.pattern.interval.value != nil && $0.metric.metric.value != nil }) { row in
                    PointMark(x: .value("Dose interval, minutes", row.night.pattern.interval.value!),
                              y: .value("Observed sleep, minutes", row.metric.metric.value!))
                        .foregroundStyle(.teal)
                        .symbol(by: .value("Reported count", row.symbol))
                }.chartSymbolScale(["Two": BasicChartSymbolShape.circle, "One": .square, "Zero": .triangle, "Unresolved": .diamond]).chartLegend(.hidden).frame(height: chartHeight)
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: typeSize.isAccessibilitySize ? 3 : 5)) }.chartYAxisLabel("Sleep (minutes)").chartXAxisLabel("Paired elapsed interval (minutes)").chartYScale(domain: 0...max(60, (rows.compactMap { $0.metric.metric.value }.max() ?? 60) * 1.1))
                Text("Unpaired observations — categorical companion, same sleep scale").font(.headline)
                categoryChart(rows.filter { $0.night.pattern.interval.value == nil })
            }
            Text("Circle: two reported · Square: one reported · Triangle: confirmed zero · Diamond: unresolved. Missing values are never plotted at zero. Counts are descriptive, not medication instructions.").font(.caption)
            comparisonRows
            Text("Exact observations").font(.headline)
            ForEach(rows) { row in
                Button { inspection.selectedObservationID = row.id } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(row.night.treatmentDate) · \(row.night.pattern.pattern.label)").bold()
                        Text("\(number(row.metric.metric.value)) minutes · \(row.metric.metric.state.rawValue) · \(row.metric.metric.reason)")
                        Text("Boundary: \(row.metric.boundaryBasis.rawValue) · Covered \(number(row.metric.coveredMinutes)) / \(number(row.metric.intervalMinutes)) min · Unmeasured \(number(row.metric.unmeasuredMinutes)) min")
                        Text("\(row.context.label) · \(row.id)").font(.caption)
                        if let episode = report.episode(for: row.night) {
                            Text("\(episode.source) · Query through \(episode.queryEnd.formatted()) · \(episode.derivationVersion ?? "Definition unavailable")").font(.caption)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(inspection.selectedObservationID == row.id ? Color.teal.opacity(0.15) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).accessibilityIdentifier("companion-observation-\(row.id)")
            }
            if rows.isEmpty { Text("No observations match the current range and filters. Missing records do not establish no sleep or no dose.") }
        }
    }
    private var dateChart: some View {
        Chart(rows.filter { $0.metric.metric.value != nil }) { row in
            PointMark(x: .value("Treatment date", row.night.treatmentDate), y: .value("Sleep minutes", row.metric.metric.value!))
                .symbol(by: .value("Reported count", row.symbol))
                .foregroundStyle(.teal)
        }.chartSymbolScale(["Two": BasicChartSymbolShape.circle, "One": .square, "Zero": .triangle, "Unresolved": .diamond]).chartLegend(.hidden).frame(height: chartHeight)
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: typeSize.isAccessibilitySize ? 3 : 5)) }.chartYAxisLabel("Sleep (minutes)").chartXAxisLabel("Treatment date; exact records below")
    }
    private func categoryChart(_ input: [SleepRow]) -> some View {
        Chart(input.filter { $0.metric.metric.value != nil }) { row in
            PointMark(x: .value("Dose pattern", row.night.pattern.pattern.label), y: .value("Sleep minutes", row.metric.metric.value!))
                .symbol(by: .value("Reported count", row.symbol))
                .foregroundStyle(.teal)
        }.chartSymbolScale(["Two": BasicChartSymbolShape.circle, "One": .square, "Zero": .triangle, "Unresolved": .diamond]).chartLegend(.hidden).frame(height: chartHeight)
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: typeSize.isAccessibilitySize ? 3 : 5)) }.chartYScale(domain: 0...max(60, (rows.compactMap { $0.metric.metric.value }.max() ?? 60) * 1.1))
            .chartYAxisLabel("Sleep (minutes)")
    }
    private var comparisonRows: some View {
        let groups = Dictionary(grouping: rows) { "\($0.night.pattern.pattern.rawValue)|\($0.metric.boundaryBasis.rawValue)|\($0.context.id)" }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Compatible comparisons").font(.headline)
            ForEach(groups.keys.sorted(), id: \.self) { key in
                if let group = groups[key], let first = group.first {
                    let values = group.compactMap { $0.metric.summaryValue(includePartial: inspection.includePartialMetrics) }.sorted()
                    Text("\(first.night.pattern.pattern.label) · \(first.context.label) · \(first.metric.boundaryBasis.rawValue): n=\(values.count), excluded=\(group.count - values.count), median \(number(quantile(values, 0.5))), middle 50% \(number(quantile(values, 0.25)))–\(number(quantile(values, 0.75))) min")
                        .font(.caption)
                }
            }
        }
    }
    private struct SleepRow: Identifiable {
        let night: DashboardCompanionProjection.Night
        let metric: DashboardSleepMetricProjection
        let context: DashboardContextStratum
        var id: String { night.id }
        var symbol: String {
            switch night.pattern.pattern {
            case .twoReported: return "Two"
            case .singlePlanned, .singleOmitted, .singleUnknownPlan: return "One"
            case .noneReported: return "Zero"
            case .incomplete, .needsReview, .inProgress: return "Unresolved"
            }
        }
    }
    private func number(_ value: Double?) -> String { value.map { String(format: "%.1f", $0) } ?? "—" }
    private func quantile(_ values: [Double], _ fraction: Double) -> Double? {
        guard !values.isEmpty, fraction == 0.5 || values.count >= 2 else { return nil }
        let index = Double(values.count - 1) * fraction, lower = Int(index), upper = min(Int(index) + 1, values.count - 1)
        return values[lower] + (values[upper] - values[lower]) * (index - Double(lower))
    }
}
