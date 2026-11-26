import SwiftUI
import Charts
import DoseCore

struct ContextMorningOutcomesView: View {
    @ObservedObject var model: DashboardAnalyticsModel
    @Environment(\.dynamicTypeSize) private var typeSize
    private var metric: ContextMorningMetric { model.contextPresentation.metric }
    private var grouping: ContextMorningGrouping { model.contextPresentation.grouping }
    private var groupID: String? { model.contextPresentation.compatibleGroupID }
    @State private var candidates: [ContextOutcomeObservation] = []
    private var report: ContextOutcomeComparison { model.contextOutcomeReport(metric: metric, grouping: grouping) }
    private var selectedGroup: ContextOutcomeComparison.Group? { report.groups.first { $0.id == groupID } }
    private var visible: [ContextOutcomeObservation] { groupID == nil ? report.observations : selectedGroup?.observations ?? [] }
    private var eligible: [ContextOutcomeObservation] { visible.filter { report.exclusionReason($0) == nil } }
    private var selected: ContextOutcomeObservation? { visible.first { $0.id == model.inspection.selectedObservationID } }
    private var exportReport: ContextOutcomeComparison {
        .init(observations: visible, asOf: report.asOf, timeZoneID: report.timeZoneID,
              filterDescription: report.filterDescription + "; compatible_group=" + (groupID ?? "all individual observations")
                + "; selected_observation=" + (model.inspection.selectedObservationID ?? "none"),
              metric: report.metric, includePartial: report.includePartial)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("How do recorded outcomes differ across contexts?").font(.title2.bold())
                Text("Each mark is one treatment-session observation. Descriptive associations do not establish cause or identify a best dose.").font(.caption)
                focalChart
                controls
                Text("\(eligible.count) available / \(visible.count) observations; \(visible.count - eligible.count) excluded. \(report.unknownContextCount) unknown contexts in the selected range.").font(.callout)
                Text(model.rangeDescription + " · As of " + timestamp(model.reportingAsOf)).font(.caption)
                if let issue = model.inspectionFilterIssue { Text(issue).foregroundStyle(.orange) }
                if let error = model.errorMessage { Text("Refresh issue: " + error).foregroundStyle(.orange) }
                if let issue = model.inspection.selectionStatus(visibleIDs: visible.map(\.id), knownIDs: model.nights.map(\.id)).explanation {
                    Text(issue).font(.caption)
                }
                if groupID != nil && selectedGroup == nil { Text("The selected compatible group is no longer available under these filters. Choose a group or reset explicitly.").font(.caption) }
                navigation
                if let selected { detail(selected) }
                if !candidates.isEmpty {
                    Text("All observations in the tapped context — choose explicitly").font(.headline)
                    ForEach(candidates) { row in Button(row.treatmentDate + " · " + display(row) + " · " + row.id) { select(row) } }
                }
                DisclosureGroup("Exact observation table (\(visible.count))") {
                    ForEach(Array(visible.enumerated()), id: \.offset) { _, row in
                        Button { select(row) } label: {
                            VStack(alignment: .leading) {
                                if row.id == model.inspection.selectedObservationID { Label("Selected observation", systemImage: "checkmark.circle.fill") }
                                Text(row.treatmentDate + " · " + row.contextLabel)
                                Text(display(row)).font(.caption)
                                Text(row.id).font(.caption2)
                                Text(report.exclusionReason(row) ?? "Available").font(.caption)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                        }.background(row.id == model.inspection.selectedObservationID ? Color.accentColor.opacity(0.15) : Color.clear)
                            .accessibilityAddTraits(row.id == model.inspection.selectedObservationID ? .isSelected : [])
                            .accessibilityIdentifier("context-row-" + row.id)
                    }
                }
                DisclosureGroup("Separate chronological morning panels") {
                    Text("Treatment-date categories, not assessment timestamps. Points are individual saved answers; no lines or pooled estimates bridge unknown content versions.").font(.caption)
                    ForEach([ContextMorningMetric.quality, .grogginess, .recovery, .symptoms]) { value in
                        chronological(value)
                    }
                }
                DisclosureGroup("Recorded context changes") {
                    Text("Recorded label references are not verified prescriptions. Unknown change dates remain unplaced.").font(.caption)
                    ForEach(model.contextAnnotations) { annotation in
                        Text(annotation.title + " · " + (annotation.effectiveAt.map(timestamp) ?? "Effective time unknown") + " · " + annotation.detail).font(.caption)
                    }
                }
                ShareLink("Export exact comparison CSV", item: exportReport.csv).accessibilityIdentifier("context-export")
                    .disabled(model.inspectionFilterIssue != nil || (groupID != nil && selectedGroup == nil))
                Text("Export contains this outcome, compatible-group selection, filters, source, timezone, as-of, counts and derivation version. Separate chronological panels are exploratory; select their outcome above to export matching rows.").font(.caption)
            }.padding().padding(.bottom, 100)
        }.navigationTitle("Context & Morning Outcomes")
            .accessibilityIdentifier("context-morning-outcomes")
            .onChange(of: metric) { _ in model.contextPresentation.compatibleGroupID = nil; candidates = [] }
            .onChange(of: grouping) { _ in model.contextPresentation.compatibleGroupID = nil; candidates = [] }
            .onChange(of: model.reportingAsOf) { _ in candidates = [] }
            .onChange(of: model.sleepSource) { _ in candidates = [] }
    }
    private var controls: some View {
        VStack(alignment: .leading) {
            Picker("Outcome", selection: $model.contextPresentation.metric) { ForEach(ContextMorningMetric.allCases) { Text($0.rawValue).tag($0) } }
                .accessibilityIdentifier("context-outcome")
            Picker("Context", selection: $model.contextPresentation.grouping) { ForEach(ContextMorningGrouping.allCases) { Text($0.rawValue).tag($0) } }
                .accessibilityIdentifier("context-grouping")
            Picker("Compatible group", selection: $model.contextPresentation.compatibleGroupID) {
                Text("All individual observations").tag(nil as String?)
                ForEach(report.groups) { group in
                    Text(group.context + " · " + (group.observations.first?.compatibilityStratum == nil ? "Unknown version · " + group.observations[0].treatmentDate : "Compatible recorded period") + " · n=\(group.eligible.count)").tag(Optional(group.id))
                }
            }
            Toggle("Include partial or stale measurements", isOn: $model.inspection.includePartialMetrics)
            Button("Reset comparison filters") { model.inspection.resetFilters(); model.contextPresentation.compatibleGroupID = nil; candidates = [] }
            if grouping == .finalWakeMethod { Text("Final-wake method was not collected in this source; Dose 2 wake method is a separate question.").font(.caption) }
        }.pickerStyle(.menu)
    }
    private var focalChart: some View {
        VStack(alignment: .leading) {
            Text(metric.rawValue + " by " + grouping.rawValue.lowercased()).font(.headline)
            if eligible.isEmpty { Text("No available observations for this outcome and filter selection.") }
            else if metric.duration {
                Chart {
                    ForEach(eligible) { row in
                        if let value = row.value {
                            PointMark(x: .value("Context", row.contextLabel), y: .value("Minutes", value))
                                .symbol(.circle).foregroundStyle(.blue)
                                .symbolSize(row.id == model.inspection.selectedObservationID ? 110 : 35)
                                .annotation(position: .top) { if row.id == model.inspection.selectedObservationID { Text("Selected").font(.caption.bold()) } }
                                .accessibilityLabel((row.id == model.inspection.selectedObservationID ? "Selected, " : "") + row.treatmentDate + ", " + row.contextLabel + ", " + display(row))
                        }
                    }
                    if let group = selectedGroup, let median = group.summary.median,
                       let low = group.summary.lowerQuartile, let high = group.summary.upperQuartile {
                        RuleMark(x: .value("Context", group.context), yStart: .value("25th percentile", low), yEnd: .value("75th percentile", high)).lineStyle(.init(lineWidth: 6)).foregroundStyle(.gray.opacity(0.5))
                        PointMark(x: .value("Context", group.context), y: .value("Median", median)).symbol(.diamond).symbolSize(90).foregroundStyle(Color.primary)
                    }
                }.frame(height: 250).chartYAxisLabel("Minutes").chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle()).onTapGesture { location in
                            let x = location.x - geometry[proxy.plotAreaFrame].origin.x
                            if let context: String = proxy.value(atX: x) { candidates = eligible.filter { $0.contextLabel == context } }
                        }
                    }
                }
                Text("Circles: individual observations; the selected circle is enlarged and labeled. Tap a context to list all its candidates. Select a compatible group to show its diamond median and gray middle-50% spread. Unknown-version observations are never pooled.").font(.caption)
            } else if let group = selectedGroup {
                Chart(group.categoryCounts.keys.sorted(), id: \.self) { category in
                    BarMark(x: .value("Answer", category), y: .value("Recorded count", group.categoryCounts[category] ?? 0))
                }.frame(height: 220).chartYAxisLabel("Recorded answers")
            } else {
                Text("Choose a compatible group for category counts. The exact table retains each original answer across incompatible or unknown versions.")
            }
        }
    }
    private var navigation: some View {
        Group {
            if typeSize.isAccessibilitySize { VStack(alignment: .leading) { navigationButtons } }
            else { HStack { navigationButtons } }
        }.buttonStyle(.bordered)
    }
    @ViewBuilder private var navigationButtons: some View {
            Button("Previous observation") { move(-1) }.disabled(visible.isEmpty || selected?.id == visible.first?.id)
            Button("Next observation") { move(1) }.disabled(visible.isEmpty || selected?.id == visible.last?.id)
    }
    private func select(_ row: ContextOutcomeObservation) { model.inspection.selectedObservationID = row.id; candidates = [] }
    private func move(_ offset: Int) {
        guard !visible.isEmpty else { return }
        let index = visible.firstIndex { $0.id == model.inspection.selectedObservationID }
        let next = index.map { min(max($0 + offset, 0), visible.count - 1) } ?? (offset > 0 ? 0 : visible.count - 1)
        select(visible[next])
    }
    private func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = model.reportingTimeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss XXX"
        return formatter.string(from: date)
    }
    private func display(_ row: ContextOutcomeObservation) -> String {
        row.value.map { $0.formatted(.number.precision(.fractionLength(0...2))) + " " + row.unit } ?? row.category ?? "Unavailable"
    }
    private func detail(_ row: ContextOutcomeObservation) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Selected: " + row.treatmentDate).font(.headline)
            Text(row.contextLabel + " · " + display(row))
            Text(row.source)
            Text(row.state.rawValue + " · " + row.reason.replacingOccurrences(of: "_", with: " "))
            Text(row.relationship)
            Text(row.occurredAt.map { "Occurrence: " + timestamp($0) } ?? "Assessment/occurrence time not collected; treatment date is a grouping label.")
            Text(row.compatibilityStratum == nil ? "Compatibility unknown; observations remain separate." : "Documented comparison period; only compatible observations are summarized.")
            DisclosureGroup("Source record identifiers") {
                Text("Observation: " + row.id + "; session: " + row.sessionID)
                Text("Compatibility: " + row.stratumLabel)
            }
        }.font(.caption).accessibilityIdentifier("context-selected-detail")
    }
    private func chronological(_ metric: ContextMorningMetric) -> some View {
        let report = model.contextOutcomeReport(metric: metric, grouping: grouping)
        return VStack(alignment: .leading) {
            Text(metric.rawValue).font(.headline)
            Chart(report.observations.filter { $0.category != nil && $0.state == .needsReview && !$0.sessionID.isEmpty }) { row in
                PointMark(x: .value("Treatment date", row.treatmentDate), y: .value("Original answer", row.category ?? "Unavailable"))
                    .symbol(.square).foregroundStyle(.orange)
                    .symbolSize(row.id == model.inspection.selectedObservationID ? 110 : 35)
                    .annotation(position: .top) { if row.id == model.inspection.selectedObservationID { Text("Selected").font(.caption.bold()) } }
                    .accessibilityLabel((row.id == model.inspection.selectedObservationID ? "Selected, " : "") + "Unconfirmed saved answer, " + row.treatmentDate + ", " + display(row))
            }.frame(height: 180)
            Text("Squares show raw saved answers needing review, including possible defaults. They are excluded from confirmed category counts; saved No is not confirmed absence. \(report.excludedCount) excluded from comparison summaries.").font(.caption)
        }
    }
}
