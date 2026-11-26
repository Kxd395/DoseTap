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
        // Interpolation keeps type checking linear on older compilers.
        let spacing: String = single ? "Single dose" : "Spacing \(Self.number(x)) min"
        let context: String = usesReported
            ? "Morning report: \(reported?.label ?? "Unknown · no usable check-in")"
            : "Reviewed work: \(work.rawValue)"
        return "\(date) · \(spacing) · Sleep \(Self.number(sleep)) min · \(context) · \(source)"
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
    static func panCenter(range: ClosedRange<Double>, bounds: ClosedRange<Double>, translation: Double,
                          length: Double, inverted: Bool = false) -> Double {
        let center = (range.lowerBound + range.upperBound) / 2
        guard translation.isFinite, length.isFinite, length > 0 else { return center }
        let half = (range.upperBound - range.lowerBound) / 2
        let direction: Double = inverted ? 1 : -1
        let shifted: Double = center + direction * (translation / length) * half * 2
        return min(bounds.upperBound - half, max(bounds.lowerBound + half, shifted))
    }
    static func domain(maximum: Double, focus: Double?, zoom: Double, minimumSpan: Double) -> ClosedRange<Double> {
        let maximum = maximum.isFinite ? min(1e9, max(0, maximum)) : 0
        let upper = max(minimumSpan, ceil(maximum / 25) * 25 + 25)
        let lower = -12.5, fullSpan = upper - lower
        let factor = zoom.isFinite ? min(8, max(1, zoom)) : 1
        let span = min(fullSpan, max(minimumSpan, fullSpan / factor))
        let middle: Double = (upper + lower) / 2
        let center: Double = focus.flatMap { $0.isFinite ? $0 : nil } ?? middle
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
    @State private var focus: CGPoint?
    @State private var dragRanges: (ClosedRange<Double>, ClosedRange<Double>)?
    @State private var pinchStartZoom: Double?
    @State private var showCandidates = false
    private var points: [SleepIntervalChartPoint] {
        rows.compactMap { .init(id: $0.id, date: $0.treatmentDate, interval: $0.x, sleep: $0.y,
                               single: $0.isConfirmedSingle, work: $0.workBeforeSleep, source: $0.source, reported: model.replayPresentation.timingContextBasis == .reported ? $0.reportedNight : nil, usesReported: model.replayPresentation.timingContextBasis == .reported) }
    }
    private var selected: SleepIntervalChartPoint? { points.first { $0.id == model.inspection.selectedObservationID } }
    private var xDomain: ClosedRange<Double> {
        SleepIntervalChartScale.domain(maximum: points.map(\.x).max() ?? 0, focus: focus.map { Double($0.x) }, zoom: zoom, minimumSpan: 50)
    }
    private var yDomain: ClosedRange<Double> {
        SleepIntervalChartScale.domain(maximum: points.map(\.sleep).max() ?? 0, focus: focus.map { Double($0.y) }, zoom: zoom, minimumSpan: 100)
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
                if zoom > 1 {
                    HStack(spacing: 12) {
                        moveButton("Move left", symbol: "arrow.left", dx: -0.25, dy: 0)
                        moveButton("Move right", symbol: "arrow.right", dx: 0.25, dy: 0)
                        moveButton("Move down", symbol: "arrow.down", dx: 0, dy: -0.25)
                        moveButton("Move up", symbol: "arrow.up", dx: 0, dy: 0.25)
                    }.buttonStyle(.bordered)
                    Text(verbatim: "View: spacing \(SleepIntervalChartPoint.number(xDomain.lowerBound))–\(SleepIntervalChartPoint.number(xDomain.upperBound))"
                         + " min · sleep \(SleepIntervalChartPoint.number(yDomain.lowerBound))–\(SleepIntervalChartPoint.number(yDomain.upperBound)) min")
                        .font(.caption).accessibilityIdentifier("dashboard-sleep-viewport")
                    Text("Drag inside the chart to move the zoomed view.").font(.caption)
                }
                Text("Tap a point for minutes; nearby nights open a dated record list. Select a night before Zoom in to focus it. Pinch to zoom; drag to move when zoomed.")
                    .font(.caption).foregroundStyle(.secondary)
                if candidates.count > 1 {
                    Button("Nearby nights: \(candidates.count) · choose a record") { showCandidates = true }
                        .accessibilityIdentifier("dashboard-sleep-overlap-open")
                }
                if showDetails, let selected {
                    Text(selected.label).font(.callout).accessibilityIdentifier("dashboard-sleep-point-details")
                    DisclosureGroup("Exact recorded values") {
                        let exactSpacing: String = selected.interval.map(String.init(describing:)) ?? "Single dose; no interval"
                        Text(verbatim: "Spacing: \(exactSpacing) · Sleep minutes: \(String(selected.sleep))")
                        Text("Observation: " + selected.id)
                        if let report = selected.reported {
                            Text(verbatim: "Morning check-in \(report.recordID) · reported \(ISO8601DateFormatter().string(from: report.reportedAt))")
                        }
                        Text("Reviewed work before sleep: " + selected.work.rawValue)
                    }.font(.caption)
                }
            }
        }.onChange(of: points) { _ in resetView() }
            .onChange(of: model.replayPresentation.timingContextBasis) { _ in resetView() }
            .sheet(isPresented: $showCandidates) {
                NavigationStack {
                    List(points.filter { candidates.contains($0.id) }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }) { point in
                        Button { select(point.id); showCandidates = false } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(point.date).font(.headline)
                                Text(point.label).font(.subheadline)
                                let pointSpacing: String = point.interval.map(String.init(describing:)) ?? "Single dose"
                                Text(verbatim: "Exact spacing: \(pointSpacing) · sleep: \(String(point.sleep)) min")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 6)
                        }.accessibilityIdentifier("dashboard-sleep-overlap-record-" + point.id)
                    }.navigationTitle("Nearby nights")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showCandidates = false } } }
                }
            }
    }
    @ViewBuilder private var zoomButtons: some View {
        Button { changeZoom(min(8, zoom * 2)) } label: { Label("Zoom in", systemImage: "plus.magnifyingglass") }
            .disabled(zoom >= 8).accessibilityIdentifier("dashboard-sleep-zoom-in")
        Button { changeZoom(max(1, zoom / 2)) } label: { Label("Zoom out", systemImage: "minus.magnifyingglass") }
            .disabled(zoom <= 1).accessibilityIdentifier("dashboard-sleep-zoom-out")
        Button("Reset") { resetView() }.disabled(zoom == 1 && candidates.isEmpty)
            .accessibilityIdentifier("dashboard-sleep-zoom-reset")
    }
    private func resetView() {
        zoom = 1; focus = nil; candidates = []; dragRanges = nil; pinchStartZoom = nil; showCandidates = false
    }
    private func changeZoom(_ value: Double) {
        if zoom == 1 {
            let middleX: Double = (xDomain.lowerBound + xDomain.upperBound) / 2
            let middleY: Double = (yDomain.lowerBound + yDomain.upperBound) / 2
            focus = selected.map { CGPoint(x: $0.x, y: $0.sleep) } ?? CGPoint(x: middleX, y: middleY)
        }
        zoom = value
        if zoom == 1 { focus = nil }
    }
    private func moveButton(_ label: String, symbol: String, dx: Double, dy: Double) -> some View {
        Button { pan(x: xDomain, y: yDomain, translation: CGSize(width: -dx, height: dy), size: CGSize(width: 1, height: 1)) } label: {
            Image(systemName: symbol).frame(minWidth: 28, minHeight: 28)
        }.accessibilityLabel(label).accessibilityIdentifier("dashboard-sleep-" + label.lowercased().replacingOccurrences(of: " ", with: "-"))
    }
    private func pan(x: ClosedRange<Double>, y: ClosedRange<Double>, translation: CGSize, size: CGSize) {
        let fullX = SleepIntervalChartScale.domain(maximum: points.map(\.x).max() ?? 0, focus: nil, zoom: 1, minimumSpan: 50)
        let fullY = SleepIntervalChartScale.domain(maximum: points.map(\.sleep).max() ?? 0, focus: nil, zoom: 1, minimumSpan: 100)
        focus = CGPoint(x: SleepIntervalChartScale.panCenter(range: x, bounds: fullX, translation: translation.width, length: size.width),
                        y: SleepIntervalChartScale.panCenter(range: y, bounds: fullY, translation: translation.height, length: size.height, inverted: true))
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
                        let gridWidth: CGFloat = minute.truncatingRemainder(dividingBy: 25) == 0 ? 0.7 : 0.35
                        let labelStep: Double = zoom > 1 ? 25 : 50
                        let tickLabel: String = minute == 0 ? "Single\ndose" : SleepIntervalChartPoint.number(minute)
                        AxisGridLine(stroke: StrokeStyle(lineWidth: gridWidth))
                            .foregroundStyle(Color.secondary.opacity(0.25))
                        if minute >= 0 && minute.truncatingRemainder(dividingBy: labelStep) == 0 {
                            AxisValueLabel { Text(verbatim: tickLabel) }
                        }
                    }
                }
            }.chartYAxis {
                AxisMarks(values: SleepIntervalChartScale.ticks(in: yDomain, step: 25)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.secondary.opacity(0.25))
                    let labelStep: Double = zoom > 1 ? 25 : 100
                    if let minute = value.as(Double.self), minute >= 0,
                       minute.truncatingRemainder(dividingBy: labelStep) == 0 { AxisValueLabel() }
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
                            // Typed steps keep this layout arithmetic within older type-checker limits.
                            let labelWidth: CGFloat = min(110, frame.width)
                            let labelX: CGFloat = min(frame.maxX - labelWidth / 2, frame.minX + target.point.x + 12 + labelWidth / 2)
                            let labelY: CGFloat = max(frame.minY + 8, frame.minY + target.point.y - 12)
                            Text(verbatim: "1 · \(SleepIntervalChartPoint.number(point.sleep)) min")
                                .font(.caption2.bold()).foregroundStyle(color(point))
                                .frame(width: labelWidth, alignment: .leading)
                                .position(x: labelX, y: labelY)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                }.frame(width: geometry.size.width, height: geometry.size.height)
                    .accessibilityElement(children: .contain)
                    .contentShape(SleepIntervalPlotHitArea(frame: frame))
                    .highPriorityGesture(SpatialTapGesture().onEnded { inspect($0.location, frame: frame, targets: targets) })
                    .highPriorityGesture(DragGesture(minimumDistance: 8).onChanged { value in
                        guard zoom > 1, pinchStartZoom == nil, frame.contains(value.startLocation) else { return }
                        if dragRanges == nil { dragRanges = (xDomain, yDomain) }
                        if let ranges = dragRanges { pan(x: ranges.0, y: ranges.1, translation: value.translation, size: frame.size) }
                    }.onEnded { _ in dragRanges = nil }, including: zoom > 1 ? .all : .none)
                    .simultaneousGesture(MagnificationGesture().onChanged { value in
                        guard value.isFinite else { return }
                        if pinchStartZoom == nil { pinchStartZoom = zoom; changeZoom(zoom) }
                        zoom = min(8, max(1, (pinchStartZoom ?? zoom) * value))
                    }.onEnded { _ in pinchStartZoom = nil; dragRanges = nil; if zoom == 1 { focus = nil } })
                    .onContinuousHover { phase in
                        if case .active(let location) = phase { inspect(location, frame: frame, targets: targets, presentChooser: false) }
                    }
            } }
    }
    private func inspect(_ location: CGPoint, frame: CGRect, targets: [DosePatternPresentation.PlotPoint], presentChooser: Bool = true) {
        guard frame.contains(location) else { return }
        candidates = DosePatternPresentation.candidates(at: CGPoint(x: location.x - frame.minX, y: location.y - frame.minY), points: targets)
        if candidates.count == 1, let id = candidates.first { select(id, clearCandidates: false) }
        else if candidates.count > 1 && presentChooser { showCandidates = true }
    }
    private func select(_ id: String, clearCandidates: Bool = true) {
        if let row = rows.first(where: { $0.id == id }) { model.selectReplayID(row.replayID) }
        if clearCandidates { candidates = [] }
    }
    private func color(_ point: SleepIntervalChartPoint) -> Color {
        SleepIntervalChartMarker.spacingColor(interval: point.x, single: point.single, palette: palette)
    }
}

private struct SleepIntervalPlotHitArea: Shape {
    let frame: CGRect
    func path(in rect: CGRect) -> Path { Path(frame) }
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
