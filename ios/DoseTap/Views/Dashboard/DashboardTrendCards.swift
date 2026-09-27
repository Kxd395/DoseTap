import SwiftUI
import Charts
import DoseCore

enum DashboardTrendMode: String, CaseIterable, Identifiable {
    case intervalVsSleep = "Interval vs Sleep"
    case recoveryTrend = "Recovery Trend"
    case cohorts = "Cohorts"
    case weekday = "Weekday"

    var id: String { rawValue }
}

struct DashboardTrendChartsCard: View {
    @Environment(\.dashboardPalette) private var palette
    @ObservedObject var model: DashboardAnalyticsModel
    @State private var trendMode: DashboardTrendMode = .intervalVsSleep

    private struct IntervalSleepPoint: Identifiable {
        let id: String
        let intervalMinutes: Double
        let sleepMinutes: Double
        let onTime: Bool
    }

    private struct RecoveryPoint: Identifiable {
        var id: Date { date }
        let date: Date
        let recovery: Double
        let hrv: Double?
    }

    private var recoveryTrendPoints: [RecoveryPoint] {
        model.whoopNights
            .compactMap { night -> RecoveryPoint? in
                guard let recovery = night.whoopRecoveryScore,
                      let date = AppFormatters.sessionDate.date(from: night.sessionDate)
                else { return nil }
                return RecoveryPoint(date: date, recovery: recovery, hrv: night.whoopHRV)
            }
            .sorted { $0.date < $1.date }
    }

    private var trendColorLegend: String {
        switch trendMode {
        case .intervalVsSleep:
            return (palette.isNight ? "Circles: inside; diamonds: outside. " : "Green circles: inside; orange diamonds: outside. ")
                + "Built-in recorded-spacing reference: 150–240 minutes inclusive, not a historical prescription."
        case .recoveryTrend:
            return palette.isNight ? "WHOOP recovery ranges use labeled symbols: 67–100, 34–66, below 34."
                : "WHOOP recovery: green 67–100, yellow/orange 34–66, red below 34. Symbols also identify ranges."
        case .cohorts:
            return palette.isNight ? "Bars are labeled Screens and No screens; these identify groups, not better sleep."
                : "Indigo: screens. Green: no screens. Colors identify groups, not better sleep."
        case .weekday:
            return "Recorded pairs within the built-in 150–240 minute inclusive reference, by weekday; not a historical prescription."
        }
    }

    private var intervalSleepPoints: [IntervalSleepPoint] {
        model.populatedNights.compactMap { night in
            guard let interval = night.exactIntervalMinutes, let sleep = model.sleepMinutes(for: night) else { return nil }
            return IntervalSleepPoint(id: night.sessionDate, intervalMinutes: Double(interval), sleepMinutes: sleep, onTime: night.onTimeDosing ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Interactive Trends")
                    .font(.headline)
                Spacer()
                Picker("Trend", selection: $trendMode) {
                    ForEach(DashboardTrendMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("dashboard-trend-picker")
            }

            #if canImport(Charts)
            chartBody
                .frame(height: 220)
            Text(trendColorLegend).font(.caption).foregroundColor(.secondary)
            if trendMode == .weekday {
                Text(model.weekdayTimingValues.map { "\($0.name): n=\($0.count)" }.joined(separator: " · "))
                    .font(.caption).foregroundColor(.secondary)
            }
            #else
            Text("Charts are unavailable on this platform build.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }

    #if canImport(Charts)
    @ViewBuilder
    private var chartBody: some View {
        switch trendMode {
        case .intervalVsSleep:
            if intervalSleepPoints.isEmpty {
                emptyChartState("Need nights with both interval and sleep data.")
            } else {
                Chart(intervalSleepPoints) { point in
                    PointMark(
                        x: .value("Interval (min)", point.intervalMinutes),
                        y: .value("Total Sleep (min)", point.sleepMinutes)
                    )
                    .foregroundStyle(palette.chart(point.onTime ? .green : .orange))
                    .symbol(by: .value("Recorded spacing", point.onTime ? "Inside reference" : "Outside reference"))
                }
                .chartSymbolScale(["Inside reference": BasicChartSymbolShape.circle, "Outside reference": .diamond])
                .chartXAxisLabel("Dose interval (minutes)")
                .accessibilityLabel("\(intervalSleepPoints.count) recorded pairs with \(model.sleepSource.rawValue) sleep")
                .chartYAxisLabel("Sleep Minutes")
            }

        case .recoveryTrend:
            let points = recoveryTrendPoints
            if points.isEmpty {
                emptyChartState("Need WHOOP recovery data. Connect WHOOP in Settings → Integrations.")
            } else {
                Chart {
                    ForEach(points) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Recovery %", point.recovery)
                        )
                        .foregroundStyle(palette.chart(.green))
                        .interpolationMethod(.linear)

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Recovery %", point.recovery)
                        )
                        .foregroundStyle(palette.recovery(point.recovery))
                        .symbol(by: .value("Recovery range", point.recovery >= 67 ? "67–100" : point.recovery >= 34 ? "34–66" : "Below 34"))
                        .symbolSize(30)
                    }

                    RuleMark(y: .value("Green Zone", 67))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(palette.chart(.green).opacity(palette.isNight ? 0.8 : 0.4))
                }
                .chartSymbolScale(["67–100": BasicChartSymbolShape.circle, "34–66": .square, "Below 34": .triangle])
                .chartYScale(domain: 0...100)
                .chartYAxisLabel("Recovery %")
            }

        case .cohorts:
            let values = model.screenSleepValues
            if values.isEmpty {
                emptyChartState("Need pre-sleep screen/no-screen data with sleep totals.")
            } else {
                Chart(values) { entry in
                    BarMark(
                        x: .value("Cohort", entry.name),
                        y: .value("Avg Sleep (min)", entry.value)
                    )
                    .foregroundStyle(palette.chart(entry.name == "No screens" ? .green : .indigo))
                    .annotation(position: .top) { Text("n=\(entry.count)").font(.caption) }
                }
                .chartYAxisLabel("Avg Sleep Minutes")
            }

        case .weekday:
            if model.weekdayTimingValues.isEmpty {
                emptyChartState("Need completed dose intervals to compute on-time weekdays.")
            } else {
                Chart(model.weekdayTimingValues) { entry in
                    BarMark(
                        x: .value("Weekday", entry.name),
                        y: .value("Recorded On-Time %", entry.value)
                    )
                    .foregroundStyle(palette.timing.gradient)
                    .annotation(position: .top) { Text("\(Int(entry.value.rounded()))%").font(.caption2) }
                }
                .chartYScale(domain: 0...100)
                .chartYAxisLabel("Recorded On-Time %")
            }
        }
    }

    private func emptyChartState(_ text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.title3)
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    #endif


}

struct DashboardRecentNightsCard: View {
    @Environment(\.dashboardPalette) private var palette
    let nights: [DashboardNightAggregate]
    var onResolveDuplicateGroup: (StoredEventDuplicateGroup) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent Nights · up to 14")
                    .font(.headline)
                Spacer()
                CurrentTimeZoneSummaryView(compact: true)
            }

            if nights.isEmpty {
                Text("No nights with dashboard data yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(nights) { night in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(shortDate(night.sessionDate)).font(.subheadline.bold())
                        Text("Dose timing: \(intervalText(night))").font(.callout).foregroundColor(palette.timing)
                        Text(sleepText(night)).font(.caption).foregroundColor(night.appleHealthSleepMinutes == nil && night.whoopSleepMinutes == nil ? .secondary : palette.sleep)
                        if let recovery = night.whoopRecoveryScore {
                            Text("WHOOP recovery: \(Int(recovery))%").font(.caption).foregroundColor(palette.recovery(recovery))
                        }
                        Text("Coverage: \(night.dataCategoryCount)/4 categories")
                            .font(.caption).foregroundColor(palette.coverage)
                        let duplicates = buildStoredEventDuplicateGroups(events: night.events)
                        if let firstGroup = duplicates.first {
                            Button {
                                onResolveDuplicateGroup(firstGroup)
                            } label: {
                                Label("\(duplicates.count)", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Resolve duplicates for \(night.sessionDate)")
                        }
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .contain)
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }

    private func shortDate(_ sessionDate: String) -> String {
        guard let date = AppFormatters.sessionDate.date(from: sessionDate) else { return sessionDate }
        return AppFormatters.shortDate.string(from: date)
    }

    private func intervalText(_ night: DashboardNightAggregate) -> String {
        if night.dose2Skipped && night.dose2Time == nil {
            return "Skipped"
        }
        if let interval = night.intervalMinutes {
            return TimeIntervalMath.formatMinutes(interval)
        }
        if night.dose1Time != nil {
            return night.isPendingDose2(at: Date()) ? "Dose 2 pending" : "Dose 2 not recorded"
        }
        return "No dose data"
    }

    private func sleepText(_ night: DashboardNightAggregate) -> String {
        var values: [String] = []
        if let minutes = night.appleHealthSleepMinutes { values.append("Apple Health: \(TimeIntervalMath.formatMinutes(Int(minutes.rounded())))") }
        if let minutes = night.whoopSleepMinutes { values.append("WHOOP: \(TimeIntervalMath.formatMinutes(Int(minutes.rounded())))") }
        return values.isEmpty ? "No sleep data" : values.joined(separator: " • ")
    }
}

struct DashboardPeriodComparisonCard: View {
    @Environment(\.dashboardPalette) private var palette
    @ObservedObject var model: DashboardAnalyticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("vs. Prior \(model.selectedRange.label)")
                    .font(.headline)
                Spacer()
                Text("\(model.priorPeriodNights.count) prior nights")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("Changes versus the preceding equal-length period: rate in percentage points (pp), other metrics in relative percent. Missing values are excluded; increases are not automatically improvements. Sleep: \(model.sleepSource.rawValue).")
                .font(.caption).foregroundColor(.secondary)
            ForEach(model.periodComparison, id: \.metricName) { delta in
                VStack(alignment: .leading, spacing: 6) {
                    Text(delta.metricName).font(.subheadline.bold())
                    Text("Current: \(delta.current.map { formatValue(delta.metricName, $0) } ?? "No data") · Prior: \(delta.prior.map { formatValue(delta.metricName, $0) } ?? "No data")")
                        .font(.subheadline).foregroundColor(comparisonColor(delta.metricName))
                    Text(delta.delta.map { String(format: "%+.0f", $0) + " " + delta.deltaUnit } ?? (delta.isNew ? "From a zero baseline" : "Change unavailable"))
                        .font(.caption.bold())
                        .foregroundColor(comparisonColor(delta.metricName))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(comparisonColor(delta.metricName).opacity(0.15)))
                }.accessibilityElement(children: .combine)
                Divider()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }

    private func comparisonColor(_ name: String) -> Color {
        ["Avg Sleep", "Sleep Quality", "Recovery", "HRV"].contains(name) ? palette.sleep : palette.timing
    }

    private func formatValue(_ name: String, _ value: Double) -> String {
        switch name {
        case "Recorded On-Time %": return String(format: "%.0f%%", value)
        case "Avg Interval": return TimeIntervalMath.formatMinutes(Int(value.rounded()))
        case "Avg Sleep": return TimeIntervalMath.formatMinutes(Int(value.rounded()))
        case "Recovery": return String(format: "%.0f%%", value)
        case "HRV": return String(format: "%.1f ms", value)
        case "Sleep Quality": return String(format: "%.1f / 5", value)
        default: return String(format: "%.1f", value)
        }
    }

}
