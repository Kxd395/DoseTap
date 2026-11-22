import DoseCore
import Foundation
import SQLite3

@MainActor
extension EventStorage {
    func daytimeCheckIns() throws -> DaytimeCheckInLedger {
        try decodeDaytimeCheckIns(exportIndependentSourceRecords(in: "daytime_checkins"))
    }

    private func decodeDaytimeCheckIns(_ rows: [StoredExportSourceRecord]) throws -> DaytimeCheckInLedger {
        let revisions = try rows.map { row in
            guard let payload = row.columns["payload"]?.text else { throw DaytimeDiaryError.unreadable }
            let entry = try DaytimeCheckIn.decode(payload)
            guard row.columns["revision_id"]?.text == entry.revisionID.uuidString,
                  row.columns["observation_id"]?.text == entry.id.uuidString else {
                throw DaytimeDiaryError.unreadable
            }
            return entry
        }
        return try DaytimeCheckInLedger(revisions: revisions)
    }

    func saveDaytimeCheckIn(_ entry: DaytimeCheckIn) throws -> Bool {
        let payload = try entry.encoded()
        guard databaseInitializationFailure == nil, let db,
              injectedMedicationFailure(at: .begin) == nil else { throw DaytimeDiaryError.notCommitted }
        return try withSQLiteTransaction {
            let tables = try independentRecordTables(checkUnknownTables: true)
            if !tables.contains("daytime_checkins") {
                // Create the owned table and its receipt in the same transaction as the first observation.
                let sql = """
                CREATE TABLE daytime_checkins (
                    revision_id TEXT PRIMARY KEY, observation_id TEXT NOT NULL, payload TEXT NOT NULL
                );
                INSERT INTO schema_migrations (id) VALUES ('native_daytime_checkins_v1');
                """
                guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw DaytimeDiaryError.notCommitted }
            }
            let ledger = try decodeDaytimeCheckIns(readIndependentRecords(table: "daytime_checkins"))
            if let saved = ledger.revisions.first(where: { $0.revisionID == entry.revisionID }) {
                guard saved == entry else { throw DaytimeDiaryError.conflict }
                return false
            }

            if let predecessor = entry.predecessorID {
                guard let current = ledger.current.first(where: { $0.id == entry.id }),
                      current.revisionID == predecessor,
                      current.activity == entry.activity, current.setting == entry.setting,
                      current.coping == entry.coping, current.copingActions == entry.copingActions,
                      current.note == entry.note, current.eventReview == entry.eventReview else {
                    throw DaytimeDiaryError.conflict
                }
            } else {
                guard entry.promptID == nil, entry.eventReview == nil, entry.sourceLinks?.isEmpty != false else {
                    throw DaytimeDiaryError.invalid
                }
            }
            _ = try DaytimeCheckInLedger(revisions: ledger.revisions + [entry])

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            let sql = "INSERT INTO daytime_checkins (revision_id, observation_id, payload) VALUES (?, ?, ?)"
            guard injectedMedicationFailure(at: .insert) == nil,
                  sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw DaytimeDiaryError.notCommitted
            }
            for (index, value) in [entry.revisionID.uuidString, entry.id.uuidString, payload].enumerated() {
                guard sqlite3_bind_text(statement, Int32(index + 1), value, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
                    throw DaytimeDiaryError.notCommitted
                }
            }
            guard sqlite3_step(statement) == SQLITE_DONE, sqlite3_changes(db) == 1,
                  injectedMedicationFailure(at: .commit) == nil else { throw DaytimeDiaryError.notCommitted }
            return true
        }
    }
}

@MainActor
extension SessionRepository {
    func daytimeCheckIns() throws -> DaytimeCheckInLedger { try storage.daytimeCheckIns() }

    func saveDaytimeCheckIn(_ entry: DaytimeCheckIn) throws {
        guard entry.recordedAt <= clock() else { throw DaytimeDiaryError.invalid }
        if try storage.saveDaytimeCheckIn(entry) { sessionDidChange.send() }
    }
}
