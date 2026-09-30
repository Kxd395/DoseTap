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

    var currentReportWindow: DashboardReportingWindow? {
        selectedRange.window(asOf: reportingAsOf, timeZone: reportingTimeZone)
    }

    private func filteredNights(prior: Bool) -> [DashboardNightAggregate] {
        guard let window = currentReportWindow else { return [] }
        return nights.filter { $0.hasAnyData && window.contains($0.sessionDate, prior: prior) }
            .sorted { $0.sessionDate > $1.sessionDate }
    }

    var rangeDescription: String {
        guard let window = currentReportWindow else { return "Reporting dates unavailable" }
        let first = window.firstTreatmentDate ?? populatedNights.last?.sessionDate
        guard let first else { return "All available local dates" }
        return "\(first) – \(window.lastTreatmentDate) · \(window.timeZone.identifier) · 6 p.m. rollover"
    }

    var healthQueryDescription: String {
        guard let query = healthQueryWindow else { return "Apple Health has not been queried for this report." }
        let formatter = DateFormatter(); formatter.locale = .current; formatter.timeZone = query.timeZone
        formatter.dateStyle = .medium; formatter.timeStyle = .short
        let period = "Apple Health query requested \(formatter.string(from: query.healthQueryStart)) – \(formatter.string(from: query.asOf)) (\(query.timeZone.identifier)); up to \(query.healthQueryDays) treatment nights."
        if query.range != selectedRange { return period + " The selected range has changed; refresh coverage is pending." }
        let coverage = query.healthQueryTruncatesPriorPeriod
            ? " The 730-night limit omits the beginning of the preceding calendar period."
            : (query.range == .all ? " All Time includes local history beyond provider retrieval." : " Query bounds include the selected and preceding periods.")
        return period + coverage + " Query bounds do not establish complete sleep measurements."
    }

    var explicitDayTypeCount: Int {
        populatedNights.filter { !$0.outcomeReadFailed && $0.outcome?.dayType != nil && $0.outcome?.dayType != .unknown }.count
    }
    var timedSleepinessCount: Int {
        populatedNights.filter {
            guard !$0.outcomeReadFailed, let value = $0.outcome?.sleepiness,
                  let assessed = $0.outcome?.assessedAt else { return false }
            return (0...10).contains(value) && assessed.timeIntervalSince1970.isFinite && assessed <= now()
        }.count
    }
    var recordedFinalWakeCount: Int {
        populatedNights.filter {
            guard !$0.outcomeReadFailed, let wake = $0.outcome?.finalWakeAt else { return false }
            return wake.timeIntervalSince1970.isFinite && wake <= now()
        }.count
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

    /// Finished civil nights only; gaps break the streak and the selected range bounds it.
    var finishedNightStreak: Int {
        guard let window = currentReportWindow else { return 0 }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = window.timeZone
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = window.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        guard let anchor = calendar.date(byAdding: .day, value: -1, to: window.endExclusive) else { return 0 }
        let eligibleKeys = Set(populatedNights.filter { $0.onTimeDosing == true }.map(\.sessionDate))
        var cursor = anchor
        var count = 0
        while let previous = calendar.date(byAdding: .day, value: -1, to: cursor),
              eligibleKeys.contains(formatter.string(from: previous)) {
            count += 1
            cursor = previous
        }
        return count
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
