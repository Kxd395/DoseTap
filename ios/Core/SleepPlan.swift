import Foundation

/// Typical wake-by time for a weekday.
/// `weekdayIndex` uses Calendar weekday semantics: 1 = Sunday, 7 = Saturday.
public struct TypicalWeekEntry: Codable, Equatable {
    public let weekdayIndex: Int
    public var wakeByHour: Int
    public var wakeByMinute: Int
    public var enabled: Bool
    
    public init(weekdayIndex: Int, wakeByHour: Int, wakeByMinute: Int, enabled: Bool = true) {
        self.weekdayIndex = weekdayIndex
        self.wakeByHour = wakeByHour
        self.wakeByMinute = wakeByMinute
        self.enabled = enabled
    }
}

/// Full typical week schedule (7 entries).
public struct TypicalWeekSchedule: Codable, Equatable {
    public var entries: [TypicalWeekEntry]
    
    public init(entries: [TypicalWeekEntry] = Self.defaultEntries) {
        self.entries = entries
    }
    
    public static var defaultEntries: [TypicalWeekEntry] {
        (1...7).map { TypicalWeekEntry(weekdayIndex: $0, wakeByHour: 7, wakeByMinute: 30, enabled: true) }
    }
    
    public func entry(for weekdayIndex: Int) -> TypicalWeekEntry {
        entries.first(where: { $0.weekdayIndex == weekdayIndex }) ?? TypicalWeekEntry(weekdayIndex: weekdayIndex, wakeByHour: 7, wakeByMinute: 30, enabled: true)
    }
}

/// Sleep planning knobs.
public struct SleepPlanSettings: Codable, Equatable {
    public var targetSleepMinutes: Int
    public var sleepLatencyMinutes: Int
    public var windDownMinutes: Int
    
    public init(targetSleepMinutes: Int = 480, sleepLatencyMinutes: Int = 15, windDownMinutes: Int = 20) {
        self.targetSleepMinutes = targetSleepMinutes
        self.sleepLatencyMinutes = sleepLatencyMinutes
        self.windDownMinutes = windDownMinutes
    }
    
    public static var `default`: SleepPlanSettings { SleepPlanSettings() }
}

/// Stateless calculator for sleep planning.
public enum SleepPlanCalculator {
    
    /// Compute wake-by Date for the active night (session key D -> wake on D+1).
    public static func wakeByDateTime(forActiveSessionKey key: String, schedule: TypicalWeekSchedule, tz: TimeZone) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = tz
        
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        
        let sessionDate = formatter.date(from: key) ?? Date()
        let nextMorning = calendar.date(byAdding: .day, value: 1, to: sessionDate) ?? sessionDate
        let weekday = calendar.component(.weekday, from: nextMorning)
        let entry = schedule.entry(for: weekday)
        
        var components = calendar.dateComponents([.year, .month, .day], from: nextMorning)
        components.hour = entry.enabled ? entry.wakeByHour : 7
        components.minute = entry.enabled ? entry.wakeByMinute : 30
        components.second = 0
        
        return calendar.date(from: components) ?? nextMorning
    }
    
    public static func recommendedInBedTime(wakeBy: Date, settings: SleepPlanSettings) -> Date {
        let totalMinutes = settings.targetSleepMinutes + settings.sleepLatencyMinutes
        return wakeBy.addingTimeInterval(-Double(totalMinutes) * 60)
    }
    
    public static func windDownStart(recommendedInBed: Date, settings: SleepPlanSettings) -> Date {
        recommendedInBed.addingTimeInterval(-Double(settings.windDownMinutes) * 60)
    }
    
    /// Returns remaining sleep minutes if user went to bed now (after latency).
    public static func expectedSleepIfInBedNow(now: Date, wakeBy: Date, settings: SleepPlanSettings) -> Double {
        let rawMinutes = wakeBy.timeIntervalSince(now) / 60 - Double(settings.sleepLatencyMinutes)
        return max(0, rawMinutes)
    }
}

/// User-selected advisory target. It never changes medication eligibility.
public enum WorkWarningTarget: String, Codable, CaseIterable, Sendable {
    case fixedCutoff, wakeBuffer, doseTarget
    public var title: String {
        switch self {
        case .fixedCutoff: return "Fixed work-night cutoff"
        case .wakeBuffer: return "Wake time minus my buffer"
        case .doseTarget: return "Existing Dose 2 target"
        }
    }
}

public struct WorkWakeException: Codable, Equatable, Sendable {
    public var isWorking: Bool
    public var wakeMinutes: Int?
    public init(isWorking: Bool, wakeMinutes: Int?) {
        self.isWorking = isWorking
        self.wakeMinutes = wakeMinutes
    }
}

public struct WorkWakeWarning: Codable, Equatable, Identifiable, Sendable {
    public let sessionId: String
    public let revision: UUID
    public let wakeDate: String
    public let timeZoneIdentifier: String
    public let requiredWake: Date
    public let targetAt: Date
    public let target: WorkWarningTarget
    public var id: String { "\(sessionId):\(revision):\(wakeDate)" }
    public var dateLabel: String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier)
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: requiredWake)
    }
    public var wakeLabel: String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier)
        formatter.timeStyle = .short
        return formatter.string(from: requiredWake)
    }
}

public struct WorkWakeSchedule: Codable, Equatable, Sendable {
    public var revision: UUID
    public var timeZoneIdentifier: String
    /// nil means unknown; an empty set means explicitly not working any day.
    public var workingWeekdays: Set<Int>?
    public var wakeMinutes: Int
    public var target: WorkWarningTarget
    public var cutoffMinutes: Int
    public var bufferMinutes: Int
    public var exceptions: [String: WorkWakeException]

    public init(timeZoneIdentifier: String = "UTC", workingWeekdays: Set<Int>? = nil, wakeMinutes: Int = 420, target: WorkWarningTarget = .fixedCutoff, cutoffMinutes: Int = 120, bufferMinutes: Int = 0) {
        revision = UUID()
        self.timeZoneIdentifier = timeZoneIdentifier
        self.workingWeekdays = workingWeekdays
        self.wakeMinutes = wakeMinutes
        self.target = target
        self.cutoffMinutes = cutoffMinutes
        self.bufferMinutes = bufferMinutes
        exceptions = [:]
    }

    public var isValid: Bool {
        TimeZone(identifier: timeZoneIdentifier) != nil && (0..<1440).contains(wakeMinutes)
            && (0..<1440).contains(cutoffMinutes) && (0...1440).contains(bufferMinutes)
            && (workingWeekdays?.allSatisfy { (1...7).contains($0) } ?? true)
            && exceptions.values.allSatisfy { $0.wakeMinutes.map { (0..<1440).contains($0) } ?? true }
    }

    public func warning(sessionId: String, sessionDate: String, dose1: Date, now: Date, doseTargetMinutes: Int, retrospective: Bool = false) -> WorkWakeWarning? {
        let timing = MedicationTiming.classify(dose1: dose1, dose2: now)
        guard isValid, timing == .inWindow || (retrospective && timing == .late),
              let timezone = TimeZone(identifier: timeZoneIdentifier) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let night = formatter.date(from: sessionDate), formatter.string(from: night) == sessionDate,
              let wakeDay = calendar.date(byAdding: .day, value: 1, to: night) else { return nil }
        let wakeDate = formatter.string(from: wakeDay)
        let exception = exceptions[wakeDate]
        let working = exception?.isWorking ?? workingWeekdays?.contains(calendar.component(.weekday, from: wakeDay)) ?? false
        guard working else { return nil }
        func localTime(_ minutes: Int, on day: Date) -> Date? {
            calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
        }
        guard let wake = localTime(exception?.wakeMinutes ?? wakeMinutes, on: wakeDay) else { return nil }
        let targetAt: Date
        switch target {
        case .fixedCutoff:
            guard var cutoff = localTime(cutoffMinutes, on: wakeDay) else { return nil }
            if cutoff > wake {
                guard let priorDay = calendar.date(byAdding: .day, value: -1, to: wakeDay), let previous = localTime(cutoffMinutes, on: priorDay) else { return nil }
                cutoff = previous
            }
            targetAt = cutoff
        case .wakeBuffer:
            targetAt = wake.addingTimeInterval(-Double(bufferMinutes) * 60)
        case .doseTarget:
            targetAt = dose1.addingTimeInterval(Double(doseTargetMinutes) * 60)
        }
        guard now > targetAt else { return nil }
        return WorkWakeWarning(sessionId: sessionId, revision: revision, wakeDate: wakeDate, timeZoneIdentifier: timeZoneIdentifier, requiredWake: wake, targetAt: targetAt, target: target)
    }
}
