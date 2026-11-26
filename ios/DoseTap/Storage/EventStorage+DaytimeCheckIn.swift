import Foundation
import SQLite3
import DoseCore

@MainActor
extension EventStorage {
    func daytimeCheckIns() throws -> DaytimeCheckInLedger {
        guard databaseInitializationFailure == nil, db != nil else { throw DaytimeDiaryError.unreadable }
        let values: [DaytimeCheckIn] = try readExportRows("SELECT revision_id, observation_id, payload FROM daytime_checkins ORDER BY rowid") { stmt in
            func text(_ column: Int32) throws -> String {
                guard sqlite3_column_type(stmt, column) == SQLITE_TEXT, let bytes = sqlite3_column_text(stmt, column),
                      let value = String(bytes: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(stmt, column))), encoding: .utf8)
                else { throw DaytimeDiaryError.unreadable }
                return value
            }
            let value = try DaytimeCheckIn.decode(text(2))
            guard try text(0) == value.revisionID.uuidString, try text(1) == value.id.uuidString else { throw DaytimeDiaryError.unreadable }
            return value
        }
        return try DaytimeCheckInLedger(revisions: values)
    }

    /// Commit one immutable revision atomically; identical retries do not append twice.
    func saveDaytimeCheckIn(_ value: DaytimeCheckIn, validateNewLinks: ([DaytimeSourceLink]) throws -> Void = { _ in throw DaytimeDiaryError.invalid }) throws -> Bool {
        let payload = try value.encoded()
        guard databaseInitializationFailure == nil, let db, injectedMedicationFailure(at: .begin) == nil,
              sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { throw DaytimeDiaryError.notCommitted }
        var committed = false
        defer { if !committed {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            storageLog.error("Independent daytime observation transaction rolled back")
        } }
        if let review = value.eventReview {
            let events = try daytimeEvents().current
            guard review.eventIDs.allSatisfy({ id in events.contains { $0.id == id && $0.occurredAt >= review.from && $0.occurredAt <= review.to } }) else { throw DaytimeDiaryError.invalid }
        }
        let ledger = try daytimeCheckIns()
        let existing = ledger.revisions.first { $0.revisionID == value.revisionID }
        if let existing {
            guard existing == value else { throw DaytimeDiaryError.conflict }
        } else {
            _ = try DaytimeCheckInLedger(revisions: ledger.revisions + [value])
            if value.predecessorID == nil, let links = value.sourceLinks, !links.isEmpty { try validateNewLinks(links) }
            guard injectedMedicationFailure(at: .insert) == nil else { throw DaytimeDiaryError.notCommitted }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "INSERT INTO daytime_checkins (revision_id, observation_id, payload) VALUES (?, ?, ?)", -1, &stmt, nil) == SQLITE_OK,
                  let stmt else { throw DaytimeDiaryError.notCommitted }
            for (index, text) in [value.revisionID.uuidString, value.id.uuidString, payload].enumerated() {
                guard sqlite3_bind_text(stmt, Int32(index + 1), text, -1, SQLITE_TRANSIENT) == SQLITE_OK else { throw DaytimeDiaryError.notCommitted }
            }
            guard sqlite3_step(stmt) == SQLITE_DONE, sqlite3_changes(db) == 1 else { throw DaytimeDiaryError.notCommitted }
        }
        guard injectedMedicationFailure(at: .commit) == nil,
              sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else { throw DaytimeDiaryError.notCommitted }
        committed = true
        storageLog.info("Independent daytime observation commit verified")
        return existing == nil
    }
}

@MainActor
extension SessionRepository {
    func daytimeCheckIns() throws -> DaytimeCheckInLedger { try storage.daytimeCheckIns() }
    func saveDaytimeCheckIn(_ value: DaytimeCheckIn) throws {
        guard value.recordedAt <= clock() else { throw DaytimeDiaryError.invalid }
        if try storage.saveDaytimeCheckIn(value, validateNewLinks: { links in
            try self.validateDaytimeSourceSelection(links, asOf: self.clock())
        }) { sessionDidChange.send() }
    }
}
