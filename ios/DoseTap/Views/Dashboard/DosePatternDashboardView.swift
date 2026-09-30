import SwiftUI
import Charts
import DoseCore

/// Each mark is one exact observation. Provider, endpoint and reference strata remain explicit.
struct DosePatternDashboardView: View {
    @ObservedObject var model: DashboardAnalyticsModel
    @State private var mode = DosePatternDisplayMode.byDate
    @State private var outcome = DosePatternSleepOutcome.mainSleep
    @State private var candidates: Set<String> = []
    @State private var expandedTables: Set<String> = []
    @State private var detailPresented = false
    @Environment(\.horizontalSizeClass) private var width
    @Environment(\.dynamicTypeSize) private var typeSize

    private struct Sample: Identifiable {
        let night: DashboardNightAggregate
        let sleep: DashboardSleepMetricProjection
        let context: DashboardContextStratum
        var id: String { night.id }
        var value: Double? { sleep.metric.value }
        var pair: Double? { night.dosePattern.interval.state == .available ? night.dosePattern.interval.value : nil }
        var key: String {
            DosePatternPresentation.comparisonKey(pattern: night.dosePattern.pattern, context: context,
                projection: sleep)
        }
    }
    private var freshness: DashboardSleepMetricProjection.Freshness {
        model.providerSnapshotIsCurrent(model.sleepSource == .appleHealth ? .health : .whoop) ? .current : .stale
    }
    private var rows: [DashboardNightAggregate] {
        model.visibleInspectionNights.sorted {
            $0.sessionDate == $1.sessionDate ? $0.id < $1.id : $0.sessionDate < $1.sessionDate
        }
    }
    private var samples: [Sample] {
        rows.map { .init(night: $0,
            sleep: DosePatternPresentation.sleepProjection($0, source: model.sleepSource, outcome: outcome, freshness: freshness),
            context: model.contextReadReady ? $0.contextStratum(for: model.sleepSource) : .unknown(observationID: $0.id)) }
    }
    private var measured: [Sample] { samples.filter { $0.value != nil } }
    private var sleepMaximum: Double { max(60, (measured.compactMap(\.value).max() ?? 0) * 1.1) }
    private var basisGroups: [[Sample]] {
        Dictionary(grouping: samples, by: { $0.sleep.boundaryBasis.rawValue }).sorted { $0.key < $1.key }.map(\.value)
    }
    private var comparisonGroups: [[Sample]] {
        Dictionary(grouping: samples.filter { model.contextReadReady && $0.context.status == .documentedReference }, by: \.key)
            .sorted { $0.key < $1.key }.map(\.value)
    }
    private var partialCount: Int { measured.filter { $0.sleep.metric.state == .partial }.count }
    private var workCurrent: Bool { model.workContextReadReady && model.workInspectionAsOf == model.reportingAsOf }
    private var periodAnnotations: [DashboardContextAnnotation] {
        guard model.contextReadReady, let timeline = model.contextTimeline, let window = model.currentReportWindow else { return [] }
        if let period = window.reviewedPeriod {
            return timeline.annotations(from: period.start, to: period.endExclusive, includeBaseline: true)
        }
        guard let start = window.start else { return model.contextAnnotations }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = model.reportingTimeZone
        guard let lower = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: start),
              let upper = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: window.endExclusive) else { return [] }
        return timeline.annotations(from: lower, to: min(upper, model.reportingAsOf), includeBaseline: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sleep & Dose Pattern").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Text("One mark is one resolved session or provider episode. Multiple observations on the same date remain separate.")
                .font(.callout).foregroundStyle(.secondary)
            controls
            Text(definition).font(.caption).foregroundStyle(.secondary)
            Text(model.sleepSource == .appleHealth ? model.healthQueryDescription : model.whoopQueryDescription)
                .font(.caption).foregroundStyle(.secondary)
            Text("\(measured.count)/\(rows.count) observations have a numeric sleep value; \(partialCount) are partial. Missing sleep is retained in the tables and is never plotted at zero.")
                .accessibilityIdentifier("dose-pattern-coverage")
            if let issue = model.inspectionFilterIssue { Text(issue).foregroundStyle(.orange) }
            if let issue = model.workContextIssue { Text(issue).foregroundStyle(.orange) }
            if !model.contextReadReady {
                Text("Reference context is not fully read. Values remain inspectable; comparisons cannot pool observations until context is available.")
                    .foregroundStyle(.orange)
            }
            if let explanation = model.inspection.selectionStatus(visibleIDs: rows.map(\.id), knownIDs: model.nights.map(\.id)).explanation {
                Text(explanation).accessibilityIdentifier("dose-pattern-selection-status")
                Button("Inspect retained selection") { detailPresented = true }
            }
            if rows.isEmpty { Text("No observations match the current period and filters. Reset filters or choose a wider period.") }
            else {
                switch mode {
                case .byDate: byDateCharts
                case .compare: comparisonCharts
                case .paired: pairedCharts
                }
                if !candidates.isEmpty {
                    exactTable(rows.filter { candidates.contains($0.id) }, title: "Choose an observation; overlapping marks remain distinct", expanded: true)
                }
                workStrip
                annotations
                exactTable(rows, title: "All observations and exact values")
            }
            HStack {
                Button("Reset filters") { model.inspection.resetFilters(); candidates = [] }
                Button("Clear selection") { model.inspection.selectedObservationID = nil; candidates = []; detailPresented = false }
            }
            if let csv = DosePatternPresentation.csv(model: model, outcome: outcome) {
                ShareLink("Share exact filtered rows as CSV", item: csv).accessibilityIdentifier("dose-pattern-export")
            } else { Text("Export becomes available after a complete local refresh with valid filters.").font(.caption) }
            Text("Descriptive observations, not dosing recommendations. Patient-entered reference labels are not verified prescriptions. Actual amounts, historical plans, and reported outcomes remain separate.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $detailPresented) {
            DosePatternDetailSheet(model: model, observationID: model.inspection.selectedObservationID,
                navigationIDs: rows.map(\.id), select: { model.inspection.selectedObservationID = $0 }, outcome: outcome)
        }
        .onChange(of: mode) { _ in candidates = [] }
        .onChange(of: model.sleepSource) { _ in candidates = [] }
        .onChange(of: outcome) { _ in candidates = [] }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if typeSize.isAccessibilitySize { modePicker.pickerStyle(.menu); sourcePicker.pickerStyle(.menu) }
            else { modePicker.pickerStyle(.segmented); sourcePicker.pickerStyle(.segmented) }
            Picker("Sleep measure", selection: $outcome) {
                ForEach(DosePatternSleepOutcome.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Dose pattern", selection: $model.inspection.dosePatternFilter) {
                Text("All patterns").tag(DashboardDosePattern.Pattern?.none)
                ForEach(DashboardDosePattern.Pattern.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
            }
            Picker("Work phase", selection: $model.inspection.workPhaseFilter) {
                Text("All phases").tag(WorkPhase?.none)
                ForEach(WorkPhase.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
            }
            Picker("Work context", selection: $model.inspection.workContextBasis) {
                ForEach(WorkContextBasis.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            if model.inspection.contextStratumID != nil {
                Button("Clear selected reference context") { model.inspection.contextStratumID = nil }
            }
            Toggle("Include partial values in numerical summaries", isOn: $model.inspection.includePartialMetrics)
                .accessibilityIdentifier("dose-pattern-include-partial")
            Text("Partial observations stay visible. Summary inclusion is explicit; source, endpoint and compatible reference context remain separate.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var modePicker: some View {
        Picker("View", selection: $mode) {
            ForEach(DosePatternDisplayMode.allCases) { Text($0.rawValue).tag($0) }
        }.accessibilityIdentifier("dose-pattern-mode")
    }
    private var sourcePicker: some View {
        Picker("Sleep source", selection: $model.sleepSource) {
            ForEach(DashboardSleepSource.allCases) { Text($0.rawValue).tag($0) }
        }
    }
    private var definition: String {
        outcome == .postDose2
            ? "Observed Apple Health asleep minutes after a usable reported Dose 2, bounded by reported final awakening or provider last observed sleep end. Each endpoint policy has its own panel. No Dose 2: not applicable. WHOOP has no compatible post-dose intervals."
            : "The selected provider's main-episode asleep duration. This is independent of dose count and is not the entire waking day or reviewed-night window. Naps are separate; providers are never substituted."
    }
    private func endpointLabel(_ basis: DashboardSleepMetricProjection.BoundaryBasis) -> String {
        basis.rawValue.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized
    }
    private var byDateCharts: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(basisGroups, id: \.first?.sleep.boundaryBasis) { group in
                if let first = group.first {
                    Text("Sleep by night • " + endpointLabel(first.sleep.boundaryBasis)).font(.headline)
                    Chart(group) { sample in
                        if let value = sample.value {
                            PointMark(x: .value("Treatment date", sample.night.sessionDate), y: .value("Sleep minutes", value))
                                .symbol(DosePatternPresentation.symbol(sample.night.dosePattern.pattern))
                                .foregroundStyle(.primary).symbolSize(sample.sleep.metric.state == .partial ? 35 : 70)
                                .accessibilityLabel(label(sample))
                        }
                    }.frame(height: 230).chartXScale(domain: Array(Set(group.map { $0.night.sessionDate })).sorted())
                        .chartYScale(domain: 0...sleepMaximum).chartYAxisLabel("Sleep (minutes)")
                        .chartOverlay { proxy in
                            GeometryReader { geometry in
                                Rectangle().fill(.clear).contentShape(Rectangle()).onTapGesture { point in
                                    let x = point.x - geometry[proxy.plotAreaFrame].origin.x
                                    if let day: String = proxy.value(atX: x) { candidates = Set(group.filter { $0.night.sessionDate == day }.map(\.id)) }
                                }
                            }
                        }
                }
            }
            Text("Circle: two reported; square: one confirmed; triangle: confirmed zero; diamond: incomplete, in progress or review. Smaller marks are partial. Tap a date for exact candidates.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var comparisonCharts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sleep by reported dose pattern").font(.headline)
            ForEach(comparisonGroups, id: \.first?.key) { group in
                if let first = group.first {
                    Text(first.night.dosePattern.pattern.label).font(.subheadline.bold())
                    Text(first.context.label + " • " + endpointLabel(first.sleep.boundaryBasis)).font(.caption)
                    let included = group.compactMap { $0.sleep.summaryValue(includePartial: model.inspection.includePartialMetrics) }
                    let summary = DiaryMetricSummary(included.map(Optional.some))
                    Text(DosePatternPresentation.summary(summary, total: group.count) + "; partial contributions \(group.filter { $0.sleep.metric.state == .partial && $0.sleep.summaryValue(includePartial: model.inspection.includePartialMetrics) != nil }.count)")
                        .font(.caption)
                    Chart(group) { sample in
                        if let value = sample.value {
                            PointMark(x: .value("Sleep minutes", value), y: .value("Pattern", first.night.dosePattern.pattern.label))
                                .symbol(DosePatternPresentation.symbol(sample.night.dosePattern.pattern)).foregroundStyle(.primary)
                                .symbolSize(sample.sleep.metric.state == .partial ? 35 : 70).accessibilityLabel(label(sample))
                        }
                    }.chartXScale(domain: 0...sleepMaximum).frame(height: 70)
                    Button("Inspect this compatible group") { candidates = Set(group.map(\.id)) }
                }
            }
            exactTable(samples.filter { $0.context.status != .documentedReference }.map(\.night),
                title: "Unknown or changing reference context — individual observations only")
            Text("Median and middle-50% spread include only the declared eligible observations in each compatible group. Unknown or changing contexts are never pooled into a numerical comparison.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var pairedCharts: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(basisGroups, id: \.first?.sleep.boundaryBasis) { group in
                if let first = group.first {
                    Text("Paired spacing and unpaired companion • " + endpointLabel(first.sleep.boundaryBasis)).font(.headline)
                    let paired = group.filter { $0.pair != nil && $0.value != nil }
                    let unpaired = group.filter { $0.pair == nil }
                    Text("\(paired.count)/\(group.count) have usable spacing and sleep; \(unpaired.count) have no usable pair. Neither missing axis is zero.").font(.caption)
                    if width == .regular { HStack(alignment: .top) { pairPanel(paired); companionPanel(unpaired) } }
                    else { pairPanel(paired); companionPanel(unpaired) }
                    Button("Inspect these observations") { candidates = Set(group.map(\.id)) }
                }
            }
            Text("Numeric spacing and categorical companion have distinct horizontal axes and the same sleep definition and vertical scale. The old spacing-reference legend is not used for dose count.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func pairPanel(_ group: [Sample]) -> some View {
        VStack(alignment: .leading) {
            Text("D1–D2 spacing").font(.subheadline.bold())
            if group.isEmpty { Text("No usable pairs with this sleep measure.") }
            Chart(group) { sample in
                if let pair = sample.pair, let value = sample.value {
                    PointMark(x: .value("D1–D2 minutes", pair), y: .value("Sleep minutes", value))
                        .symbol(DosePatternPresentation.symbol(sample.night.dosePattern.pattern)).foregroundStyle(.primary)
                        .symbolSize(sample.sleep.metric.state == .partial ? 35 : 70)
                        .accessibilityLabel(label(sample))
                }
            }.frame(height: 230).chartYScale(domain: 0...sleepMaximum)
                .chartXAxisLabel("Reported spacing (minutes)").chartYAxisLabel("Sleep (minutes)")
        }.frame(maxWidth: .infinity)
    }
    private func companionPanel(_ group: [Sample]) -> some View {
        VStack(alignment: .leading) {
            Text("No usable D1–D2 spacing").font(.subheadline.bold())
            if group.compactMap(\.value).isEmpty { Text("No observed sleep values; statuses remain in the exact table.") }
            Chart(group) { sample in
                if let value = sample.value {
                    PointMark(x: .value("Pattern", sample.night.dosePattern.pattern.label), y: .value("Sleep minutes", value))
                        .symbol(DosePatternPresentation.symbol(sample.night.dosePattern.pattern)).foregroundStyle(.primary)
                        .symbolSize(sample.sleep.metric.state == .partial ? 35 : 70)
                        .accessibilityLabel(label(sample))
                }
            }.frame(height: 230).chartYScale(domain: 0...sleepMaximum).chartYAxisLabel("Sleep (minutes)")
        }.frame(maxWidth: .infinity)
    }
    private var workStrip: some View {
        DisclosureGroup("Work phase strip • \(model.inspection.workContextBasis.rawValue)") {
            ForEach(rows) { night in
                let phase = model.workClassification(for: night.id)
                Text(night.sessionDate + " • " + discriminator(night) + " • "
                    + (workCurrent ? phase?.phase.label ?? "Unknown / no reviewed association" : "Unavailable / read incomplete")
                    + (phase.map { " • " + $0.detail } ?? ""))
                    .font(.caption)
            }
        }
    }
    private var annotations: some View {
        DisclosureGroup("Reference and questionnaire version evidence") {
            ForEach(periodAnnotations) { annotation in
                Text(annotation.title + " • " + (annotation.effectiveAt.map(timestamp) ?? "Effective date not collected; observed " + timestamp(annotation.observedAt))
                    + " • " + annotation.detail).font(.caption)
            }
            Text("Evidence follows the selected period, retaining the original effective date of baseline references. These dates retain their source meaning; a recorded questionnaire version does not establish a rollout date.").font(.caption)
        }
    }
    private func label(_ sample: Sample) -> String {
        DosePatternPresentation.description(sample.night, sleep: sample.value) + "; "
            + DosePatternPresentation.sleepDescription(sample.night, source: model.sleepSource, outcome: outcome, freshness: freshness)
    }
    private func timestamp(_ date: Date) -> String {
        guard date.timeIntervalSince1970.isFinite else { return "Invalid timestamp — review" }
        let formatter = DateFormatter(); formatter.timeZone = model.reportingTimeZone
        formatter.dateStyle = .medium; formatter.timeStyle = .medium
        return formatter.string(from: date) + " • " + model.reportingTimeZone.identifier
    }
    private func discriminator(_ night: DashboardNightAggregate) -> String {
        (night.dose1Time ?? (model.sleepSource == .appleHealth ? night.healthSummary?.sleepOnset : nil)).map(timestamp)
            ?? "Occurrence anchor unavailable; " + night.id
    }
    private func exactTable(_ observations: [DashboardNightAggregate], title: String, expanded: Bool = false) -> some View {
        DisclosureGroup(title, isExpanded: Binding(get: { expanded || expandedTables.contains(title) }, set: { value in
            if value { expandedTables.insert(title) } else { expandedTables.remove(title) }
        })) {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(observations) { night in
                    Button {
                        model.inspection.selectedObservationID = night.id; detailPresented = true
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(night.sessionDate + " • " + night.dosePattern.pattern.label).font(.callout.bold())
                            Text(discriminator(night)).font(.caption)
                            Text(DosePatternPresentation.description(night, sleep: DosePatternPresentation.sleepValue(night, source: model.sleepSource, outcome: outcome, freshness: freshness))).font(.caption)
                            Text(DosePatternPresentation.sleepDescription(night, source: model.sleepSource, outcome: outcome, freshness: freshness)).font(.caption)
                            Text(night.providerAssociation).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).accessibilityIdentifier("dose-pattern-row-\(night.id)")
                    if model.contextReadReady {
                        Button("Filter to this exact reference context") { model.inspection.contextStratumID = night.contextStratum(for: model.sleepSource).id }
                            .font(.caption)
                    }
                    Divider()
                }
            }.padding(.top, 8)
        }
    }
}
