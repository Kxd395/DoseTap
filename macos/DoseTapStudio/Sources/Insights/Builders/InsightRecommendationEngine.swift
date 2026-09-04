import Foundation

enum InsightRecommendationMode: String, CaseIterable, Identifiable, Sendable {
    case restfulSleep = "restful_sleep"
    case naturalWakeProbability = "natural_wake_probability"
    case nextDayFunction = "next_day_function"
    case workNightSafety = "work_night_safety"

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .restfulSleep:
            return "Restful Sleep Insight"
        case .naturalWakeProbability:
            return "Natural Wake Insight"
        case .nextDayFunction:
            return "Next-Day Function Insight"
        case .workNightSafety:
            return "Work-Night Safety Insight"
        }
    }

    var summaryLabel: String {
        switch self {
        case .restfulSleep:
            return "restful sleep"
        case .naturalWakeProbability:
            return "natural wake probability"
        case .nextDayFunction:
            return "next-day function"
        case .workNightSafety:
            return "work-night safety"
        }
    }

    var transparencySummary: String {
        switch self {
        case .restfulSleep:
            return "Composite uses morning sleep quality, readiness, total sleep, efficiency, wake disruption, stage balance, and wearable recovery signals."
        case .naturalWakeProbability:
            return "Composite uses natural-wake rate, alarm dependence, wake disruption, stage balance, and respiratory/restorative sleep context."
        case .nextDayFunction:
            return "Composite uses readiness, clarity, sleep inertia, driving confidence, sleepiness burden, stage balance, and wearable recovery signals."
        case .workNightSafety:
            return "Composite uses driving confidence, daytime sleepiness, cataplexy burden, alarm dependence, skip/late risk, stage balance, and wearable recovery signals."
        }
    }
}

struct InsightTimingBand: Hashable, Sendable {
    let label: String
    let minMinutes: Int
    let maxMinutes: Int

    func contains(_ intervalMinutes: Int) -> Bool {
        (minMinutes...maxMinutes).contains(intervalMinutes)
    }
}

struct InsightRecommendationCandidate: Hashable, Sendable, Identifiable {
    let band: InsightTimingBand
    let sampleCount: Int
    let averageScore: Double
    let averageSleepQuality: Double?
    let averageReadiness: Double?
    let averageTotalSleepMinutes: Double?
    let averageSleepEfficiency: Double?
    let averageWakeDisruptionCount: Double?
    let naturalWakeRate: Double?
    let averageDrivingConfidence: Double?
    let averageDaytimeSleepiness: Double?
    let averageHRV: Double?
    let averageRestingHeartRate: Double?
    let averageRespiratoryRate: Double?
    let averageRestorativeSleepRatio: Double?
    let averageSleepStageBalance: Double?
    let alarmDependenceRate: Double?
    let skipLateRiskRate: Double?
    let operationalRiskRate: Double?

    var id: String { band.label }
}

struct InsightRecommendationNightDetail: Hashable, Sendable, Identifiable {
    let sessionDate: String
    let intervalMinutes: Int?
    let bandLabel: String?
    let score: Double?
    let sleepQuality: Double?
    let readiness: Int?
    let wakeType: String
    let nightType: String
    let exclusionReasons: [String]
    let trainable: Bool

    var id: String { sessionDate }
}

struct InsightRecommendationResult: Hashable, Sendable {
    let mode: InsightRecommendationMode
    let cohortKey: String?
    let cohortDescription: String
    let confidenceBucket: InsightConfidenceBucket
    let recommendedBand: InsightTimingBand?
    let nightsUsed: Int
    let nightsExcluded: Int
    let summary: String
    let topFactors: [String]
    let matchedNights: [InsightRecommendationNightDetail]
    let excludedNights: [InsightRecommendationNightDetail]
    let disclaimer: String
    let candidates: [InsightRecommendationCandidate]
}

struct InsightRecommendationEngine {
    static let defaultBands: [InsightTimingBand] = [
        InsightTimingBand(label: "150-165", minMinutes: 150, maxMinutes: 165),
        InsightTimingBand(label: "166-180", minMinutes: 166, maxMinutes: 180),
        InsightTimingBand(label: "181-210", minMinutes: 181, maxMinutes: 210),
        InsightTimingBand(label: "211-240", minMinutes: 211, maxMinutes: 240)
    ]

    private struct CohortBandBaseline {
        let averageHRV: Double?
        let averageRestingHeartRate: Double?
        let averageRespiratoryRate: Double?
        let averageRestorativeSleepRatio: Double?
        let averageSleepStageBalance: Double?
        let averageWakeDisruptionCount: Double?
        let averageAlarmDependenceRate: Double?
        let averageSkipLateRiskRate: Double?
        let averageOperationalRiskRate: Double?
    }

    func recommend(
        sessions: [InsightSession],
        mode: InsightRecommendationMode,
        preferredCohortKey: String? = nil
    ) -> InsightRecommendationResult {
        let recommendationCandidates = sessions.filter {
            $0.intervalMinutes != nil || $0.anchoredIntervalMinutes != nil || $0.dose2Skipped
        }
        let trainable = recommendationCandidates.filter(\.countsTowardRecommendationTraining)
        let cohortKey = preferredCohortKey ?? mostCommonCohortKey(from: trainable)

        guard let cohortKey else {
            return InsightRecommendationResult(
                mode: mode,
                cohortKey: nil,
                cohortDescription: "No comparable cohort is established yet.",
                confidenceBucket: .insufficient,
                recommendedBand: nil,
                nightsUsed: 0,
                nightsExcluded: recommendationCandidates.count,
                summary: "Not enough comparable nights yet.",
                topFactors: [],
                matchedNights: [],
                excludedNights: recommendationCandidates.map { makeNightDetail(for: $0, bands: Self.defaultBands, mode: mode) },
                disclaimer: disclaimerText,
                candidates: []
            )
        }

        let cohortSessions = recommendationCandidates.filter { $0.comparableCohortKey == cohortKey }
        let eligibleSessions = cohortSessions.filter(\.countsTowardRecommendationTraining)
        let anchoredCohortSessions = cohortSessions.filter { $0.anchoredIntervalMinutes != nil }
        let baseline = CohortBandBaseline(
            averageHRV: average(eligibleSessions.compactMap(\.hrvMs)),
            averageRestingHeartRate: average(eligibleSessions.compactMap(\.restingHeartRate)),
            averageRespiratoryRate: average(eligibleSessions.compactMap(\.respiratoryRate)),
            averageRestorativeSleepRatio: average(eligibleSessions.compactMap(\.restorativeSleepRatio)),
            averageSleepStageBalance: average(eligibleSessions.compactMap(\.sleepStageBalanceScore)),
            averageWakeDisruptionCount: average(eligibleSessions.compactMap(\.wakeDisruptionCount).map(Double.init)),
            averageAlarmDependenceRate: rate(for: anchoredCohortSessions) { $0.likelyNaturalWake == false },
            averageSkipLateRiskRate: rate(for: anchoredCohortSessions) { $0.hasSkipOrLateRiskSignal },
            averageOperationalRiskRate: average(eligibleSessions.map(\.operationalRiskRate))
        )

        let candidates = Self.defaultBands.compactMap { band -> InsightRecommendationCandidate? in
            let bandSessions = eligibleSessions.filter {
                guard let intervalMinutes = $0.intervalMinutes else { return false }
                return band.contains(intervalMinutes)
            }
            guard !bandSessions.isEmpty else { return nil }
            let bandAnchoredSessions = anchoredCohortSessions.filter {
                guard let anchoredIntervalMinutes = $0.anchoredIntervalMinutes else { return false }
                return band.contains(anchoredIntervalMinutes)
            }

            let averageSleepQuality = average(bandSessions.compactMap(\.morningSleepQuality))
            let averageReadiness = average(bandSessions.compactMap(\.morningReadiness).map(Double.init))
            let averageTotalSleepMinutes = average(bandSessions.compactMap(\.totalSleepMinutes))
            let averageSleepEfficiency = average(bandSessions.compactMap(\.sleepEfficiency))
            let averageWakeDisruptionCount = average(bandSessions.compactMap(\.wakeDisruptionCount).map(Double.init))
            let naturalWakeRate = naturalWakeRate(for: bandSessions)
            let alarmDependenceRate = rate(for: bandAnchoredSessions) { $0.likelyNaturalWake == false }
            let averageDrivingConfidence = average(bandSessions.compactMap { $0.morning?.drivingConfidence }.map(Double.init))
            let averageDaytimeSleepiness = average(bandSessions.compactMap { $0.morning?.daytimeSleepiness }.map(Double.init))
            let averageHRV = average(bandSessions.compactMap(\.hrvMs))
            let averageRestingHeartRate = average(bandSessions.compactMap(\.restingHeartRate))
            let averageRespiratoryRate = average(bandSessions.compactMap(\.respiratoryRate))
            let averageRestorativeSleepRatio = average(bandSessions.compactMap(\.restorativeSleepRatio))
            let averageSleepStageBalance = average(bandSessions.compactMap(\.sleepStageBalanceScore))
            let skipLateRiskRate = rate(for: bandAnchoredSessions) { $0.hasSkipOrLateRiskSignal }
            let operationalRiskRate = average(bandSessions.map(\.operationalRiskRate))

            let score = candidateScore(
                sessions: bandSessions,
                mode: mode,
                baseline: baseline,
                averageSleepEfficiency: averageSleepEfficiency,
                averageWakeDisruptionCount: averageWakeDisruptionCount,
                naturalWakeRate: naturalWakeRate,
                alarmDependenceRate: alarmDependenceRate,
                averageDrivingConfidence: averageDrivingConfidence,
                averageDaytimeSleepiness: averageDaytimeSleepiness,
                averageHRV: averageHRV,
                averageRestingHeartRate: averageRestingHeartRate,
                averageRespiratoryRate: averageRespiratoryRate,
                averageRestorativeSleepRatio: averageRestorativeSleepRatio,
                averageSleepStageBalance: averageSleepStageBalance,
                skipLateRiskRate: skipLateRiskRate,
                operationalRiskRate: operationalRiskRate
            )
            guard let score else { return nil }

            return InsightRecommendationCandidate(
                band: band,
                sampleCount: bandSessions.count,
                averageScore: score,
                averageSleepQuality: averageSleepQuality,
                averageReadiness: averageReadiness,
                averageTotalSleepMinutes: averageTotalSleepMinutes,
                averageSleepEfficiency: averageSleepEfficiency,
                averageWakeDisruptionCount: averageWakeDisruptionCount,
                naturalWakeRate: naturalWakeRate,
                averageDrivingConfidence: averageDrivingConfidence,
                averageDaytimeSleepiness: averageDaytimeSleepiness,
                averageHRV: averageHRV,
                averageRestingHeartRate: averageRestingHeartRate,
                averageRespiratoryRate: averageRespiratoryRate,
                averageRestorativeSleepRatio: averageRestorativeSleepRatio,
                averageSleepStageBalance: averageSleepStageBalance,
                alarmDependenceRate: alarmDependenceRate,
                skipLateRiskRate: skipLateRiskRate,
                operationalRiskRate: operationalRiskRate
            )
        }
        .sorted {
            if $0.averageScore == $1.averageScore {
                return $0.sampleCount > $1.sampleCount
            }
            return $0.averageScore > $1.averageScore
        }

        guard let best = candidates.first else {
            return InsightRecommendationResult(
                mode: mode,
                cohortKey: cohortKey,
                cohortDescription: cohortDescription(for: cohortSessions, cohortKey: cohortKey),
                confidenceBucket: .insufficient,
                recommendedBand: nil,
                nightsUsed: 0,
                nightsExcluded: cohortSessions.count,
                summary: "Comparable nights exist, but none have enough outcome data for \(mode.summaryLabel).",
                topFactors: [],
                matchedNights: cohortSessions.map { makeNightDetail(for: $0, bands: Self.defaultBands, mode: mode) },
                excludedNights: cohortSessions
                    .filter { !$0.countsTowardRecommendationTraining }
                    .map { makeNightDetail(for: $0, bands: Self.defaultBands, mode: mode) },
                disclaimer: disclaimerText,
                candidates: []
            )
        }

        let confidence = confidenceBucket(for: best.sampleCount, totalEligible: eligibleSessions.count)
        let cohortDescription = cohortDescription(for: cohortSessions, cohortKey: cohortKey)
        let summary: String
        if confidence == .insufficient {
            summary = "Not enough evidence in cohort \(cohortKey) yet."
        } else {
            summary = "\(best.band.label) minutes is historically associated with the strongest \(mode.summaryLabel) outcomes in cohort \(cohortKey), based on \(best.sampleCount) comparable night\(best.sampleCount == 1 ? "" : "s")."
        }

        return InsightRecommendationResult(
            mode: mode,
            cohortKey: cohortKey,
            cohortDescription: cohortDescription,
            confidenceBucket: confidence,
            recommendedBand: confidence == .insufficient ? nil : best.band,
            nightsUsed: eligibleSessions.count,
            nightsExcluded: max(0, cohortSessions.count - eligibleSessions.count),
            summary: summary,
            topFactors: topFactors(best: best, runnerUp: candidates.dropFirst().first, mode: mode),
            matchedNights: eligibleSessions.map { makeNightDetail(for: $0, bands: Self.defaultBands, mode: mode) }
                .sorted { lhs, rhs in
                    if lhs.score == rhs.score {
                        return lhs.sessionDate > rhs.sessionDate
                    }
                    return (lhs.score ?? 0) > (rhs.score ?? 0)
                },
            excludedNights: cohortSessions
                .filter { !$0.countsTowardRecommendationTraining }
                .map { makeNightDetail(for: $0, bands: Self.defaultBands, mode: mode) }
                .sorted { $0.sessionDate > $1.sessionDate },
            disclaimer: disclaimerText,
            candidates: candidates
        )
    }

    var disclaimerText: String {
        "Observational insight only. This does not recommend dosing outside the prescribed 150-240 minute window and is not prescribing guidance."
    }

    private func mostCommonCohortKey(from sessions: [InsightSession]) -> String? {
        Dictionary(grouping: sessions, by: \.comparableCohortKey)
            .max { lhs, rhs in lhs.value.count < rhs.value.count }?
            .key
    }

    private func score(session: InsightSession, mode: InsightRecommendationMode) -> Double? {
        switch mode {
        case .restfulSleep:
            return average([
                normalizedFivePoint(session.morningSleepQuality),
                normalizedFivePoint(session.morningReadiness),
                normalizedPercent(session.sleepEfficiency),
                normalizedMinutes(session.totalSleepMinutes, target: 480)
            ])
        case .naturalWakeProbability:
            switch session.likelyNaturalWake {
            case true:
                return 1.0
            case false:
                return 0.0
            case nil:
                return nil
            }
        case .nextDayFunction:
            return average([
                normalizedFivePoint(session.morningReadiness),
                normalizedFivePoint(session.morning?.mentalClarity),
                inverseInertiaScore(session.morning?.sleepInertiaDuration),
                normalizedFivePoint(session.morning?.drivingConfidence),
                inverseFivePoint(session.morning?.daytimeSleepiness),
                cataplexySafetyScore(session.morning?.cataplexyBurden)
            ])
        case .workNightSafety:
            let weekdayBias = session.classification.tags.contains(.weekdayDemandNight) ? 1.0 : 0.8
            let base = average([
                normalizedFivePoint(session.morningReadiness),
                normalizedFivePoint(session.morning?.drivingConfidence),
                inverseFivePoint(session.morning?.daytimeSleepiness),
                cataplexySafetyScore(session.morning?.cataplexyBurden),
                inverseInertiaScore(session.morning?.sleepInertiaDuration),
                session.likelyNaturalWake == false ? 0.8 : 1.0
            ])
            let commuteBias: Double
            if session.hasLongCommuteBurden {
                commuteBias = 0.9
            } else {
                commuteBias = 1.0
            }
            let forcedWakeBias = session.classification.tags.contains(.forcedWakeNight) ? 0.9 : 1.0
            return base.map { $0 * weekdayBias * commuteBias * forcedWakeBias }
        }
    }

    private func candidateScore(
        sessions: [InsightSession],
        mode: InsightRecommendationMode,
        baseline: CohortBandBaseline,
        averageSleepEfficiency: Double?,
        averageWakeDisruptionCount: Double?,
        naturalWakeRate: Double?,
        alarmDependenceRate: Double?,
        averageDrivingConfidence: Double?,
        averageDaytimeSleepiness: Double?,
        averageHRV: Double?,
        averageRestingHeartRate: Double?,
        averageRespiratoryRate: Double?,
        averageRestorativeSleepRatio: Double?,
        averageSleepStageBalance: Double?,
        skipLateRiskRate: Double?,
        operationalRiskRate: Double?
    ) -> Double? {
        let baseOutcome = average(sessions.compactMap { score(session: $0, mode: mode) })
        let hrvScore = positiveDeltaScore(averageHRV, baseline: baseline.averageHRV, spread: 8)
        let restingHeartRateScore = inverseDeltaScore(averageRestingHeartRate, baseline: baseline.averageRestingHeartRate, spread: 4)
        let respiratoryRateScore = inverseDeltaScore(averageRespiratoryRate, baseline: baseline.averageRespiratoryRate, spread: 1.2)
        let restorativeSleepScore = positiveDeltaScore(averageRestorativeSleepRatio, baseline: baseline.averageRestorativeSleepRatio, spread: 0.06)
        let sleepStageBalanceScore = positiveDeltaScore(averageSleepStageBalance, baseline: baseline.averageSleepStageBalance, spread: 0.12)
        let wakeDisruptionScore = inverseDeltaScore(averageWakeDisruptionCount, baseline: baseline.averageWakeDisruptionCount, spread: 1.0)
        let alarmDependenceScore = inverseDeltaScore(alarmDependenceRate, baseline: baseline.averageAlarmDependenceRate, spread: 0.2)
        let skipLateRiskScore = inverseDeltaScore(skipLateRiskRate, baseline: baseline.averageSkipLateRiskRate, spread: 0.2)
        let operationalRiskScore = inverseDeltaScore(operationalRiskRate, baseline: baseline.averageOperationalRiskRate, spread: 0.2)

        switch mode {
        case .restfulSleep:
            return average([
                baseOutcome,
                normalizedPercent(averageSleepEfficiency),
                normalizedMinutes(average(sessions.compactMap(\.totalSleepMinutes)), target: 480),
                restorativeSleepScore,
                sleepStageBalanceScore,
                wakeDisruptionScore,
                alarmDependenceScore,
                skipLateRiskScore,
                hrvScore,
                restingHeartRateScore,
                respiratoryRateScore
            ])
        case .naturalWakeProbability:
            return average([
                baseOutcome,
                naturalWakeRate,
                alarmDependenceScore,
                wakeDisruptionScore,
                restorativeSleepScore,
                sleepStageBalanceScore,
                respiratoryRateScore,
                skipLateRiskScore,
                operationalRiskScore
            ])
        case .nextDayFunction:
            return average([
                baseOutcome,
                hrvScore,
                restingHeartRateScore,
                respiratoryRateScore,
                wakeDisruptionScore,
                sleepStageBalanceScore,
                skipLateRiskScore,
                inverseFivePoint(averageDaytimeSleepiness.map { Int($0.rounded()) }),
                normalizedFivePoint(averageDrivingConfidence.map { Int($0.rounded()) })
            ])
        case .workNightSafety:
            return average([
                baseOutcome,
                normalizedFivePoint(averageDrivingConfidence.map { Int($0.rounded()) }),
                inverseFivePoint(averageDaytimeSleepiness.map { Int($0.rounded()) }),
                alarmDependenceScore,
                skipLateRiskScore,
                wakeDisruptionScore,
                operationalRiskScore,
                sleepStageBalanceScore,
                hrvScore,
                restingHeartRateScore,
                respiratoryRateScore
            ])
        }
    }

    private func confidenceBucket(for bestSampleCount: Int, totalEligible: Int) -> InsightConfidenceBucket {
        if bestSampleCount >= 4 && totalEligible >= 8 {
            return .high
        }
        if bestSampleCount >= 3 && totalEligible >= 5 {
            return .medium
        }
        if bestSampleCount >= 2 && totalEligible >= 3 {
            return .low
        }
        return .insufficient
    }

    private func normalizedFivePoint(_ value: Int?) -> Double? {
        guard let value else { return nil }
        return min(max(Double(value) / 5.0, 0), 1)
    }

    private func normalizedFivePoint(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return min(max(value / 5.0, 0), 1)
    }

    private func normalizedPercent(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return min(max(value / 100.0, 0), 1)
    }

    private func positiveDeltaScore(_ value: Double?, baseline: Double?, spread: Double) -> Double? {
        guard let value else { return nil }
        guard let baseline else { return nil }
        let normalized = 0.5 + ((value - baseline) / max(spread, 0.0001)) * 0.5
        return min(max(normalized, 0), 1)
    }

    private func inverseDeltaScore(_ value: Double?, baseline: Double?, spread: Double) -> Double? {
        guard let value else { return nil }
        guard let baseline else { return nil }
        let normalized = 0.5 - ((value - baseline) / max(spread, 0.0001)) * 0.5
        return min(max(normalized, 0), 1)
    }

    private func inverseFivePoint(_ value: Int?) -> Double? {
        guard let value else { return nil }
        let clamped = min(max(value, 1), 5)
        return 1.0 - (Double(clamped - 1) / 4.0)
    }

    private func normalizedMinutes(_ value: Double?, target: Double) -> Double? {
        guard let value else { return nil }
        return min(max(value / target, 0), 1)
    }

    private func inverseInertiaScore(_ rawValue: String?) -> Double? {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "none", "<5 minutes", "lessthanfive":
            return 1.0
        case "5-15 minutes", "fivetofifteen":
            return 0.8
        case "15-30 minutes", "fifteentothirty":
            return 0.6
        case "30-60 minutes", "thirtytosixty":
            return 0.4
        case ">1 hour", "morethanhour":
            return 0.0
        default:
            return nil
        }
    }

    private func naturalWakeRate(for sessions: [InsightSession]) -> Double? {
        let classified = sessions.compactMap(\.likelyNaturalWake)
        guard !classified.isEmpty else { return nil }
        let naturalCount = classified.filter { $0 }.count
        return Double(naturalCount) / Double(classified.count)
    }

    private func rate(for sessions: [InsightSession], matching predicate: (InsightSession) -> Bool) -> Double? {
        guard !sessions.isEmpty else { return nil }
        let matches = sessions.filter(predicate).count
        return Double(matches) / Double(sessions.count)
    }

    private func cataplexySafetyScore(_ rawValue: String?) -> Double? {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "none":
            return 1.0
        case "mild":
            return 0.75
        case "moderate":
            return 0.4
        case "severe":
            return 0.0
        case "unsure":
            return nil
        default:
            return nil
        }
    }

    private func cohortDescription(for sessions: [InsightSession], cohortKey: String) -> String {
        guard !sessions.isEmpty else { return "No comparable nights in cohort \(cohortKey)." }

        let workCount = sessions.filter { $0.nightTypeFilter == .work }.count
        let offCount = sessions.filter { $0.nightTypeFilter == .off }.count
        let transitionCount = sessions.filter { $0.nightTypeFilter == .transition }.count
        let naturalCount = sessions.filter { $0.nightWakeFilter == .natural }.count
        let alarmCount = sessions.filter { $0.nightWakeFilter == .alarm }.count
        let highDemandCount = sessions.filter { $0.scheduleFilter == .highDemand }.count
        let forcedWakeCount = sessions.filter { $0.classification.tags.contains(.forcedWakeNight) }.count
        let sleepTherapyCount = sessions.filter(\.hasSleepTherapyContext).count
        let clinicalContextCount = sessions.filter(\.hasClinicalContext).count
        let fastMetabolizerCount = sessions.filter(\.hasFastMetabolizerReference).count

        let scheduleLabel: String
        if transitionCount > max(workCount, offCount) {
            scheduleLabel = "transition nights"
        } else if workCount >= offCount {
            scheduleLabel = "mostly work nights"
        } else {
            scheduleLabel = "mostly off nights"
        }

        let wakeLabel: String
        if naturalCount > alarmCount {
            wakeLabel = "mostly natural wake"
        } else if alarmCount > 0 {
            wakeLabel = "mostly alarm-dependent wake"
        } else {
            wakeLabel = "mixed wake pattern"
        }

        let demandLabel = highDemandCount > 0 ? "with high next-day demand represented" : "with baseline next-day demand"
        let forcedWakeLabel = forcedWakeCount > 0 ? ", \(forcedWakeCount) forced-wake night(s)" : ""
        let therapyLabel = sleepTherapyCount > 0 ? ", \(sleepTherapyCount) sleep-therapy night(s)" : ""
        let clinicalLabel = clinicalContextCount > 0 ? ", \(clinicalContextCount) clinical-context night(s)" : ""
        let metabolizerLabel = fastMetabolizerCount > 0 ? ", \(fastMetabolizerCount) fast-metabolizer reference night(s)" : ""
        return "Cohort \(cohortKey) covers \(sessions.count) comparable nights: \(scheduleLabel), \(wakeLabel), \(demandLabel)\(forcedWakeLabel)\(therapyLabel)\(clinicalLabel)\(metabolizerLabel)."
    }

    private func topFactors(
        best: InsightRecommendationCandidate,
        runnerUp: InsightRecommendationCandidate?,
        mode: InsightRecommendationMode
    ) -> [String] {
        var factors: [String] = []

        if let sleepQuality = metricDelta(best.averageSleepQuality, runnerUp?.averageSleepQuality, decimals: 1, suffix: " / 5") {
            factors.append("Higher average sleep quality \(sleepQuality)")
        }
        if let readiness = metricDelta(best.averageReadiness, runnerUp?.averageReadiness, decimals: 1, suffix: " / 5") {
            factors.append("Higher average readiness \(readiness)")
        }
        if let totalSleep = metricDelta(best.averageTotalSleepMinutes, runnerUp?.averageTotalSleepMinutes, decimals: 0, suffix: " min") {
            factors.append("More total sleep \(totalSleep)")
        }
        if let wakeRate = metricDelta(best.naturalWakeRate.map { $0 * 100 }, runnerUp?.naturalWakeRate.map { $0 * 100 }, decimals: 0, suffix: "%") {
            factors.append("Better natural wake rate \(wakeRate)")
        }
        if let alarmDependence = inverseMetricDelta(best.alarmDependenceRate.map { $0 * 100 }, runnerUp?.alarmDependenceRate.map { $0 * 100 }, decimals: 0, suffix: "%") {
            factors.append("Lower alarm dependence \(alarmDependence)")
        }
        if let drivingConfidence = metricDelta(best.averageDrivingConfidence, runnerUp?.averageDrivingConfidence, decimals: 1, suffix: " / 5") {
            factors.append("Higher driving confidence \(drivingConfidence)")
        }
        if let daytimeSleepiness = inverseMetricDelta(best.averageDaytimeSleepiness, runnerUp?.averageDaytimeSleepiness, decimals: 1, suffix: " / 5") {
            factors.append("Lower daytime sleepiness \(daytimeSleepiness)")
        }
        if let sleepEfficiency = metricDelta(best.averageSleepEfficiency, runnerUp?.averageSleepEfficiency, decimals: 1, suffix: "%") {
            factors.append("Higher sleep efficiency \(sleepEfficiency)")
        }
        if let hrv = metricDelta(best.averageHRV, runnerUp?.averageHRV, decimals: 1, suffix: " ms") {
            factors.append("Higher HRV \(hrv)")
        }
        if let restingHeartRate = inverseMetricDelta(best.averageRestingHeartRate, runnerUp?.averageRestingHeartRate, decimals: 1, suffix: " bpm") {
            factors.append("Lower resting HR \(restingHeartRate)")
        }
        if let respiratoryRate = inverseMetricDelta(best.averageRespiratoryRate, runnerUp?.averageRespiratoryRate, decimals: 1, suffix: " br/min") {
            factors.append("Lower respiratory rate \(respiratoryRate)")
        }
        if let restorativeRatio = metricDelta(best.averageRestorativeSleepRatio.map { $0 * 100 }, runnerUp?.averageRestorativeSleepRatio.map { $0 * 100 }, decimals: 0, suffix: "%") {
            factors.append("More restorative sleep \(restorativeRatio)")
        }
        if let stageBalance = metricDelta(best.averageSleepStageBalance, runnerUp?.averageSleepStageBalance, decimals: 2, suffix: "") {
            factors.append("Better sleep-stage balance \(stageBalance)")
        }
        if let disruption = inverseMetricDelta(best.averageWakeDisruptionCount, runnerUp?.averageWakeDisruptionCount, decimals: 1, suffix: " wakes") {
            factors.append("Lower wake disruption \(disruption)")
        }
        if let risk = inverseMetricDelta(best.operationalRiskRate.map { $0 * 100 }, runnerUp?.operationalRiskRate.map { $0 * 100 }, decimals: 0, suffix: "%") {
            factors.append("Lower operational risk \(risk)")
        }
        if let skipLateRisk = inverseMetricDelta(best.skipLateRiskRate.map { $0 * 100 }, runnerUp?.skipLateRiskRate.map { $0 * 100 }, decimals: 0, suffix: "%") {
            factors.append("Lower skip / late risk \(skipLateRisk)")
        }

        if factors.isEmpty {
            factors.append("Largest usable sample in the cohort (\(best.sampleCount) nights)")
        }

        switch mode {
        case .naturalWakeProbability:
            return factors.filter {
                $0.contains("natural wake") ||
                $0.contains("alarm dependence") ||
                $0.contains("wake disruption") ||
                $0.contains("skip / late risk") ||
                $0.contains("respiratory rate") ||
                $0.contains("operational risk") ||
                $0.contains("sample")
            }
        case .workNightSafety:
            return factors.filter {
                $0.contains("readiness") ||
                $0.contains("wake disruption") ||
                $0.contains("sleep quality") ||
                $0.contains("sleep-stage balance") ||
                $0.contains("driving confidence") ||
                $0.contains("daytime sleepiness") ||
                $0.contains("alarm dependence") ||
                $0.contains("skip / late risk") ||
                $0.contains("operational risk") ||
                $0.contains("resting HR") ||
                $0.contains("respiratory rate") ||
                $0.contains("HRV") ||
                $0.contains("sample")
            }
        default:
            return Array(factors.prefix(3))
        }
    }

    private func metricDelta(_ best: Double?, _ runnerUp: Double?, decimals: Int, suffix: String) -> String? {
        guard let best else { return nil }
        if let runnerUp, abs(best - runnerUp) < 0.05 {
            return nil
        }
        return "(\(formatted(best, decimals: decimals))\(suffix)\(runnerUp.map { " vs \(formatted($0, decimals: decimals))\(suffix)" } ?? ""))"
    }

    private func inverseMetricDelta(_ best: Double?, _ runnerUp: Double?, decimals: Int, suffix: String) -> String? {
        guard let best, let runnerUp else { return nil }
        if best >= runnerUp {
            return nil
        }
        return "(\(formatted(best, decimals: decimals))\(suffix) vs \(formatted(runnerUp, decimals: decimals))\(suffix))"
    }

    private func formatted(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", value)
    }

    private func makeNightDetail(
        for session: InsightSession,
        bands: [InsightTimingBand],
        mode: InsightRecommendationMode
    ) -> InsightRecommendationNightDetail {
        let bandLabel = (session.intervalMinutes ?? session.anchoredIntervalMinutes).flatMap { interval in
            bands.first(where: { $0.contains(interval) })?.label
        }
        return InsightRecommendationNightDetail(
            sessionDate: session.sessionDate,
            intervalMinutes: session.intervalMinutes,
            bandLabel: bandLabel,
            score: score(session: session, mode: mode),
            sleepQuality: session.morningSleepQuality,
            readiness: session.morningReadiness,
            wakeType: session.wakeSignalLabel,
            nightType: session.explicitNightTypeLabel ?? session.nightTypeFilter.rawValue,
            exclusionReasons: session.classification.exclusionReasons,
            trainable: session.countsTowardRecommendationTraining
        )
    }

    private func average(_ values: [Double?]) -> Double? {
        average(values.compactMap { $0 })
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
