import Foundation

/// Explicit selection of existing evidence, never a new event or a causal pairing.
public struct DaytimeSourceLink: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case nap, medication, mainWake }
    public enum TimePrecision: String, Codable, Sendable { case recordedOccurrence, reported, approximate, unknown }
    public let schemaVersion: Int
    public let kind: Kind
    public let sourceID: String
    public let sourceRevisionID: String?
    public let evidenceKey: String
    public let sourceEventIDs: [String]
    public let sourceCalendarDay: String?
    public let timeZoneIdentifier: String?
    public let start: Date?
    public let end: Date?
    public let timePrecision: TimePrecision
    public let selectedAt: Date
    public var id: String { kind.rawValue + ":" + sourceID }

    public init(kind: Kind, sourceID: String, sourceRevisionID: String? = nil, evidenceKey: String,
                sourceEventIDs: [String] = [], sourceCalendarDay: String? = nil, timeZoneIdentifier: String? = nil,
                start: Date? = nil, end: Date? = nil, timePrecision: TimePrecision = .unknown, selectedAt: Date) throws {
        schemaVersion = 1; self.kind = kind; self.sourceID = sourceID; self.sourceRevisionID = sourceRevisionID
        self.evidenceKey = evidenceKey; self.sourceEventIDs = sourceEventIDs.sorted()
        self.sourceCalendarDay = sourceCalendarDay; self.timeZoneIdentifier = timeZoneIdentifier
        self.start = start; self.end = end; self.timePrecision = timePrecision; self.selectedAt = selectedAt
        try validate()
    }

    public func validate() throws {
        func validID(_ value: String) -> Bool {
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= 300 && !value.contains("\0")
        }
        let dates = [start, end].compactMap { $0 }
        guard schemaVersion == 1, validID(sourceID), sourceRevisionID.map(validID) ?? true,
              evidenceKey.count == 64, evidenceKey.allSatisfy({ "0123456789abcdef".contains($0) }),
              sourceEventIDs.count <= 32, sourceEventIDs.allSatisfy(validID), Set(sourceEventIDs).count == sourceEventIDs.count,
              selectedAt.timeIntervalSince1970.isFinite,
              dates.allSatisfy({ $0.timeIntervalSince1970.isFinite && $0 <= selectedAt }),
              timePrecision == .unknown || !dates.isEmpty,
              timeZoneIdentifier.map({ validID($0) && (TimeZone(identifier: $0) != nil || (kind == .medication && sourceCalendarDay == nil)) }) ?? true,
              sourceCalendarDay.map(DashboardReportingWindow.isValidDateKey) ?? true,
              sourceCalendarDay == nil || timeZoneIdentifier != nil,
              kind != .nap || (sourceCalendarDay != nil && timeZoneIdentifier != nil) else { throw DaytimeDiaryError.invalid }
        if let start, let end, end < start { throw DaytimeDiaryError.invalid }
        if let day = sourceCalendarDay, let zoneName = timeZoneIdentifier, let zone = TimeZone(identifier: zoneName) {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            let components = calendar.dateComponents([.era, .year, .month, .day], from: selectedAt)
            guard components.era == 1, let year = components.year, (1...9999).contains(year),
                  let month = components.month, let date = components.day,
                  day <= String(format: "%04d-%02d-%02d", year, month, date) else { throw DaytimeDiaryError.invalid }
        }
    }

    static func validate(_ values: [Self]?, recordedAt: Date) throws {
        guard let values else { return }
        guard values.count <= 32, Set(values.map(\.id)).count == values.count else { throw DaytimeDiaryError.invalid }
        var underlying = Set<String>()
        for value in values {
            try value.validate()
            guard value.selectedAt <= recordedAt else { throw DaytimeDiaryError.invalid }
            for source in value.sourceEventIDs {
                guard underlying.insert(value.kind.rawValue + ":" + source).inserted else { throw DaytimeDiaryError.invalid }
            }
        }
    }
}
