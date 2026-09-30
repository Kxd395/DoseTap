import Foundation
import SQLite3
import DoseCore

extension EventStorage {
    func loadDaytimePrompts() throws -> DaytimePromptLedger {
        guard databaseInitializationFailure == nil, db != nil else { throw DaytimeDiaryError.unreadable }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM daytime_prompt_state WHERE id = 1", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw DaytimeDiaryError.unreadable }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return DaytimePromptLedger() }
        guard result == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { throw DaytimeDiaryError.unreadable }
        let value = try DaytimePromptLedger.decodePayload(Data(String(cString: text).utf8))
        try value.validate(); return value
    }
    func saveDaytimePrompts(_ value: DaytimePromptLedger) throws {
        try value.validate()
        guard databaseInitializationFailure == nil, db != nil else { throw DaytimeDiaryError.notCommitted }
        let payload = String(decoding: try value.encodedPayload(), as: UTF8.self)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO daytime_prompt_state (id, payload) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw DaytimeDiaryError.notCommitted }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_text(statement, 1, payload, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_DONE else { throw DaytimeDiaryError.notCommitted }
    }
}

extension SessionRepository {
    func daytimePrompts() throws -> DaytimePromptLedger { try storage.loadDaytimePrompts() }
    func saveDaytimePrompts(_ value: DaytimePromptLedger) throws { try storage.saveDaytimePrompts(value) }
    var daytimePromptSleepActive: Bool {
        if dose1Time != nil && wakeFinalTime == nil && !checkInCompleted { return true }
        let events = fetchRecentEvents(limit: 500).sorted { $0.timestamp < $1.timestamp }
        var nap = false, mainSleep = false
        for event in events {
            let type = event.eventType.lowercased().replacingOccurrences(of: " ", with: "_")
            if type == "nap_start" { nap = true }
            if type == "nap_end" { nap = false }
            if ["lights_out", "lightsout"].contains(type) { mainSleep = true }
            if ["wake_final", "wakefinal"].contains(type) { mainSleep = false }
        }
        return nap || (mainSleep && !checkInCompleted)
    }
}
