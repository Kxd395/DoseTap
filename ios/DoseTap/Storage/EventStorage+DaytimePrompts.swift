import DoseCore
import Foundation
import SQLite3

extension StoredExportSourceRecord {
    func savedReminderPayload() throws -> Data {
        guard sourceTable == "daytime_prompt_state", columns["id"]?.integer == 1,
              let payload = columns["payload"]?.text else { throw DaytimeDiaryError.unreadable }
        return Data(payload.utf8)
    }
}

@MainActor
extension EventStorage {
    private func reminderPayload(in rows: [StoredExportSourceRecord]) throws -> Data? {
        guard let first = rows.first else { return nil }
        guard rows.count == 1 else { throw DaytimeDiaryError.unreadable }
        return try first.savedReminderPayload()
    }

    func daytimePrompts() throws -> DaytimePromptLedger {
        let rows = try exportIndependentSourceRecords(in: "daytime_prompt_state")
        return try reminderPayload(in: rows).map(DaytimePromptLedger.decodePayload) ?? DaytimePromptLedger()
    }

    func saveDaytimePrompts(_ value: DaytimePromptLedger, replacing expected: DaytimePromptLedger) throws -> Bool {
        let encoded = try value.encodedPayload()
        let canonical = try DaytimePromptLedger.decodePayload(encoded)
        guard databaseInitializationFailure == nil, let db,
              injectedMedicationFailure(at: .begin) == nil else { throw DaytimeDiaryError.notCommitted }

        return try withSQLiteTransaction {
            let tables = try independentRecordTables(checkUnknownTables: true)
            let exists = tables.contains("daytime_prompt_state")
            let payload = exists ? try reminderPayload(in: readIndependentRecords(table: "daytime_prompt_state")) : nil
            let current = try payload.map(DaytimePromptLedger.decodePayload) ?? DaytimePromptLedger()
            if current == canonical { return false }
            guard current == expected else { throw DaytimeDiaryError.conflict }

            if let payload {
                // Codable ignores unknown fields. Preserve newer ledgers for a compatible writer.
                let original = try JSONSerialization.jsonObject(with: payload) as? NSDictionary
                let known = try JSONSerialization.jsonObject(with: current.encodedPayload()) as? NSDictionary
                guard let original, let known, original == known else { throw DaytimeDiaryError.unreadable }
            }
            if !exists {
                let create = """
                    CREATE TABLE daytime_prompt_state (id INTEGER PRIMARY KEY CHECK (id = 1), payload TEXT NOT NULL);
                    INSERT INTO schema_migrations (id) VALUES ('native_daytime_prompts_v1');
                    """
                guard sqlite3_exec(db, create, nil, nil, nil) == SQLITE_OK else { throw DaytimeDiaryError.notCommitted }
            }

            let sql = payload == nil
                ? "INSERT INTO daytime_prompt_state (id, payload) VALUES (1, ?1)"
                : "UPDATE daytime_prompt_state SET payload = ?1 WHERE id = 1"
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard injectedMedicationFailure(at: .insert) == nil,
                  sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
                  sqlite3_bind_text(statement, 1, String(decoding: encoded, as: UTF8.self), -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_DONE, sqlite3_changes(db) == 1,
                  injectedMedicationFailure(at: .commit) == nil else { throw DaytimeDiaryError.notCommitted }
            return true
        }
    }
}

@MainActor
extension SessionRepository {
    func daytimePrompts() throws -> DaytimePromptLedger { try storage.daytimePrompts() }

    func saveDaytimePrompts(_ value: DaytimePromptLedger, replacing expected: DaytimePromptLedger) throws {
        if try storage.saveDaytimePrompts(value, replacing: expected) { sessionDidChange.send() }
    }
}
