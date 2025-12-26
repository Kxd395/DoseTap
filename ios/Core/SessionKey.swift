import Foundation

/// Computes the canonical session key for a given timestamp.
/// A session starts at `rolloverHour` (default 18 / 6PM) in the provided timezone.
/// - Parameters:
///   - date: The timestamp to evaluate.
///   - timeZone: Explicit timezone (do not rely on TimeZone.current elsewhere).
///   - rolloverHour: Hour (0-23) when a new session begins.
/// - Returns: Session key in `yyyy-MM-dd` format.
public func sessionKey(for date: Date, timeZone: TimeZone, rolloverHour: Int = 18) -> String {
    let identity = SessionIdentity(date: date, timeZone: timeZone, rolloverHour: rolloverHour)
    return identity.key
}

/// Encapsulates the identity of a dosing session.
/// A session is defined by its start date (the calendar day it belongs to, 
/// where a day starts at the rollover hour).
public struct SessionIdentity: Equatable, Hashable, Sendable {
    public let date: Date
    public let timeZone: TimeZone
    public let rolloverHour: Int

    public init(date: Date, timeZone: TimeZone, rolloverHour: Int = 18) {
        self.date = date
        self.timeZone = timeZone
        self.rolloverHour = rolloverHour
    }

    public var key: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let hour = calendar.component(.hour, from: date)
        let sessionDate: Date
        if hour < rolloverHour {
            sessionDate = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        } else {
            sessionDate = date
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: sessionDate)
    }
}

/// Computes the pre-sleep target session key.
/// If before rollover, use the upcoming night's calendar date (no day subtraction).
public func preSleepSessionKey(for date: Date, timeZone: TimeZone, rolloverHour: Int = 18) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    
    let hour = calendar.component(.hour, from: date)
    let sessionDate = hour < rolloverHour ? date : date
    
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: sessionDate)
}

/// Computes the next rollover Date from a reference time.
public func nextRollover(after date: Date, timeZone: TimeZone, rolloverHour: Int = 18) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone

    var components = calendar.dateComponents([.year, .month, .day], from: date)
    components.hour = rolloverHour
    components.minute = 0
    components.second = 0

    let todayRollover = calendar.date(from: components) ?? date
    if todayRollover > date {
        return todayRollover
    }
    // Move to next day rollover
    let nextDay = calendar.date(byAdding: .day, value: 1, to: todayRollover) ?? todayRollover
    return nextDay
}
