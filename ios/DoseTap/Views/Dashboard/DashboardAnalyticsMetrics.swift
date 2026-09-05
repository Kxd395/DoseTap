import Foundation
import DoseCore

extension DashboardAnalyticsModel {
    // MARK: - Range-filtered views

    var populatedNights: [DashboardNightAggregate] {
        filteredNights(prior: false)
    }

    var priorPeriodNights: [DashboardNightAggregate] {
        selectedRange == .all ? [] : filteredNights(prior: true)
    }

    private func filteredNights(prior: Bool) -> [DashboardNightAggregate] {
        let key = SessionIdentity(date: now(), timeZone: .current, rolloverHour: 18).key
        guard let anchor = Self.keyFormatter.date(from: key) else { return [] }
        let cutoff = selectedRange.cutoffDate(from: anchor)
        let lower = prior ? selectedRange.priorPeriodCutoff(from: anchor).start : cutoff
        return nights.filter { night in
            guard night.hasAnyData,
                  let date = Self.keyFormatter.date(from: night.sessionDate),
                  Self.keyFormatter.string(from: date) == night.sessionDate else { return false }
            return date >= lower && (prior ? date < cutoff : date <= anchor)
        }.sorted { $0.sessionDate > $1.sessionDate }
    }

    var trendNights: [DashboardNightAggregate] {
        Array(populatedNights.prefix(14))
    }

    var dosingNights: [DashboardNightAggregate] {
        populatedNights.filter { $0.dose1Time != nil || $0.dose2Time != nil || $0.dose2Skipped }
    }

    var onTimePercentage: Double? {
        let values = dosingNights.compactMap(\.onTimeDosing)
        guard !values.isEmpty else { return nil }
        let onTime = values.filter { $0 }.count
        return (Double(onTime) / Double(values.count)) * 100
    }

    var eligibleDose2OutcomeCount: Int {
        dosingNights.filter { $0.dose1Time != nil && !$0.isPendingDose2(at: now()) }.count
    }

    var recordedDose2OutcomeCount: Int {
        dosingNights.filter {
            $0.dose1Time != nil && ($0.dose2Time != nil || $0.dose2Skipped)
        }.count
    }

    var pendingDose2OutcomeCount: Int { dosingNights.filter { $0.isPendingDose2(at: now()) }.count }

    var missingDose2OutcomeCount: Int {
        max(0, eligibleDose2OutcomeCount - recordedDose2OutcomeCount)
    }

    var averageIntervalMinutes: Double? {
        let intervals = dosingNights.compactMap(\.exactIntervalMinutes)
        guard !intervals.isEmpty else { return nil }
        return Double(intervals.reduce(0, +)) / Double(intervals.count)
    }

    var completionRate: Double? {
        guard eligibleDose2OutcomeCount > 0 else { return nil }
        return Double(recordedDose2OutcomeCount) / Double(eligibleDose2OutcomeCount) * 100
    }

    var averageSnoozeCount: Double? {
        guard !dosingNights.isEmpty else { return nil }
        let total = dosingNights.reduce(0) { $0 + $1.snoozeCount }
        return Double(total) / Double(dosingNights.count)
    }

    var averageSleepMinutes: Double? {
        let values = populatedNights.compactMap { sleepMinutes(for: $0) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageAppleHealthSleepMinutes: Double? {
        let values = populatedNights.compactMap(\.appleHealthSleepMinutes)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageWhoopSleepMinutes: Double? {
        let values = populatedNights.compactMap(\.whoopSleepMinutes)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageTTFW: Double? {
        let values = populatedNights.compactMap(\.ttfwMinutes)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageWakeCount: Double? {
        let values = populatedNights.compactMap(\.wakeCount).map(Double.init)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - WHOOP Aggregate Metrics

    var whoopNights: [DashboardNightAggregate] {
        populatedNights.filter { $0.whoopSummary?.hasValidSleepData == true }
    }

    var averageWhoopRecovery: Double? {
        let values = whoopNights.compactMap(\.whoopRecoveryScore)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageWhoopHRV: Double? {
        let values = whoopNights.compactMap(\.whoopHRV)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageWhoopSleepEfficiency: Double? {
        let values = whoopNights.compactMap(\.whoopSleepEfficiency)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageWhoopRespiratoryRate: Double? {
        let values = whoopNights.compactMap(\.whoopRespiratoryRate)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageWhoopRestingHR: Double? {
        let values = whoopNights.compactMap { $0.whoopSummary?.restingHeartRate }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageWhoopDeepMinutes: Double? {
        let values = whoopNights.compactMap(\.whoopDeepSleepMinutes).map(Double.init)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageWhoopREMMinutes: Double? {
        let values = whoopNights.filter { $0.whoopSummary?.hasCompleteSleepStages == true }.compactMap { $0.whoopSummary?.remMinutes }.map(Double.init)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageWhoopLightMinutes: Double? {
        let values = whoopNights.filter { $0.whoopSummary?.hasCompleteSleepStages == true }.compactMap { $0.whoopSummary?.lightMinutes }.map(Double.init)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageWhoopAwakeMinutes: Double? {
        let values = whoopNights.filter { $0.whoopSummary?.hasAwakeData == true }.compactMap { $0.whoopSummary?.awakeMinutes }.map(Double.init)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageWhoopDisturbances: Double? {
        let values = whoopNights.compactMap(\.whoopDisturbances).map(Double.init)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Check-in & Pre-Sleep Completion

    var doseEffectivenessReport: DoseEffectivenessReport {
        let dataPoints: [DoseEffectivenessDataPoint] = dosingNights.filter { $0.exactIntervalMinutes != nil }.map { night in
            DoseEffectivenessDataPoint(
                date: Self.keyFormatter.date(from: night.sessionDate) ?? Date(),
                intervalMinutes: night.exactIntervalMinutes,
                dose2Skipped: false, // This report only receives recorded timestamp pairs.
                totalSleepMinutes: sleepMinutes(for: night),
                deepSleepMinutes: sleepSource == .whoop ? night.whoopDeepSleepMinutes.map(Double.init) : nil,
                recoveryScore: sleepSource == .whoop ? night.whoopRecoveryScore.map(Int.init) : nil,
                averageHRV: sleepSource == .whoop ? night.whoopHRV : nil,
                awakenings: sleepSource == .whoop ? night.whoopDisturbances : night.wakeCount
            )
        }
        return DoseEffectivenessCalculator.analyze(dataPoints)
    }

    var morningCheckInRate: Double? {
        guard !populatedNights.isEmpty else { return nil }
        let withCheckIn = populatedNights.filter { $0.morningCheckIn != nil }.count
        return (Double(withCheckIn) / Double(populatedNights.count)) * 100
    }

    var preSleepLogRate: Double? {
        guard !populatedNights.isEmpty else { return nil }
        let withLog = populatedNights.filter { $0.preSleepLog?.completionState == "complete" }.count
        return (Double(withLog) / Double(populatedNights.count)) * 100
    }

    var averageSleepQuality: Double? {
        let values = populatedNights.compactMap { $0.morningCheckIn?.sleepQuality }
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    var averageReadiness: Double? {
        let values = populatedNights.compactMap { $0.morningCheckIn?.readinessForDay }
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    // MARK: - Nap Metrics

    var napNightCount: Int {
        populatedNights.filter { $0.napSummary.count > 0 }.count
    }

    var averageNapMinutes: Double? {
        let napNights = populatedNights.filter { $0.napSummary.count > 0 }
        guard !napNights.isEmpty else { return nil }
        let totalMinutes = napNights.reduce(0) { $0 + $1.napSummary.totalMinutes }
        return Double(totalMinutes) / Double(napNights.count)
    }

    var duplicateNightCount: Int {
        populatedNights.filter { $0.duplicateClusterCount > 0 }.count
    }

    var missingHealthSummaryCount: Int {
        populatedNights.filter { $0.healthSummary == nil }.count
    }

    var threeCategoryNightCount: Int {
        populatedNights.filter { $0.dataCompletenessScore >= 0.75 }.count
    }


}
