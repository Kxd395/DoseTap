import Foundation

public enum PhysicianReviewError: Error, Equatable {
    case invalidDate, invalidPeriod, missingCompletedVisit, invalidRevision, invalidText
}

public struct PhysicianVisit: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let revisionID: UUID
    public let predecessorID: UUID?
    public let occurredAt: Date
    public let recordedAt: Date
    public let note: String

    public init(id: UUID = UUID(), revisionID: UUID = UUID(), predecessorID: UUID? = nil,
                occurredAt: Date, recordedAt: Date, note: String = "", now: Date) throws {
        self.id = id; self.revisionID = revisionID; self.predecessorID = predecessorID
        self.occurredAt = occurredAt; self.recordedAt = recordedAt; self.note = note
        try validate(now: now)
    }
    public func validate(now: Date) throws {
        guard [occurredAt, recordedAt, now].allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              occurredAt <= recordedAt, recordedAt <= now else { throw PhysicianReviewError.invalidDate }
        guard note.count <= 4000 else { throw PhysicianReviewError.invalidText }
        guard revisionID != predecessorID else { throw PhysicianReviewError.invalidRevision }
    }
}

/// Bookings are deliberately not completed-visit history.
public struct PhysicianAppointment: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable { case planned, cancelled, rescheduled }
    public let id: UUID
    public let scheduledAt: Date
    public let status: Status
    public init(id: UUID, scheduledAt: Date, status: Status) {
        self.id = id; self.scheduledAt = scheduledAt; self.status = status
    }
}

public struct PhysicianVisitLedger: Codable, Equatable, Sendable {
    public private(set) var revisions: [PhysicianVisit] = []
    public var appointments: [PhysicianAppointment] = []
    public init() {}
    public var current: [PhysicianVisit] {
        let replaced = Set(revisions.compactMap(\.predecessorID))
        return revisions.filter { !replaced.contains($0.revisionID) }.sorted {
            $0.occurredAt == $1.occurredAt ? $0.id.uuidString < $1.id.uuidString : $0.occurredAt > $1.occurredAt
        }
    }
    public func lastCompleted(asOf: Date) -> PhysicianVisit? { current.first { $0.occurredAt <= asOf } }
    public mutating func append(_ visit: PhysicianVisit, now: Date) throws {
        try visit.validate(now: now)
        guard !revisions.contains(where: { $0.revisionID == visit.revisionID }) else { throw PhysicianReviewError.invalidRevision }
        if let prior = current.first(where: { $0.id == visit.id }) {
            guard visit.predecessorID == prior.revisionID, visit.recordedAt >= prior.recordedAt else { throw PhysicianReviewError.invalidRevision }
        } else if visit.predecessorID != nil { throw PhysicianReviewError.invalidRevision }
        revisions.append(visit)
    }
    public func validate(now: Date) throws {
        var rebuilt = Self()
        for visit in revisions { try rebuilt.append(visit, now: now) }
        guard Set(appointments.map(\.id)).count == appointments.count,
              appointments.allSatisfy({ $0.scheduledAt.timeIntervalSince1970.isFinite }) else { throw PhysicianReviewError.invalidDate }
    }
}

public enum PhysicianReportRange: Equatable, Sendable {
    case days7, days28, days90, sixMonths, twelveMonths, sinceCompletedVisit
    case custom(start: Date, endExclusive: Date)
}

public struct PhysicianReportPeriod: Codable, Equatable, Sendable {
    public static let definitionVersion = "physician-period.v1"
    public let version: String
    public let start: Date
    public let endExclusive: Date
    public let capturedAt: Date
    public let timeZoneIdentifier: String
    public let completedVisitID: UUID?
    public let label: String
    public let calendarDayCount: Int
    public func contains(_ date: Date) -> Bool { date >= start && date < endExclusive }

    public static func resolve(_ range: PhysicianReportRange, ledger: PhysicianVisitLedger,
                               asOf: Date, timeZone: TimeZone) throws -> Self {
        guard asOf.timeIntervalSince1970.isFinite else { throw PhysicianReviewError.invalidDate }
        try ledger.validate(now: asOf)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: asOf)
        var start: Date?, end = asOf, visitID: UUID?, label: String
        switch range {
        case .days7: start = calendar.date(byAdding: .day, value: -6, to: today); label = "7 calendar days"
        case .days28: start = calendar.date(byAdding: .day, value: -27, to: today); label = "28 calendar days"
        case .days90: start = calendar.date(byAdding: .day, value: -89, to: today); label = "90 calendar days"
        case .sixMonths: start = calendar.date(byAdding: .month, value: -6, to: today); label = "6 calendar months"
        case .twelveMonths: start = calendar.date(byAdding: .month, value: -12, to: today); label = "12 calendar months"
        case .sinceCompletedVisit:
            guard let visit = ledger.lastCompleted(asOf: asOf) else { throw PhysicianReviewError.missingCompletedVisit }
            start = visit.occurredAt; visitID = visit.id; label = "Since last completed visit"
        case let .custom(lower, upper): start = lower; end = upper; label = "Custom period"
        }
        guard let start, [start, end].allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              start < end, end <= asOf,
              let lastIncluded = Optional(Date(timeIntervalSince1970: end.timeIntervalSince1970.nextDown)),
              let count = calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                                   to: calendar.startOfDay(for: lastIncluded)).day,
              count >= 0, count < 36600 else { throw PhysicianReviewError.invalidPeriod }
        return Self(version: definitionVersion, start: start, endExclusive: end, capturedAt: asOf, timeZoneIdentifier: timeZone.identifier,
                    completedVisitID: visitID, label: label, calendarDayCount: count + 1)
    }
}
