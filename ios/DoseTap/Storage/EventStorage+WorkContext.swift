import Foundation
import SQLite3
import DoseCore

enum WorkContextStorageError: LocalizedError {
    case unavailable, invalid, stale
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Work context could not be saved or loaded. Retry after reopening."
        case .invalid: return "Work context is invalid or would replace recorded history."
        case .stale: return "Work context changed. Reopen it before saving your changes."
        }
    }
}

extension EventStorage {
    func loadWorkContext() throws -> WorkContextDocument? {
        guard databaseInitializationFailure == nil, db != nil else { throw WorkContextStorageError.unavailable }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM work_block_context WHERE id = 1", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw WorkContextStorageError.unavailable }
        defer { sqlite3_finalize(statement) }
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW, let bytes = sqlite3_column_text(statement, 0) else { throw WorkContextStorageError.unavailable }
        let value = try JSONDecoder().decode(WorkContextDocument.self, from: Data(String(cString: bytes).utf8))
        guard value.isValid else { throw WorkContextStorageError.invalid }
        return value
    }

    func saveWorkContext(_ value: WorkContextDocument, expectedRevision: UUID?) throws {
        guard value.isValid else { throw WorkContextStorageError.invalid }
        guard databaseInitializationFailure == nil, let db, sqlite3_get_autocommit(db) != 0,
              sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { throw WorkContextStorageError.unavailable }
        var committed = false
        defer { if !committed { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) } }
        let previous = try loadWorkContext()
        guard previous?.revision == expectedRevision else { throw WorkContextStorageError.stale }
        if let previous {
            guard value.revision != previous.revision, value.rosters.starts(with: previous.rosters),
                  value.occurrences.starts(with: previous.occurrences), value.associations.starts(with: previous.associations) else {
                throw WorkContextStorageError.invalid
            }
        }
        let payload = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO work_block_context(id, payload) VALUES(1, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw WorkContextStorageError.unavailable }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, payload, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_DONE, sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else {
            throw WorkContextStorageError.unavailable
        }
        committed = true
    }
}

@MainActor
extension SessionRepository {
    func workContext() throws -> WorkContextDocument? { try storage.loadWorkContext() }
    func saveWorkContext(_ value: WorkContextDocument, expectedRevision: UUID?) throws {
        try storage.saveWorkContext(value, expectedRevision: expectedRevision)
        sessionDidChange.send()
    }
}
