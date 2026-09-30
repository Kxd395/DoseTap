import Foundation

public struct DashboardDoseReview: Codable, Equatable, Sendable {
    public let version: Int
    public let revisionID: UUID
    public let observationID: String
    public let sourceFingerprint: String
    public let confirmedCount: Int?
    public let historicalPlanCount: Int?
    public let secondNotTaken: Bool?
    public let recordedAt: Date
    public let reason: String
    public init(observationID: String, sourceFingerprint: String, confirmedCount: Int?,
                historicalPlanCount: Int?, secondNotTaken: Bool?, recordedAt: Date,
                reason: String, revisionID: UUID = UUID()) {
        version = 1; self.revisionID = revisionID; self.observationID = observationID
        self.sourceFingerprint = sourceFingerprint; self.confirmedCount = confirmedCount
        self.historicalPlanCount = historicalPlanCount; self.secondNotTaken = secondNotTaken
        self.recordedAt = recordedAt; self.reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public func validationError(now: Date) -> String? {
        guard version == 1, !observationID.isEmpty, observationID.count <= 1000,
              !sourceFingerprint.isEmpty, !observationID.contains("\0"), reason.count <= 500,
              recordedAt.timeIntervalSince1970.isFinite, now.timeIntervalSince1970.isFinite,
              recordedAt <= now, confirmedCount.map({ (0...2).contains($0) }) ?? true,
              historicalPlanCount.map({ (1...2).contains($0) }) ?? true,
              !(secondNotTaken == true && confirmedCount == 2) else {
            return "Review the reported count, plan and recording time before saving."
        }
        return nil
    }
    /// Full canonical evidence comparison, not a hash of private data for transport.
    public static func fingerprint(_ events: [StoredDoseEvent]) -> String? {
        guard events.allSatisfy({ $0.timestamp.timeIntervalSince1970.isFinite }) else { return nil }
        let rows = events.map { [$0.id, $0.sessionId ?? "", $0.sessionDate, $0.eventType,
                                 String($0.timestamp.timeIntervalSince1970.bitPattern), $0.metadata ?? ""] }
            .sorted { $0.lexicographicallyPrecedes($1) }
        return (try? JSONEncoder().encode(rows)).map { $0.base64EncodedString() }
    }
}

public enum DashboardDoseReviewError: Error, LocalizedError {
    case invalid(String), changed, storage
    public var errorDescription: String? {
        switch self {
        case .invalid(let detail): return detail
        case .changed: return "This review changed. Reopen it before saving a correction."
        case .storage: return "The dose-history review could not be read or saved. Your medication records were not changed. Try again."
        }
    }
}

public struct DashboardDoseReviewLedger: Codable, Equatable, Sendable {
    public private(set) var revisions: [DashboardDoseReview] = []
    public init() {}
    public var current: DashboardDoseReview? { revisions.last }
    public func current(matching fingerprint: String) -> DashboardDoseReview? {
        current?.sourceFingerprint == fingerprint ? current : nil
    }
    public mutating func append(_ review: DashboardDoseReview, expectedRevision: UUID?, now: Date) throws {
        if let message = review.validationError(now: now) { throw DashboardDoseReviewError.invalid(message) }
        if revisions.contains(review) { return }
        guard current?.revisionID == expectedRevision,
              current.map({ $0.observationID == review.observationID && $0.recordedAt <= review.recordedAt }) ?? true,
              !revisions.contains(where: { $0.revisionID == review.revisionID }),
              current == nil || !review.reason.isEmpty else { throw DashboardDoseReviewError.changed }
        revisions.append(review)
    }
    public func validated(now: Date) throws -> Self {
        var checked = Self()
        for review in revisions { try checked.append(review, expectedRevision: checked.current?.revisionID, now: now) }
        guard checked.revisions.count == revisions.count else { throw DashboardDoseReviewError.changed }
        return checked
    }
}
