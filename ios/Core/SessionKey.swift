import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

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

/// Generates a deterministic UUID from a date-string session ID
/// Used for migrating legacy date-based session IDs to UUID format
/// - Parameter dateString: Legacy session ID in format "yyyy-MM-dd"
/// - Returns: Deterministic UUID string
public func deterministicSessionUUID(for dateString: String) -> String {
    #if canImport(CryptoKit)
    if #available(iOS 13.0, macOS 10.15, watchOS 6.0, *) {
        let data = Data(dateString.utf8)
        let hash = SHA256.hash(data: data)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        // Format as UUID: 8-4-4-4-12
        let uuid = "\(hashString.prefix(8))-\(hashString.dropFirst(8).prefix(4))-\(hashString.dropFirst(12).prefix(4))-\(hashString.dropFirst(16).prefix(4))-\(hashString.dropFirst(20).prefix(12))"
        return uuid.uppercased()
    } else {
        return fallbackDeterministicUUID(for: dateString)
    }
    #else
    return fallbackDeterministicUUID(for: dateString)
    #endif
}

private func fallbackDeterministicUUID(for dateString: String) -> String {
    // Fallback for platforms without CryptoKit: use simple hash
    let hash = abs(dateString.hashValue)
    let hashString = String(format: "%016llx", UInt64(hash))
    let uuid = "\(hashString.prefix(8))-\(hashString.dropFirst(8).prefix(4))-\(hashString.dropFirst(12).prefix(4))-0000-000000000000"
    return uuid.uppercased()
}
