import Foundation

/// An independent, patient-reported custom diary. Never a clinical scale or session action.
public struct DaytimeCheckIn: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, CaseIterable, Sendable { case answered, unsure, incomplete, skipped }
    public enum Origin: String, Codable, CaseIterable, Sendable { case userInitiated, scheduled, retrospective }
    public enum Activity: String, Codable, CaseIterable, Sendable {
        case seatedTask = "Seated task / reading", screen = "Watching a screen", conversation = "Conversation"
        case walking = "Standing / walking", resting = "Resting", passenger = "Passenger travel", other = "Other", unsure = "Unsure"
    }
    public enum Coping: String, Codable, CaseIterable, Sendable { case unanswered = "Not answered", no = "No", yes = "Yes", unsure = "Unsure" }
    public enum Action: String, Codable, CaseIterable, Sendable {
        case movement = "Movement", changeTask = "Changing task", conversation = "Seeking conversation"
        case caffeine = "Caffeine", breakTaken = "Taking a break", stopped = "Avoiding / stopping an activity"
    }
    public enum Setting: String, Codable, CaseIterable, Sendable { case unanswered = "Not answered", work = "At work", offWork = "Off work", unsure = "Unsure" }
    public let id: UUID
    public let revisionID: UUID
    public let predecessorID: UUID?
    public let createdAt: Date
    public let recordedAt: Date
    public let assessedAt: Date
    public let timeZoneIdentifier: String
    public let utcOffsetSeconds: Int
    public let instrumentID: String
    public let contentVersion: String
    public let language: String
    public let response: Int?
    public let status: Status
    public let origin: Origin
    public let activity: Activity?
    public let setting: Setting
    public let coping: Coping
    public let copingActions: [Action]
    public let note: String
    public let correctionReason: String?
    public let eventReview: DaytimeEventReview?
    public let promptID: UUID?

    public init(id: UUID = UUID(), revisionID: UUID = UUID(), predecessorID: UUID? = nil,
                createdAt: Date? = nil, assessedAt: Date, recordedAt: Date, timeZoneIdentifier: String,
                response: Int?, status: Status = .answered, origin: Origin = .userInitiated,
                activity: Activity? = nil, setting: Setting = .unanswered, coping: Coping = .unanswered,
                copingActions: Set<Action> = [], note: String = "", correctionReason: String? = nil, promptID: UUID? = nil, eventReview: DaytimeEventReview? = nil) throws {
        self.id = id; self.revisionID = revisionID; self.predecessorID = predecessorID
        self.createdAt = createdAt ?? recordedAt; self.assessedAt = assessedAt; self.recordedAt = recordedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        utcOffsetSeconds = TimeZone(identifier: timeZoneIdentifier)?.secondsFromGMT(for: assessedAt) ?? 0
        instrumentID = "dosetap.custom-current-sleepiness"; contentVersion = "custom-0-10-v1"; language = "en"
        self.response = response; self.status = status; self.origin = origin; self.activity = activity
        self.setting = setting; self.coping = coping; self.copingActions = copingActions.sorted { $0.rawValue < $1.rawValue }
        self.note = note; self.correctionReason = correctionReason; self.promptID = promptID; self.eventReview = eventReview
        try validate()
    }

    public func validate() throws {
        try eventReview?.validate()
        guard eventReview.map({ $0.to <= recordedAt }) ?? true, instrumentID == "dosetap.custom-current-sleepiness", contentVersion == "custom-0-10-v1", language == "en",
              let zone = TimeZone(identifier: timeZoneIdentifier), zone.secondsFromGMT(for: assessedAt) == utcOffsetSeconds,
              [createdAt, assessedAt, recordedAt].allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              createdAt <= recordedAt, assessedAt <= recordedAt,
              (status == .answered ? response.map { (0...10).contains($0) } == true : response == nil),
              coping == .yes || copingActions.isEmpty, note.count <= 2000,
              origin != .scheduled || promptID != nil,
              predecessorID == nil ? correctionReason == nil : correctionReason.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 2000 }) == true
        else { throw DaytimeDiaryError.invalid }
    }

    public func corrected(response: Int?, status: Status, reason: String, recordedAt: Date) throws -> Self {
        try Self(id: id, predecessorID: revisionID, createdAt: createdAt, assessedAt: assessedAt,
                 recordedAt: recordedAt, timeZoneIdentifier: timeZoneIdentifier, response: response, status: status,
                 origin: origin, activity: activity, setting: setting, coping: coping, copingActions: Set(copingActions),
                 note: note, correctionReason: reason, promptID: promptID, eventReview: eventReview)
    }

    public func encoded() throws -> String {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .secondsSince1970
        guard let value = String(data: try encoder.encode(self), encoding: .utf8) else { throw DaytimeDiaryError.invalid }
        return value
    }
    public static func decode(_ payload: String) throws -> Self {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let value = try decoder.decode(Self.self, from: Data(payload.utf8)); try value.validate(); return value
    }
}

public enum DaytimeDiaryError: Error, LocalizedError {
    case invalid, conflict, unreadable, notCommitted
    public var errorDescription: String? {
        switch self {
        case .invalid: return "Review the rating, observation time and optional answers. No observation was saved."
        case .conflict: return "This observation changed. Reload its history before correcting it."
        case .unreadable: return "Daytime records could not be read completely. Existing records were not changed."
        case .notCommitted: return "The observation was not saved. Your entry is retained; retry when ready."
        }
    }
}

public struct DaytimeCheckInLedger: Sendable {
    public let revisions: [DaytimeCheckIn]
    public let current: [DaytimeCheckIn]
    public init(revisions: [DaytimeCheckIn]) throws {
        guard Set(revisions.map(\.revisionID)).count == revisions.count else { throw DaytimeDiaryError.conflict }
        for value in revisions { try value.validate() }
        for group in Dictionary(grouping: revisions, by: \.id).values {
            guard group.filter({ $0.predecessorID == nil }).count == 1 else { throw DaytimeDiaryError.conflict }
            let children = group.compactMap(\.predecessorID)
            guard Set(children).count == children.count else { throw DaytimeDiaryError.conflict }
            for value in group where value.predecessorID != nil {
                guard let old = group.first(where: { $0.revisionID == value.predecessorID }),
                      old.createdAt == value.createdAt, old.recordedAt <= value.recordedAt,
                      old.assessedAt == value.assessedAt, old.origin == value.origin, old.promptID == value.promptID,
                      old.timeZoneIdentifier == value.timeZoneIdentifier else { throw DaytimeDiaryError.conflict }
                var seen: Set<UUID> = [value.revisionID]; var cursor = old
                while let predecessor = cursor.predecessorID {
                    guard seen.insert(cursor.revisionID).inserted, let next = group.first(where: { $0.revisionID == predecessor }) else { throw DaytimeDiaryError.conflict }
                    cursor = next
                }
            }
        }
        self.revisions = revisions
        let superseded = Set(revisions.compactMap(\.predecessorID))
        current = revisions.filter { !superseded.contains($0.revisionID) }.sorted {
            $0.assessedAt == $1.assessedAt ? $0.id.uuidString < $1.id.uuidString : $0.assessedAt > $1.assessedAt
        }
    }
}
