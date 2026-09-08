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
                kpi("Finished-night streak", "\(model.finishedNightStreak) nights")
                kpi("Nights with data", "\(model.populatedNights.count)")
                kpi("Coverage · 3+ categories", "\(model.threeCategoryNightCount) nights", color: DashboardPalette.coverage)
                kpi("WHOOP Recovery", model.averageWhoopRecovery.map { String(format: "%.0f%%", $0) } ?? "No data", color: DashboardPalette.recovery(model.averageWhoopRecovery))
                kpi("WHOOP HRV", model.averageWhoopHRV.map { String(format: "%.0f ms", $0) } ?? "No data", color: DashboardPalette.sleep)
            }
            Text("In-window rate uses \(model.recordedPairCount) valid recorded pairs. Outcomes: \(model.recordedDose2OutcomeCount)/\(model.eligibleDose2OutcomeCount), including explicit skips; pending nights are excluded.")
                .font(.caption).foregroundColor(.secondary)
            Text("Streak ends with the previous night, resets at gaps and is limited to this range. Coverage counts records, not confidence.")
                .font(.caption).foregroundColor(.secondary)
            Label(tonightStatus, systemImage: "moon")
                .font(.callout).foregroundColor(DashboardPalette.timing)
            if let lastRefresh = model.lastRefresh {
                Text("Updated \(lastRefresh.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding().background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemGray6)))
    }

    private func kpi(_ title: String, _ value: String, color: Color = DashboardPalette.timing) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.title2.bold()).foregroundColor(value == "No data" || value == "—" ? .secondary : color)
        }.accessibilityElement(children: .combine)
    }

    private var tonightStatus: String {
        switch core.currentStatus {
        case .noDose1: return "Tonight: Dose 1 not recorded"
        case .beforeWindow: return "Tonight: Waiting for Dose 2 window"
        case .active, .nearClose: return "Tonight: Dose 2 window open"
        case .closed: return "Tonight: Dose 2 window closed"
        case .completed, .finalizing: return "Tonight: Session complete"
        }
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
            metricRow(title: "Duplicate Nights", value: "\(model.duplicateNightCount)")
            metricRow(title: "Record review flags", value: "\(model.duplicateNightCount + model.missingDose2OutcomeCount)")
            Text("Review flags count duplicate-event nights and unrecorded Dose 2 outcomes; one night may contribute both.")
                .font(.caption).foregroundColor(.secondary)
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
                .foregroundColor(value == "No data" ? .secondary : (title == "Record review flags" && value != "0" ? DashboardPalette.review : DashboardPalette.timing))
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
            metricRow(title: "Avg WHOOP Sleep", value: formatMinutes(model.averageWhoopSleepMinutes))
            metricRow(title: "Time to first wake · Health", value: formatMinutes(model.averageTTFW))
            metricRow(title: "Avg wakes · Health", value: model.averageWakeCount.map { String(format: "%.1f", $0) } ?? "No data")
            metricRow(title: "Bathroom logs", value: "\(model.bathroomLogCount)")
            Text("First-wake timing n=\(model.populatedNights.compactMap(\.ttfwMinutes).count); wake counts n=\(model.populatedNights.compactMap(\.wakeCount).count). Bathroom logs do not measure duration.")
                .font(.caption).foregroundColor(.secondary)
            metricRow(title: "Avg Sleep Quality", value: model.averageSleepQuality.map { String(format: "%.1f / 5", $0) } ?? "No data")
            Text("Morning ratings: n=\(model.populatedNights.filter { $0.morningCheckIn != nil }.count).")
                .font(.caption).foregroundColor(.secondary)
            metricRow(title: "Avg Readiness", value: model.averageReadiness.map { String(format: "%.1f / 5", $0) } ?? "No data")
            metricRow(title: "Nap Nights", value: "\(model.napNightCount)")
            metricRow(title: "Avg nap time per nap night", value: formatMinutes(model.averageNapMinutes))


        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }

    private func metricRow(title: String, value: String, color: Color = DashboardPalette.sleep) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(value == "No data" ? .secondary : color)
        }
    }

    private func formatMinutes(_ value: Double?) -> String {
        guard let value else { return "No data" }
        return TimeIntervalMath.formatMinutes(Int(value.rounded()))
    }

    private func recoveryColor(_ score: Double) -> Color {
        DashboardPalette.recovery(score)
    }
}

struct DashboardWHOOPCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                biometricTile(icon: "waveform.path.ecg", title: "HRV", value: model.averageWhoopHRV.map { String(format: "%.0f ms", $0) } ?? "No data", color: DashboardPalette.sleep)
                biometricTile(icon: "heart.fill", title: "Resting HR", value: model.averageWhoopRestingHR.map { String(format: "%.0f bpm", $0) } ?? "No data", color: DashboardPalette.sleep)
                biometricTile(icon: "moon.fill", title: "Sleep Efficiency", value: model.averageWhoopSleepEfficiency.map { String(format: "%.0f%%", $0) } ?? "No data", color: DashboardPalette.sleep)
                biometricTile(icon: "lungs.fill", title: "Respiratory Rate", value: model.averageWhoopRespiratoryRate.map { String(format: "%.1f brpm", $0) } ?? "No data", color: DashboardPalette.sleep)
            }
            if model.averageWhoopDeepMinutes == nil && model.averageWhoopREMMinutes == nil {
                Text("Sleep stages: No complete stage readings").font(.callout).foregroundColor(.secondary)
            }
            if model.averageWhoopAwakeMinutes == nil {
                Text("Awake: No data").font(.callout).foregroundColor(.secondary)
            }
            if model.averageWhoopDisturbances == nil {
                Text("Disturbances: No data").font(.callout).foregroundColor(.secondary)
            }
            if model.averageWhoopRecovery == nil {
                Text("WHOOP Recovery: No data").font(.callout).foregroundColor(.secondary)
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
                .foregroundColor(value == "No data" ? .secondary : color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline.bold())
                    .foregroundColor(value == "No data" ? .secondary : color)
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
        DashboardPalette.recovery(score)
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
                .foregroundColor(model.morningCheckInRate == nil ? .secondary : DashboardPalette.coverage)
            Text("Pre-sleep log rate: \(model.preSleepLogRate.map { String(format: "%.0f%%", $0) } ?? "No data")")
                .font(.subheadline)
                .foregroundColor(model.preSleepLogRate == nil ? .secondary : DashboardPalette.coverage)
            Text("Nights without Apple Health data: \(model.missingHealthSummaryCount)")
                .font(.subheadline)
                .foregroundColor(DashboardPalette.coverage)
            Text("Nights with duplicate event clusters: \(model.duplicateNightCount)")
                .font(.subheadline)
                .foregroundColor(DashboardPalette.coverage)
            Text("Categories: dose outcome, sleep reading, morning check-in, completed pre-sleep log.")
                .font(.caption).foregroundColor(.secondary)
            Text("Nights with at least 3 of 4 data categories: \(model.threeCategoryNightCount)")
                .font(.subheadline)
                .foregroundColor(DashboardPalette.coverage)
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
