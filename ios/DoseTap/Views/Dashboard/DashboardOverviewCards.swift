import SwiftUI
import DoseCore

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

            if let recovery = model.averageWhoopRecovery {
                HStack(spacing: 10) {
                    dashboardKPI(
                        title: "Recovery",
                        value: String(format: "%.0f%%", recovery),
                        color: recovery >= 67 ? .green : recovery >= 34 ? .orange : .red
                    )
                    if let hrv = model.averageWhoopHRV {
                        dashboardKPI(
                            title: "HRV",
                            value: String(format: "%.0f ms", hrv),
                            color: .blue
                        )
                    }
                    Spacer()
                }
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

struct DashboardWHOOPCard: View {
    @ObservedObject var model: DashboardAnalyticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "w.circle.fill")
                    .font(.headline)
                    .foregroundColor(.green)
                Text("WHOOP Recovery & Biometrics")
                    .font(.headline)
                Spacer()
                Text("\(model.whoopNights.count) nights")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let recovery = model.averageWhoopRecovery {
                HStack(spacing: 16) {
                    recoveryGauge(score: recovery)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Avg Recovery")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f%%", recovery))
                            .font(.title2.bold())
                            .foregroundColor(whoopRecoveryColor(recovery))
                        Text(recoveryLabel(recovery))
                            .font(.caption2)
                            .foregroundColor(whoopRecoveryColor(recovery))
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Divider()

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 10) {
                if let hrv = model.averageWhoopHRV {
                    biometricTile(
                        icon: "waveform.path.ecg",
                        title: "HRV",
                        value: String(format: "%.0f ms", hrv),
                        color: .blue
                    )
                }
                if let rhr = model.averageWhoopRestingHR {
                    biometricTile(
                        icon: "heart.fill",
                        title: "Resting HR",
                        value: String(format: "%.0f bpm", rhr),
                        color: .red
                    )
                }
                if let efficiency = model.averageWhoopSleepEfficiency {
                    biometricTile(
                        icon: "moon.fill",
                        title: "Sleep Efficiency",
                        value: String(format: "%.0f%%", efficiency),
                        color: .purple
                    )
                }
                if let rr = model.averageWhoopRespiratoryRate {
                    biometricTile(
                        icon: "lungs.fill",
                        title: "Respiratory Rate",
                        value: String(format: "%.1f brpm", rr),
                        color: .teal
                    )
                }
            }

            if model.averageWhoopDeepMinutes != nil || model.averageWhoopREMMinutes != nil {
                Divider()
                Text("Avg Sleep Stages")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                sleepStageBar

                HStack(spacing: 12) {
                    if let deep = model.averageWhoopDeepMinutes {
                        stageLegend(label: "Deep", value: formatMin(deep), color: .indigo)
                    }
                    if let rem = model.averageWhoopREMMinutes {
                        stageLegend(label: "REM", value: formatMin(rem), color: .cyan)
                    }
                    if let dist = model.averageWhoopDisturbances {
                        stageLegend(label: "Disturbances", value: String(format: "%.1f", dist), color: .orange)
                    }
                }
                .font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }

    private func recoveryGauge(score: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray4), lineWidth: 6)
                .frame(width: 56, height: 56)
            Circle()
                .trim(from: 0, to: CGFloat(min(score, 100)) / 100)
                .stroke(whoopRecoveryColor(score), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 56, height: 56)
            Text(String(format: "%.0f", score))
                .font(.caption.bold())
                .foregroundColor(whoopRecoveryColor(score))
        }
    }

    private func biometricTile(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var sleepStageBar: some View {
        let deep = model.averageWhoopDeepMinutes ?? 0
        let rem = model.averageWhoopREMMinutes ?? 0
        let total = deep + rem
        if total > 0 {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.indigo)
                        .frame(width: max(geo.size.width * CGFloat(deep / total) - 1, 4))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.cyan)
                        .frame(width: max(geo.size.width * CGFloat(rem / total) - 1, 4))
                }
            }
            .frame(height: 10)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    private func stageLegend(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(label): \(value)")
                .foregroundColor(.secondary)
        }
    }

    private func whoopRecoveryColor(_ score: Double) -> Color {
        if score >= 67 { return .green }
        if score >= 34 { return .orange }
        return .red
    }

    private func recoveryLabel(_ score: Double) -> String {
        if score >= 67 { return "Green — Ready" }
        if score >= 34 { return "Yellow — Strained" }
        return "Red — Rest"
    }

    private func formatMin(_ minutes: Double) -> String {
        let hours = Int(minutes) / 60
        let mins = Int(minutes) % 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
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
