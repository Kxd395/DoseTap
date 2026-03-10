import Foundation

extension DashboardAnalyticsModel {
    // MARK: - Mood & Symptom Metrics (from Morning Check-In)

    private var nightsWithCheckIn: [DashboardNightAggregate] {
        populatedNights.filter { $0.morningCheckIn != nil }
    }

    var averageMentalClarity: Double? {
        let values = nightsWithCheckIn.compactMap { $0.morningCheckIn?.mentalClarity }
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    var moodDistribution: [String: Int] {
        var counts: [String: Int] = [:]
        for night in nightsWithCheckIn {
            let mood = night.morningCheckIn?.mood ?? "unknown"
            counts[mood, default: 0] += 1
        }
        return counts
    }

    var anxietyDistribution: [String: Int] {
        var counts: [String: Int] = [:]
        for night in nightsWithCheckIn {
            let level = night.morningCheckIn?.anxietyLevel ?? "unknown"
            counts[level, default: 0] += 1
        }
        return counts
    }

    var averageMorningStressLevel: Double? {
        let values = nightsWithCheckIn.compactMap { $0.morningCheckIn?.stressLevel }
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    var highMorningStressRate: Double? {
        percentage(
            matching: nightsWithCheckIn.compactMap { $0.morningCheckIn?.stressLevel },
            where: { $0 >= 4 }
        )
    }

    var averageStressDeltaToWake: Double? {
        let deltas = populatedNights.compactMap { night -> Double? in
            guard
                let preSleep = night.preSleepLog?.answers?.stressLevel,
                let morning = night.morningCheckIn?.stressLevel
            else {
                return nil
            }
            return Double(morning - preSleep)
        }
        guard !deltas.isEmpty else { return nil }
        return deltas.reduce(0, +) / Double(deltas.count)
    }

    var morningStressDriverCounts: [CommonStressDriver: Int] {
        let drivers = nightsWithCheckIn.flatMap { $0.morningCheckIn?.resolvedStressDrivers ?? [] }
        return counts(for: drivers)
    }

    var topMorningStressDriver: CommonStressDriver? {
        topKey(in: morningStressDriverCounts)
    }

    var morningStressProgressionCounts: [CommonStressProgression: Int] {
        let progression = nightsWithCheckIn.compactMap { $0.morningCheckIn?.stressProgression }
        return counts(for: progression)
    }

    var worseByWakeStressRate: Double? {
        percentage(
            matching: nightsWithCheckIn.compactMap { $0.morningCheckIn?.stressProgression },
            where: { $0 == .worse || $0 == .muchWorse }
        )
    }

    var grogginessDistribution: [String: Int] {
        var counts: [String: Int] = [:]
        for night in nightsWithCheckIn {
            let g = night.morningCheckIn?.grogginess ?? "unknown"
            counts[g, default: 0] += 1
        }
        return counts
    }

    var narcolepsySymptomRate: Double? {
        guard !nightsWithCheckIn.isEmpty else { return nil }
        let symptomatic = nightsWithCheckIn.filter { $0.morningCheckIn?.hasNarcolepsySymptoms == true }.count
        return (Double(symptomatic) / Double(nightsWithCheckIn.count)) * 100
    }

    var sleepParalysisCount: Int {
        nightsWithCheckIn.filter { $0.morningCheckIn?.hadSleepParalysis == true }.count
    }

    var hallucinationCount: Int {
        nightsWithCheckIn.filter { $0.morningCheckIn?.hadHallucinations == true }.count
    }

    var automaticBehaviorCount: Int {
        nightsWithCheckIn.filter { $0.morningCheckIn?.hadAutomaticBehavior == true }.count
    }

    var dreamRecallRate: Double? {
        guard !nightsWithCheckIn.isEmpty else { return nil }
        let recalls = nightsWithCheckIn.filter { $0.morningCheckIn?.dreamRecall != "none" }.count
        return (Double(recalls) / Double(nightsWithCheckIn.count)) * 100
    }

    // MARK: - Period Comparison

    struct PeriodDelta {
        let metricName: String
        let current: Double?
        let prior: Double?

        var delta: Double? {
            guard let c = current, let p = prior, p != 0 else { return nil }
            return ((c - p) / abs(p)) * 100
        }

        var isNew: Bool {
            guard let c = current, let p = prior else { return false }
            return p == 0 && c > 0
        }

        var improving: Bool? {
            guard let d = delta else { return nil }
            return d > 0
        }
    }

    var periodComparison: [PeriodDelta] {
        let prior = priorPeriodNights
        guard !prior.isEmpty else { return [] }
        let priorDosing = prior.filter { $0.dose1Time != nil || $0.dose2Time != nil || $0.dose2Skipped }

        func avg(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }

        func pct(_ count: Int, _ total: Int) -> Double? {
            total == 0 ? nil : (Double(count) / Double(total)) * 100
        }

        let priorOnTime: Double? = {
            let vals = priorDosing.compactMap(\.onTimeDosing)
            guard !vals.isEmpty else { return nil }
            return pct(vals.filter { $0 }.count, vals.count)
        }()
        let priorAvgInterval = avg(priorDosing.compactMap(\.intervalMinutes).map(Double.init))
        let priorAvgSleep = avg(prior.compactMap(\.totalSleepMinutes))
        let priorAvgQuality = avg(prior.compactMap { $0.morningCheckIn?.sleepQuality }.map(Double.init))

        let priorWhoopNights = prior.filter { $0.whoopSummary?.hasValidSleepData == true }
        let priorAvgRecovery = avg(priorWhoopNights.compactMap(\.whoopRecoveryScore))
        let priorAvgHRV = avg(priorWhoopNights.compactMap(\.whoopHRV))

        var deltas = [
            PeriodDelta(metricName: "On-Time %", current: onTimePercentage, prior: priorOnTime),
            PeriodDelta(metricName: "Avg Interval", current: averageIntervalMinutes, prior: priorAvgInterval),
            PeriodDelta(metricName: "Avg Sleep", current: averageSleepMinutes, prior: priorAvgSleep),
            PeriodDelta(metricName: "Sleep Quality", current: averageSleepQuality, prior: priorAvgQuality),
        ]

        if averageWhoopRecovery != nil || priorAvgRecovery != nil {
            deltas.append(PeriodDelta(metricName: "Recovery", current: averageWhoopRecovery, prior: priorAvgRecovery))
        }
        if averageWhoopHRV != nil || priorAvgHRV != nil {
            deltas.append(PeriodDelta(metricName: "HRV", current: averageWhoopHRV, prior: priorAvgHRV))
        }

        return deltas
    }
}
