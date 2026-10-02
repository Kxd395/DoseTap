import SwiftUI
import Charts

struct SleepIntervalChartPoint: Identifiable, Equatable {
    let id: String, date: String, source: String
    let interval: Double?, sleep: Double
    let single: Bool
    let work: DashboardWorkBeforeSleep
    let reported: DashboardReportedNightContext?
    let usesReported: Bool
    var x: Double { single ? 0 : interval ?? 0 }
    var label: String {
        date + " · " + (single ? "Single dose" : "Spacing " + Self.number(x) + " min")
            + " · Sleep " + Self.number(sleep) + " min · " + (usesReported ? "Morning report: " + (reported?.label ?? "Unknown · no usable check-in") : "Reviewed work: " + work.rawValue) + " · " + source
    }
    static func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
    init?(id: String, date: String, interval: Double?, sleep: Double?, single: Bool,
          work: DashboardWorkBeforeSleep, source: String, reported: DashboardReportedNightContext? = nil, usesReported: Bool = false) {
        guard let sleep, sleep.isFinite, sleep >= 0,
              interval.map({ $0.isFinite && $0 >= 0 }) ?? single else { return nil }
        self.id = id; self.date = date; self.interval = single ? nil : interval
        self.sleep = sleep; self.single = single; self.work = work; self.source = source; self.reported = reported; self.usesReported = usesReported
    }
}

enum SleepIntervalChartScale {
    static func ticks(in range: ClosedRange<Double>, step: Double) -> [Double] {
        guard range.lowerBound.isFinite, range.upperBound.isFinite, step.isFinite, step > 0 else { return [] }
        let stride = max(step, ceil((range.upperBound - range.lowerBound) / (120 * step)) * step)
        guard stride.isFinite else { return [] }
        let first = ceil(range.lowerBound / stride) * stride
        return (0...120).map { first + Double($0) * stride }.filter { range.contains($0) }
    }
    static func domain(maximum: Double, focus: Double?, zoom: Double, minimumSpan: Double) -> ClosedRange<Double> {
        let maximum = maximum.isFinite ? min(1e9, max(0, maximum)) : 0
        let upper = max(minimumSpan, ceil(maximum / 25) * 25 + 25)
        let lower = -12.5, fullSpan = upper - lower
        let factor = zoom.isFinite ? min(8, max(1, zoom)) : 1
        let span = min(fullSpan, max(minimumSpan, fullSpan / factor))
        let center = focus.flatMap { $0.isFinite ? $0 : nil } ?? (upper + lower) / 2
        let start = min(upper - span, max(lower, center - span / 2))
        return start...(start + span)
    }
}

struct DashboardSleepIntervalChart: View {
    @ObservedObject var model: DashboardAnalyticsModel
    let rows: [ReplayComparisonRow]
    var showDetails = true
    @Environment(\.dashboardPalette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var zoom = 1.0
    @State private var candidates: Set<String> = []
    private var points: [SleepIntervalChartPoint] {
        rows.compactMap { .init(id: $0.id, date: $0.treatmentDate, interval: $0.x, sleep: $0.y,
                               single: $0.isConfirmedSingle, work: $0.workBeforeSleep, source: $0.source, reported: model.replayPresentation.timingContextBasis == .reported ? $0.reportedNight : nil, usesReported: model.replayPresentation.timingContextBasis == .reported) }
    }
    private var selected: SleepIntervalChartPoint? { points.first { $0.id == model.inspection.selectedObservationID } }
    private var xDomain: ClosedRange<Double> {
        SleepIntervalChartScale.domain(maximum: points.map(\.x).max() ?? 0, focus: selected?.x, zoom: zoom, minimumSpan: 50)
    }
    private var yDomain: ClosedRange<Double> {
        SleepIntervalChartScale.domain(maximum: points.map(\.sleep).max() ?? 0, focus: selected?.sleep, zoom: zoom, minimumSpan: 100)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if points.isEmpty { Text("No nights with confirmed dose history and recorded sleep in this view.").font(.caption) }
            else {
                plot.frame(height: typeSize.isAccessibilitySize ? 420 : 300)
                ViewThatFits(in: .horizontal) {
                    HStack { zoomButtons }
                    VStack(alignment: .leading) { zoomButtons }
                }.buttonStyle(.bordered).controlSize(.small)
                Text("Tap a point for minutes. Pinch to zoom; zoom follows the selected night. Pointer hover also inspects points.")
                    .font(.caption).foregroundStyle(.secondary)
                if candidates.count > 1 {
                    Text("Overlapping nights: choose a record").font(.caption.bold())
                    ForEach(points.filter { candidates.contains($0.id) }) { point in
                        Button(point.label) { select(point.id) }.font(.caption)
                    }
                }
                if showDetails, let selected {
                    Text(selected.label).font(.callout).accessibilityIdentifier("dashboard-sleep-point-details")
                    DisclosureGroup("Exact recorded values") {
                        Text("Spacing: " + (selected.interval.map(String.init(describing:)) ?? "Single dose; no interval")
                             + " · Sleep minutes: " + String(selected.sleep))
                        Text("Observation: " + selected.id)
                        if let report = selected.reported {
                            Text("Morning check-in " + report.recordID + " · reported " + ISO8601DateFormatter().string(from: report.reportedAt))
                        }
                        Text("Reviewed work before sleep: " + selected.work.rawValue)
                    }.font(.caption)
                }
            }
        }.onChange(of: points) { _ in zoom = 1; candidates = [] }
            .onChange(of: model.replayPresentation.timingContextBasis) { _ in zoom = 1; candidates = [] }
    }
    @ViewBuilder private var zoomButtons: some View {
        Button { zoom = min(8, zoom * 2) } label: { Label("Zoom in", systemImage: "plus.magnifyingglass") }
            .disabled(zoom >= 8).accessibilityIdentifier("dashboard-sleep-zoom-in")
        Button { zoom = max(1, zoom / 2) } label: { Label("Zoom out", systemImage: "minus.magnifyingglass") }
            .disabled(zoom <= 1).accessibilityIdentifier("dashboard-sleep-zoom-out")
        Button("Reset") { zoom = 1; candidates = [] }.disabled(zoom == 1 && candidates.isEmpty)
            .accessibilityIdentifier("dashboard-sleep-zoom-reset")
    }
    private var plot: some View {
        Chart(points) { point in
            PointMark(x: .value("Spacing", point.x), y: .value("Sleep", point.sleep))
                .symbol { SleepIntervalChartMarker(work: point.work, color: color(point), reported: point.reported, usesReported: model.replayPresentation.timingContextBasis == .reported, selected: point.id == selected?.id) }
                .foregroundStyle(color(point))
                .accessibilityHidden(true)
        }.chartXScale(domain: xDomain).chartYScale(domain: yDomain)
            .chartPlotStyle { $0.clipped() }
            .chartXAxisLabel("Spacing (min) · 0 = Single dose")
            .chartYAxisLabel("Recorded sleep (min)")
            .chartXAxis {
                AxisMarks(values: SleepIntervalChartScale.ticks(in: xDomain, step: 12.5)) { value in
                    if let minute = value.as(Double.self) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: minute.truncatingRemainder(dividingBy: 25) == 0 ? 0.7 : 0.35))
                            .foregroundStyle(Color.secondary.opacity(0.25))
                        if minute >= 0 && minute.truncatingRemainder(dividingBy: zoom > 1 ? 25 : 50) == 0 {
                            AxisValueLabel { Text(minute == 0 ? "Single\ndose" : SleepIntervalChartPoint.number(minute)) }
                        }
                    }
                }
            }.chartYAxis {
                AxisMarks(values: SleepIntervalChartScale.ticks(in: yDomain, step: 25)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.secondary.opacity(0.25))
                    if let minute = value.as(Double.self), minute >= 0,
                       minute.truncatingRemainder(dividingBy: zoom > 1 ? 25 : 100) == 0 { AxisValueLabel() }
                }
            }.accessibilityIdentifier("dashboard-interval-points")
            .chartOverlay { proxy in GeometryReader { geometry in
                let frame = geometry[proxy.plotAreaFrame]
                let targets: [DosePatternPresentation.PlotPoint] = points.compactMap { point in
                    guard xDomain.contains(point.x), yDomain.contains(point.sleep),
                          let x = proxy.position(forX: point.x), let y = proxy.position(forY: point.sleep) else { return nil }
                    return .init(id: point.id, point: CGPoint(x: x, y: y))
                }
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(.clear).contentShape(Rectangle())
                    ForEach(points) { point in
                        if let target = targets.first(where: { $0.id == point.id }) {
                            Button { select(point.id) } label: { Color.clear.frame(width: 44, height: 44).contentShape(Circle()) }
                                .buttonStyle(.plain).accessibilityLabel(point.label)
                                .accessibilityIdentifier("dashboard-interval-point-" + point.id)
                                .accessibilityValue(point.id == selected?.id ? "Selected" : "Not selected")
                                .accessibilityAction { select(point.id) }
                                .position(x: frame.minX + target.point.x, y: frame.minY + target.point.y)
                        }
                    }
                    ForEach(points.filter(\.single)) { point in
                        if let target = targets.first(where: { $0.id == point.id }) {
                            Text("1 · " + SleepIntervalChartPoint.number(point.sleep) + " min")
                                .font(.caption2.bold()).foregroundStyle(color(point))
                                .frame(width: min(110, frame.width), alignment: .leading)
                                .position(x: min(frame.maxX - min(110, frame.width) / 2, frame.minX + target.point.x + 12 + min(110, frame.width) / 2),
                                          y: max(frame.minY + 8, frame.minY + target.point.y - 12))
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                }.frame(width: geometry.size.width, height: geometry.size.height)
                    .accessibilityElement(children: .contain)
                    .highPriorityGesture(SpatialTapGesture().onEnded { inspect($0.location, frame: frame, targets: targets) })
                    .simultaneousGesture(MagnificationGesture().onEnded { value in
                        guard value.isFinite else { return }; zoom = min(8, max(1, zoom * value))
                    })
                    .onContinuousHover { phase in
                        if case .active(let location) = phase { inspect(location, frame: frame, targets: targets) }
                    }
            } }
    }
    private func inspect(_ location: CGPoint, frame: CGRect, targets: [DosePatternPresentation.PlotPoint]) {
        guard frame.contains(location) else { return }
        candidates = DosePatternPresentation.candidates(at: CGPoint(x: location.x - frame.minX, y: location.y - frame.minY), points: targets)
        if candidates.count == 1, let id = candidates.first { select(id, clearCandidates: false) }
    }
    private func select(_ id: String, clearCandidates: Bool = true) {
        if let row = rows.first(where: { $0.id == id }) { model.selectReplayID(row.replayID) }
        if clearCandidates { candidates = [] }
    }
    private func color(_ point: SleepIntervalChartPoint) -> Color {
        SleepIntervalChartMarker.spacingColor(interval: point.x, single: point.single, palette: palette)
    }
}

/// Shape expresses confirmed work context independently of the spacing color.
struct SleepIntervalChartMarker: View {
    let work: DashboardWorkBeforeSleep
    let color: Color
    var reported: DashboardReportedNightContext? = nil
    var usesReported = false
    let selected: Bool
    private var symbol: String {
        if usesReported {
            switch reported?.type {
            case .workNight: return "square"
            case .offNight: return "circle"
            case .transitionIntoWorkBlock, .transitionOutOfWorkBlock: return "triangle"
            case .recoveryNight: return "hexagon"
            case .unsure, nil: return "diamond"
            }
        }
        switch work { case .work: return "square"; case .off: return "circle"; case .unknown: return "diamond" }
    }
    static func spacingColor(interval: Double, single: Bool = false, palette: DashboardPalette) -> Color {
        if single { return palette.chart(Color(red: 0.15, green: 0.82, blue: 0.73), warmth: 0.4) }
        if interval < 150 { return palette.chart(Color(red: 0.73, green: 0.47, blue: 1), warmth: 0.8) }
        if interval > 240 { return palette.chart(Color(red: 1, green: 0.68, blue: 0.25), warmth: 0.6) }
        return palette.chart(Color(red: 0.18, green: 0.62, blue: 1))
    }
    var body: some View {
        ZStack {
            Image(systemName: symbol + ".fill").foregroundStyle(color)
            Image(systemName: symbol).foregroundStyle(Color.primary.opacity(0.85))
        }.rotationEffect(.degrees(usesReported && reported?.type == .transitionOutOfWorkBlock ? 180 : 0))
            .font(.system(size: selected ? 19 : 14, weight: .medium))
            .frame(width: selected ? 20 : 16, height: selected ? 20 : 16)
            .accessibilityHidden(true)
    }
}
