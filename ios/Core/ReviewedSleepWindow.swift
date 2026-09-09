import Foundation

/// User-reviewed observation bounds, not measured sleep or final awakening.
public struct ReviewedSleepWindow: Codable, Hashable, Sendable {
    public let version: Int
    public let source: String
    public let sessionID: String
    public let start: Date
    public let end: Date
    public let reviewedAt: Date
    public let entryTimeZoneID: String
    public let startUTCOffsetSeconds: Int
    public let endUTCOffsetSeconds: Int

    public init(sessionID: String, start: Date, end: Date, entryTimeZone: TimeZone, reviewedAt: Date) {
        version = 1; source = "user_reviewed"
        self.sessionID = sessionID; self.start = start; self.end = end; self.reviewedAt = reviewedAt
        entryTimeZoneID = entryTimeZone.identifier
        startUTCOffsetSeconds = start.timeIntervalSinceReferenceDate.isFinite ? entryTimeZone.secondsFromGMT(for: start) : 0
        endUTCOffsetSeconds = end.timeIntervalSinceReferenceDate.isFinite ? entryTimeZone.secondsFromGMT(for: end) : 0
    }

    public func validationError(now: Date) -> String? {
        guard version == 1, source == "user_reviewed",
              !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              TimeZone(identifier: entryTimeZoneID) != nil,
              TimeZone(secondsFromGMT: startUTCOffsetSeconds) != nil,
              TimeZone(secondsFromGMT: endUTCOffsetSeconds) != nil else {
            return "The saved night window's identity or entry information needs review."
        }
        guard [start, end, reviewedAt, now].allSatisfy({ $0.timeIntervalSinceReferenceDate.isFinite }),
              end.timeIntervalSince(start).isFinite, start < end,
              end <= reviewedAt, reviewedAt <= now else {
            return "Choose a window that ends after it starts and no later than its review time."
        }
        return nil
    }
}
