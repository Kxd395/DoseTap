import Foundation
import SQLite3
import DoseCore

@MainActor
extension EventStorage {
    enum MedicationCaptureError: Error, LocalizedError {
        case invalid, conflict, unreadable, notCommitted
        var errorDescription: String? {
            switch self {
            case .invalid: return "Review the medication, positive amount and occurrence time before saving."
            case .conflict: return "This entry was already saved with different details. Review the saved entry."
            case .unreadable: return "Medication history could not be checked. No new entry was saved."
            case .notCommitted: return "Medication was not saved. Your entry is kept for retry."
            }
        }
    }

    /// Strict reads for capture/duplicate decisions. Date grouping is never a matching constraint.
    func medicationCaptureRows(column: String, value: String) throws -> [StoredMedicationEntry] {
        guard ["id", "medication_id"].contains(column) else { throw MedicationCaptureError.invalid }
        return try readExportRows("""
        SELECT id, session_id, session_date, medication_id, dose_mg, dose_unit, formulation,
               taken_at_utc, local_offset_minutes, notes, confirmed_duplicate, created_at
        FROM medication_events WHERE \(column) = ? ORDER BY taken_at_utc DESC, id
        """, binding: value) { stmt in
            func text(_ index: Int32, nullable: Bool = false) throws -> String? {
                if nullable && sqlite3_column_type(stmt, index) == SQLITE_NULL { return nil }
                guard sqlite3_column_type(stmt, index) == SQLITE_TEXT,
                      let pointer = sqlite3_column_text(stmt, index),
                      let value = String(bytes: UnsafeBufferPointer(start: pointer, count: Int(sqlite3_column_bytes(stmt, index))), encoding: .utf8)
                else { throw MedicationCaptureError.unreadable }
                return value
            }
            func date(_ index: Int32) throws -> Date {
                let raw = try text(index)!
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let value = iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) { return value }
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                guard let value = formatter.date(from: raw) else { throw MedicationCaptureError.unreadable }
                return value
            }
            guard sqlite3_column_type(stmt, 4) == SQLITE_INTEGER,
                  sqlite3_column_type(stmt, 8) == SQLITE_INTEGER,
                  sqlite3_column_type(stmt, 10) == SQLITE_INTEGER,
                  [0, 1].contains(sqlite3_column_int64(stmt, 10)) else { throw MedicationCaptureError.unreadable }
            return try StoredMedicationEntry(id: text(0)!, sessionId: text(1, nullable: true), sessionDate: text(2)!,
                medicationId: text(3)!, doseMg: Int(sqlite3_column_int64(stmt, 4)), takenAtUTC: date(7),
                doseUnit: text(5)!, formulation: text(6)!, localOffsetMinutes: Int(sqlite3_column_int64(stmt, 8)),
                notes: text(9, nullable: true), confirmedDuplicate: sqlite3_column_int64(stmt, 10) == 1, createdAt: date(11))
        }
    }

    func medicationCaptureDuplicates(medicationId: String, takenAt: Date) throws -> [StoredMedicationEntry] {
        try medicationCaptureRows(column: "medication_id", value: medicationId).filter {
            abs($0.takenAtUTC.timeIntervalSince(takenAt)) < Double(MedicationConfig.duplicateGuardMinutes * 60)
        }
    }

    /// One transaction protects command identity, duplicate review and the insert. Never replaces a row.
    func commitMedicationCapture(_ entry: StoredMedicationEntry, reviewedDuplicateIDs: Set<String>) throws -> DuplicateGuardResult {
        guard databaseInitializationFailure == nil, let db,
              sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { throw MedicationCaptureError.notCommitted }
        var committed = false
        defer { if !committed { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) } }
        if let existing = try medicationCaptureRows(column: "id", value: entry.id).first {
            guard existing.medicationId == entry.medicationId, existing.doseMg == entry.doseMg,
                  isoFormatter.string(from: existing.takenAtUTC) == isoFormatter.string(from: entry.takenAtUTC),
                  existing.doseUnit == entry.doseUnit, existing.formulation == entry.formulation,
                  existing.notes == entry.notes, existing.sessionId == nil else { throw MedicationCaptureError.conflict }
            return .notDuplicate
        }
        let duplicates = try medicationCaptureDuplicates(medicationId: entry.medicationId, takenAt: entry.takenAtUTC)
        if let first = duplicates.first,
           !entry.confirmedDuplicate || reviewedDuplicateIDs != Set(duplicates.map(\.id)) {
            return DuplicateGuardResult(isDuplicate: true, existingEntry: MedicationEntry(id: first.id,
                sessionId: first.sessionId, sessionDate: first.sessionDate, medicationId: first.medicationId,
                doseMg: first.doseMg, takenAtUTC: first.takenAtUTC, notes: first.notes,
                confirmedDuplicate: first.confirmedDuplicate, createdAt: first.createdAt),
                minutesDelta: Int(abs(first.takenAtUTC.timeIntervalSince(entry.takenAtUTC)) / 60))
        }
        guard injectedMedicationFailure(at: .insert) == nil else { throw MedicationCaptureError.notCommitted }
        let sql = """
        INSERT INTO medication_events (id, session_id, session_date, medication_id, dose_mg, dose_unit,
            formulation, taken_at_utc, local_offset_minutes, notes, confirmed_duplicate, created_at)
        VALUES (?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw MedicationCaptureError.notCommitted }
        defer { sqlite3_finalize(statement) }
        func bind(_ index: Int32, _ value: String?) throws {
            let result = value.map { sqlite3_bind_text(statement, index, $0, -1, SQLITE_TRANSIENT) } ?? sqlite3_bind_null(statement, index)
            guard result == SQLITE_OK else { throw MedicationCaptureError.notCommitted }
        }
        try bind(1, entry.id); try bind(2, entry.sessionDate); try bind(3, entry.medicationId)
        guard sqlite3_bind_int64(statement, 4, Int64(entry.doseMg)) == SQLITE_OK else { throw MedicationCaptureError.notCommitted }
        try bind(5, entry.doseUnit); try bind(6, entry.formulation); try bind(7, isoFormatter.string(from: entry.takenAtUTC))
        guard sqlite3_bind_int64(statement, 8, Int64(entry.localOffsetMinutes)) == SQLITE_OK else { throw MedicationCaptureError.notCommitted }
        try bind(9, entry.notes)
        guard sqlite3_bind_int(statement, 10, entry.confirmedDuplicate ? 1 : 0) == SQLITE_OK else { throw MedicationCaptureError.notCommitted }
        try bind(11, isoFormatter.string(from: entry.createdAt))
        guard sqlite3_step(statement) == SQLITE_DONE, sqlite3_changes(db) == 1,
              sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else { throw MedicationCaptureError.notCommitted }
        committed = true
        return .notDuplicate
    }
}
