import SwiftUI
import DoseCore

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

    func cutoffDate(from anchor: Date = Date()) -> Date {
        guard self != .all else { return .distantPast }
        return Calendar.current.date(byAdding: .day, value: -(days - 1), to: anchor) ?? .distantPast
    }

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
        if let whoopMin = whoopSummary?.totalSleepMinutes, whoopMin > 0 {
            return Double(whoopMin)
        }
        return healthSummary?.totalSleepMinutes
    }

    var ttfwMinutes: Double? { healthSummary?.ttfwMinutes }
    var wakeCount: Int? { healthSummary?.wakeCount }
    var whoopRecoveryScore: Double? { whoopSummary?.recoveryScore }
    var whoopHRV: Double? { whoopSummary?.hrvMs }
    var whoopSleepEfficiency: Double? { whoopSummary?.sleepEfficiency }
    var whoopRespiratoryRate: Double? { whoopSummary?.respiratoryRate }
    var whoopDisturbances: Int? { whoopSummary.map(\.disturbanceCount) }
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
