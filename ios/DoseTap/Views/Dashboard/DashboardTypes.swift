import SwiftUI
import DoseCore

enum DashboardSleepSource: String, CaseIterable, Identifiable {
    case appleHealth = "Apple Health"
    case whoop = "WHOOP"
    var id: String { rawValue }
}

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

    func cutoffDate(from anchor: Date = Date(), calendar: Calendar = .current) -> Date {
        guard self != .all else { return .distantPast }
        return calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: anchor)) ?? .distantPast
    }

    func priorPeriodCutoff(from anchor: Date = Date(), calendar: Calendar = .current) -> (start: Date, end: Date) {
        let end = cutoffDate(from: anchor, calendar: calendar)
        let start = calendar.date(byAdding: .day, value: -days, to: end) ?? .distantPast
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

    var exactIntervalMinutes: Double? {
        guard let dose1Time, let dose2Time else { return nil }
        let seconds = dose2Time.timeIntervalSince(dose1Time)
        return seconds.isFinite && seconds >= 0 ? seconds / 60 : nil
    }

    func isPendingDose2(at now: Date) -> Bool {
        guard let dose1Time, dose2Time == nil, !dose2Skipped else { return false }
        return now < dose1Time.addingTimeInterval(Double(DoseCore.DoseWindowConfig().maxIntervalMin) * 60)
    }

    var intervalMinutes: Int? {
        guard let dose1Time, let dose2Time else { return nil }
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
        dose1Time != nil || dose2Time != nil || dose2Skipped || extraDoseCount > 0 || !events.isEmpty || morningCheckIn != nil || preSleepLog != nil || healthSummary != nil || whoopSummary != nil
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
enum DashboardPalette {
    static let timing: Color = .blue
    static let sleep: Color = .purple
    static let coverage: Color = .teal
    static let review: Color = .orange

    static func recovery(_ score: Double?) -> Color {
        guard let score else { return .secondary }
        return score >= 67 ? .green : score >= 34 ? .orange : .red
    }
}
