import Foundation
import SQLite3
import DoseCore

extension SessionRepository {
    func dashboardDoseReviews() throws -> [String: DashboardDoseReviewLedger] {
        try storage.dashboardDoseReviews(now: clock())
    }
    func saveDashboardDoseReview(_ review: DashboardDoseReview, sessionDate: String, expectedRevision: UUID?, allowDateCorrection: Bool = false) throws {
        try storage.saveDashboardDoseReview(review, sessionDate: sessionDate, expectedRevision: expectedRevision, now: clock(), allowDateCorrection: allowDateCorrection)
        sessionDidChange.send()
    }
}

extension EventStorage {
    func dashboardDoseReviews(now: Date) throws -> [String: DashboardDoseReviewLedger] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT observation_id, payload FROM dashboard_dose_reviews", -1, &statement, nil) == SQLITE_OK else {
            throw DashboardDoseReviewError.storage
        }
        defer { sqlite3_finalize(statement) }
        var result: [String: DashboardDoseReviewLedger] = [:]
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            guard let identity = sqlite3_column_text(statement, 0), let payload = sqlite3_column_text(statement, 1) else {
                throw DashboardDoseReviewError.storage
            }
            guard sqlite3_column_type(statement, 0) == SQLITE_TEXT, sqlite3_column_type(statement, 1) == SQLITE_TEXT,
                  let id = String(data: Data(bytes: identity, count: Int(sqlite3_column_bytes(statement, 0))), encoding: .utf8) else { throw DashboardDoseReviewError.storage }
            let ledger = try JSONDecoder().decode(DashboardDoseReviewLedger.self, from: Data(bytes: payload, count: Int(sqlite3_column_bytes(statement, 1)))).validated(now: now)
            guard ledger.current?.observationID == id, result[id] == nil else { throw DashboardDoseReviewError.storage }
            result[id] = ledger
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw DashboardDoseReviewError.storage }
        return result
    }
    func saveDashboardDoseReview(_ review: DashboardDoseReview, sessionDate: String,
                                 expectedRevision: UUID?, now: Date, allowDateCorrection: Bool = false) throws {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let date = formatter.date(from: sessionDate), formatter.string(from: date) == sessionDate else {
            throw DashboardDoseReviewError.invalid("The treatment date needs review.")
        }
        try withSQLiteTransaction {
            var ledger = try dashboardDoseReviews(now: now)[review.observationID] ?? DashboardDoseReviewLedger()
            var existing: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT session_date FROM dashboard_dose_reviews WHERE observation_id=?1", -1, &existing, nil) == SQLITE_OK else { throw DashboardDoseReviewError.storage }
            defer { sqlite3_finalize(existing) }
            guard sqlite3_bind_text(existing, 1, review.observationID, -1, SQLITE_TRANSIENT) == SQLITE_OK else { throw DashboardDoseReviewError.storage }
            let status = sqlite3_step(existing)
            if status == SQLITE_ROW {
                guard let bytes = sqlite3_column_text(existing, 0),
                      let previousDate = String(data: Data(bytes: bytes, count: Int(sqlite3_column_bytes(existing, 0))), encoding: .utf8),
                      previousDate == sessionDate || (allowDateCorrection && ledger.current.map {
                          expectedRevision == $0.revisionID && review.revisionID != $0.revisionID
                              && review.sourceFingerprint != $0.sourceFingerprint
                              && !review.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      } == true) else { throw DashboardDoseReviewError.changed }
            } else if status != SQLITE_DONE { throw DashboardDoseReviewError.storage }
            let original = ledger
            try ledger.append(review, expectedRevision: expectedRevision, now: now)
            if original == ledger { return }
            let data = try JSONEncoder().encode(ledger)
            guard let payload = String(data: data, encoding: .utf8) else { throw DashboardDoseReviewError.storage }
            var statement: OpaquePointer?
            let sql = "INSERT INTO dashboard_dose_reviews (observation_id, session_date, payload) VALUES (?1, ?2, ?3) ON CONFLICT(observation_id) DO UPDATE SET payload=excluded.payload, session_date=excluded.session_date"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw DashboardDoseReviewError.storage }
            defer { sqlite3_finalize(statement) }
            for (index, value) in [review.observationID, sessionDate, payload].enumerated() {
                guard sqlite3_bind_text(statement, Int32(index + 1), value, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
                    throw DashboardDoseReviewError.storage
                }
            }
            guard sqlite3_step(statement) == SQLITE_DONE else { throw DashboardDoseReviewError.storage }
        }
    }
}
