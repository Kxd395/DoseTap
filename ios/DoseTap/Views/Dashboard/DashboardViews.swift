import SwiftUI
import Charts
import DoseCore
import os.log
#if canImport(UIKit)
import UIKit
#endif

struct DashboardTabView: View {
    @ObservedObject var core: DoseTapCore
    @ObservedObject var eventLogger: EventLogger
    @ObservedObject private var sessionRepo = SessionRepository.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var model = DashboardAnalyticsModel()
    @StateObject private var cloudSync = CloudKitSyncService.shared
    @State private var resolvingDuplicateGroup: StoredEventDuplicateGroup?
    @State private var cloudSyncError: String?

    private var isWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad || horizontalSizeClass == .regular
    }

    private var columns: [GridItem] {
        isWideLayout
            ? [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            : [GridItem(.flexible())]
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // MARK: Date Range Picker
                    Picker("Range", selection: $model.selectedRange) {
                        ForEach(DashboardDateRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    Text(model.selectedRange.label + " • \(model.populatedNights.count) nights")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    DashboardExecutiveSummaryCard(model: model, core: core)
                        .gridCellColumns(columns.count)

                    // Period comparison (if prior data exists)
                    if !model.periodComparison.isEmpty {
                        DashboardPeriodComparisonCard(model: model)
                            .gridCellColumns(columns.count)
                    }

                    DashboardDosingSnapshotCard(model: model)
                    DashboardSleepSnapshotCard(model: model)

                    DashboardLifestyleFactorsCard(model: model)
                    DashboardMoodSymptomsCard(model: model)

                    DashboardDataQualityCard(model: model)
                    DashboardIntegrationsCard(states: model.integrationStates)

                    DashboardTrendChartsCard(model: model)
                        .gridCellColumns(columns.count)

                    DashboardRecentNightsCard(
                        nights: model.trendNights,
                        onResolveDuplicateGroup: { group in
                            resolvingDuplicateGroup = group
                        }
                    )
                        .gridCellColumns(columns.count)

                    DashboardCapturedMetricsCard(categories: model.metricsCatalog)
                        .gridCellColumns(columns.count)
                }
                .padding()
                .padding(.bottom, 90)
            }
            .navigationTitle("Dashboard")
            .refreshable {
                model.refresh()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if cloudSync.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button {
                            Task {
                                do {
                                    try await cloudSync.syncNow(days: 120)
                                    model.refresh()
                                } catch {
                                    cloudSyncError = error.localizedDescription
                                }
                            }
                        } label: {
                            Image(systemName: "icloud.and.arrow.up")
                        }
                        .accessibilityLabel("Sync with iCloud")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if model.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button {
                            model.refresh()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh dashboard")
                    }
                }
            }
            .overlay {
                if model.isLoading && model.nights.isEmpty {
                    ProgressView("Building dashboard…")
                }
            }
            .task {
                model.refresh()
            }
            .onReceive(sessionRepo.sessionDidChange) { _ in
                model.refresh()
            }
            .sheet(item: $resolvingDuplicateGroup) { group in
                DuplicateResolutionSheet(
                    group: group,
                    onKeepEvent: { keep in
                        for event in group.events where event.id != keep.id {
                            sessionRepo.deleteSleepEvent(id: event.id)
                        }
                        model.refresh()
                    },
                    onDeleteEvent: { event in
                        sessionRepo.deleteSleepEvent(id: event.id)
                        model.refresh()
                    },
                    onMergeGroup: {
                        if let canonical = group.events.sorted(by: { $0.timestamp < $1.timestamp }).first {
                            for event in group.events where event.id != canonical.id {
                                sessionRepo.deleteSleepEvent(id: event.id)
                            }
                            model.refresh()
                        }
                    }
                )
            }
            .alert("Cloud Sync", isPresented: Binding(
                get: { cloudSyncError != nil },
                set: { if !$0 { cloudSyncError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(cloudSyncError ?? "Unknown cloud sync error")
            }
        }
    }
}

struct DashboardExecutiveSummaryCard: View {
    @ObservedObject var model: DashboardAnalyticsModel
    @ObservedObject var core: DoseTapCore

    private var nextActionText: String {
        switch core.currentStatus {
        case .noDose1:
            return "Tonight: Take Dose 1 to start session tracking."
        case .beforeWindow:
            return "Tonight: Dose 2 window has not opened yet."
        case .active, .nearClose:
            return "Tonight: Dose 2 is active. Keep interval in the 150-240m range."
        case .closed:
            return "Tonight: Dose 2 window closed. Review trend for drift."
        case .completed, .finalizing:
            return "Tonight: Session complete. Use review findings to adjust next night."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Operations Snapshot")
                .font(.headline)

            HStack(spacing: 10) {
                dashboardKPI(
                    title: "On-Time",
                    value: model.onTimePercentage.map { String(format: "%.0f%%", $0) } ?? "—",
                    color: kpiColor(for: model.onTimePercentage, good: 70, okay: 40)
                )
                dashboardKPI(
                    title: "Completion",
                    value: model.completionRate.map { String(format: "%.0f%%", $0) } ?? "—",
                    color: kpiColor(for: model.completionRate, good: 80, okay: 50)
                )
                dashboardKPI(
                    title: "Streak",
                    value: "\(model.consecutiveOnTimeStreak)",
                    color: model.consecutiveOnTimeStreak >= 5 ? .green
                         : model.consecutiveOnTimeStreak > 0 ? .orange : .secondary
                )
                dashboardKPI(
                    title: "Confidence",
                    value: "\(model.highConfidenceNightCount)",
                    color: model.highConfidenceNightCount >= 5 ? .green
                         : model.highConfidenceNightCount > 0 ? .blue : .secondary
                )
            }

            Text(nextActionText)
                .font(.caption)
                .foregroundColor(.secondary)

            if let lastRefresh = model.lastRefresh {
                Text("Updated \(lastRefresh.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }

    private func dashboardKPI(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    /// Returns green/orange/red based on percentage thresholds.
    private func kpiColor(for value: Double?, good: Double, okay: Double) -> Color {
        guard let value else { return .secondary }
        if value >= good { return .green }
        if value >= okay { return .orange }
        return .red
    }
}

struct DashboardDosingSnapshotCard: View {
    @ObservedObject var model: DashboardAnalyticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dosing Performance")
                .font(.headline)
            metricRow(title: "Avg Interval", value: formatInterval(minutes: model.averageIntervalMinutes))
            metricRow(title: "Avg Snoozes", value: model.averageSnoozeCount.map { String(format: "%.1f", $0) } ?? "No data")
            metricRow(title: "Duplicate Nights", value: "\(model.duplicateNightCount)")
            metricRow(title: "Quality Issues", value: "\(model.qualityIssueCount)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }

    private func metricRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
        }
    }

    private func formatInterval(minutes: Double?) -> String {
        guard let minutes else { return "No data" }
        return TimeIntervalMath.formatMinutes(Int(minutes.rounded()))
    }
}

struct DashboardSleepSnapshotCard: View {
    @ObservedObject var model: DashboardAnalyticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sleep Outcomes")
                .font(.headline)
            metricRow(title: "Avg Total Sleep", value: formatMinutes(model.averageSleepMinutes))
            metricRow(title: "Avg TTFW", value: formatMinutes(model.averageTTFW))
            metricRow(title: "Avg Wake Count", value: model.averageWakeCount.map { String(format: "%.1f", $0) } ?? "No data")
            metricRow(title: "Avg Bathroom Wake", value: formatMinutes(model.averageBathroomWakeMinutes))
            metricRow(title: "Avg Sleep Quality", value: model.averageSleepQuality.map { String(format: "%.1f / 5", $0) } ?? "No data")
            metricRow(title: "Avg Readiness", value: model.averageReadiness.map { String(format: "%.1f / 5", $0) } ?? "No data")
            if model.napNightCount > 0 {
                metricRow(title: "Nap Nights", value: "\(model.napNightCount)")
                metricRow(title: "Avg Nap Duration", value: formatMinutes(model.averageNapMinutes))
            }

            // WHOOP metrics (only when data exists)
            if model.averageWhoopRecovery != nil || model.averageWhoopHRV != nil {
                Divider()
                HStack(spacing: 4) {
                    Image(systemName: "w.circle.fill")
                        .font(.caption)
                    Text("WHOOP Metrics")
                        .font(.caption.bold())
                }
                .foregroundColor(.secondary)
                .padding(.top, 2)

                if let recovery = model.averageWhoopRecovery {
                    metricRow(title: "Avg Recovery", value: String(format: "%.0f%%", recovery), color: recoveryColor(recovery))
                }
                if let hrv = model.averageWhoopHRV {
                    metricRow(title: "Avg HRV", value: String(format: "%.0f ms", hrv))
                }
                if let efficiency = model.averageWhoopSleepEfficiency {
                    metricRow(title: "Avg Sleep Efficiency", value: String(format: "%.0f%%", efficiency))
                }
                if let rr = model.averageWhoopRespiratoryRate {
                    metricRow(title: "Avg Respiratory Rate", value: String(format: "%.1f brpm", rr))
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

    private func metricRow(title: String, value: String, color: Color = .secondary) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(color)
        }
    }

    private func formatMinutes(_ value: Double?) -> String {
        guard let value else { return "No data" }
        return TimeIntervalMath.formatMinutes(Int(value.rounded()))
    }

    private func recoveryColor(_ score: Double) -> Color {
        if score >= 67 { return .green }
        if score >= 34 { return .orange }
        return .red
    }
}

struct DashboardDataQualityCard: View {
    @ObservedObject var model: DashboardAnalyticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Data Quality")
                .font(.headline)
            Text("Morning check-in rate: \(model.morningCheckInRate.map { String(format: "%.0f%%", $0) } ?? "No data")")
                .font(.subheadline)
                .foregroundColor(rateColor(model.morningCheckInRate))
            Text("Pre-sleep log rate: \(model.preSleepLogRate.map { String(format: "%.0f%%", $0) } ?? "No data")")
                .font(.subheadline)
                .foregroundColor(rateColor(model.preSleepLogRate))
            Text("Nights missing Apple Health summary: \(model.missingHealthSummaryCount)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Nights with duplicate event clusters: \(model.duplicateNightCount)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("High confidence nights (>=0.75 completeness): \(model.highConfidenceNightCount)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            if let error = model.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }

    private func rateColor(_ rate: Double?) -> Color {
        guard let rate else { return .secondary }
        if rate >= 75 { return .green }
        if rate >= 40 { return .orange }
        return .red
    }
}

struct DashboardIntegrationsCard: View {
    let states: [DashboardIntegrationState]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Integrations")
                .font(.headline)

            if states.isEmpty {
                Text("No integration states available yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(states) { state in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Circle()
                                .fill(state.color)
                                .frame(width: 8, height: 8)
                            Text(state.name)
                                .font(.subheadline.bold())
                            Spacer()
                            Text(state.status)
                                .font(.caption)
                                .foregroundColor(state.color)
                        }
                        Text(state.detail)
                            .font(.caption)
                            .foregroundColor(.secondary)
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
}

enum DashboardTrendMode: String, CaseIterable, Identifiable {
    case intervalVsSleep = "Interval vs Sleep"
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
            guard let onTime = night.onTimeDosing, let date = AppFormatters.sessionDate.date(from: night.sessionDate) else { continue }
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

// MARK: - Period Comparison Card

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
                    if let d = delta.delta {
                        Text(d >= 0 ? "+\(String(format: "%.0f", d))%" : "\(String(format: "%.0f", d))%")
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
        guard let d = delta.delta else { return .secondary }
        // For "On-Time %" and "Avg Sleep" and "Sleep Quality", higher is better
        // For "Avg Interval", closer to 165 is better — simplified to higher = neutral
        if d > 5 { return .green }
        if d < -5 { return .red }
        return .secondary
    }
}

// MARK: - Lifestyle Factors Card

struct DashboardLifestyleFactorsCard: View {
    @ObservedObject var model: DashboardAnalyticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lifestyle Factors")
                .font(.headline)

            if model.averageStressLevel != nil || model.caffeineRate != nil {
                if let stress = model.averageStressLevel {
                    metricRow(title: "Avg Stress", value: String(format: "%.1f / 10", stress), color: stressColor(stress))
                }
                factorRow(title: "Caffeine", rate: model.caffeineRate, impact: model.sleepQualityByCaffeine)
                factorRow(title: "Alcohol", rate: model.alcoholRate, impact: model.sleepQualityByAlcohol)
                factorRow(title: "Screens in Bed", rate: model.screenTimeRate, impact: model.sleepQualityByScreens)

                if let exercise = model.exerciseRate {
                    metricRow(title: "Exercise Days", value: String(format: "%.0f%%", exercise), color: .green)
                }
                if let meals = model.lateMealRate {
                    metricRow(title: "Late Meals", value: String(format: "%.0f%%", meals), color: meals > 40 ? .orange : .secondary)
                }
            } else {
                Text("Complete pre-sleep logs to see lifestyle impact.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }

    private func metricRow(title: String, value: String, color: Color = .secondary) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(color)
        }
    }

    @ViewBuilder
    private func factorRow(title: String, rate: Double?, impact: (with: Double?, without: Double?)) -> some View {
        if let rate {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(String(format: "%.0f%%", rate))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                // Show sleep quality delta if we have both
                if let w = impact.with, let wo = impact.without {
                    let diff = w - wo
                    Text(diff >= 0 ? "+\(String(format: "%.1f", diff))" : String(format: "%.1f", diff))
                        .font(.caption2.bold())
                        .foregroundColor(diff >= 0 ? .green : .orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill((diff >= 0 ? Color.green : Color.orange).opacity(0.15)))
                }
            }
        }
    }

    private func stressColor(_ level: Double) -> Color {
        if level <= 3 { return .green }
        if level <= 6 { return .orange }
        return .red
    }
}

// MARK: - Mood & Symptoms Card

struct DashboardMoodSymptomsCard: View {
    @ObservedObject var model: DashboardAnalyticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mood & Symptoms")
                .font(.headline)

            if model.averageMentalClarity != nil || model.narcolepsySymptomRate != nil {
                if let clarity = model.averageMentalClarity {
                    metricRow(title: "Mental Clarity", value: String(format: "%.1f / 10", clarity))
                }
                if let dreamRecall = model.dreamRecallRate {
                    metricRow(title: "Dream Recall", value: String(format: "%.0f%%", dreamRecall))
                }

                // Mood breakdown
                if !model.moodDistribution.isEmpty {
                    let topMood = model.moodDistribution.max(by: { $0.value < $1.value })
                    if let top = topMood {
                        metricRow(title: "Top Mood", value: "\(top.key.capitalized) (\(top.value)x)")
                    }
                }

                // Anxiety
                if !model.anxietyDistribution.isEmpty {
                    let anxious = model.anxietyDistribution.filter { $0.key != "none" }.values.reduce(0, +)
                    let total = model.anxietyDistribution.values.reduce(0, +)
                    if total > 0 {
                        let pct = (Double(anxious) / Double(total)) * 100
                        metricRow(title: "Anxiety Reported", value: String(format: "%.0f%%", pct), color: pct > 50 ? .orange : .secondary)
                    }
                }

                // Grogginess
                if !model.grogginessDistribution.isEmpty {
                    let severe = (model.grogginessDistribution["severe"] ?? 0) + (model.grogginessDistribution["moderate"] ?? 0)
                    let total = model.grogginessDistribution.values.reduce(0, +)
                    if total > 0 {
                        let pct = (Double(severe) / Double(total)) * 100
                        metricRow(title: "Moderate+ Grogginess", value: String(format: "%.0f%%", pct), color: pct > 50 ? .orange : .secondary)
                    }
                }

                // Narcolepsy symptoms
                if let narcoRate = model.narcolepsySymptomRate, narcoRate > 0 {
                    Divider()
                    Text("Narcolepsy Symptoms")
                        .font(.caption.bold())
                        .foregroundColor(.orange)
                    symptomRow(title: "Sleep Paralysis", count: model.sleepParalysisCount)
                    symptomRow(title: "Hallucinations", count: model.hallucinationCount)
                    symptomRow(title: "Automatic Behavior", count: model.automaticBehaviorCount)
                }
            } else {
                Text("Complete morning check-ins to track mood & symptoms.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }

    private func metricRow(title: String, value: String, color: Color = .secondary) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(color)
        }
    }

    private func symptomRow(title: String, count: Int) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption)
                .foregroundColor(.orange)
            Text(title).font(.caption)
            Spacer()
            Text("\(count) night\(count == 1 ? "" : "s")")
                .font(.caption.weight(.semibold))
                .foregroundColor(.orange)
        }
    }
}

struct DashboardCapturedMetricsCard: View {
    let categories: [DashboardMetricCategory]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Captured Metrics Inventory")
                .font(.headline)
            Text("This is the complete metric surface currently modeled for dashboarding.")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(categories) { category in
                VStack(alignment: .leading, spacing: 6) {
                    Text(category.title)
                        .font(.subheadline.bold())
                    ForEach(category.metrics, id: \.self) { metric in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(metric)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

