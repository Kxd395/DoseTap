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
