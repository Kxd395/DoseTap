import Foundation

/// Unmodified WHOOP v2 episode bounds, not a measured final-asleep or reported-wake time.
/// Missing/invalid bounds remain source evidence but never establish an eligible interval.
public struct WHOOPSleepEndpointEvidence: Codable, Equatable, Sendable {
    public let sleepID: String
    public let originalStart: Date?
    public let originalEnd: Date?
    public let providerTimeZoneOffset: String?
    public let providerUpdatedAt: Date?
    public let provenance: String
    public let version: Int
    private static let source = "whoop.v2.activity.sleep.start-end"

    public init(sleepID: String, originalStart: Date?, originalEnd: Date?,
                providerTimeZoneOffset: String?, providerUpdatedAt: Date?) {
        self.sleepID = sleepID; self.originalStart = originalStart; self.originalEnd = originalEnd
        self.providerTimeZoneOffset = providerTimeZoneOffset; self.providerUpdatedAt = providerUpdatedAt
        provenance = Self.source; version = 1
    }

    public var validatedInterval: DateInterval? {
        guard !sleepID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let start = originalStart, let end = originalEnd,
              start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
              start < end else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Named endpoints each belong to [startInclusive, endExclusive); no clipping or prorating.
    /// Current access/snapshot and summary identity must also be verified by the caller.
    public func endpointsAreWithin(startInclusive: Date, endExclusive: Date, asOf: Date) -> Bool {
        guard [startInclusive, endExclusive, asOf].allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              startInclusive < endExclusive, let interval = validatedInterval else { return false }
        return interval.start >= startInclusive && interval.end < endExclusive && interval.end <= asOf
    }

    private enum CodingKeys: String, CodingKey {
        case sleepID, originalStart, originalEnd, providerTimeZoneOffset, providerUpdatedAt, provenance, version
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .version) == 1,
              try values.decode(String.self, forKey: .provenance) == Self.source else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Unsupported WHOOP endpoint evidence provenance or version"))
        }
        self.init(sleepID: try values.decode(String.self, forKey: .sleepID),
                  originalStart: try values.decodeIfPresent(Date.self, forKey: .originalStart),
                  originalEnd: try values.decodeIfPresent(Date.self, forKey: .originalEnd),
                  providerTimeZoneOffset: try values.decodeIfPresent(String.self, forKey: .providerTimeZoneOffset),
                  providerUpdatedAt: try values.decodeIfPresent(Date.self, forKey: .providerUpdatedAt))
    }
}
