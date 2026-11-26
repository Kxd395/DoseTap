import Foundation

/// Local-only review evidence; the private source fingerprint is deliberately absent.
public struct DashboardSharedDoseReview: Codable, Equatable, Sendable {
    public let version: Int
    public let observationID: String
    public let sessionID: String
    public let treatmentDate: String
    public let revisionID: UUID
    public let recordedAt: Date
    public let confirmedCount: Int?
    public let historicalPlanCount: Int?
    public let secondNotTaken: Bool?
    public let evidenceIDs: [String]

    public static func project(_ review: DashboardDoseReview, sessionID: String, treatmentDate: String,
                               events: [StoredDoseEvent], capturedAt: Date) -> Self? {
        guard !sessionID.isEmpty, sessionID != treatmentDate,
              review.observationID == "session:" + sessionID,
              review.validationError(now: capturedAt) == nil,
              review.sourceFingerprint == DashboardDoseReview.observationFingerprint(
                  observationID: review.observationID, sessionDate: treatmentDate, events: events, providerFingerprint: nil),
              events.allSatisfy({ $0.sessionId == sessionID && $0.sessionDate == treatmentDate &&
                  !$0.id.isEmpty && $0.timestamp <= capturedAt }),
              Set(events.map(\.id)).count == events.count,
              DashboardReportingWindow.isValidDateKey(treatmentDate) else { return nil }
        let projected = Self(version: 1, observationID: review.observationID, sessionID: sessionID,
                    treatmentDate: treatmentDate, revisionID: review.revisionID, recordedAt: review.recordedAt,
                    confirmedCount: review.confirmedCount, historicalPlanCount: review.historicalPlanCount,
                    secondNotTaken: review.secondNotTaken, evidenceIDs: events.map(\.id).sorted())
        guard (try? projected.validate(capturedAt: capturedAt)) != nil else { return nil }
        return projected
    }

    public func validate(capturedAt: Date) throws {
        guard version == 1, !sessionID.isEmpty, sessionID.count <= 1000, !sessionID.contains("\0"), sessionID != treatmentDate,
              observationID == "session:" + sessionID, DashboardReportingWindow.isValidDateKey(treatmentDate),
              recordedAt.timeIntervalSince1970.isFinite, recordedAt <= capturedAt,
              confirmedCount.map({ (0...2).contains($0) }) ?? true,
              historicalPlanCount.map({ (1...2).contains($0) }) ?? true,
              !(secondNotTaken == true && confirmedCount == 2),
              evidenceIDs.allSatisfy({ !$0.isEmpty && $0.count <= 1000 && !$0.contains("\0") }),
              Set(evidenceIDs).count == evidenceIDs.count else { throw DashboardSnapshotError.invalidPayload }
    }
    /// A review can describe only the complete dose evidence of its exact local identity.
    static func validate(_ reviews: [Self], in snapshot: CloudDashboardSnapshot) throws {
        guard !reviews.isEmpty else { return }
        guard Set(reviews.map(\.observationID)).count == reviews.count,
              Set(reviews.map(\.revisionID)).count == reviews.count else { throw DashboardSnapshotError.invalidPayload }
        func rows(_ dataset: DashboardDataset, tables: Set<String>) throws -> [BindingRow] {
            guard let data = snapshot.sections.first(where: { $0.dataset == dataset })?.rows else {
                throw DashboardSnapshotError.incompleteDataset
            }
            let rows = try JSONDecoder().decode([BindingRow].self, from: data)
            guard rows.allSatisfy({ tables.contains($0.sourceTable) }) else { throw DashboardSnapshotError.invalidPayload }
            return rows
        }
        let doses = try rows(.doseEvents, tables: ["dose_events"])
        let sessions = try rows(.sessions, tables: ["sleep_sessions", "current_session"])
        for review in reviews {
            try review.validate(capturedAt: snapshot.capturedAt)
            let identityRows = (sessions + doses).filter { $0.text("session_id") == review.sessionID }
            let doseRows = doses.filter { $0.text("session_id") == review.sessionID }
            let ids = doseRows.compactMap { $0.text("id") }
            guard !identityRows.isEmpty, identityRows.allSatisfy({ $0.text("session_date") == review.treatmentDate }),
                  ids.count == doseRows.count, Set(ids).count == ids.count,
                  Set(ids) == Set(review.evidenceIDs) else { throw DashboardSnapshotError.invalidPayload }
        }
    }
    private struct BindingRow: Decodable {
        struct Column: Decodable { let type: String; let text: String? }
        let sourceTable: String
        let columns: [String: Column]
        func text(_ key: String) -> String? { columns[key]?.type == "text" ? columns[key]?.text : nil }
    }

}
