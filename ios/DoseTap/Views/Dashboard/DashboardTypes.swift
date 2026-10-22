import SwiftUI
import DoseCore

enum DashboardSleepSource: String, CaseIterable, Identifiable {
    case appleHealth = "Apple Health"
    case whoop = "WHOOP"
    var id: String { rawValue }
}

typealias DashboardDateRange = DashboardReportingRange

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
    var healthSummary: HealthKitService.SleepNightSummary?
    var whoopSummary: WHOOPNightSummary?
    let duplicateClusterCount: Int
    let napSummary: SessionRepository.NapSummary
    var outcome: NightOutcomeDiary? = nil
    var outcomeReadFailed = false

    var effectiveWakeMethod: Dose2WakeKind {
        guard dose2Time != nil, !outcomeReadFailed else { return .unknown }
        // Legacy questionnaires may carry this answer forward from another night.
        // Only the explicitly saved, session-bound diary is comparison evidence.
        return outcome?.wakeMethod ?? .unknown
    }

    var postDoseSleep: PostDoseSleepEstimate? {
        guard let dose2Time, let wake = outcome?.finalWakeAt ?? healthSummary?.finalWake else { return nil }
        return PostDoseSleepEstimate.calculate(dose2: dose2Time, finalWake: wake,
            intervals: healthSummary?.recordedIntervals ?? [])
    }

    var id: String { sessionDate }

    var exactIntervalMinutes: Double? {
        guard let dose1Time, let dose2Time else { return nil }
        let seconds = dose2Time.timeIntervalSince(dose1Time)
        return seconds.isFinite && seconds > 0 ? seconds / 60 : nil
    }

    func isPendingDose2(at now: Date) -> Bool {
        guard let dose1Time, dose2Time == nil, !dose2Skipped else { return false }
        return now <= dose1Time.addingTimeInterval(Double(DoseCore.DoseWindowConfig().maxIntervalMin) * 60)
    }

    var intervalMinutes: Int? {
        guard let dose1Time, let dose2Time, exactIntervalMinutes != nil else { return nil }
        let minutes = TimeIntervalMath.minutesBetween(start: dose1Time, end: dose2Time)
        return minutes >= 0 ? minutes : nil
    }

    var onTimeDosing: Bool? {
        guard let dose1Time, let dose2Time, exactIntervalMinutes != nil else { return nil }
        return MedicationTiming.classify(dose1: dose1Time, dose2: dose2Time) == .inWindow
    }

    var appleHealthSleepMinutes: Double? {
        healthSummary?.totalSleepMinutes
    }

    var whoopSleepMinutes: Double? {
        guard whoopSummary?.hasCompleteSleepStages == true, let minutes = whoopSummary?.totalSleepMinutes, minutes > 0 else { return nil }
        return Double(minutes)
    }

    var ttfwMinutes: Double? { healthSummary?.ttfwMinutes }
    var wakeCount: Int? { healthSummary?.wakeCount }
    var whoopRecoveryScore: Double? { whoopSummary?.recoveryScore }
    var whoopHRV: Double? { whoopSummary?.hrvMs }
    var whoopSleepEfficiency: Double? { whoopSummary?.sleepEfficiency }
    var whoopRespiratoryRate: Double? { whoopSummary?.respiratoryRate }
    var whoopDisturbances: Int? { whoopSummary?.hasDisturbanceData == true ? whoopSummary?.disturbanceCount : nil }
    var whoopDeepSleepMinutes: Int? { whoopSummary?.hasCompleteSleepStages == true ? whoopSummary?.deepMinutes : nil }

    var bathroomEventCount: Int {
        events.filter { normalizeStoredEventType($0.eventType) == "bathroom" }.count
    }

    var hasAnyData: Bool {
        dose1Time != nil || dose2Time != nil || dose2Skipped || extraDoseCount > 0 || !events.isEmpty || morningCheckIn != nil || preSleepLog != nil || healthSummary != nil || whoopSummary != nil || outcome != nil || outcomeReadFailed
    }

    var dataCategoryCount: Int {
        var count = 0
        if dose1Time != nil && (dose2Time != nil || dose2Skipped) { count += 1 }
        if healthSummary != nil || whoopSummary != nil { count += 1 }
        if morningCheckIn != nil { count += 1 }
        if preSleepLog?.completionState == "complete" { count += 1 }
        return count
    }

    var dataCompletenessScore: Double { Double(dataCategoryCount) / 4 }



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


/// Category accents are descriptive, not health or treatment ratings.
struct DashboardPalette {
    var isNight = false
    var timing: Color { chart(.blue) }
    var sleep: Color { chart(.purple) }
    var coverage: Color { chart(.teal) }
    var review: Color { chart(.orange, warmth: 0.6) }

    /// Input to the existing global filter, not an additional night filter.
    func chart(_ normal: Color, warmth: Double = 1) -> Color {
        isNight ? Color(red: 1, green: warmth, blue: warmth * 0.8) : normal
    }

    var legend: String {
        isNight
            ? "Night Mode uses bright warm values. Category labels, chart symbols and series names identify the data. Review flags need a record check; missing data stays labeled. Color alone is not a health rating."
            : "Blue values: dose timing. Purple: sleep and check-ins. Teal: record coverage. Gray: context or no data. Orange review flags need a record check. Chart legends identify their series; WHOOP recovery uses its labeled ranges. Color alone is not a health rating."
    }

    func recovery(_ score: Double?) -> Color {
        guard let score else { return .secondary }
        return chart(score >= 67 ? .green : score >= 34 ? .orange : .red)
    }
}

private struct DashboardPaletteKey: EnvironmentKey {
    static let defaultValue = DashboardPalette()
}

extension EnvironmentValues {
    var dashboardPalette: DashboardPalette {
        get { self[DashboardPaletteKey.self] }
        set { self[DashboardPaletteKey.self] = newValue }
    }
}
