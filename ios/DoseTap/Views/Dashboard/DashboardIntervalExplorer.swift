import SwiftUI
import Charts
import DoseCore

struct DashboardIntervalExplorer: View {
    @ObservedObject var model: DashboardAnalyticsModel
    let snapshots: [DashboardReplaySnapshot]
    var focusedTiming = false
    @Environment(\.dashboardPalette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var candidates: Set<String> = []
    private var mode: String { focusedTiming ? model.replayPresentation.timingMode : model.replayPresentation.intervalMode }
    private var preset: DashboardIntervalPreset { focusedTiming ? .dose1ToDose2 : model.replayPresentation.preset }
    private var outcome: ReplayComparedOutcome { focusedTiming ? .mainSleep : model.replayPresentation.comparedOutcome }
    private var rows: [ReplayComparisonRow] {
        model.replayComparisons(for: snapshots, outcome: outcome, preset: preset)
    }
    private var workRows: [ReplayComparisonRow] {
        rows.filter { model.replayPresentation.timingWorkFilter == nil || $0.workBeforeSleep == model.replayPresentation.timingWorkFilter }
    }
    private var filtered: [ReplayComparisonRow] {
        workRows.filter { focusedTiming || model.replayPresentation.selectedBinLower == nil || $0.binLower == model.replayPresentation.selectedBinLower }
    }
    private var bins: [Double: Int] { Dictionary(grouping: workRows.compactMap(\.binLower), by: { $0 }).mapValues(\.count) }
    private var paired: Bool { mode == "Compare outcome" || mode == "Sleep vs spacing" }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if focusedTiming {
                Text("Dose timing").font(.title2.bold())
                countLabel
                Picker("Timing view", selection: $model.replayPresentation.timingMode) {
                    Text("By date").tag("By date")
                    Text("Sleep vs spacing").tag("Sleep vs spacing")
                }.pickerStyle(.menu).accessibilityIdentifier("dashboard-timing-mode")
                if paired {
                    Picker("Sleep source", selection: $model.sleepSource) {
                        ForEach(DashboardSleepSource.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.menu)
                }
            } else {
            Picker("Curated interval", selection: $model.replayPresentation.preset) {
                ForEach(DashboardIntervalPreset.allCases) { Text($0.rawValue).tag($0) }
            }.accessibilityIdentifier("dashboard-interval-preset")
            Picker("Interval display", selection: $model.replayPresentation.intervalMode) {
                ForEach(["By date", "Distribution", "Compare outcome"], id: \.self) { Text($0) }
            }.pickerStyle(.menu).accessibilityIdentifier("dashboard-interval-display")
            Picker("Compared outcome", selection: $model.replayPresentation.comparedOutcome) {
                ForEach(ReplayComparedOutcome.allCases) { Text($0.rawValue).tag($0) }
            }.accessibilityIdentifier("dashboard-interval-outcome")
            Toggle("Include partial values", isOn: $model.inspection.includePartialMetrics)
            }
            Picker("Work before sleep", selection: $model.replayPresentation.timingWorkFilter) {
                Text("All days").tag(DashboardWorkBeforeSleep?.none)
                ForEach(DashboardWorkBeforeSleep.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
            }.pickerStyle(.menu).accessibilityIdentifier("dashboard-timing-work")
            if !focusedTiming { countLabel }
            if !focusedTiming && (mode == "Distribution" || model.replayPresentation.selectedBinLower != nil) {
                Picker("Distribution rows", selection: $model.replayPresentation.selectedBinLower) {
                    Text("All bins and missing intervals").tag(Double?.none)
                    ForEach(bins.keys.sorted(), id: \.self) { lower in
                        Text(ReplayComparisonRow.binLabel(lower) + " (\(bins[lower] ?? 0))").tag(Optional(lower))
                    }
                }.accessibilityIdentifier("dashboard-interval-bin")
                if let lower = model.replayPresentation.selectedBinLower {
                    Text("Table and filtered export: \(ReplayComparisonRow.binLabel(lower)). Missing or excluded values are outside this bin.").font(.caption)
                    Button("Clear interval bin") { model.replayPresentation.selectedBinLower = nil }
                }
            }
            if let selected = model.inspection.selectedObservationID, !filtered.contains(where: { $0.id == selected }) {
                Text("Selected observation is outside the interval filter. Its identity is retained; adjust the work or interval filters to inspect it.").font(.caption)
            }
            if mode == "Distribution" { distribution }
            else if filtered.contains(where: { plotX($0) != nil && (!paired || $0.y != nil) }) { pointChart }
            else { Text(paired ? "No nights with confirmed dose history and recorded sleep in this view." : "No recorded pairs in this period") }
            if paired && outcome == .mainSleep {
                Text(model.sleepPairingSummary).font(.caption)
                if model.unmatchedSelectedSleepCount > 0 {
                    NavigationLink("Review unmatched sleep (\(model.unmatchedSelectedSleepCount))") { ProviderSessionAssociationView(model: model) }
                }
            }
            if mode != "Distribution" { legends }
            if let row = filtered.first(where: { $0.id == model.inspection.selectedObservationID }) { tableRow(row) }
            else { Text("Tap a point to see that night.").font(.caption).foregroundStyle(.secondary) }
            DisclosureGroup("Chart details") {
                Text("Work before sleep uses confirmed saved history. Square: workday; circle: off day; diamond: unknown. A planned shift alone is not confirmed work.")
                Text("150–240 minutes inclusive is the built-in spacing reference, not a prescription. Elapsed time is not sleep duration.")
                if paired { Text("Single dose sits at the labeled zero position. It has no dose-to-dose interval. Y shows recorded main sleep from the selected source; missing sleep is not plotted.") }
                Text("Reference: dose_spacing_reference_v1_150_240_minutes. Associations do not establish medication effects.")
            }.font(.caption)
            if !candidates.isEmpty {
                Text("Observations at the selected position").font(.headline)
                ForEach(filtered.filter { candidates.contains($0.id) }) { row in
                    Button(row.treatmentDate + " · " + row.workBeforeSleep.rawValue) { select(row) }
                }
            }
            if focusedTiming { DisclosureGroup("All nights and source details") { recordRows } }
            else { recordRows }
            if filtered.isEmpty { Text("No observations match this interval filter.") }
        }.onChange(of: model.replayPresentation.preset) { _ in candidates = []; model.replayPresentation.selectedBinLower = nil }
            .onChange(of: mode) { _ in candidates = [] }
            .onChange(of: model.replayPresentation.timingWorkFilter) { _ in candidates = [] }
            .onChange(of: model.replayPresentation.comparedOutcome) { _ in candidates = [] }
    }
    private var countLabel: some View {
        Text("\(filtered.filter { plotX($0) != nil && (!paired || $0.y != nil) }.count) plotted · \(filtered.count) nights")
            .font(.caption).accessibilityIdentifier("dashboard-timing-count")
    }
    private var recordRows: some View {
        ForEach(filtered) { row in
            Button((row.id == model.inspection.selectedObservationID ? "Selected · " : "Select · ") + row.treatmentDate + " · " + (row.isConfirmedSingle ? "Single dose" : number(row.x) + " min")) { select(row) }
                .accessibilityIdentifier("dashboard-interval-row-" + row.id)
                .accessibilityAddTraits(model.inspection.selectedObservationID == row.id ? .isSelected : [])
            tableRow(row)
        }
    }
    private var distribution: some View {
        Chart(bins.keys.sorted(), id: \.self) { lower in
            BarMark(x: .value("Minutes", ReplayComparisonRow.binLabel(lower)), y: .value("Observations", bins[lower] ?? 0))
                .foregroundStyle(model.replayPresentation.selectedBinLower == lower ? palette.sleep : palette.timing)
                .accessibilityLabel(ReplayComparisonRow.binLabel(lower) + ": \(bins[lower] ?? 0) observations")
        }.frame(height: typeSize.isAccessibilitySize ? 340 : 240)
            .accessibilityIdentifier("dashboard-interval-distribution")
            .chartOverlay { proxy in GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle()).onTapGesture { point in
                    let frame = geometry[proxy.plotAreaFrame]
                    guard frame.contains(point), let lower = bins.keys.min(by: {
                        abs((proxy.position(forX: ReplayComparisonRow.binLabel($0)) ?? -.infinity) - (point.x - frame.minX))
                        < abs((proxy.position(forX: ReplayComparisonRow.binLabel($1)) ?? -.infinity) - (point.x - frame.minX))
                    }) else { return }
                    model.replayPresentation.selectedBinLower = lower
                }
            } }
    }
    private var pointChart: some View {
        Chart {
            if preset == .dose1ToDose2 {
                if paired { RectangleMark(xStart: .value("Reference start", 150), xEnd: .value("Reference end", 240)).foregroundStyle(palette.timing.opacity(0.08)) }
                else { RectangleMark(yStart: .value("Reference start", 150), yEnd: .value("Reference end", 240)).foregroundStyle(palette.timing.opacity(0.08)) }
            }
            ForEach(filtered) { row in
            if let x = plotX(row) {
                if paired, let y = row.y {
                    PointMark(x: .value("Interval minutes", x), y: .value(outcome.rawValue, y))
                        .foregroundStyle(timingColor(row))
                        .symbol(symbol(row.workBeforeSleep))
                        .symbolSize(row.id == model.inspection.selectedObservationID ? 125 : 45)
                        .accessibilityHidden(true)
                } else if !paired {
                    PointMark(x: .value("Treatment date", date(row)), y: .value("Interval minutes", x))
                        .foregroundStyle(timingColor(row))
                        .symbol(symbol(row.workBeforeSleep))
                        .symbolSize(row.id == model.inspection.selectedObservationID ? 125 : 45)
                        .accessibilityHidden(true)
                }
            }
            }
        }.chartYAxisLabel(paired ? (outcome == .mainSleep ? "Sleep (min)" : "Sleepiness (0–10)") : "Dose interval (min)")
            .chartXAxisLabel(paired ? "Dose spacing (min) · 0 = Single dose" : "Night")
            .chartXAxis {
                if paired {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine(); AxisTick()
                        AxisValueLabel { if let minutes = value.as(Double.self) { Text(minutes == 0 ? "Single\ndose" : minutes.formatted()) } }
                    }
                } else { AxisMarks(values: .automatic(desiredCount: 4)) }
            }
            .frame(height: typeSize.isAccessibilitySize ? 360 : 260)
            .accessibilityIdentifier("dashboard-interval-points")
            .chartOverlay { proxy in GeometryReader { geometry in
                let frame = geometry[proxy.plotAreaFrame]
                let points: [DosePatternPresentation.PlotPoint] = filtered.compactMap { row in
                    guard let interval = plotX(row) else { return nil }
                    let x = paired ? proxy.position(forX: interval) : proxy.position(forX: date(row))
                    guard let x, let value = paired ? row.y : interval, let y = proxy.position(forY: value) else { return nil }
                    return .init(id: row.id, point: CGPoint(x: x, y: y))
                }
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(.clear).contentShape(Rectangle())
                    ForEach(filtered) { row in
                        if let point = points.first(where: { $0.id == row.id }) {
                            Button { select(row) } label: { Color.clear.frame(width: 44, height: 44).contentShape(Circle()) }
                                .buttonStyle(.plain).accessibilityLabel(pointLabel(row))
                                .accessibilityIdentifier("dashboard-interval-point-" + row.id)
                                .accessibilityValue(row.id == model.inspection.selectedObservationID ? "Selected" : "Not selected")
                                .accessibilityAction { select(row) }
                                .position(x: frame.minX + point.point.x, y: frame.minY + point.point.y)
                        }
                    }
                }.frame(width: geometry.size.width, height: geometry.size.height)
                    .accessibilityElement(children: .contain)
                    .highPriorityGesture(SpatialTapGesture().onEnded { value in
                        let tap = value.location
                        guard frame.contains(tap) else { return }
                        candidates = DosePatternPresentation.candidates(at: CGPoint(x: tap.x - frame.minX, y: tap.y - frame.minY), points: points)
                        if candidates.count == 1, let row = filtered.first(where: { candidates.contains($0.id) }) { select(row) }
                    })
            } }
    }
    private func plotX(_ row: ReplayComparisonRow) -> Double? { paired ? row.sleepComparisonX : row.x }
    private func symbol(_ work: DashboardWorkBeforeSleep) -> BasicChartSymbolShape {
        switch work { case .work: return .square; case .off: return .circle; case .unknown: return .diamond }
    }
    private func timingColor(_ row: ReplayComparisonRow) -> Color {
        if row.isConfirmedSingle { return palette.coverage }
        switch row.referenceGroup {
        case "Within reference": return palette.timing
        case "Below reference": return palette.chart(.purple, warmth: 0.8)
        case "Above reference": return palette.review
        default: return palette.chart(.gray)
        }
    }
    private var legends: some View {
        VStack(alignment: .leading, spacing: 6) {
            (Text("● Within 150–240 min  ").foregroundColor(palette.timing) + Text("● Below  ").foregroundColor(palette.chart(.purple, warmth: 0.8)) + Text("● Above").foregroundColor(palette.review))
            Text("Work before sleep: ■ Work   ● Off   ◆ Unknown").foregroundStyle(.secondary)
            if paired { Text("● Single dose · no spacing interval").foregroundStyle(palette.coverage) }
        }.font(.caption).fixedSize(horizontal: false, vertical: true)
    }
    private func tableRow(_ row: ReplayComparisonRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text((row.id == model.inspection.selectedObservationID ? "Selected · " : "") + row.treatmentDate).font(.headline)
            Text(row.isConfirmedSingle ? "Single dose · Dose 2 not taken or one dose confirmed" : "Dose interval: \(number(row.x)) min")
            if let snapshot = snapshots.first(where: { $0.sessionID == row.replayID }), preset == .dose1ToDose2 {
                let markers = snapshot.markers.filter { $0.id == row.interval.startID || $0.id == row.interval.endID || (row.isConfirmedSingle && $0.kind == .dose1) }
                ForEach(markers) { marker in Text(marker.kind.label + ": " + stamp(marker.occurredAt)).font(.subheadline) }
            }
            if !row.isConfirmedSingle, let group = row.referenceGroup { Text(group).font(.subheadline) }
            Text("Work before sleep: " + row.workBeforeSleep.rawValue).font(.subheadline)
            if paired { Text("Recorded sleep: \(number(row.y)) min · \(row.source)") }
            DisclosureGroup("Record and source details") {
                Text(row.id)
                if let snapshot = snapshots.first(where: { $0.sessionID == row.replayID }) { Text(snapshot.sourcePolicy) }
                Text("Interval: \(row.interval.state.rawValue) · \(row.interval.reason)")
                Text("\(row.outcome.rawValue): \(number(row.metric.value)) \(row.metric.unit) · \(row.metric.state.rawValue) · \(row.metric.reason)")
                Text("\(row.source) · source \(row.sourceRecordID ?? "unavailable") · observed \(stamp(row.observedAt)) · captured \(stamp(row.capturedAt))")
                Text("Endpoints \(row.interval.startID ?? "missing") → \(row.interval.endID ?? "missing"); definition \(row.definition); context \(row.contextID)")
            }.font(.caption)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(row.id == model.inspection.selectedObservationID ? palette.timing.opacity(0.12) : Color.clear)
    }
    private func select(_ row: ReplayComparisonRow) { model.selectReplayID(row.replayID) }
    private func pointLabel(_ row: ReplayComparisonRow) -> String {
        row.treatmentDate + "; " + row.workBeforeSleep.rawValue + "; " + (row.isConfirmedSingle ? "Single dose" : "interval " + number(row.x) + " minutes; " + (row.referenceGroup ?? "Unclassified")) + "; " + row.outcome.rawValue + " " + number(row.y)
    }
    private func number(_ value: Double?) -> String { value.map { $0.formatted(.number.precision(.fractionLength(0...6))) } ?? "unavailable" }
    private func stamp(_ date: Date?) -> String {
        guard let date, date.timeIntervalSince1970.isFinite else { return "unavailable or invalid" }
        let formatter = DateFormatter(); formatter.timeZone = model.reportingTimeZone; formatter.dateFormat = "MMM d HH:mm ZZZZZ"
        return formatter.string(from: date)
    }
    private func date(_ row: ReplayComparisonRow) -> Date {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = model.reportingTimeZone; formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: row.treatmentDate) ?? model.reportingAsOf
    }
}
