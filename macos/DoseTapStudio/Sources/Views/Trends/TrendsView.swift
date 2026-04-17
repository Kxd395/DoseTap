import SwiftUI
import Charts

struct TrendsView: View {
    @ObservedObject var dataStore: DataStore
    @State private var filters = InsightFilterState()

    private var recentSessions: [InsightSession] {
        let filtered = dataStore.insightSessions.filter { $0.matches(filters: filters) }
        return Array(filtered.prefix(30).reversed())
    }

    private var averageInterval: Int? {
        let values = recentSessions.compactMap(\.intervalMinutes)
        guard !values.isEmpty else { return nil }
        return Int(Double(values.reduce(0, +)) / Double(values.count))
    }

    private var lateCount: Int {
        recentSessions.filter(\.isLateDose2).count
    }

    private var skippedCount: Int {
        recentSessions.filter(\.dose2Skipped).count
    }

    private var issueCount: Int {
        recentSessions.filter { !$0.qualityFlags.isEmpty }.count
    }

    private var highStressCount: Int {
        recentSessions.filter { ($0.preSleepStressLevel ?? 0) >= 4 }.count
    }

    private var missingMorningCount: Int {
        recentSessions.filter { $0.morning == nil }.count
    }

    private var averageSleepQuality: Double? {
        let values = recentSessions.compactMap(\.morningSleepQuality)
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    private var averageReadiness: Double? {
        let values = recentSessions.compactMap(\.morningReadiness)
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    private var averageSleepEfficiency: Double? {
        let values = recentSessions.compactMap(\.sleepEfficiency)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var averageRecovery: Double? {
        let values = recentSessions.compactMap(\.whoopRecovery)
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    private var averageTotalSleepMinutes: Double? {
        let values = recentSessions.compactMap(\.totalSleepMinutes)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var healthKitCount: Int {
        recentSessions.filter { $0.healthKit != nil }.count
    }

    private var whoopCount: Int {
        recentSessions.filter { $0.whoop != nil }.count
    }

    private var likelyNaturalWakeCount: Int {
        recentSessions.filter { $0.likelyNaturalWake == true }.count
    }

    private var alarmAssistedCount: Int {
        recentSessions.filter { $0.likelyNaturalWake == false }.count
    }

    private var lateMealCount: Int {
        recentSessions.filter(\.hasLateMealContext).count
    }

    private var scheduleMarkerCount: Int {
        recentSessions.filter { !($0.context?.scheduleMarkers.isEmpty ?? true) }.count
    }

    private var trainableNightCount: Int {
        recentSessions.filter(\.countsTowardRecommendationTraining).count
    }

    private var highConfidenceCount: Int {
        recentSessions.filter { $0.classification.confidenceBucket == .high }.count
    }

    private var stressCorrelationSessions: [InsightSession] {
        recentSessions.filter { $0.preSleepStressLevel != nil && $0.morningSleepQuality != nil }
    }

    private var readinessSessions: [InsightSession] {
        recentSessions.filter { $0.morningReadiness != nil || $0.medicationCount > 0 }
    }

    private var recoveryTrendSessions: [InsightSession] {
        recentSessions.filter { $0.sleepEfficiency != nil || $0.whoopRecovery != nil }
    }

    private var restorativeSleepSessions: [InsightSession] {
        recentSessions.filter { $0.totalSleepMinutes != nil || $0.wakeDisruptionCount != nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Trends")
                    .font(.largeTitle.bold())

                filterBar
                summaryRow

                if recentSessions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.line.downtrend.xyaxis")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("No trend data available")
                            .font(.headline)
                        Text("Import session exports to populate interval and event trends.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    intervalChartCard
                    eventChartCard
                    morningTrendCard
                    recoveryTrendCard
                    restorativeSleepCard
                    stressCorrelationCard
                    outlierCard
                }
            }
            .padding()
        }
        .navigationTitle("Trends")
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            Toggle("Quality Issues", isOn: $filters.qualityIssuesOnly)
                .toggleStyle(.switch)
            Toggle("Trainable", isOn: $filters.trainableOnly)
                .toggleStyle(.switch)

            Picker("Night Type", selection: $filters.nightType) {
                ForEach(InsightNightTypeFilter.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.menu)

            Picker("Wake", selection: $filters.wakeType) {
                ForEach(InsightWakeTypeFilter.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.menu)

            Picker("Schedule", selection: $filters.schedule) {
                ForEach(InsightScheduleFilter.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.menu)

            Spacer()
        }
    }

    private var summaryRow: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 150)),
                GridItem(.flexible(minimum: 150)),
                GridItem(.flexible(minimum: 150)),
                GridItem(.flexible(minimum: 150))
            ],
            alignment: .leading,
            spacing: 12
        ) {
            trendCard(title: "30-Night Avg Interval", value: averageInterval.map { "\($0)m" } ?? "—", accent: .blue)
            trendCard(title: "Avg Sleep Quality", value: averageSleepQuality.map { String(format: "%.1f/5", $0) } ?? "—", accent: .indigo)
            trendCard(title: "Avg Readiness", value: averageReadiness.map { String(format: "%.1f/5", $0) } ?? "—", accent: .teal)
            trendCard(title: "Avg Total Sleep", value: averageTotalSleepMinutes.map(durationText) ?? "—", accent: .green)
            trendCard(title: "Avg Sleep Eff.", value: averageSleepEfficiency.map { String(format: "%.1f%%", $0) } ?? "—", accent: .mint)
            trendCard(title: "Avg Recovery", value: averageRecovery.map { String(format: "%.0f%%", $0) } ?? "—", accent: .purple)
            trendCard(title: "Apple Health", value: "\(healthKitCount)", accent: .green)
            trendCard(title: "WHOOP", value: "\(whoopCount)", accent: .purple)
            trendCard(title: "Likely Natural Wake", value: "\(likelyNaturalWakeCount)", accent: .teal)
            trendCard(title: "Alarm-Assisted", value: "\(alarmAssistedCount)", accent: .orange)
            trendCard(title: "Late Meal Nights", value: "\(lateMealCount)", accent: .pink)
            trendCard(title: "Schedule Markers", value: "\(scheduleMarkerCount)", accent: .indigo)
            trendCard(title: "Trainable Nights", value: "\(trainableNightCount)", accent: .green)
            trendCard(title: "High Confidence", value: "\(highConfidenceCount)", accent: .blue)
            trendCard(title: "High Stress", value: "\(highStressCount)", accent: .pink)
            trendCard(title: "Missing Morning", value: "\(missingMorningCount)", accent: .orange)
            trendCard(title: "Late Dose 2", value: "\(lateCount)", accent: .orange)
            trendCard(title: "Skipped", value: "\(skippedCount)", accent: .red)
            trendCard(title: "Flags", value: "\(issueCount)", accent: .purple)
        }
    }

    private var intervalChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dose Interval Trend")
                .font(.headline)

            Chart(recentSessions) { session in
                if let interval = session.intervalMinutes {
                    LineMark(
                        x: .value("Night", session.sessionDate),
                        y: .value("Interval", interval)
                    )
                    .foregroundStyle(.blue)

                    PointMark(
                        x: .value("Night", session.sessionDate),
                        y: .value("Interval", interval)
                    )
                    .foregroundStyle(pointColor(for: session))
                }

                RuleMark(y: .value("Window Start", 150))
                    .foregroundStyle(.green.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))

                RuleMark(y: .value("Window End", 240))
                    .foregroundStyle(.orange.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
            }
            .frame(height: 240)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var eventChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Night Event Load")
                .font(.headline)

            Chart(recentSessions) { session in
                BarMark(
                    x: .value("Night", session.sessionDate),
                    y: .value("Events", session.eventCount)
                )
                .foregroundStyle(barColor(for: session))
            }
            .frame(height: 220)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var morningTrendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Morning Outcome Trend")
                .font(.headline)

            if readinessSessions.isEmpty {
                Text("Import nights with morning check-ins to view readiness and medication context.")
                    .foregroundColor(.secondary)
            } else {
                Chart(readinessSessions) { session in
                    if let readiness = session.morningReadiness {
                        BarMark(
                            x: .value("Night", session.sessionDate),
                            y: .value("Readiness", readiness)
                        )
                        .foregroundStyle(.teal.gradient)
                    }

                    if session.medicationCount > 0 {
                        PointMark(
                            x: .value("Night", session.sessionDate),
                            y: .value("Medication Count", min(5, session.medicationCount))
                        )
                        .foregroundStyle(.pink)
                        .symbolSize(70)
                    }
                }
                .frame(height: 220)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var recoveryTrendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Imported Recovery & Sleep Efficiency")
                .font(.headline)

            if recoveryTrendSessions.isEmpty {
                Text("Import WHOOP or sleep-efficiency-enriched nights to compare recovery and sleep efficiency.")
                    .foregroundColor(.secondary)
            } else {
                Chart(recoveryTrendSessions) { session in
                    if let sleepEfficiency = session.sleepEfficiency {
                        LineMark(
                            x: .value("Night", session.sessionDate),
                            y: .value("Sleep Efficiency", sleepEfficiency)
                        )
                        .foregroundStyle(.mint)

                        PointMark(
                            x: .value("Night", session.sessionDate),
                            y: .value("Sleep Efficiency", sleepEfficiency)
                        )
                        .foregroundStyle(.mint)
                    }

                    if let recovery = session.whoopRecovery {
                        LineMark(
                            x: .value("Night", session.sessionDate),
                            y: .value("Recovery", recovery)
                        )
                        .foregroundStyle(.purple)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))

                        PointMark(
                            x: .value("Night", session.sessionDate),
                            y: .value("Recovery", recovery)
                        )
                        .foregroundStyle(.purple)
                    }
                }
                .frame(height: 220)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var restorativeSleepCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Restorative Sleep Context")
                .font(.headline)

            if restorativeSleepSessions.isEmpty {
                Text("Import Apple Health or WHOOP nightly sleep summaries to view total sleep and wake disruption.")
                    .foregroundColor(.secondary)
            } else {
                Chart(restorativeSleepSessions) { session in
                    if let totalSleepMinutes = session.totalSleepMinutes {
                        BarMark(
                            x: .value("Night", session.sessionDate),
                            y: .value("Total Sleep (hours)", totalSleepMinutes / 60.0)
                        )
                        .foregroundStyle(barColor(for: session).opacity(0.7))
                    }

                    if let wakeDisruptionCount = session.wakeDisruptionCount {
                        PointMark(
                            x: .value("Night", session.sessionDate),
                            y: .value("Wake Disruption Count", wakeDisruptionCount)
                        )
                        .foregroundStyle(.red)
                        .symbolSize(80)
                    }
                }
                .frame(height: 220)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var stressCorrelationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pre-Sleep Stress vs Morning Quality")
                .font(.headline)

            if stressCorrelationSessions.isEmpty {
                Text("Import nights with both pre-sleep and morning check-ins to view factor correlation.")
                    .foregroundColor(.secondary)
            } else {
                Chart(stressCorrelationSessions) { session in
                    PointMark(
                        x: .value("Stress", session.preSleepStressLevel ?? 0),
                        y: .value("Sleep Quality", session.morningSleepQuality ?? 0)
                    )
                    .foregroundStyle(pointColor(for: session))
                    .symbolSize(110)
                }
                .chartXScale(domain: 1...5)
                .chartYScale(domain: 1...5)
                .frame(height: 220)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var outlierCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Outliers")
                .font(.headline)

            let outliers = recentSessions.filter { session in
                session.isLateDose2 || session.dose2Skipped || !session.qualityFlags.isEmpty
            }

            if outliers.isEmpty {
                Text("No late, skipped, or flagged nights in the most recent imported set.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(outliers.prefix(8)) { session in
                    HStack {
                        Text(session.sessionDate)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(outlierLabel(for: session))
                            .foregroundColor(outlierColor(for: session))
                    }
                    if session.id != outliers.prefix(8).last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func trendCard(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title2.bold())
                .foregroundColor(accent)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 150, alignment: .leading)
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func durationText(_ minutes: Double) -> String {
        let roundedMinutes = Int(minutes.rounded())
        return "\(roundedMinutes / 60)h \(roundedMinutes % 60)m"
    }

    private func pointColor(for session: InsightSession) -> Color {
        if session.dose2Skipped {
            return .red
        }
        if session.isLateDose2 {
            return .orange
        }
        return .green
    }

    private func barColor(for session: InsightSession) -> Color {
        if !session.qualityFlags.isEmpty {
            return .purple
        }
        if session.eventCount >= 6 {
            return .orange
        }
        return .blue
    }

    private func outlierLabel(for session: InsightSession) -> String {
        if session.dose2Skipped {
            return "Dose 2 skipped"
        }
        if session.isLateDose2 {
            return "Late Dose 2"
        }
        if let quality = session.morningSleepQuality, quality <= 2 {
            return "Poor morning quality"
        }
        return session.qualitySummary
    }

    private func outlierColor(for session: InsightSession) -> Color {
        if session.dose2Skipped {
            return .red
        }
        if session.isLateDose2 {
            return .orange
        }
        if let quality = session.morningSleepQuality, quality <= 2 {
            return .pink
        }
        return .purple
    }
}

#Preview {
    TrendsView(dataStore: DataStore())
}
