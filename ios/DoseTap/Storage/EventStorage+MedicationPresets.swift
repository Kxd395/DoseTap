import Foundation
import SQLite3
import DoseCore

enum MedicationPresetLedgerError: Error, LocalizedError {
    case conflict, unreadable, notCommitted
    var errorDescription: String? {
        switch self {
        case .conflict: return "The medication revision changed or this ID has different details. Reload and review it."
        case .unreadable: return "The medication preset ledger could not be read completely. Records were not changed."
        case .notCommitted: return "The medication record was not saved. Keep the entry and retry."
        }
    }
}

@MainActor
extension EventStorage {
    private func presetText(_ stmt: OpaquePointer, _ index: Int32) throws -> String? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL { return nil }
        guard sqlite3_column_type(stmt, index) == SQLITE_TEXT, let bytes = sqlite3_column_text(stmt, index),
              let text = String(bytes: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(stmt, index))), encoding: .utf8)
        else { throw MedicationPresetLedgerError.unreadable }
        return text
    }

    private func readPresetLedger() throws -> MedicationPresetExportSnapshot {
        let presets: [String] = try readExportRows("SELECT id, preset_id, predecessor_id, recorded_at_utc, payload FROM medication_preset_revisions ORDER BY recorded_at_utc, id") { stmt in
            guard let payload = try presetText(stmt, 4) else { throw MedicationPresetLedgerError.unreadable }
            let value = try MedicationPresetExportSnapshot.decodePreset(payload)
            guard try presetText(stmt, 0) == value.revisionID.uuidString,
                  try presetText(stmt, 1) == value.presetID.uuidString,
                  try presetText(stmt, 2) == value.supersedesRevisionID?.uuidString,
                  try presetText(stmt, 3) == isoFormatter.string(from: value.recordedAt),
                  try MedicationPresetExportSnapshot.encode(value) == payload else { throw MedicationPresetLedgerError.unreadable }
            return payload
        }
        let administrations: [String] = try readExportRows("SELECT id, revision_id, recorded_at_utc, occurred_at_utc, payload FROM confirmed_medication_administrations ORDER BY recorded_at_utc, id") { stmt in
            guard let payload = try presetText(stmt, 4) else { throw MedicationPresetLedgerError.unreadable }
            let value = try MedicationPresetExportSnapshot.decodeAdministration(payload)
            guard try presetText(stmt, 0) == value.id.uuidString,
                  try presetText(stmt, 1) == value.preset.revisionID.uuidString,
                  try presetText(stmt, 2) == isoFormatter.string(from: value.recordedAt),
                  try presetText(stmt, 3) == value.occurredAt.map(isoFormatter.string(from:)),
                  try MedicationPresetExportSnapshot.encode(value) == payload else { throw MedicationPresetLedgerError.unreadable }
            return payload
        }
        return try MedicationPresetExportSnapshot(presetRevisions: presets, administrations: administrations)
    }

    /// One read transaction includes both independent collections; never date-grouped or row-limited.
    func medicationPresetExportSnapshot() throws -> MedicationPresetExportSnapshot {
        guard databaseInitializationFailure == nil, let db else { throw MedicationPresetLedgerError.unreadable }
        if sqlite3_get_autocommit(db) == 0 { return try readPresetLedger() }
        guard sqlite3_exec(db, "BEGIN DEFERRED", nil, nil, nil) == SQLITE_OK else { throw MedicationPresetLedgerError.unreadable }
        var committed = false
        defer { if !committed { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) } }
        let snapshot = try readPresetLedger()
        guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else { throw MedicationPresetLedgerError.unreadable }
        committed = true
        return snapshot
    }

    private func presetTransaction(_ action: () throws -> Bool) throws -> Bool {
        guard databaseInitializationFailure == nil, let db, injectedMedicationFailure(at: .begin) == nil,
              sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { throw MedicationPresetLedgerError.notCommitted }
        var committed = false
        defer { if !committed { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) } }
        let inserted = try action()
        guard injectedMedicationFailure(at: .commit) == nil,
              sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else { throw MedicationPresetLedgerError.notCommitted }
        committed = true
        return inserted
    }

    private func insertPresetRow(_ sql: String, values: [String?]) throws {
        guard injectedMedicationFailure(at: .insert) == nil else { throw MedicationPresetLedgerError.notCommitted }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw MedicationPresetLedgerError.notCommitted }
        for (index, value) in values.enumerated() {
            let result = value.map { sqlite3_bind_text(stmt, Int32(index + 1), $0, -1, SQLITE_TRANSIENT) }
                ?? sqlite3_bind_null(stmt, Int32(index + 1))
            guard result == SQLITE_OK else { throw MedicationPresetLedgerError.notCommitted }
        }
        guard sqlite3_step(stmt) == SQLITE_DONE, sqlite3_changes(db) == 1 else { throw MedicationPresetLedgerError.notCommitted }
    }

    func saveMedicationPresetRevision(_ value: MedicationPresetRevision) throws -> Bool {
        let payload = try MedicationPresetExportSnapshot.encode(value)
        return try presetTransaction {
            let snapshot = try readPresetLedger()
            if let old = try snapshot.presetRevisions.first(where: { try MedicationPresetExportSnapshot.decodePreset($0).revisionID == value.revisionID }) {
                guard old == payload else { throw MedicationPresetLedgerError.conflict }
                return false
            }
            _ = try MedicationPresetExportSnapshot(presetRevisions: snapshot.presetRevisions + [payload], administrations: snapshot.administrations)
            try insertPresetRow("INSERT INTO medication_preset_revisions (id, preset_id, predecessor_id, recorded_at_utc, payload) VALUES (?, ?, ?, ?, ?)",
                values: [value.revisionID.uuidString, value.presetID.uuidString, value.supersedesRevisionID?.uuidString,
                         isoFormatter.string(from: value.recordedAt), payload])
            return true
        }
    }

    func saveConfirmedMedicationAdministration(_ value: ConfirmedMedicationAdministration) throws -> Bool {
        let payload = try MedicationPresetExportSnapshot.encode(value)
        return try presetTransaction {
            let snapshot = try readPresetLedger()
            if let old = try snapshot.administrations.first(where: { try MedicationPresetExportSnapshot.decodeAdministration($0).id == value.id }) {
                guard old == payload else { throw MedicationPresetLedgerError.conflict }
                return false
            }
            _ = try MedicationPresetExportSnapshot(presetRevisions: snapshot.presetRevisions, administrations: snapshot.administrations + [payload])
            try insertPresetRow("INSERT INTO confirmed_medication_administrations (id, revision_id, recorded_at_utc, occurred_at_utc, payload) VALUES (?, ?, ?, ?, ?)",
                values: [value.id.uuidString, value.preset.revisionID.uuidString, isoFormatter.string(from: value.recordedAt),
                         value.occurredAt.map(isoFormatter.string(from:)), payload])
            return true
        }
    }
}

@MainActor
extension SessionRepository {
    func medicationPresetExportSnapshot() throws -> MedicationPresetExportSnapshot { try storage.medicationPresetExportSnapshot() }
    func saveMedicationPresetRevision(_ value: MedicationPresetRevision) throws {
        guard value.recordedAt <= clock() else { throw MedicationPresetError.invalidTime }
        if try storage.saveMedicationPresetRevision(value) { sessionDidChange.send() }
    }
    func saveConfirmedMedicationAdministration(_ value: ConfirmedMedicationAdministration) throws {
        guard value.recordedAt <= clock() else { throw MedicationPresetError.invalidTime }
        if try storage.saveConfirmedMedicationAdministration(value) { sessionDidChange.send() }
    }
}
