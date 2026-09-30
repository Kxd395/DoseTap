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
        guard status == SQLITE_ROW else { throw WorkContextStorageError.unavailable }
        guard sqlite3_column_type(statement, 0) == SQLITE_TEXT,
              let bytes = sqlite3_column_text(statement, 0) else { throw WorkContextStorageError.invalid }
        let count = Int(sqlite3_column_bytes(statement, 0))
        guard count > 0 else { throw WorkContextStorageError.invalid }
        let payload = Data(bytes: bytes, count: count)
        guard String(data: payload, encoding: .utf8) != nil else { throw WorkContextStorageError.invalid }
        let value = try JSONDecoder().decode(WorkContextDocument.self, from: payload)
        guard value.isValid else { throw WorkContextStorageError.invalid }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw WorkContextStorageError.unavailable }
        return value
    }

    func saveWorkContext(_ value: WorkContextDocument, expectedRevision: UUID?) throws {
        guard databaseInitializationFailure == nil, let db, sqlite3_get_autocommit(db) != 0,
              sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { throw WorkContextStorageError.unavailable }
        var committed = false
        defer { if !committed { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) } }
        try writeWorkContextInCurrentTransaction(value, expectedRevision: expectedRevision)
        guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else { throw WorkContextStorageError.unavailable }
        committed = true
    }

    /// Call only inside the successful prospective pre-sleep insertion transaction.
    /// The caller owns commit/rollback; edits and retries retain the original capture.
    func captureWorkPlanInCurrentTransaction(preSleepLogID: String, sessionID: String?, capturedAt: Date) throws -> WorkPlanSnapshot? {
        guard databaseInitializationFailure == nil, let db, sqlite3_get_autocommit(db) == 0 else { throw WorkContextStorageError.unavailable }
        guard var value = try loadWorkContext() else { return nil }
        if let original = value.planSnapshots?.first(where: { $0.preSleepLogID == preSleepLogID }) { return original }
        let previousRevision = value.revision
        guard let snapshot = value.capturePlan(preSleepLogID: preSleepLogID, sessionID: sessionID, at: capturedAt) else { throw WorkContextStorageError.invalid }
        try writeWorkContextInCurrentTransaction(value, expectedRevision: previousRevision)
        return snapshot
    }

    private func writeWorkContextInCurrentTransaction(_ value: WorkContextDocument, expectedRevision: UUID?) throws {
        guard value.isValid else { throw WorkContextStorageError.invalid }
        guard let db, sqlite3_get_autocommit(db) == 0 else { throw WorkContextStorageError.unavailable }
        let previous = try loadWorkContext()
        guard previous?.revision == expectedRevision else { throw WorkContextStorageError.stale }
        if let previous {
            guard value.revision != previous.revision, value.rosters.starts(with: previous.rosters),
                  value.occurrences.starts(with: previous.occurrences), value.associations.starts(with: previous.associations),
                  (value.planSnapshots ?? []).starts(with: previous.planSnapshots ?? []),
                  (value.shiftEvents ?? []).starts(with: previous.shiftEvents ?? []) else { throw WorkContextStorageError.invalid }
        }
        let payload = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO work_block_context(id, payload) VALUES(1, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw WorkContextStorageError.unavailable }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_text(statement, 1, payload, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_DONE else { throw WorkContextStorageError.unavailable }
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
