import SwiftUI
import Charts
import DoseCore
import os.log
#if canImport(UIKit)
import UIKit
#endif

let dashboardLogger = Logger(subsystem: "com.dosetap.app", category: "Dashboard")

@MainActor
final class DashboardAnalyticsModel: ObservableObject {
    @Published var nights: [DashboardNightAggregate] = []
    @Published var integrationStates: [DashboardIntegrationState] = []
    @Published var isLoading = false
    @Published var lastRefresh: Date?
    @Published var errorMessage: String?
    @Published var selectedRange: DashboardDateRange = .month

    let sessionRepo = SessionRepository.shared
    let settings = UserSettingsManager.shared
    let healthKit = HealthKitService.shared
    let whoop = WHOOPService.shared
    let cloudSync = CloudKitSyncService.shared

    /// Cancels in-flight refresh when a new one starts (prevents race on rapid range changes).
    var refreshTask: Task<Void, Never>?

    static let keyFormatter: DateFormatter = AppFormatters.sessionDate

    // MARK: - Range-filtered views

    /// All nights that have any data, filtered to the selected range.
    var populatedNights: [DashboardNightAggregate] {
        let cutoff = selectedRange.cutoffDate()
        return nights.filter { night in
            guard night.hasAnyData else { return false }
            guard let d = Self.keyFormatter.date(from: night.sessionDate) else { return true }
            return d >= cutoff
        }
    }

    /// Prior-period equivalent of populatedNights for comparison.
    var priorPeriodNights: [DashboardNightAggregate] {
        guard selectedRange != .all else { return [] }
        let pp = selectedRange.priorPeriodCutoff()
        return nights.filter { night in
            guard night.hasAnyData else { return false }
            guard let d = Self.keyFormatter.date(from: night.sessionDate) else { return false }
            return d >= pp.start && d < pp.end
        }
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

    var averageIntervalMinutes: Double? {
        let intervals = dosingNights.compactMap(\.intervalMinutes)
        guard !intervals.isEmpty else { return nil }
        return Double(intervals.reduce(0, +)) / Double(intervals.count)
    }

    var completionRate: Double? {
        let eligible = dosingNights.filter { $0.dose1Time != nil }
        guard !eligible.isEmpty else { return nil }
        let completed = eligible.filter { $0.dose2Time != nil || $0.dose2Skipped }.count
        return (Double(completed) / Double(eligible.count)) * 100
    }

    var averageSnoozeCount: Double? {
        guard !dosingNights.isEmpty else { return nil }
        let total = dosingNights.reduce(0) { $0 + $1.snoozeCount }
        return Double(total) / Double(dosingNights.count)
    }

    var averageSleepMinutes: Double? {
        let values = populatedNights.compactMap(\.totalSleepMinutes)
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

    var averageBathroomWakeMinutes: Double? {
        let nightsWithBathroom = populatedNights.filter { $0.bathroomEventCount > 0 }
        guard !nightsWithBathroom.isEmpty else { return nil }
        let estimatedMinutes = nightsWithBathroom.reduce(0) { $0 + ($1.bathroomEventCount * 5) }
        return Double(estimatedMinutes) / Double(nightsWithBathroom.count)
    }

    // MARK: - WHOOP Aggregate Metrics

    /// Nights that have WHOOP data with valid sleep scores.
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
        let values = whoopNights.compactMap(\.whoopDeepSleepMinutes).map { Double($0) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageWhoopREMMinutes: Double? {
        let values = whoopNights.compactMap { $0.whoopSummary?.remMinutes }.map { Double($0) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageWhoopLightMinutes: Double? {
        let values = whoopNights.compactMap { $0.whoopSummary?.lightMinutes }.map { Double($0) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageWhoopAwakeMinutes: Double? {
        let values = whoopNights.compactMap { $0.whoopSummary?.awakeMinutes }.map { Double($0) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageWhoopDisturbances: Double? {
        let values = whoopNights.compactMap(\.whoopDisturbances).map { Double($0) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Check-in & Pre-Sleep Completion

    // MARK: - Dose Effectiveness Analysis

    /// Maps dashboard aggregates to DoseEffectivenessDataPoints and runs the calculator.
    var doseEffectivenessReport: DoseEffectivenessReport {
        let dataPoints: [DoseEffectivenessDataPoint] = populatedNights.map { night in
            DoseEffectivenessDataPoint(
                date: Self.keyFormatter.date(from: night.sessionDate) ?? Date(),
                intervalMinutes: night.intervalMinutes.map(Double.init),
                dose2Skipped: night.dose2Skipped,
                totalSleepMinutes: night.totalSleepMinutes,
                deepSleepMinutes: night.whoopDeepSleepMinutes.map(Double.init),
                recoveryScore: night.whoopRecoveryScore.map(Int.init),
                averageHRV: night.whoopHRV,
                awakenings: night.wakeCount ?? night.whoopDisturbances
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
        let withLog = populatedNights.filter { $0.preSleepLog != nil }.count
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

    // MARK: - Streaks

    var consecutiveOnTimeStreak: Int {
        var streak = 0
        let sorted = dosingNights.sorted { $0.sessionDate > $1.sessionDate }
        for night in sorted {
            guard night.onTimeDosing == true else { break }
            streak += 1
        }
        return streak
    }

    var duplicateNightCount: Int {
        populatedNights.filter { $0.duplicateClusterCount > 0 }.count
    }

    var missingHealthSummaryCount: Int {
        guard settings.healthKitEnabled else { return 0 }
        return trendNights.filter {
            $0.healthSummary == nil && ($0.dose1Time != nil || !$0.events.isEmpty || $0.morningCheckIn != nil)
        }.count
    }

    var highConfidenceNightCount: Int {
        populatedNights.filter { $0.dataCompletenessScore >= 0.75 }.count
    }

    var qualityIssueCount: Int {
        trendNights.reduce(0) { $0 + $1.qualityFlags.count }
    }

    // MARK: - Lifestyle Factor Metrics (from Pre-Sleep Log)

    private var nightsWithPreSleep: [DashboardNightAggregate] {
        populatedNights.filter { $0.preSleepLog?.answers != nil }
    }

    var averageStressLevel: Double? {
        let values = nightsWithPreSleep.compactMap { $0.preSleepLog?.answers?.stressLevel }
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    var highPreSleepStressRate: Double? {
        percentage(
            matching: nightsWithPreSleep.compactMap { $0.preSleepLog?.answers?.stressLevel },
            where: { $0 >= 4 }
        )
    }

    var preSleepStressDriverCounts: [CommonStressDriver: Int] {
        let drivers = nightsWithPreSleep.flatMap { $0.preSleepLog?.answers?.resolvedStressDrivers ?? [] }
        return counts(for: drivers)
    }

    var topPreSleepStressDriver: CommonStressDriver? {
        topKey(in: preSleepStressDriverCounts)
    }

    var stressTrendPoints: [DashboardStressTrendPoint] {
        populatedNights.compactMap { night -> DashboardStressTrendPoint? in
            guard let date = Self.keyFormatter.date(from: night.sessionDate) else {
                return nil
            }
            let bedtimeDrivers = night.preSleepLog?.answers?.resolvedStressDrivers ?? []
            let wakeDrivers = night.morningCheckIn?.resolvedStressDrivers ?? []
            let point = DashboardStressTrendPoint(
                sessionDate: night.sessionDate,
                date: date,
                bedtimeStress: night.preSleepLog?.answers?.stressLevel.map(Double.init),
                wakeStress: night.morningCheckIn?.stressLevel.map(Double.init),
                sleepQuality: night.morningCheckIn.map { Double($0.sleepQuality) },
                readiness: night.morningCheckIn.map { Double($0.readinessForDay) },
                intervalMinutes: night.intervalMinutes.map(Double.init),
                bedtimeDrivers: bedtimeDrivers,
                wakeDrivers: wakeDrivers
            )
            if point.bedtimeStress == nil &&
                point.wakeStress == nil &&
                point.sleepQuality == nil &&
                point.readiness == nil &&
                bedtimeDrivers.isEmpty &&
                wakeDrivers.isEmpty {
                return nil
            }
            return point
        }
        .sorted { $0.date < $1.date }
    }

    var stressTrendNightCount: Int {
        stressTrendPoints.count
    }

    var combinedStressDriverCounts: [CommonStressDriver: Int] {
        counts(for: stressTrendPoints.flatMap { $0.bedtimeDrivers + $0.wakeDrivers })
    }

    var carryoverStressDriverCounts: [CommonStressDriver: Int] {
        counts(for: stressTrendPoints.flatMap(\.carryoverDrivers))
    }

    var recurringStressDrivers: [DashboardStressDriverFrequency] {
        combinedStressDriverCounts.map { driver, totalCount in
            DashboardStressDriverFrequency(
                driver: driver,
                totalCount: totalCount,
                carryoverCount: carryoverStressDriverCounts[driver, default: 0]
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalCount == rhs.totalCount {
                if lhs.carryoverCount == rhs.carryoverCount {
                    return lhs.driver.displayText < rhs.driver.displayText
                }
                return lhs.carryoverCount > rhs.carryoverCount
            }
            return lhs.totalCount > rhs.totalCount
        }
    }

    var topRecurringStressDriver: CommonStressDriver? {
        recurringStressDrivers.first?.driver
    }

    var topCarryoverStressDriver: CommonStressDriver? {
        topKey(in: carryoverStressDriverCounts)
    }

    var stressCarryoverNightRate: Double? {
        percentage(
            matching: stressTrendPoints.compactMap { point -> Bool? in
                guard !point.bedtimeDrivers.isEmpty, !point.wakeDrivers.isEmpty else {
                    return nil
                }
                return !point.carryoverDrivers.isEmpty
            },
            where: { $0 }
        )
    }

    var sleepQualityByHighBedtimeStress: (high: Double?, lower: Double?) {
        let high = populatedNights.compactMap { night -> Double? in
            guard let stress = night.preSleepLog?.answers?.stressLevel, stress >= 4 else {
                return nil
            }
            guard let sleepQuality = night.morningCheckIn?.sleepQuality else {
                return nil
            }
            return Double(sleepQuality)
        }
        let lower = populatedNights.compactMap { night -> Double? in
            guard let stress = night.preSleepLog?.answers?.stressLevel, stress <= 3 else {
                return nil
            }
            guard let sleepQuality = night.morningCheckIn?.sleepQuality else {
                return nil
            }
            return Double(sleepQuality)
        }
        return (average(high), average(lower))
    }

    var readinessByHighBedtimeStress: (high: Double?, lower: Double?) {
        let high = populatedNights.compactMap { night -> Double? in
            guard let stress = night.preSleepLog?.answers?.stressLevel, stress >= 4 else {
                return nil
            }
            guard let readiness = night.morningCheckIn?.readinessForDay else {
                return nil
            }
            return Double(readiness)
        }
        let lower = populatedNights.compactMap { night -> Double? in
            guard let stress = night.preSleepLog?.answers?.stressLevel, stress <= 3 else {
                return nil
            }
            guard let readiness = night.morningCheckIn?.readinessForDay else {
                return nil
            }
            return Double(readiness)
        }
        return (average(high), average(lower))
    }

    var intervalByHighBedtimeStress: (high: Double?, lower: Double?) {
        let high = populatedNights.compactMap { night -> Double? in
            guard let stress = night.preSleepLog?.answers?.stressLevel, stress >= 4 else {
                return nil
            }
            return night.intervalMinutes.map(Double.init)
        }
        let lower = populatedNights.compactMap { night -> Double? in
            guard let stress = night.preSleepLog?.answers?.stressLevel, stress <= 3 else {
                return nil
            }
            return night.intervalMinutes.map(Double.init)
        }
        return (average(high), average(lower))
    }

    var caffeineRate: Double? {
        guard !nightsWithPreSleep.isEmpty else { return nil }
        let withCaffeine = nightsWithPreSleep.filter {
            $0.preSleepLog?.answers?.hasCaffeineIntake == true
        }.count
        return (Double(withCaffeine) / Double(nightsWithPreSleep.count)) * 100
    }

    var alcoholRate: Double? {
        guard !nightsWithPreSleep.isEmpty else { return nil }
        let withAlcohol = nightsWithPreSleep.filter {
            guard let a = $0.preSleepLog?.answers?.alcohol else { return false }
            return a != PreSleepLogAnswers.AlcoholLevel.none
        }.count
        return (Double(withAlcohol) / Double(nightsWithPreSleep.count)) * 100
    }

    var exerciseRate: Double? {
        guard !nightsWithPreSleep.isEmpty else { return nil }
        let withExercise = nightsWithPreSleep.filter {
            guard let e = $0.preSleepLog?.answers?.exercise else { return false }
            return e != PreSleepLogAnswers.ExerciseLevel.none
        }.count
        return (Double(withExercise) / Double(nightsWithPreSleep.count)) * 100
    }

    var screenTimeRate: Double? {
        guard !nightsWithPreSleep.isEmpty else { return nil }
        let withScreens = nightsWithPreSleep.filter {
            guard let s = $0.preSleepLog?.answers?.screensInBed else { return false }
            return s != PreSleepLogAnswers.ScreensInBed.none
        }.count
        return (Double(withScreens) / Double(nightsWithPreSleep.count)) * 100
    }

    var lateMealRate: Double? {
        guard !nightsWithPreSleep.isEmpty else { return nil }
        let withMeal = nightsWithPreSleep.filter {
            guard let m = $0.preSleepLog?.answers?.lateMeal else { return false }
            return m != PreSleepLogAnswers.LateMeal.none
        }.count
        return (Double(withMeal) / Double(nightsWithPreSleep.count)) * 100
    }

    /// Average sleep quality on caffeine vs. no-caffeine nights.
    var sleepQualityByCaffeine: (with: Double?, without: Double?) {
        let withCaff = populatedNights.filter {
            $0.preSleepLog?.answers?.hasCaffeineIntake == true
        }.compactMap { $0.morningCheckIn?.sleepQuality }
        let noCaff = populatedNights.filter {
            $0.preSleepLog?.answers?.hasCaffeineIntake != true
        }.compactMap { $0.morningCheckIn?.sleepQuality }
        let avgWith = withCaff.isEmpty ? nil : Double(withCaff.reduce(0, +)) / Double(withCaff.count)
        let avgWithout = noCaff.isEmpty ? nil : Double(noCaff.reduce(0, +)) / Double(noCaff.count)
        return (avgWith, avgWithout)
    }

    /// Average sleep quality on alcohol vs. no-alcohol nights.
    var sleepQualityByAlcohol: (with: Double?, without: Double?) {
        let withAlc = populatedNights.filter {
            guard let a = $0.preSleepLog?.answers?.alcohol else { return false }
            return a != PreSleepLogAnswers.AlcoholLevel.none
        }.compactMap { $0.morningCheckIn?.sleepQuality }
        let noAlc = populatedNights.filter {
            $0.preSleepLog?.answers?.alcohol == PreSleepLogAnswers.AlcoholLevel.none || $0.preSleepLog?.answers?.alcohol == nil
        }.compactMap { $0.morningCheckIn?.sleepQuality }
        let avgWith = withAlc.isEmpty ? nil : Double(withAlc.reduce(0, +)) / Double(withAlc.count)
        let avgWithout = noAlc.isEmpty ? nil : Double(noAlc.reduce(0, +)) / Double(noAlc.count)
        return (avgWith, avgWithout)
    }

    /// Average sleep quality on screen vs. no-screen nights.
    var sleepQualityByScreens: (with: Double?, without: Double?) {
        let withScr = populatedNights.filter {
            guard let s = $0.preSleepLog?.answers?.screensInBed else { return false }
            return s != PreSleepLogAnswers.ScreensInBed.none
        }.compactMap { $0.morningCheckIn?.sleepQuality }
        let noScr = populatedNights.filter {
            $0.preSleepLog?.answers?.screensInBed == PreSleepLogAnswers.ScreensInBed.none || $0.preSleepLog?.answers?.screensInBed == nil
        }.compactMap { $0.morningCheckIn?.sleepQuality }
        let avgWith = withScr.isEmpty ? nil : Double(withScr.reduce(0, +)) / Double(withScr.count)
        let avgWithout = noScr.isEmpty ? nil : Double(noScr.reduce(0, +)) / Double(noScr.count)
        return (avgWith, avgWithout)
    }

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
        /// True when current has data but prior was 0 (can't compute % change).
        var isNew: Bool {
            guard let c = current, let p = prior else { return false }
            return p == 0 && c > 0
        }
        var improving: Bool? {
            guard let d = delta else { return nil }
            // For most metrics, positive = good. Override per-metric if needed.
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
        let priorAvgInterval = avg(priorDosing.compactMap(\.intervalMinutes).map { Double($0) })
        let priorAvgSleep = avg(prior.compactMap(\.totalSleepMinutes))
        let priorAvgQuality = avg(prior.compactMap { $0.morningCheckIn?.sleepQuality }.map { Double($0) })

        // WHOOP prior-period metrics
        let priorWhoopNights = prior.filter { $0.whoopSummary?.hasValidSleepData == true }
        let priorAvgRecovery = avg(priorWhoopNights.compactMap(\.whoopRecoveryScore))
        let priorAvgHRV = avg(priorWhoopNights.compactMap(\.whoopHRV))

        var deltas = [
            PeriodDelta(metricName: "On-Time %", current: onTimePercentage, prior: priorOnTime),
            PeriodDelta(metricName: "Avg Interval", current: averageIntervalMinutes, prior: priorAvgInterval),
            PeriodDelta(metricName: "Avg Sleep", current: averageSleepMinutes, prior: priorAvgSleep),
            PeriodDelta(metricName: "Sleep Quality", current: averageSleepQuality, prior: priorAvgQuality),
        ]

        // Add WHOOP deltas only when both periods have data
        if averageWhoopRecovery != nil || priorAvgRecovery != nil {
            deltas.append(PeriodDelta(metricName: "Recovery", current: averageWhoopRecovery, prior: priorAvgRecovery))
        }
        if averageWhoopHRV != nil || priorAvgHRV != nil {
            deltas.append(PeriodDelta(metricName: "HRV", current: averageWhoopHRV, prior: priorAvgHRV))
        }

        return deltas
    }

    private enum DoseEventKind {
        case dose1
        case dose2
        case dose2Skipped
        case extraDose
        case other
    }

    private struct DerivedDoseMetrics {
        let dose1Time: Date?
        let dose2Time: Date?
        let dose2Skipped: Bool
        let extraDoseCount: Int
    }

    private func normalizedDoseEventKind(_ rawType: String) -> DoseEventKind {
        let normalized = rawType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")

        switch normalized {
        case "dose1", "dose_1", "dose1_taken", "dose_1_taken":
            return .dose1
        case "dose2", "dose_2", "dose2_taken", "dose_2_taken", "dose2_early", "dose_2_early", "dose2_late", "dose_2_late", "dose_2_(early)", "dose_2_(late)":
            return .dose2
        case "dose2_skipped", "dose_2_skipped", "dose2skipped", "dose_2_skipped_reason", "skip", "skipped":
            return .dose2Skipped
        case "extra_dose", "extra_dose_taken", "extra", "dose3", "dose_3", "dose_3_taken":
            return .extraDose
        default:
            return .other
        }
    }

    private func deriveDoseMetrics(from doseEvents: [DoseCore.StoredDoseEvent]) -> DerivedDoseMetrics {
        let sorted = doseEvents.sorted { $0.timestamp < $1.timestamp }
        let dose1 = sorted.first { normalizedDoseEventKind($0.eventType) == .dose1 }?.timestamp
        let dose2 = sorted.first { normalizedDoseEventKind($0.eventType) == .dose2 }?.timestamp
        let skipped = sorted.contains { normalizedDoseEventKind($0.eventType) == .dose2Skipped }
        let extraCount = sorted.filter { normalizedDoseEventKind($0.eventType) == .extraDose }.count

        // Legacy fallback when explicit dose1 markers are missing.
        if dose1 == nil {
            let doseLike = sorted.filter {
                let kind = normalizedDoseEventKind($0.eventType)
                return kind == .dose1 || kind == .dose2 || kind == .extraDose
            }
            if let inferredDose1 = doseLike.first?.timestamp {
                let inferredDose2 = dose2 ?? (doseLike.count > 1 ? doseLike[1].timestamp : nil)
                return DerivedDoseMetrics(
                    dose1Time: inferredDose1,
                    dose2Time: inferredDose2,
                    dose2Skipped: skipped,
                    extraDoseCount: extraCount
                )
            }
        }

        return DerivedDoseMetrics(
            dose1Time: dose1,
            dose2Time: dose2,
            dose2Skipped: skipped,
            extraDoseCount: extraCount
        )
    }

    let metricsCatalog: [DashboardMetricCategory] = [
        DashboardMetricCategory(
            id: "dosing",
            title: "Dosing & Timing",
            metrics: [
                "Dose 1 timestamp",
                "Dose 2 timestamp",
                "Dose 2 skipped status",
                "Inter-dose interval (minutes)",
                "On-time dosing (150-240m window)",
                "Snooze count",
                "Extra dose count",
                "Consecutive on-time streak"
            ]
        ),
        DashboardMetricCategory(
            id: "sleep",
            title: "Sleep (Apple Health + Manual)",
            metrics: [
                "Total sleep minutes",
                "Time to first wake (TTFW)",
                "Wake count (Apple Health)",
                "Sleep source",
                "Bathroom wake count",
                "Lights Out and Wake Up events",
                "Nap count and duration",
                "Sleep quality (morning check-in)",
                "Readiness for day"
            ]
        ),
        DashboardMetricCategory(
            id: "checkins",
            title: "Check-Ins & Symptoms",
            metrics: [
                "Morning check-in completion",
                "Sleep quality and restedness",
                "Grogginess and sleep inertia",
                "Dream recall",
                "Physical and respiratory symptom flags",
                "Mood, anxiety, stress, readiness",
                "Stressors and stress progression",
                "Sleep therapy and environment flags"
            ]
        ),
        DashboardMetricCategory(
            id: "quality",
            title: "Data Quality & Reliability",
            metrics: [
                "Duplicate event cluster count",
                "Completeness score (0.0-1.0)",
                "Missing Dose 2 outcome",
                "Missing HealthKit summary",
                "Missing morning check-in",
                "Morning check-in completion rate",
                "Pre-sleep log completion rate",
                "Integration authorization state"
            ]
        )
    ]

}
