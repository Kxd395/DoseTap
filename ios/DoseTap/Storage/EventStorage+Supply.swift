import Foundation
import SQLite3
import DoseCore

enum SupplyStorageError: LocalizedError {
    case unavailable, invalid
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Supply information could not be saved or loaded. Please retry."
        case .invalid: return "This supply record is invalid or uses an unsupported version."
        }
    }
}

extension EventStorage {
    func loadSupply() throws -> SupplyBackup {
        guard databaseInitializationFailure == nil, db != nil else { throw SupplyStorageError.unavailable }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM supply_state WHERE id = 1", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw SupplyStorageError.unavailable }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return SupplyBackup() }
        guard result == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { throw SupplyStorageError.unavailable }
        let value = try JSONDecoder().decode(SupplyBackup.self, from: Data(String(cString: text).utf8))
        guard value.isValid else { throw SupplyStorageError.invalid }
        return value
    }

    /// One SQLite statement commits reminder and bottle records atomically.
    func saveSupply(_ value: SupplyBackup) throws {
        guard value.isValid else { throw SupplyStorageError.invalid }
        guard databaseInitializationFailure == nil, db != nil else { throw SupplyStorageError.unavailable }
        let payload = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO supply_state (id, payload) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw SupplyStorageError.unavailable }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_text(statement, 1, payload, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_DONE else { throw SupplyStorageError.unavailable }
    }
}

extension SessionRepository {
    func loadSupply() throws -> SupplyBackup { try storage.loadSupply() }
    func saveSupply(_ value: SupplyBackup) throws {
        try storage.saveSupply(value)
        supplyGeneration &+= 1
        sessionDidChange.send()
    }
}
