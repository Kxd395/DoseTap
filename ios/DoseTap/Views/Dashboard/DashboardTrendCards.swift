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
    @ObservedObject var model: DashboardAnalyticsModel
    @State private var trendMode: DashboardTrendMode = .intervalVsSleep

    private struct IntervalSleepPoint: Identifiable {
        let id = UUID()
        let intervalMinutes: Double
        let sleepMinutes: Double
        let onTime: Bool
    }

    private struct NamedValue: Identifiable {
        let id = UUID()
        let name: String
        let value: Double
    }

    private struct RecoveryPoint: Identifiable {
        let id = UUID()
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

    private var intervalSleepPoints: [IntervalSleepPoint] {
        model.populatedNights.compactMap { night in
            guard let interval = night.intervalMinutes, let sleep = night.totalSleepMinutes else { return nil }
            return IntervalSleepPoint(intervalMinutes: Double(interval), sleepMinutes: sleep, onTime: night.onTimeDosing ?? false)
        }
    }

    private var cohortSleepValues: [NamedValue] {
        let withScreens = model.populatedNights.filter {
            guard let screens = $0.preSleepLog?.answers?.screensInBed else { return false }
            return screens != .none && $0.totalSleepMinutes != nil
        }
        let withoutScreens = model.populatedNights.filter {
            guard let screens = $0.preSleepLog?.answers?.screensInBed else { return false }
            return screens == .none && $0.totalSleepMinutes != nil
        }
        let withAvg = averageSleep(for: withScreens)
        let withoutAvg = averageSleep(for: withoutScreens)
        return [
            NamedValue(name: "Screens", value: withAvg),
            NamedValue(name: "No Screens", value: withoutAvg)
        ]
    }

    private var weekdayOnTimeValues: [NamedValue] {
        let calendar = Calendar.current
        let weekdaySymbols = calendar.shortWeekdaySymbols

        var buckets: [Int: [Bool]] = [:]
        for night in model.populatedNights {
            guard let onTime = night.onTimeDosing,
                  let date = AppFormatters.sessionDate.date(from: night.sessionDate)
            else { continue }
            let weekday = calendar.component(.weekday, from: date)
            buckets[weekday, default: []].append(onTime)
        }

        return (1...7).map { weekday in
            let values = buckets[weekday] ?? []
            let ratio = values.isEmpty ? 0 : (Double(values.filter { $0 }.count) / Double(values.count)) * 100
            return NamedValue(name: weekdaySymbols[weekday - 1], value: ratio)
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
            }

            #if canImport(Charts)
            chartBody
                .frame(height: 220)
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
                    .foregroundStyle(point.onTime ? .green : .orange)
                }
                .chartXAxisLabel("Dose Interval")
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
                        .foregroundStyle(.green)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Recovery %", point.recovery)
                        )
                        .foregroundStyle(point.recovery >= 67 ? .green : point.recovery >= 34 ? .orange : .red)
                        .symbolSize(30)
                    }

                    RuleMark(y: .value("Green Zone", 67))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.green.opacity(0.4))
                }
                .chartYScale(domain: 0...100)
                .chartYAxisLabel("Recovery %")
            }

        case .cohorts:
            let values = cohortSleepValues
            if values.allSatisfy({ $0.value <= 0 }) {
                emptyChartState("Need pre-sleep screen/no-screen data with sleep totals.")
            } else {
                Chart(values) { entry in
                    BarMark(
                        x: .value("Cohort", entry.name),
                        y: .value("Avg Sleep (min)", entry.value)
                    )
                    .foregroundStyle(entry.name == "No Screens" ? .green : .indigo)
                }
                .chartYAxisLabel("Avg Sleep Minutes")
            }

        case .weekday:
            if weekdayOnTimeValues.allSatisfy({ $0.value == 0 }) {
                emptyChartState("Need completed dose intervals to compute on-time weekdays.")
            } else {
                Chart(weekdayOnTimeValues) { entry in
                    BarMark(
                        x: .value("Weekday", entry.name),
                        y: .value("On-Time %", entry.value)
                    )
                    .foregroundStyle(.blue.gradient)
                }
                .chartYScale(domain: 0...100)
                .chartYAxisLabel("On-Time %")
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

    private func averageSleep(for nights: [DashboardNightAggregate]) -> Double {
        let values = nights.compactMap(\.totalSleepMinutes)
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}

struct DashboardRecentNightsCard: View {
    let nights: [DashboardNightAggregate]
    var onResolveDuplicateGroup: (StoredEventDuplicateGroup) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Night Aggregates")
                .font(.headline)

            if nights.isEmpty {
                Text("No nights with dashboard data yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(nights) { night in
                    HStack(spacing: 10) {
                        Text(shortDate(night.sessionDate))
                            .font(.caption.bold())
                            .frame(width: 58, alignment: .leading)

                        Text(intervalText(night))
                            .font(.caption)
                            .foregroundColor(night.onTimeDosing == true ? .green : .secondary)
                            .frame(width: 88, alignment: .leading)

                        Text(sleepText(night))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 84, alignment: .leading)

                        if let recovery = night.whoopRecoveryScore {
                            Text("\(Int(recovery))%")
                                .font(.caption2.bold())
                                .foregroundColor(recovery >= 67 ? .green : recovery >= 34 ? .orange : .red)
                                .frame(width: 36, alignment: .leading)
                        }

                        Text("Q \(Int((night.dataCompletenessScore * 100).rounded()))%")
                            .font(.caption2)
                            .foregroundColor(night.dataCompletenessScore >= 0.75 ? .green : .orange)
                            .frame(width: 50, alignment: .leading)

                        Spacer()

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
                    .padding(.vertical, 2)
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
        if night.dose2Skipped {
            return "Skipped"
        }
        if let interval = night.intervalMinutes {
            return TimeIntervalMath.formatMinutes(interval)
        }
        return "No interval"
    }

    private func sleepText(_ night: DashboardNightAggregate) -> String {
        guard let totalSleepMinutes = night.totalSleepMinutes else { return "No sleep data" }
        return TimeIntervalMath.formatMinutes(Int(totalSleepMinutes.rounded()))
    }
}

struct DashboardPeriodComparisonCard: View {
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

            ForEach(model.periodComparison, id: \.metricName) { delta in
                HStack {
                    Text(delta.metricName)
                        .font(.subheadline)
                    Spacer()
                    if let current = delta.current {
                        Text(formatValue(delta.metricName, current))
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("—")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    if let deltaValue = delta.delta {
                        Text(deltaValue >= 0 ? "+\(String(format: "%.0f", deltaValue))%" : "\(String(format: "%.0f", deltaValue))%")
                            .font(.caption.bold())
                            .foregroundColor(deltaColor(delta))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(deltaColor(delta).opacity(0.15))
                            )
                    } else if delta.isNew {
                        Text("New")
                            .font(.caption.bold())
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.blue.opacity(0.15))
                            )
                    }
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

    private func formatValue(_ name: String, _ value: Double) -> String {
        switch name {
        case "On-Time %": return String(format: "%.0f%%", value)
        case "Avg Interval": return TimeIntervalMath.formatMinutes(Int(value.rounded()))
        case "Avg Sleep": return TimeIntervalMath.formatMinutes(Int(value.rounded()))
        case "Sleep Quality": return String(format: "%.1f / 5", value)
        default: return String(format: "%.1f", value)
        }
    }

    private func deltaColor(_ delta: DashboardAnalyticsModel.PeriodDelta) -> Color {
        guard let deltaValue = delta.delta else { return .secondary }
        if deltaValue > 5 { return .green }
        if deltaValue < -5 { return .red }
        return .secondary
    }
}
