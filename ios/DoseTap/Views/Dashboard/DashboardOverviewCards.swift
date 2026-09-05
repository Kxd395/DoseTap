import SwiftUI
import DoseCore

struct DashboardExecutiveSummaryCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var model: DashboardAnalyticsModel
    @ObservedObject var core: DoseTapCore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recorded Nights").font(.headline)
            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible(), alignment: .leading)] : [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 12) {
                kpi("In-window pairs", model.onTimePercentage.map { String(format: "%.0f%%", $0) } ?? "—")
                kpi("Outcomes recorded", model.completionRate.map { String(format: "%.0f%%", $0) } ?? "—")
                kpi("Recorded pairs", "\(model.recordedPairCount)")
                kpi("Pending Dose 2", "\(model.pendingDose2OutcomeCount)")
            }
            Text("In-window rate uses \(model.recordedPairCount) valid recorded pairs. Outcomes: \(model.recordedDose2OutcomeCount)/\(model.eligibleDose2OutcomeCount), including explicit skips; pending nights are excluded.")
                .font(.caption).foregroundColor(.secondary)
            if let lastRefresh = model.lastRefresh {
                Text("Updated \(lastRefresh.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding().background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemGray6)))
    }

    private func kpi(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.title2.bold())
        }.accessibilityElement(children: .combine)
    }
}

struct DashboardDosingSnapshotCard: View {
    @ObservedObject var model: DashboardAnalyticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recorded Dose Timing")
                .font(.headline)
            metricRow(title: "Avg Interval", value: formatInterval(minutes: model.averageIntervalMinutes))
            metricRow(title: "Avg Snoozes", value: model.averageSnoozeCount.map { String(format: "%.1f", $0) } ?? "No data")
            metricRow(title: "Missing Dose 2 Outcomes", value: "\(model.missingDose2OutcomeCount)")
            metricRow(title: "Early pairs", value: "\(model.timingCount(.early))")
            metricRow(title: "In-window pairs", value: "\(model.timingCount(.inWindow))")
            metricRow(title: "Late pairs", value: "\(model.timingCount(.late))")
            metricRow(title: "Explicitly skipped", value: "\(model.skippedDose2Count)")
            metricRow(title: "Extra doses logged", value: "\(model.extraDoseCount)")
            Text("Timing describes recorded timestamps using the app's existing window. It does not assess treatment effectiveness.")
                .font(.caption).foregroundColor(.secondary)
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
            Text("Sleep readings: Apple Health n=\(model.populatedNights.compactMap(\.appleHealthSleepMinutes).count), WHOOP n=\(model.populatedNights.compactMap(\.whoopSleepMinutes).count).")
                .font(.caption).foregroundColor(.secondary)
            metricRow(title: "Avg Apple Health Sleep", value: formatMinutes(model.averageAppleHealthSleepMinutes))
            if model.averageWhoopSleepMinutes != nil {
                metricRow(title: "Avg WHOOP Sleep", value: formatMinutes(model.averageWhoopSleepMinutes))
            }
            metricRow(title: "Time to first wake · Health", value: formatMinutes(model.averageTTFW))
            metricRow(title: "Avg wakes · Health", value: model.averageWakeCount.map { String(format: "%.1f", $0) } ?? "No data")
            metricRow(title: "Bathroom logs", value: "\(model.bathroomLogCount)")
            Text("First-wake timing n=\(model.populatedNights.compactMap(\.ttfwMinutes).count); wake counts n=\(model.populatedNights.compactMap(\.wakeCount).count). Bathroom logs do not measure duration.")
                .font(.caption).foregroundColor(.secondary)
            metricRow(title: "Avg Sleep Quality", value: model.averageSleepQuality.map { String(format: "%.1f / 5", $0) } ?? "No data")
            Text("Morning ratings: n=\(model.populatedNights.filter { $0.morningCheckIn != nil }.count).")
                .font(.caption).foregroundColor(.secondary)
            metricRow(title: "Avg Readiness", value: model.averageReadiness.map { String(format: "%.1f / 5", $0) } ?? "No data")
            if model.napNightCount > 0 {
                metricRow(title: "Nap Nights", value: "\(model.napNightCount)")
                metricRow(title: "Avg nap time per nap night", value: formatMinutes(model.averageNapMinutes))
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

            Text("Recovery n=\(model.whoopNights.compactMap(\.whoopRecoveryScore).count) · HRV n=\(model.whoopNights.compactMap(\.whoopHRV).count). Missing readings are excluded from each average.")
                .font(.caption).foregroundColor(.secondary)
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

                VStack(alignment: .leading, spacing: 8) {
                    if let light = model.averageWhoopLightMinutes {
                        stageLegend(label: "Light", value: formatMin(light), color: .blue)
                    }
                    if let awake = model.averageWhoopAwakeMinutes {
                        stageLegend(label: "Awake (outside sleep total)", value: formatMin(awake), color: .gray)
                    }
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
        let light = model.averageWhoopLightMinutes ?? 0
        let total = deep + rem + light
        if total > 0 {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Color.blue.frame(width: geo.size.width * CGFloat(light / total))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.indigo)
                        .frame(width: geo.size.width * CGFloat(deep / total))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.cyan)
                        .frame(width: geo.size.width * CGFloat(rem / total))
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
        if score >= 67 { return "WHOOP green range" }
        if score >= 34 { return "WHOOP yellow range" }
        return "WHOOP red range"
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
            Text("Data Coverage")
                .font(.headline)
            Text("Rates use all \(model.populatedNights.count) nights with data in this range. Coverage describes available records, not accuracy or statistical confidence.")
                .font(.caption).foregroundColor(.secondary)
            Text("Apple Health: \(model.populatedNights.filter { $0.healthSummary != nil }.count) nights • WHOOP: \(model.whoopNights.count) nights")
                .font(.caption).foregroundColor(.secondary)
            Text("Morning check-in rate: \(model.morningCheckInRate.map { String(format: "%.0f%%", $0) } ?? "No data")")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Pre-sleep log rate: \(model.preSleepLogRate.map { String(format: "%.0f%%", $0) } ?? "No data")")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Nights without Apple Health data: \(model.missingHealthSummaryCount)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Nights with duplicate event clusters: \(model.duplicateNightCount)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Categories: dose outcome, sleep reading, morning check-in, completed pre-sleep log.")
                .font(.caption).foregroundColor(.secondary)
            Text("Nights with at least 3 of 4 data categories: \(model.threeCategoryNightCount)")
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
