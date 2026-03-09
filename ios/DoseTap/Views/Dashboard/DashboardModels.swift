import SwiftUI
import Charts
import DoseCore
import os.log
#if canImport(UIKit)
import UIKit
#endif

private let dashboardLogger = Logger(subsystem: "com.dosetap.app", category: "Dashboard")

enum DashboardDateRange: String, CaseIterable, Identifiable {
    case week = "7D"
    case twoWeeks = "14D"
    case month = "30D"
    case quarter = "90D"
    case year = "1Y"
    case all = "All"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .week:     return 7
        case .twoWeeks: return 14
        case .month:    return 30
        case .quarter:  return 90
        case .year:     return 365
        case .all:      return 9999
        }
    }

    var label: String {
        switch self {
        case .week:     return "Week"
        case .twoWeeks: return "2 Weeks"
        case .month:    return "Month"
        case .quarter:  return "Quarter"
        case .year:     return "Year"
        case .all:      return "All Time"
        }
    }

    /// Calendar date for the start of this range (inclusive).
    func cutoffDate(from anchor: Date = Date()) -> Date {
        guard self != .all else { return .distantPast }
        return Calendar.current.date(byAdding: .day, value: -(days - 1), to: anchor) ?? .distantPast
    }

    /// The equivalent prior period (e.g. "last week" when range is "this week").
    func priorPeriodCutoff(from anchor: Date = Date()) -> (start: Date, end: Date) {
        let end = cutoffDate(from: anchor)
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? .distantPast
        return (start, end)
    }
}

struct DashboardNightAggregate: Identifiable {
    let sessionDate: String
    let dose1Time: Date?
    let dose2Time: Date?
    let dose2Skipped: Bool
    let snoozeCount: Int
    let extraDoseCount: Int
    let events: [StoredSleepEvent]
    let morningCheckIn: StoredMorningCheckIn?
    let preSleepLog: StoredPreSleepLog?
    let healthSummary: HealthKitService.SleepNightSummary?
    let whoopSummary: WHOOPNightSummary?
    let duplicateClusterCount: Int
    let napSummary: SessionRepository.NapSummary

    var id: String { sessionDate }

    var intervalMinutes: Int? {
        guard let dose1Time, let dose2Time else { return nil }
        let minutes = TimeIntervalMath.minutesBetween(start: dose1Time, end: dose2Time)
        return minutes >= 0 ? minutes : nil
    }

    var onTimeDosing: Bool? {
        guard let intervalMinutes else { return nil }
        return (150...240).contains(intervalMinutes)
    }

    var totalSleepMinutes: Double? {
        // Prefer WHOOP when available, fall back to HealthKit
        if let whoopMin = whoopSummary?.totalSleepMinutes, whoopMin > 0 {
            return Double(whoopMin)
        }
        return healthSummary?.totalSleepMinutes
    }
    var ttfwMinutes: Double? { healthSummary?.ttfwMinutes }
    var wakeCount: Int? { healthSummary?.wakeCount }

    // MARK: - WHOOP-specific computed properties

    /// Recovery score from WHOOP (0-100).
    var whoopRecoveryScore: Double? { whoopSummary?.recoveryScore }
    /// HRV in ms from WHOOP recovery data.
    var whoopHRV: Double? { whoopSummary?.hrvMs }
    /// Sleep efficiency percentage from WHOOP.
    var whoopSleepEfficiency: Double? { whoopSummary?.sleepEfficiency }
    /// Respiratory rate from WHOOP.
    var whoopRespiratoryRate: Double? { whoopSummary?.respiratoryRate }
    /// Disturbance count from WHOOP.
    var whoopDisturbances: Int? { whoopSummary.map(\.disturbanceCount) }
    /// Deep sleep minutes from WHOOP.
    var whoopDeepSleepMinutes: Int? { whoopSummary?.deepMinutes }

    var bathroomEventCount: Int {
        events.filter { normalizeStoredEventType($0.eventType) == "bathroom" }.count
    }

    var hasAnyData: Bool {
        dose1Time != nil || dose2Time != nil || dose2Skipped || !events.isEmpty || morningCheckIn != nil || preSleepLog != nil || healthSummary != nil || whoopSummary != nil
    }

    var dataCompletenessScore: Double {
        var score = 0.0
        if dose1Time != nil && (dose2Time != nil || dose2Skipped) { score += 0.25 }
        if healthSummary != nil || whoopSummary != nil { score += 0.25 }
        if morningCheckIn != nil { score += 0.25 }
        if preSleepLog != nil { score += 0.25 }
        return score
    }

    var qualityFlags: [String] {
        var flags: [String] = []
        if duplicateClusterCount > 0 {
            flags.append("Duplicate event cluster")
        }
        if dose1Time != nil && dose2Time == nil && !dose2Skipped {
            flags.append("Dose 2 outcome missing")
        }
        return flags
    }
}

struct DashboardIntegrationState: Identifiable {
    let id: String
    let name: String
    let status: String
    let detail: String
    let color: Color
}

struct DashboardStressTrendPoint: Identifiable {
    let sessionDate: String
    let date: Date
    let bedtimeStress: Double?
    let wakeStress: Double?
    let sleepQuality: Double?
    let readiness: Double?
    let intervalMinutes: Double?
    let bedtimeDrivers: [CommonStressDriver]
    let wakeDrivers: [CommonStressDriver]

    var id: String { sessionDate }

    var carryoverDrivers: [CommonStressDriver] {
        let wakeSet = Set(wakeDrivers)
        var seen: Set<CommonStressDriver> = []
        return bedtimeDrivers.filter { driver in
            wakeSet.contains(driver) && seen.insert(driver).inserted
        }
    }
}

struct DashboardStressDriverFrequency: Identifiable {
    let driver: CommonStressDriver
    let totalCount: Int
    let carryoverCount: Int

    var id: String { driver.rawValue }
}

struct DashboardMetricCategory: Identifiable {
    let id: String
    let title: String
    let metrics: [String]
}

@MainActor
final class DashboardAnalyticsModel: ObservableObject {
    @Published var nights: [DashboardNightAggregate] = []
    @Published var integrationStates: [DashboardIntegrationState] = []
    @Published var isLoading = false
    @Published var lastRefresh: Date?
    @Published var errorMessage: String?
    @Published var selectedRange: DashboardDateRange = .month

    private let sessionRepo = SessionRepository.shared
    private let settings = UserSettingsManager.shared
    private let healthKit = HealthKitService.shared
    private let whoop = WHOOPService.shared
    private let cloudSync = CloudKitSyncService.shared

    /// Cancels in-flight refresh when a new one starts (prevents race on rapid range changes).
    private var refreshTask: Task<Void, Never>?

    private static let keyFormatter: DateFormatter = AppFormatters.sessionDate

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

    func refresh(days: Int = 730) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.performRefresh(days: days)
        }
    }

    private func performRefresh(days: Int) async {
        isLoading = true
        errorMessage = nil

        let sessions = sessionRepo.fetchRecentSessions(days: days)
        var sessionByKey: [String: SessionSummary] = [:]
        for session in sessions {
            sessionByKey[session.sessionDate] = session
        }

        var healthByKey: [String: HealthKitService.SleepNightSummary] = [:]
        if settings.healthKitEnabled {
            healthKit.checkAuthorizationStatus()
            if healthKit.isAuthorized {
                await healthKit.computeTTFWBaseline(days: max(14, min(days, 120)))
                // Bail if a newer refresh has been started while we awaited HealthKit.
                guard !Task.isCancelled else { return }
                for summary in healthKit.sleepHistory {
                    let key = sessionRepo.sessionDateString(for: eveningAnchorDate(for: summary.date))
                    if healthByKey[key] == nil {
                        healthByKey[key] = summary
                    }
                }
            } else if let lastError = healthKit.lastError, !lastError.isEmpty {
                errorMessage = lastError
            }
        }

        // WHOOP data — fetch when enabled and connected
        var whoopByKey: [String: WHOOPNightSummary] = [:]
        if WHOOPService.isEnabled && settings.whoopEnabled && whoop.isConnected {
            do {
                let fetchDays = min(days, 30) // WHOOP API: limit to 30 days per request
                let sleeps = try await whoop.fetchRecentSleep(nights: fetchDays)
                guard !Task.isCancelled else { return }
                for sleep in sleeps where sleep.scoreState?.uppercased() == "SCORED" {
                    let summary = sleep.toNightSummary()
                    let key = sessionRepo.sessionDateString(for: summary.date)
                    if whoopByKey[key] == nil {
                        whoopByKey[key] = summary
                    }
                }
                // Recovery is enrichment, not a hard requirement for showing WHOOP sleep.
                do {
                    let recoveries = try await whoop.fetchRecoveryData(
                        from: Calendar.current.date(byAdding: .day, value: -fetchDays, to: Date()) ?? Date(),
                        to: Date()
                    )
                    guard !Task.isCancelled else { return }
                    for recovery in recoveries {
                        if let sleepId = recovery.sleepId,
                           let existingKey = whoopByKey.first(where: { $0.value.sleepId == sleepId })?.key {
                            var updated = whoopByKey[existingKey]!
                            updated.recoveryScore = recovery.score?.recoveryScore
                            updated.hrvMs = recovery.score?.hrvMs
                            updated.restingHeartRate = recovery.score?.restingHeartRate
                            whoopByKey[existingKey] = updated
                        }
                    }
                } catch {
                    dashboardLogger.warning("WHOOP recovery fetch failed: \(error.localizedDescription)")
                }
            } catch {
                dashboardLogger.warning("WHOOP fetch failed: \(error.localizedDescription)")
                // Non-fatal: dashboard still loads with local data
            }
        }

        let calendar = Calendar.current
        let sessionKeys: [String] = (0..<days).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            return sessionRepo.sessionDateString(for: eveningAnchorDate(for: date))
        }

        let aggregates: [DashboardNightAggregate] = sessionKeys.map { key in
            let summary = sessionByKey[key] ?? SessionSummary(sessionDate: key)
            let doseLog = sessionRepo.fetchDoseLog(forSession: key)
            let doseEvents = sessionRepo.fetchDoseEvents(forSessionDate: key)
            let derivedDose = deriveDoseMetrics(from: doseEvents)
            let events = sessionRepo.fetchSleepEvents(for: key).sorted { $0.timestamp < $1.timestamp }
            let duplicateClusters = buildStoredEventDuplicateGroups(events: events).count
            let sessionId = sessionRepo.fetchSessionId(forSessionDate: key) ?? key

            return DashboardNightAggregate(
                sessionDate: key,
                dose1Time: summary.dose1Time ?? doseLog?.dose1Time ?? derivedDose.dose1Time,
                dose2Time: summary.dose2Time ?? doseLog?.dose2Time ?? derivedDose.dose2Time,
                dose2Skipped: summary.dose2Skipped || doseLog?.dose2Skipped == true || derivedDose.dose2Skipped,
                snoozeCount: summary.snoozeCount,
                extraDoseCount: derivedDose.extraDoseCount,
                events: events,
                morningCheckIn: sessionRepo.fetchMorningCheckIn(for: key),
                preSleepLog: sessionRepo.fetchMostRecentPreSleepLog(sessionId: sessionId),
                healthSummary: healthByKey[key],
                whoopSummary: whoopByKey[key],
                duplicateClusterCount: duplicateClusters,
                napSummary: sessionRepo.napSummary(for: key)
            )
        }

        nights = aggregates.sorted { $0.sessionDate > $1.sessionDate }
        integrationStates = buildIntegrationStates(healthMatches: healthByKey.count, whoopMatches: whoopByKey.count)
        lastRefresh = Date()
        isLoading = false
    }

    private func counts<T: Hashable>(for values: [T]) -> [T: Int] {
        var result: [T: Int] = [:]
        for value in values {
            result[value, default: 0] += 1
        }
        return result
    }

    private func topKey<T: Hashable>(in counts: [T: Int]) -> T? {
        counts.max(by: { lhs, rhs in
            if lhs.value == rhs.value {
                return String(describing: lhs.key) > String(describing: rhs.key)
            }
            return lhs.value < rhs.value
        })?.key
    }

    private func percentage<T>(
        matching values: [T],
        where predicate: (T) -> Bool
    ) -> Double? {
        guard !values.isEmpty else { return nil }
        let matches = values.filter(predicate).count
        return (Double(matches) / Double(values.count)) * 100
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func buildIntegrationStates(healthMatches: Int, whoopMatches: Int = 0) -> [DashboardIntegrationState] {
        let healthState = DashboardIntegrationState(
            id: "healthkit",
            name: "Apple Health",
            status: settings.healthKitEnabled
                ? (healthKit.isAuthorized ? "Connected" : "Needs Authorization")
                : "Disabled",
            detail: settings.healthKitEnabled
                ? (healthKit.isAuthorized
                    ? "\(healthMatches) nights with sleep summaries mapped"
                    : (healthKit.lastError ?? "Enable read access for sleep analysis"))
                : "Enable in Settings to ingest sleep stages automatically.",
            color: settings.healthKitEnabled ? (healthKit.isAuthorized ? .green : .orange) : .gray
        )

        let whoopState: DashboardIntegrationState
        if !WHOOPService.isEnabled {
            // WHOOP not connected — user hasn't linked their account yet
            whoopState = DashboardIntegrationState(
                id: "whoop",
                name: "WHOOP",
                status: "Not Connected",
                detail: "Connect WHOOP in Settings → Integrations to import sleep & recovery data.",
                color: .gray
            )
        } else {
            let whoopDetail: String
            if settings.whoopEnabled {
                if whoop.isConnected {
                    let syncInfo = whoop.lastSyncTime.map { " • Last sync \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
                    whoopDetail = whoopMatches > 0
                        ? "\(whoopMatches) nights with sleep data\(syncInfo)"
                        : "Connected — no scored sleep data yet\(syncInfo)"
                } else {
                    whoopDetail = "Connect in Settings to ingest recovery/strain metrics."
                }
            } else {
                whoopDetail = "Turn on WHOOP integration in Settings when ready."
            }
            whoopState = DashboardIntegrationState(
                id: "whoop",
                name: "WHOOP",
                status: settings.whoopEnabled
                    ? (whoop.isConnected ? "Connected" : "Not Connected")
                    : "Disabled",
                detail: whoopDetail,
                color: settings.whoopEnabled ? (whoop.isConnected ? .green : .orange) : .gray
            )
        }

        let cloudState = DashboardIntegrationState(
            id: "cloud",
            name: "Cloud Sync",
            status: cloudSync.cloudSyncAvailableInBuild
                ? (cloudSync.lastSyncDate == nil ? "Not Synced" : "Active")
                : "Disabled",
            detail: cloudSync.cloudSyncAvailableInBuild
                ? (cloudSync.lastSyncDate == nil
                    ? cloudSync.statusMessage
                    : "Last sync \(cloudSync.lastSyncDate?.formatted(date: .omitted, time: .shortened) ?? "") • \(cloudSync.statusMessage)")
                : "Cloud sync requires iCloud entitlements and a paid Apple Developer team profile.",
            color: cloudSync.cloudSyncAvailableInBuild
                ? (cloudSync.lastSyncDate == nil ? .orange : .green)
                : .gray
        )

        let exportState = DashboardIntegrationState(
            id: "export",
            name: "Share & Export",
            status: "Ready",
            detail: "Timeline review snapshot sharing is active (theme-aware export).",
            color: .teal
        )

        return [healthState, whoopState, cloudState, exportState]
    }
}
