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
    /// Full chart ranges fitted to the recorded values. The spacing axis always
    /// shows the 150–240 minute reference; single-dose nights get their own
    /// column left of the spacing axis instead of sitting at a fake 0 minutes.
    struct Fitted: Equatable {
        let x: ClosedRange<Double>
        let y: ClosedRange<Double>
        let singleColumnX: Double?
        let spacingStart: Double
        var dividerX: Double? { singleColumnX.map { ($0 + spacingStart) / 2 } }
    }
    static func fitted(intervals: [Double], sleeps: [Double], hasSingle: Bool) -> Fitted {
        let intervals = intervals.filter { $0.isFinite && $0 >= 0 && $0 < 1e6 }
        let sleeps = sleeps.filter { $0.isFinite && $0 >= 0 && $0 < 1e6 }
        let spacingStart = floor(min(intervals.min() ?? 150, 150) / 30) * 30
        let spacingEnd = ceil(max(intervals.max() ?? 240, 240) / 30) * 30
        let singleX: Double? = hasSingle ? spacingStart - 40 : nil
        let xLower = (singleX.map { $0 - 20 }) ?? spacingStart - 10
        var sleepLow = floor((sleeps.min() ?? 360) / 60) * 60
        var sleepHigh = ceil((sleeps.max() ?? 480) / 60) * 60
        if sleepHigh - sleepLow < 120 { sleepLow = max(0, sleepLow - 60); sleepHigh = sleepLow + max(120, sleepHigh - sleepLow) }
        return Fitted(x: xLower...(spacingEnd + 10), y: (sleepLow - 15)...(sleepHigh + 15),
                      singleColumnX: singleX, spacingStart: spacingStart)
    }
    static func hourLabel(_ minutes: Double) -> String {
        let hours = minutes / 60
        return hours == hours.rounded() ? "\(Int(hours)) h" : String(format: "%.1f h", hours)
    }
    static func plotX(_ point: SleepIntervalChartPoint, fitted: Fitted) -> Double {
        point.single ? fitted.singleColumnX ?? 0 : point.x
    }
    /// Plain duration for readouts: "2 h 46 m", "45 m".
    static func duration(_ minutes: Double) -> String {
        guard minutes.isFinite else { return "—" }
        let total = Int(minutes.rounded())
        return total >= 60 ? "\(total / 60) h \(String(format: "%02d", total % 60)) m" : "\(total) m"
    }
    static func panCenter(range: ClosedRange<Double>, bounds: ClosedRange<Double>, translation: Double,
                          length: Double, inverted: Bool = false) -> Double {
        let center = (range.lowerBound + range.upperBound) / 2
        guard translation.isFinite, length.isFinite, length > 0 else { return center }
        let half = (range.upperBound - range.lowerBound) / 2
        let shifted = center + (inverted ? 1 : -1) * translation / length * half * 2
        return min(bounds.upperBound - half, max(bounds.lowerBound + half, shifted))
    }
    /// With `minimum`, the full view runs from `minimum` to `maximum` exactly
    /// (see `fitted`); without it, the legacy zero-anchored view is used.
    static func domain(maximum: Double, focus: Double?, zoom: Double, minimumSpan: Double,
                       minimum: Double? = nil) -> ClosedRange<Double> {
        let maximum = maximum.isFinite ? min(1e9, max(0, maximum)) : 0
        let lower: Double, upper: Double
        if let minimum, minimum.isFinite, minimum < maximum {
            lower = minimum; upper = max(maximum, minimum + minimumSpan)
        } else {
            upper = max(minimumSpan, ceil(maximum / 25) * 25 + 25); lower = -12.5
        }
        let fullSpan = upper - lower
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
    @State private var focus: CGPoint?
    @State private var dragRanges: (ClosedRange<Double>, ClosedRange<Double>)?
    @State private var pinchStartZoom: Double?
    @State private var showCandidates = false
    private var points: [SleepIntervalChartPoint] {
        rows.compactMap { .init(id: $0.id, date: $0.treatmentDate, interval: $0.x, sleep: $0.y,
                               single: $0.isConfirmedSingle, work: $0.workBeforeSleep, source: $0.source, reported: model.replayPresentation.timingContextBasis == .reported ? $0.reportedNight : nil, usesReported: model.replayPresentation.timingContextBasis == .reported) }
    }
    private var selected: SleepIntervalChartPoint? { points.first { $0.id == model.inspection.selectedObservationID } }
    private var fitted: SleepIntervalChartScale.Fitted {
        SleepIntervalChartScale.fitted(intervals: points.compactMap(\.interval), sleeps: points.map(\.sleep),
                                       hasSingle: points.contains(where: \.single))
    }
    private func plotX(_ point: SleepIntervalChartPoint) -> Double { SleepIntervalChartScale.plotX(point, fitted: fitted) }
    private func fullDomain(_ range: ClosedRange<Double>, focus: Double?, minimumSpan: Double) -> ClosedRange<Double> {
        SleepIntervalChartScale.domain(maximum: range.upperBound, focus: focus, zoom: zoom, minimumSpan: minimumSpan, minimum: range.lowerBound)
    }
    private var xDomain: ClosedRange<Double> { fullDomain(fitted.x, focus: focus.map { Double($0.x) }, minimumSpan: 50) }
    private var yDomain: ClosedRange<Double> { fullDomain(fitted.y, focus: focus.map { Double($0.y) }, minimumSpan: 100) }
    /// Current setting, shown as a reference line; not a historical prescription.
    private var targetMinutes: Double? {
        let value = Double(UserSettingsManager.shared.targetIntervalMinutes)
        return (150...240).contains(value) ? value : nil
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
                    Text("View: spacing " + SleepIntervalChartPoint.number(xDomain.lowerBound) + "–" + SleepIntervalChartPoint.number(xDomain.upperBound)
                         + " min · sleep " + SleepIntervalChartPoint.number(yDomain.lowerBound) + "–" + SleepIntervalChartPoint.number(yDomain.upperBound) + " min")
                        .font(.caption).accessibilityIdentifier("dashboard-sleep-viewport")
                    Text("Drag inside the chart to move the zoomed view.").font(.caption)
                }
                Text("Tap a point to see that night. Pinch or use Zoom to look closer.")
                    .font(.caption).foregroundStyle(.secondary)
                if candidates.count > 1 {
                    Button("Nearby nights: \(candidates.count) · choose a record") { showCandidates = true }
                        .accessibilityIdentifier("dashboard-sleep-overlap-open")
                }
                if showDetails, let selected {
                    SleepIntervalReadout(point: selected)
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
                                Text("Exact spacing: " + (point.interval.map(String.init(describing:)) ?? "Single dose") + " · sleep: " + String(point.sleep) + " min")
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
            focus = selected.map { CGPoint(x: plotX($0), y: $0.sleep) }
                ?? CGPoint(x: (xDomain.lowerBound + xDomain.upperBound) / 2, y: (yDomain.lowerBound + yDomain.upperBound) / 2)
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
        let fullX = fitted.x, fullY = fitted.y
        focus = CGPoint(x: SleepIntervalChartScale.panCenter(range: x, bounds: fullX, translation: translation.width, length: size.width),
                        y: SleepIntervalChartScale.panCenter(range: y, bounds: fullY, translation: translation.height, length: size.height, inverted: true))
    }
    private var plot: some View {
        Chart {
            RectangleMark(xStart: .value("Reference start", 150), xEnd: .value("Reference end", 240))
                .foregroundStyle(palette.timing.opacity(palette.isNight ? 0.16 : 0.09))
                .annotation(position: .overlay, alignment: .top, spacing: 4) {
                    Text("150–240").font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
                }
                .accessibilityHidden(true)
            if let target = targetMinutes {
                RuleMark(x: .value("Your target", target))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.7))
                    .accessibilityHidden(true)
            }
            if let divider = fitted.dividerX {
                RuleMark(x: .value("Single-dose column", divider))
                    .lineStyle(StrokeStyle(lineWidth: 0.8))
                    .foregroundStyle(Color.secondary.opacity(0.45))
                    .accessibilityHidden(true)
            }
            ForEach(points) { point in
            PointMark(x: .value("Spacing", plotX(point)), y: .value("Sleep", point.sleep))
                .symbol { SleepIntervalChartMarker(work: point.work, color: color(point), reported: point.reported, usesReported: model.replayPresentation.timingContextBasis == .reported, selected: point.id == selected?.id) }
                .foregroundStyle(color(point))
                .accessibilityHidden(true)
            }
        }.chartXScale(domain: xDomain).chartYScale(domain: yDomain)
            .chartPlotStyle { $0.clipped() }
            .chartXAxisLabel("Dose 1 → Dose 2 spacing (min)")
            .chartYAxisLabel("Sleep (h)")
            .chartXAxis {
                AxisMarks(values: xTicks) { value in
                    if let minute = value.as(Double.self) {
                        if minute == fitted.singleColumnX {
                            AxisValueLabel { Text("Single") }
                        } else {
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.secondary.opacity(0.22))
                            // No label at the right edge, where it would be cut to "…".
                            if minute.truncatingRemainder(dividingBy: xLabelStep) == 0, minute <= xDomain.upperBound - 15 {
                                AxisValueLabel { Text(SleepIntervalChartPoint.number(minute)) }
                            }
                        }
                    }
                }
            }.chartYAxis {
                AxisMarks(values: SleepIntervalChartScale.ticks(in: yDomain, step: zoom > 1 ? 30 : 60)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.secondary.opacity(0.22))
                    if let minute = value.as(Double.self), minute >= 0 {
                        AxisValueLabel { Text(SleepIntervalChartScale.hourLabel(minute)) }
                    }
                }
            }.accessibilityIdentifier("dashboard-interval-points")
            .chartOverlay { proxy in GeometryReader { geometry in
                let frame = geometry[proxy.plotAreaFrame]
                let targets: [DosePatternPresentation.PlotPoint] = points.compactMap { point in
                    guard xDomain.contains(plotX(point)), yDomain.contains(point.sleep),
                          let x = proxy.position(forX: plotX(point)), let y = proxy.position(forY: point.sleep) else { return nil }
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
    /// Spacing gridlines every 30 minutes from the start of the spacing axis,
    /// plus the single-dose column position.
    private var xTicks: [Double] {
        let spacing = SleepIntervalChartScale.ticks(in: max(fitted.spacingStart, xDomain.lowerBound)...max(fitted.spacingStart, xDomain.upperBound), step: 30)
        return (fitted.singleColumnX.map { xDomain.contains($0) ? [$0] : [] } ?? []) + spacing
    }
    private var xLabelStep: Double { (xDomain.upperBound - xDomain.lowerBound) > 240 ? 60 : 30 }
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
    /// Two spacing states plus a neutral single-dose color. Position already
    /// says whether a night is below or above the reference, so color only
    /// separates "inside 150–240" from "outside". In Night Mode the states
    /// differ in brightness, which survives the red filter.
    static func spacingColor(interval: Double, single: Bool = false, palette: DashboardPalette) -> Color {
        if single { return palette.chart(DashboardPalette.neutralSeries, warmth: 0.55) }
        if interval < 150 || interval > 240 { return palette.chart(DashboardPalette.secondarySeries, warmth: 0.3) }
        return palette.chart(DashboardPalette.primarySeries)
    }
    var body: some View {
        ZStack {
            Image(systemName: symbol + ".fill").foregroundStyle(color)
            Image(systemName: symbol).foregroundStyle(Color.primary.opacity(selected ? 0.95 : 0.55))
        }.rotationEffect(.degrees(usesReported && reported?.type == .transitionOutOfWorkBlock ? 180 : 0))
            .font(.system(size: selected ? 16 : 11, weight: selected ? .bold : .regular))
            .frame(width: selected ? 18 : 13, height: selected ? 18 : 13)
            .accessibilityHidden(true)
    }
}

/// Short readout for the tapped night: values people read, not record IDs.
struct SleepIntervalReadout: View {
    let point: SleepIntervalChartPoint
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(point.date).font(.subheadline.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                value(point.single ? "Dose 2" : "Spacing",
                      point.interval.map { SleepIntervalChartScale.duration($0) } ?? "Single dose")
                value("Sleep", SleepIntervalChartScale.duration(point.sleep))
            }
            Text(Self.context(point) + " · " + point.source)
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dashboard-sleep-point-details")
    }
    private func value(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(text).font(.title3.weight(.semibold)).monospacedDigit()
        }
    }
    static func context(_ point: SleepIntervalChartPoint) -> String {
        if point.usesReported { return "Morning report: " + (point.reported?.label ?? "no usable check-in") }
        switch point.work {
        case .work: return "Work before sleep"
        case .off: return "Off day"
        case .unknown: return "Work not reviewed"
        }
    }
}
