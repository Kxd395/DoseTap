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
    @ScaledMetric(relativeTo: .caption2) private var accessiblePlotHeight: CGFloat = 230
    @ScaledMetric(relativeTo: .caption2) private var accessibleComparisonHeight: CGFloat = 100

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
                Button("Reset filters") { model.inspection.resetFilters(); candidates = [] }.accessibilityIdentifier("dose-pattern-reset-filters")
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
            }.accessibilityIdentifier("dose-pattern-outcome")
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
                    Text("Vertical: sleep (minutes). Horizontal: treatment date; date ticks show month–day at accessibility sizes. Exact tables retain full dates.").font(.caption)
                    Chart(group) { sample in
                        if let value = sample.value {
                            PointMark(x: .value("Treatment date", sample.night.sessionDate), y: .value("Sleep minutes", value))
                                .symbol(DosePatternPresentation.symbol(sample.night.dosePattern.pattern))
                                .foregroundStyle(.primary).symbolSize(sample.sleep.metric.state == .partial ? 35 : 70)
                                .accessibilityLabel(label(sample))
                                .annotation(position: .top) { selectedAnnotation(sample.id) }
                        }
                    }.frame(height: plotHeight).chartXScale(domain: Array(Set(group.map { $0.night.sessionDate })).sorted())
                        .chartYScale(domain: 0...sleepMaximum).chartYAxis { numericAxis }
                        .chartXAxis { categoricalAxis(dates: true) }
                        .chartOverlay { plotOverlay(group, axes: .date, proxy: $0) }
                }
            }
            Text("Circle: two reported; square: one confirmed; triangle: confirmed zero; diamond: incomplete, in progress or review. Smaller marks are partial. Tap a mark for exact candidates; overlapping marks stay separate.")
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
                    let partialCount: Int = group.filter { $0.sleep.metric.state == .partial && $0.sleep.summaryValue(includePartial: model.inspection.includePartialMetrics) != nil }.count
                    Text(verbatim: "\(DosePatternPresentation.summary(summary, total: group.count)); partial contributions \(partialCount)")
                        .font(.caption)
                    Text("Horizontal: sleep (minutes). Vertical: reported dose pattern; the full category label is shown above.").font(.caption)
                    Chart(group) { sample in
                        if let value = sample.value {
                            PointMark(x: .value("Sleep minutes", value), y: .value("Pattern", first.night.dosePattern.pattern.label))
                                .symbol(DosePatternPresentation.symbol(sample.night.dosePattern.pattern)).foregroundStyle(.primary)
                                .symbolSize(sample.sleep.metric.state == .partial ? 35 : 70).accessibilityLabel(label(sample))
                                .annotation(position: .top) { selectedAnnotation(sample.id) }
                        }
                    }.chartXScale(domain: 0...sleepMaximum).frame(height: typeSize.isAccessibilitySize ? accessibleComparisonHeight : 100)
                        .chartXAxis { numericAxis }.chartYAxis { categoricalAxis(dates: false) }
                        .chartOverlay { plotOverlay(group, axes: .comparison, proxy: $0) }
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
            Text("Horizontal: reported D1–D2 spacing (minutes). Vertical: sleep (minutes).").font(.caption)
            if group.isEmpty { Text("No usable pairs with this sleep measure.") }
            Chart(group) { sample in
                if let pair = sample.pair, let value = sample.value {
                    PointMark(x: .value("D1–D2 minutes", pair), y: .value("Sleep minutes", value))
                        .symbol(DosePatternPresentation.symbol(sample.night.dosePattern.pattern)).foregroundStyle(.primary)
                        .symbolSize(sample.sleep.metric.state == .partial ? 35 : 70)
                        .accessibilityLabel(label(sample))
                                .annotation(position: .top) { selectedAnnotation(sample.id) }
                }
            }.frame(height: plotHeight).chartYScale(domain: 0...sleepMaximum)
                .chartXAxis { numericAxis }.chartYAxis { numericAxis }
                .chartOverlay { plotOverlay(group, axes: .spacing, proxy: $0) }
        }.frame(maxWidth: .infinity)
    }
    private func companionPanel(_ group: [Sample]) -> some View {
        VStack(alignment: .leading) {
            Text("No usable D1–D2 spacing").font(.subheadline.bold())
            Text("Horizontal: reported dose pattern. Vertical: sleep (minutes). Categories: "
                + Array(Set(group.map { $0.night.dosePattern.pattern.label })).sorted().joined(separator: "; ")).font(.caption)
            if group.compactMap(\.value).isEmpty { Text("No observed sleep values; statuses remain in the exact table.") }
            Chart(group) { sample in
                if let value = sample.value {
                    PointMark(x: .value("Pattern", sample.night.dosePattern.pattern.label), y: .value("Sleep minutes", value))
                        .symbol(DosePatternPresentation.symbol(sample.night.dosePattern.pattern)).foregroundStyle(.primary)
                        .symbolSize(sample.sleep.metric.state == .partial ? 35 : 70)
                        .accessibilityLabel(label(sample))
                                .annotation(position: .top) { selectedAnnotation(sample.id) }
                }
            }.frame(height: plotHeight).chartYScale(domain: 0...sleepMaximum)
                .chartXAxis { categoricalAxis(dates: false) }.chartYAxis { numericAxis }
                .chartOverlay { plotOverlay(group, axes: .companion, proxy: $0) }
        }.frame(maxWidth: .infinity)
    }
    private var plotHeight: CGFloat { typeSize.isAccessibilitySize ? accessiblePlotHeight : 230 }
    private var numericAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: typeSize.isAccessibilitySize ? 3 : 5)) { value in
            AxisGridLine(); AxisTick()
            AxisValueLabel {
                if let number = value.as(Double.self) {
                    Text(number.formatted(.number.precision(.fractionLength(0...1)))).font(.caption2)
                }
            }
        }
    }
    private func categoricalAxis(dates: Bool) -> some AxisContent {
        AxisMarks(values: .automatic(desiredCount: typeSize.isAccessibilitySize ? 2 : 5)) { value in
            AxisGridLine(); AxisTick()
            AxisValueLabel {
                if let label = value.as(String.self) {
                    Text(dates && typeSize.isAccessibilitySize ? String(label.suffix(5)) : categoryTick(label))
                        .font(.caption2).frame(maxWidth: typeSize.isAccessibilitySize ? 140 : nil)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.center)
                }
            }
        }
    }
    private func categoryTick(_ label: String) -> String {
        guard typeSize.isAccessibilitySize,
              let pattern = DashboardDosePattern.Pattern.allCases.first(where: { $0.label == label }) else { return label }
        switch pattern {
        case .twoReported: return "Two reported"
        case .singlePlanned: return "One, planned"
        case .singleOmitted: return "One, D2 omitted"
        case .singleUnknownPlan: return "One, plan unknown"
        case .noneReported: return "Zero confirmed"
        case .incomplete: return "Incomplete"
        case .needsReview: return "Review needed"
        case .inProgress: return "In progress"
        }
    }
    private enum PlotAxes: String { case date, spacing, companion, comparison }
    @ViewBuilder private func selectedAnnotation(_ id: String) -> some View {
        if model.inspection.selectedObservationID == id { Text("Selected").font(.caption2.bold()) }
    }
    private func plotPositions(_ group: [Sample], axes: PlotAxes, proxy: ChartProxy) -> [DosePatternPresentation.PlotPoint] {
        group.compactMap { sample in
            guard let value = sample.value else { return nil }
            let x: CGFloat?, y: CGFloat?
            switch axes {
            case .date: x = proxy.position(forX: sample.night.sessionDate); y = proxy.position(forY: value)
            case .spacing:
                guard let pair = sample.pair else { return nil }
                x = proxy.position(forX: pair); y = proxy.position(forY: value)
            case .companion: x = proxy.position(forX: sample.night.dosePattern.pattern.label); y = proxy.position(forY: value)
            case .comparison: x = proxy.position(forX: value); y = proxy.position(forY: sample.night.dosePattern.pattern.label)
            }
            guard let x, let y, x.isFinite, y.isFinite else { return nil }
            return .init(id: sample.id, point: CGPoint(x: x, y: y))
        }
    }
    private func plotOverlay(_ group: [Sample], axes: PlotAxes, proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            let bounds = geometry[proxy.plotAreaFrame]
            let points = plotPositions(group, axes: axes, proxy: proxy)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(.clear).contentShape(Rectangle()).onTapGesture { location in
                    guard bounds.contains(location) else { return }
                    candidates = DosePatternPresentation.candidates(at: CGPoint(x: location.x - bounds.minX, y: location.y - bounds.minY), points: points)
                }
                ForEach(points, id: \.id) { point in
                    Button { candidates = DosePatternPresentation.candidates(at: point.point, points: points) } label: {
                        Rectangle().fill(.clear).frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).position(x: bounds.minX + point.point.x, y: bounds.minY + point.point.y)
                        .accessibilityLabel("Inspect " + (group.first { $0.id == point.id }.map(label) ?? "observation"))
                        .accessibilityHint("Shows all overlapping observations; choose the exact session in the candidate table.")
                        .accessibilityValue(model.inspection.selectedObservationID == point.id ? "Selected observation" : "Unselected observation")
                        .accessibilityIdentifier("dose-pattern-point-\(axes.rawValue)-\(point.id)")
                }
            }.accessibilityElement(children: .contain)
        }
    }
    private var workStrip: some View {
        DisclosureGroup("Work phase strip • \(model.inspection.workContextBasis.rawValue)") {
            ForEach(rows) { night in
                let phase = model.workClassification(for: night.id)
                let phaseLabel: String = workCurrent ? phase?.phase.label ?? "Unknown / no reviewed association" : "Unavailable / read incomplete"
                let phaseDetail: String = phase.map { " • \($0.detail)" } ?? ""
                Text(verbatim: "\(night.sessionDate) • \(discriminator(night)) • \(phaseLabel)\(phaseDetail)")
                    .font(.caption)
            }
        }
    }
    private var annotations: some View {
        DisclosureGroup("Reference and questionnaire version evidence") {
            ForEach(periodAnnotations) { annotation in
                let effective: String = annotation.effectiveAt.map(timestamp) ?? "Effective date not collected; observed \(timestamp(annotation.observedAt))"
                Text(verbatim: "\(annotation.title) • \(effective) • \(annotation.detail)").font(.caption)
            }
            Text("Evidence follows the selected period, retaining the original effective date of baseline references. These dates retain their source meaning; a recorded questionnaire version does not establish a rollout date.").font(.caption)
        }
    }
    private func label(_ sample: Sample) -> String {
        let description = DosePatternPresentation.description(sample.night, sleep: sample.value)
        let sleep = DosePatternPresentation.sleepDescription(sample.night, source: model.sleepSource, outcome: outcome, freshness: freshness)
        return "\(description); \(sleep)"
    }
    private func timestamp(_ date: Date) -> String {
        guard date.timeIntervalSince1970.isFinite else { return "Invalid timestamp — review" }
        let formatter = DateFormatter(); formatter.timeZone = model.reportingTimeZone
        formatter.dateStyle = .medium; formatter.timeStyle = .medium
        return formatter.string(from: date) + " • " + model.reportingTimeZone.identifier
    }
    private func discriminator(_ night: DashboardNightAggregate) -> String {
        let anchor: Date? = night.dose1Time ?? (model.sleepSource == .appleHealth ? night.healthSummary?.sleepOnset : nil)
        return anchor.map(timestamp) ?? "Occurrence anchor unavailable; \(night.id)"
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
                            if model.inspection.selectedObservationID == night.id { Text("Selected observation").font(.caption.bold()) }
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
