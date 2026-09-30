import SwiftUI
import Charts
import DoseCore

struct DashboardIntervalExplorer: View {
    @ObservedObject var model: DashboardAnalyticsModel
    let snapshots: [DashboardReplaySnapshot]
    @Environment(\.dashboardPalette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var candidates: Set<String> = []
    private var mode: String { model.replayPresentation.intervalMode }
    private var rows: [ReplayComparisonRow] {
        snapshots.compactMap { model.replayComparison(for: $0, outcome: model.replayPresentation.comparedOutcome,
            preset: model.replayPresentation.preset) }
    }
    private var filtered: [ReplayComparisonRow] {
        rows.filter { model.replayPresentation.selectedBinLower == nil || $0.binLower == model.replayPresentation.selectedBinLower }
    }
    private var bins: [Double: Int] { Dictionary(grouping: rows.compactMap(\.binLower), by: { $0 }).mapValues(\.count) }
    private var paired: Bool { mode == "Compare outcome" }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            Text("\(filtered.filter { $0.x != nil }.count) eligible intervals; \(filtered.filter(\.paired).count) paired outcomes / \(filtered.count) displayed observations. Elapsed time is not sleep duration; associations do not establish medication effects.").font(.caption)
            if model.replayPresentation.preset == .dose1ToDose2 {
                Text("150–240 minutes inclusive: built-in reference only, not a prescription or safety classification. Reference: dose_spacing_reference_v1_150_240_minutes.").font(.caption)
            }
            if mode == "Distribution" || model.replayPresentation.selectedBinLower != nil {
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
                Text("Selected observation is outside the interval filter. Its identity is retained; clear the bin to inspect it.").font(.caption)
            }
            if mode == "Distribution" { distribution }
            else { pointChart }
            if !candidates.isEmpty {
                Text("Observations at the selected position").font(.headline)
                ForEach(filtered.filter { candidates.contains($0.id) }) { row in
                    Button(row.treatmentDate + " · " + row.id) { select(row) }
                }
            }
            Text("Exact interval and outcome table").font(.headline)
            ForEach(filtered) { row in
                Button { select(row) } label: { tableRow(row) }
                    .buttonStyle(.plain).accessibilityIdentifier("dashboard-interval-row-" + row.id)
                    .accessibilityAddTraits(model.inspection.selectedObservationID == row.id ? .isSelected : [])
            }
            if filtered.isEmpty { Text("No observations match this interval filter.") }
        }.onChange(of: model.replayPresentation.preset) { _ in candidates = []; model.replayPresentation.selectedBinLower = nil }
            .onChange(of: mode) { _ in candidates = [] }
            .onChange(of: model.replayPresentation.comparedOutcome) { _ in candidates = [] }
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
        Chart(filtered) { row in
            if let x = row.x {
                if paired, let y = row.y {
                    PointMark(x: .value("Interval minutes", x), y: .value(model.replayPresentation.comparedOutcome.rawValue, y))
                        .foregroundStyle(by: .value("Reference group", row.referenceGroup ?? "Unclassified"))
                        .symbolSize(row.id == model.inspection.selectedObservationID ? 125 : 45)
                        .accessibilityHidden(true)
                } else if !paired {
                    PointMark(x: .value("Treatment date", date(row)), y: .value("Interval minutes", x))
                        .foregroundStyle(by: .value("Reference group", row.referenceGroup ?? "Unclassified"))
                        .symbolSize(row.id == model.inspection.selectedObservationID ? 125 : 45)
                        .accessibilityHidden(true)
                }
            }
        }.frame(height: typeSize.isAccessibilitySize ? 360 : 250)
            .accessibilityIdentifier("dashboard-interval-points")
            .chartOverlay { proxy in GeometryReader { geometry in
                let frame = geometry[proxy.plotAreaFrame]
                let points: [DosePatternPresentation.PlotPoint] = filtered.compactMap { row in
                    guard let interval = row.x else { return nil }
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
    private func tableRow(_ row: ReplayComparisonRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text((row.id == model.inspection.selectedObservationID ? "Selected · " : "") + row.treatmentDate + " · " + row.id).font(.subheadline.bold())
            Text("Interval: \(number(row.interval.minutes)) min · \(row.interval.state.rawValue) · \(row.interval.reason)")
            Text("\(row.outcome.rawValue): \(number(row.metric.value)) \(row.metric.unit) · \(row.metric.state.rawValue) · \(row.metric.reason)")
            Text("Paired plot: \(row.paired ? "included" : "excluded") · \(row.referenceGroup ?? "No reference group")").font(.caption.bold())
            Text("\(row.source) · source \(row.sourceRecordID ?? "unavailable") · observed \(stamp(row.observedAt)) · captured \(stamp(row.capturedAt))").font(.caption)
            Text("Endpoints \(row.interval.startID ?? "missing") → \(row.interval.endID ?? "missing"); definition \(row.definition); context \(row.contextID)").font(.caption)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            .background(row.id == model.inspection.selectedObservationID ? palette.timing.opacity(0.12) : Color.clear)
            .accessibilityElement(children: .combine)
    }
    private func select(_ row: ReplayComparisonRow) { model.selectReplayID(row.replayID) }
    private func pointLabel(_ row: ReplayComparisonRow) -> String {
        row.treatmentDate + "; " + row.id + "; interval " + number(row.x) + " minutes; " + row.outcome.rawValue + " " + number(row.y)
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
