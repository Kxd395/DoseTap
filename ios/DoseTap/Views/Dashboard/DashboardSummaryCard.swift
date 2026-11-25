import SwiftUI
#if canImport(Charts)
import Charts
#endif

/// One night reduced to the values the Summary needs. Missing values stay nil;
/// they are never counted as zero.
struct DashboardSummaryNight: Equatable {
    let date: String
    let interval: Double?
    let inWindow: Bool?
    let sleep: Double?
    let single: Bool
}

struct DashboardSummaryTile: Identifiable, Equatable {
    enum Kind: String { case spacing, inWindow, sleep, nights }
    let kind: Kind
    var id: String { kind.rawValue }
    let title: String
    let value: String
    let detail: String
    let change: String?
    /// Chronological values for a sparkline; empty when the tile has none.
    let spark: [Double]
    /// 0–1 share for a meter; nil when the tile has none.
    let share: Double?
}

/// Presentation-only summary of the selected period. Medians are used because
/// one unusual night should not move the headline number.
enum DashboardSummary {
    static func median(_ values: [Double]) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    static func minutes(_ value: Double) -> String { "\(Int(value.rounded())) min" }

    static func duration(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        return total >= 60 ? "\(total / 60) h \(String(format: "%02d", total % 60)) m" : "\(total) m"
    }

    static func signed(_ value: Int, unit: String) -> String {
        value == 0 ? "No change" : (value > 0 ? "+" : "−") + "\(abs(value))" + unit
    }

    static func tiles(current: [DashboardSummaryNight], prior: [DashboardSummaryNight]) -> [DashboardSummaryTile] {
        let chronological = current.sorted { $0.date < $1.date }
        let intervals = chronological.compactMap(\.interval)
        let priorIntervals = prior.compactMap(\.interval)
        let sleeps = chronological.compactMap(\.sleep)
        let priorSleeps = prior.compactMap(\.sleep)
        let classified = chronological.compactMap(\.inWindow)
        let priorClassified = prior.compactMap(\.inWindow)
        let comparison = " vs previous period"

        var tiles: [DashboardSummaryTile] = []

        let spacing = median(intervals)
        tiles.append(.init(
            kind: .spacing, title: "Median spacing",
            value: spacing.map(minutes) ?? "No pairs",
            detail: intervals.isEmpty ? "No Dose 1 → Dose 2 pairs" : "\(intervals.count) dose pairs",
            change: zip2(spacing, median(priorIntervals)).map { signed(Int(($0 - $1).rounded()), unit: " min") + comparison },
            spark: intervals, share: nil))

        let share = classified.isEmpty ? nil : Double(classified.filter { $0 }.count) / Double(classified.count)
        let priorShare = priorClassified.isEmpty ? nil : Double(priorClassified.filter { $0 }.count) / Double(priorClassified.count)
        tiles.append(.init(
            kind: .inWindow, title: "Within 150–240",
            value: share.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
            detail: classified.isEmpty ? "No dose pairs" : "\(classified.filter { $0 }.count) of \(classified.count) pairs",
            change: zip2(share, priorShare).map { signed(Int((($0 - $1) * 100).rounded()), unit: " pts") + comparison },
            spark: [], share: share))

        let sleep = median(sleeps)
        tiles.append(.init(
            kind: .sleep, title: "Median sleep",
            value: sleep.map(duration) ?? "No sleep",
            detail: sleeps.isEmpty ? "No recorded sleep" : "\(sleeps.count) nights with sleep",
            change: zip2(sleep, median(priorSleeps)).map { signed(Int(($0 - $1).rounded()), unit: " min") + comparison },
            spark: sleeps, share: nil))

        let singles = chronological.filter(\.single).count
        tiles.append(.init(
            kind: .nights, title: "Nights logged",
            value: "\(chronological.count)",
            detail: singles == 0 ? "No single-dose nights" : "\(singles) single-dose " + (singles == 1 ? "night" : "nights"),
            change: prior.isEmpty ? nil : signed(chronological.count - prior.count, unit: " nights") + comparison,
            spark: [], share: nil))
        return tiles
    }

    /// Trailing median over up to `window` recorded values, in input order.
    /// Returns nil entries until at least `minimum` values are available.
    static func rollingMedian(_ values: [Double], window: Int = 14, minimum: Int = 3) -> [Double?] {
        values.indices.map { index in
            let slice = Array(values[max(0, index - window + 1)...index])
            return slice.count >= minimum ? median(slice) : nil
        }
    }

    private static func zip2(_ a: Double?, _ b: Double?) -> (Double, Double)? {
        guard let a, let b else { return nil }
        return (a, b)
    }
}

extension DashboardAnalyticsModel {
    func summaryNight(_ night: DashboardNightAggregate) -> DashboardSummaryNight {
        DashboardSummaryNight(date: night.sessionDate, interval: night.exactIntervalMinutes,
                              inWindow: night.onTimeDosing, sleep: sleepMinutes(for: night),
                              single: night.dose1Time != nil && night.dose2Time == nil && night.dose2Skipped)
    }
    var summaryTiles: [DashboardSummaryTile] {
        DashboardSummary.tiles(current: dosingNights.map(summaryNight), prior: priorPeriodNights
            .filter { $0.dose1Time != nil || $0.dose2Time != nil || $0.dose2Skipped }.map(summaryNight))
    }
}

struct DashboardSummaryCard: View {
    @ObservedObject var model: DashboardAnalyticsModel
    @Environment(\.dashboardPalette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.isLoading && model.populatedNights.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No session or provider observations in this range").font(.headline)
                    Text("Choose a wider range, record a night from Tonight, or Refresh connected sleep sources.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("dashboard-summary-empty")
            } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top),
                                     count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                ForEach(model.summaryTiles) { tile in
                    DashboardSummaryTileView(tile: tile)
                }
            }
            #if canImport(Charts)
            DashboardSpacingOverTimeChart(model: model)
            #endif
            }
        }
        .accessibilityIdentifier("dashboard-summary")
    }
}

struct DashboardSummaryTileView: View {
    let tile: DashboardSummaryTile
    @Environment(\.dashboardPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title and value read as one item; detail lines follow separately.
            VStack(alignment: .leading, spacing: 4) {
                Text(tile.title).font(.caption).foregroundStyle(.secondary)
                Text(tile.value).font(.title2.weight(.semibold)).monospacedDigit()
                    .minimumScaleFactor(0.8).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("dashboard-summary-\(tile.id)-value")
            if tile.spark.count >= 2 {
                DashboardSparkline(values: tile.spark, color: palette.timing).frame(height: 22)
                    .accessibilityHidden(true)
            } else if let share = tile.share {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.2))
                        Capsule().fill(palette.timing).frame(width: geo.size.width * share)
                    }
                }.frame(height: 6).padding(.vertical, 8).accessibilityHidden(true)
            }
            Text(tile.detail).font(.caption).foregroundStyle(.secondary)
            if let change = tile.change {
                Text(change).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard-summary-" + tile.id)
    }
}

/// Minimal line without axes; the tile text carries the numbers.
struct DashboardSparkline: View {
    let values: [Double]
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let low = values.min() ?? 0, high = values.max() ?? 1
            let span = max(high - low, 1)
            Path { path in
                for (index, value) in values.enumerated() {
                    let x = geo.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                    let y = geo.size.height * (1 - CGFloat((value - low) / span))
                    index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                }
            }.stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

#if canImport(Charts)
/// Dose spacing per night over the selected period, with the 150–240 reference
/// band, the current target setting and a 14-night trailing median.
struct DashboardSpacingOverTimeChart: View {
    @ObservedObject var model: DashboardAnalyticsModel
    @Environment(\.dashboardPalette) private var palette
    @State private var selectedDate: String?

    struct Point: Identifiable {
        let date: Date, key: String, interval: Double, inWindow: Bool, median: Double?
        var id: String { key }
    }

    private var nights: [DashboardSummaryNight] {
        model.dosingNights.map(model.summaryNight).sorted { $0.date < $1.date }
    }
    private var points: [Point] {
        let paired = nights.filter { $0.interval != nil }
        let medians = DashboardSummary.rollingMedian(paired.compactMap(\.interval))
        return zip(paired, medians).compactMap { night, median in
            guard let interval = night.interval, let date = AppFormatters.sessionDate.date(from: night.date) else { return nil }
            return Point(date: date, key: night.date, interval: interval, inWindow: night.inWindow ?? false, median: median)
        }
    }
    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.interval)
        let low = floor(min(values.min() ?? 150, 150) / 30) * 30 - 15
        let high = ceil(max(values.max() ?? 240, 240) / 30) * 30 + 15
        return low...high
    }
    private var target: Double? {
        let value = Double(UserSettingsManager.shared.targetIntervalMinutes)
        return (150...240).contains(value) ? value : nil
    }
    private var singleCount: Int { nights.filter(\.single).count }
    private var selected: Point? { points.first { $0.key == selectedDate } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dose spacing over time").font(.headline)
            if points.count < 2 {
                Text("Spacing over time appears after two nights with Dose 1 and Dose 2 recorded.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                chart.frame(height: 200)
                if let selected {
                    Text(selected.key + " · " + DashboardSummary.minutes(selected.interval)
                         + (selected.median.map { " · 14-night median " + DashboardSummary.minutes($0) } ?? ""))
                        .font(.callout.weight(.semibold)).monospacedDigit()
                        .accessibilityIdentifier("dashboard-spacing-time-readout")
                }
                Text(legend).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("dashboard-spacing-over-time")
    }

    private var legend: String {
        var text = "Dots: each night. Line: 14-night median. Band: 150–240 min reference."
        if target != nil { text += " Dashed: your current target." }
        if singleCount > 0 {
            text += " \(singleCount) single-dose " + (singleCount == 1 ? "night has" : "nights have") + " no spacing and " + (singleCount == 1 ? "is" : "are") + " not shown."
        }
        return text
    }

    private var chart: some View {
        Chart {
            RectangleMark(yStart: .value("Reference start", 150), yEnd: .value("Reference end", 240))
                .foregroundStyle(palette.timing.opacity(palette.isNight ? 0.16 : 0.09))
            if let target {
                RuleMark(y: .value("Target", target))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
            ForEach(points) { point in
                PointMark(x: .value("Night", point.date, unit: .day), y: .value("Spacing", point.interval))
                    .symbolSize(point.key == selectedDate ? 70 : 28)
                    .foregroundStyle(SleepIntervalChartMarker.spacingColor(interval: point.interval, palette: palette)
                        .opacity(point.key == selectedDate || selectedDate == nil ? 1 : 0.55))
            }
            ForEach(points.filter { $0.median != nil }) { point in
                LineMark(x: .value("Night", point.date, unit: .day), y: .value("Median", point.median ?? 0))
                    .foregroundStyle(palette.chart(Color.primary, warmth: 1))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(values: SleepIntervalChartScale.ticks(in: yDomain, step: 30)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.secondary.opacity(0.22))
                if let minute = value.as(Double.self), minute.truncatingRemainder(dividingBy: 60) == 0 { AxisValueLabel() }
            }
        }
        .chartYAxisLabel("min")
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { value in
                        let frame = geometry[proxy.plotAreaFrame]
                        guard let date: Date = proxy.value(atX: value.location.x - frame.minX) else { return }
                        let nearest = points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
                        selectedDate = nearest?.key == selectedDate ? nil : nearest?.key
                    })
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dose spacing over time")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard let first = points.first, let last = points.last else { return "" }
        let latestMedian = points.last(where: { $0.median != nil })?.median
        return "\(points.count) nights from \(first.key) to \(last.key)."
            + (latestMedian.map { " Latest 14-night median " + DashboardSummary.minutes($0) + "." } ?? "")
    }
}
#endif
