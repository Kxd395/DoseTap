import Foundation

public struct DaytimeEvent: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case unplannedSleep = "Unplanned sleep", interruptedActivity = "Activity interrupted by sleepiness"
        case struggling = "Struggling to stay awake", unclear = "Unclear event"
    }
    public enum Precision: String, Codable, CaseIterable, Sendable { case reported = "Reported time", approximate = "Approximate time" }
    public let version: Int
    public let id: UUID
    public let revisionID: UUID
    public let predecessorID: UUID?
    public let createdAt: Date
    public let occurredAt: Date
    public let recordedAt: Date
    public let timeZoneIdentifier: String
    public let kind: Kind
    public let precision: Precision
    public let durationSeconds: Double?
    public let note: String
    public let correctionReason: String?
    public var isReportedSleep: Bool { kind == .unplannedSleep }
    public init(id: UUID = UUID(), revisionID: UUID = UUID(), predecessorID: UUID? = nil, createdAt: Date? = nil,
                kind: Kind, occurredAt: Date, recordedAt: Date, timeZoneIdentifier: String,
                precision: Precision = .approximate, durationSeconds: Double? = nil, note: String = "", correctionReason: String? = nil) throws {
        version = 1; self.id = id; self.revisionID = revisionID; self.predecessorID = predecessorID; self.createdAt = createdAt ?? recordedAt
        self.kind = kind; self.occurredAt = occurredAt; self.recordedAt = recordedAt; self.timeZoneIdentifier = timeZoneIdentifier
        self.precision = precision; self.durationSeconds = durationSeconds; self.note = note; self.correctionReason = correctionReason
        try validate()
    }
    public func validate() throws {
        guard version == 1, [createdAt, occurredAt, recordedAt].allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              occurredAt <= recordedAt, createdAt <= recordedAt, TimeZone(identifier: timeZoneIdentifier) != nil,
              durationSeconds.map({ $0.isFinite && $0 >= 0 && occurredAt.addingTimeInterval($0) <= recordedAt }) ?? true,
              note.count <= 2000,
              predecessorID == nil ? correctionReason == nil : correctionReason.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 2000 }) == true
        else { throw DaytimeDiaryError.invalid }
    }
    public func corrected(kind: Kind, note: String, reason: String, recordedAt: Date) throws -> Self {
        try Self(id: id, predecessorID: revisionID, createdAt: createdAt, kind: kind, occurredAt: occurredAt,
                 recordedAt: recordedAt, timeZoneIdentifier: timeZoneIdentifier, precision: precision,
                 durationSeconds: durationSeconds, note: note, correctionReason: reason)
    }
    public func encoded() throws -> String {
        try validate(); let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .secondsSince1970
        guard let result = String(data: try encoder.encode(self), encoding: .utf8) else { throw DaytimeDiaryError.invalid }; return result
    }
    public static func decode(_ payload: String) throws -> Self {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let result = try decoder.decode(Self.self, from: Data(payload.utf8)); try result.validate(); return result
    }
}

public struct DaytimeEventLedger: Sendable {
    public let revisions: [DaytimeEvent]
    public let current: [DaytimeEvent]
    public init(revisions: [DaytimeEvent]) throws {
        guard Set(revisions.map(\.revisionID)).count == revisions.count else { throw DaytimeDiaryError.conflict }
        for value in revisions { try value.validate() }
        for group in Dictionary(grouping: revisions, by: \.id).values {
            guard group.filter({ $0.predecessorID == nil }).count == 1,
                  Set(group.compactMap(\.predecessorID)).count == group.compactMap(\.predecessorID).count else { throw DaytimeDiaryError.conflict }
            for value in group where value.predecessorID != nil {
                guard let old = group.first(where: { $0.revisionID == value.predecessorID }), old.createdAt == value.createdAt,
                      old.occurredAt == value.occurredAt, old.recordedAt <= value.recordedAt else { throw DaytimeDiaryError.conflict }
                var seen: Set<UUID> = [value.revisionID]; var cursor = old
                while let predecessor = cursor.predecessorID {
                    guard seen.insert(cursor.revisionID).inserted, let next = group.first(where: { $0.revisionID == predecessor }) else { throw DaytimeDiaryError.conflict }
                    cursor = next
                }
            }
        }
        self.revisions = revisions
        let replaced = Set(revisions.compactMap(\.predecessorID))
        current = revisions.filter { !replaced.contains($0.revisionID) }.sorted {
            $0.occurredAt == $1.occurredAt ? $0.id.uuidString < $1.id.uuidString : $0.occurredAt > $1.occurredAt
        }
    }
}

public struct DaytimeEventReview: Codable, Equatable, Sendable {
    public enum Status: String, Codable, CaseIterable, Sendable {
        case notReviewed = "Not reviewed", noneReported = "No events reported", eventsReported = "Events reported", unsure = "Unsure"
    }
    public let from: Date
    public let to: Date
    public let status: Status
    public let eventIDs: [UUID]
    public init(from: Date, to: Date, status: Status, eventIDs: [UUID] = []) throws {
        self.from = from; self.to = to; self.status = status; self.eventIDs = eventIDs.sorted { $0.uuidString < $1.uuidString }; try validate()
    }
    public func validate() throws {
        guard from.timeIntervalSince1970.isFinite, to.timeIntervalSince1970.isFinite, from <= to,
              Set(eventIDs).count == eventIDs.count,
              status == .eventsReported ? !eventIDs.isEmpty : eventIDs.isEmpty else { throw DaytimeDiaryError.invalid }
    }
}
