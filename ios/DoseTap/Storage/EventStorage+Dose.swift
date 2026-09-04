import Foundation
import SQLite3
import DoseCore
import os.log

// MARK: - Dose Event Operations, Undo, and Time Editing

enum CanonicalDoseEventType: String, CaseIterable {
    case dose1 = "dose1"
    case dose2 = "dose2"
    case extraDose = "extra_dose"
    case dose2Skipped = "dose2_skipped"
    case snooze = "snooze"

    init?(canonicalizing rawValue: String) {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")

        switch normalized {
        case "dose1", "dose_1", "dose1_taken", "dose_1_taken":
            self = .dose1
        case "dose2", "dose_2", "dose2_taken", "dose_2_taken",
             "dose2_early", "dose_2_early", "dose2_late", "dose_2_late",
             "dose_2_(early)", "dose_2_(late)":
            self = .dose2
        case "extra_dose", "extra_dose_taken", "extra", "dose3", "dose_3", "dose_3_taken":
            self = .extraDose
        case "dose2_skipped", "dose_2_skipped", "skip", "skipped":
            self = .dose2Skipped
        case "snooze", "dose2_snoozed":
            self = .snooze
        default:
            return nil
        }
    }

    var countsAsTakenDose: Bool {
        switch self {
        case .dose1, .dose2, .extraDose:
            return true
        case .dose2Skipped, .snooze:
            return false
        }
    }
}

extension EventStorage {

    // MARK: - Transaction Boundary

    private func medicationFailure(
        operation: MedicationMutationOperation,
        failure: MedicationStorageInjectedFailure,
        point: MedicationStorageFaultPoint
    ) -> MedicationMutationResult {
        .failed(MedicationMutationFailure(
            operation: operation,
            code: failure.code,
            stage: point.stage,
            sqliteCode: failure.sqliteCode,
            detail: failure.detail
        ))
    }

    private func performMedicationTransaction(
        operation: MedicationMutationOperation,
        sessionId: String,
        sessionDate: String,
        timestamp: Date?,
        body: () throws -> Void
    ) -> MedicationMutationResult {
        if let initializationFailure = databaseInitializationFailure {
            return medicationFailure(
                operation: operation,
                failure: initializationFailure,
                point: .open
            )
        }
        guard let db else {
            return .failed(MedicationMutationFailure(
                operation: operation,
                code: .databaseUnavailable,
                stage: .open,
                detail: "SQLite database handle is unavailable"
            ))
        }

        if let injected = injectedMedicationFailure(at: .preflight) {
            return medicationFailure(operation: operation, failure: injected, point: .preflight)
        }

        if let injected = injectedMedicationFailure(at: .begin) {
            return medicationFailure(operation: operation, failure: injected, point: .begin)
        }
        let beginResult = sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil)
        guard beginResult == SQLITE_OK else {
            let mapped = medicationStorageFailure(
                sqliteCode: sqlite3_extended_errcode(db),
                detail: String(cString: sqlite3_errmsg(db))
            )
            let failure = MedicationStorageInjectedFailure(
                code: mapped.code == .statement ? .transaction : mapped.code,
                sqliteCode: mapped.sqliteCode,
                detail: mapped.detail
            )
            return medicationFailure(operation: operation, failure: failure, point: .begin)
        }

        do {
            try body()
            if let injected = injectedMedicationFailure(at: .commit) {
                throw Self.prefixedMedicationFailure(injected, point: .commit)
            }
            let commitResult = sqlite3_exec(db, "COMMIT", nil, nil, nil)
            guard commitResult == SQLITE_OK else {
                let mapped = medicationStorageFailure(
                    sqliteCode: sqlite3_extended_errcode(db),
                    detail: String(cString: sqlite3_errmsg(db))
                )
                throw Self.prefixedMedicationFailure(
                    MedicationStorageInjectedFailure(
                        code: mapped.code == .statement ? .transaction : mapped.code,
                        sqliteCode: mapped.sqliteCode,
                        detail: mapped.detail
                    ),
                    point: .commit
                )
            }
            return .committed(MedicationMutationReceipt(
                operation: operation,
                sessionId: sessionId,
                sessionDate: sessionDate,
                timestamp: timestamp
            ))
        } catch let originalFailure as MedicationStorageInjectedFailure {
            if let rollbackFailure = injectedMedicationFailure(at: .rollback) {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return medicationFailure(
                    operation: operation,
                    failure: rollbackFailure,
                    point: .rollback
                )
            }
            let rollbackResult = sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            if rollbackResult != SQLITE_OK {
                let mapped = medicationStorageFailure(
                    sqliteCode: sqlite3_extended_errcode(db),
                    detail: "Rollback failed after \(originalFailure.detail): \(String(cString: sqlite3_errmsg(db)))"
                )
                let rollbackFailure = MedicationStorageInjectedFailure(
                    code: mapped.code == .statement ? .transaction : mapped.code,
                    sqliteCode: mapped.sqliteCode,
                    detail: mapped.detail
                )
                return medicationFailure(
                    operation: operation,
                    failure: rollbackFailure,
                    point: .rollback
                )
            }

            // Statement helpers attach their point in a lightweight prefix.
            let point = Self.medicationFaultPoint(from: originalFailure.detail) ?? .update
            let sanitizedFailure = MedicationStorageInjectedFailure(
                code: originalFailure.code,
                sqliteCode: originalFailure.sqliteCode,
                detail: Self.removingMedicationFaultPrefix(from: originalFailure.detail)
            )
            return medicationFailure(
                operation: operation,
                failure: sanitizedFailure,
                point: point
            )
        } catch {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return .failed(MedicationMutationFailure(
                operation: operation,
                code: .unknown,
                stage: .rollback,
                detail: error.localizedDescription
            ))
        }
    }

    private static func prefixedMedicationFailure(
        _ failure: MedicationStorageInjectedFailure,
        point: MedicationStorageFaultPoint
    ) -> MedicationStorageInjectedFailure {
        MedicationStorageInjectedFailure(
            code: failure.code,
            sqliteCode: failure.sqliteCode,
            detail: "[\(point.stage.rawValue)]\(failure.detail)"
        )
    }

    private static func medicationFaultPoint(
        from detail: String
    ) -> MedicationStorageFaultPoint? {
        if detail.hasPrefix("[delete]") { return .delete }
        if detail.hasPrefix("[insert]") { return .insert }
        if detail.hasPrefix("[update]") { return .update }
        if detail.hasPrefix("[commit]") { return .commit }
        if detail.hasPrefix("[preflight]") { return .preflight }
        return nil
    }

    private static func removingMedicationFaultPrefix(from detail: String) -> String {
        guard detail.first == "[", let end = detail.firstIndex(of: "]") else {
            return detail
        }
        return String(detail[detail.index(after: end)...])
    }

    private func executeMedicationStatement(
        _ sql: String,
        at point: MedicationStorageFaultPoint,
        requireChanges: Bool = false,
        bind: (OpaquePointer) -> Void = { _ in }
    ) throws {
        if let injected = injectedMedicationFailure(at: point) {
            throw Self.prefixedMedicationFailure(injected, point: point)
        }
        guard let db else {
            throw Self.prefixedMedicationFailure(
                MedicationStorageInjectedFailure(
                    code: .databaseUnavailable,
                    detail: "SQLite database handle is unavailable"
                ),
                point: point
            )
        }

        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw Self.prefixedMedicationFailure(
                medicationStorageFailure(
                    sqliteCode: sqlite3_extended_errcode(db),
                    detail: String(cString: sqlite3_errmsg(db))
                ),
                point: point
            )
        }
        defer { sqlite3_finalize(statement) }
        bind(statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw Self.prefixedMedicationFailure(
                medicationStorageFailure(
                    sqliteCode: sqlite3_extended_errcode(db),
                    detail: String(cString: sqlite3_errmsg(db))
                ),
                point: point
            )
        }
        if requireChanges, sqlite3_changes(db) == 0 {
            throw Self.prefixedMedicationFailure(
                MedicationStorageInjectedFailure(
                    code: .precondition,
                    detail: "The active medication record changed before this write could commit. Reload and retry."
                ),
                point: .preflight
            )
        }
    }

    /// Read the original rows while holding the same write transaction that
    /// replaces them. Raw metadata preserves any earlier correction chain.
    private func correctionMetadata(_ metadata: String?, sessionId: String, sessionDate: String, eventTypes: String) throws -> String {
        let sql = "SELECT id, event_type, timestamp, session_date, session_id, metadata, created_at FROM dose_events WHERE (session_id = ? OR ((session_id IS NULL OR session_id = session_date) AND session_date = ?)) AND event_type IN (\(eventTypes)) ORDER BY timestamp, id"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw MedicationStorageInjectedFailure(code: .statement, detail: "Cannot preserve the original medication record. Retry without changing history.")
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, sessionId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, sessionDate, -1, SQLITE_TRANSIENT)
        let keys = ["id", "event_type", "timestamp", "session_date", "session_id", "metadata", "created_at"]
        var previous: [[String: Any]] = []
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            var row: [String: Any] = [:]
            for (index, key) in keys.enumerated() {
                row[key] = sqlite3_column_text(statement, Int32(index)).map { String(cString: $0) } as Any? ?? NSNull()
            }
            previous.append(row)
            step = sqlite3_step(statement)
        }
        guard step == SQLITE_DONE else {
            throw MedicationStorageInjectedFailure(code: .statement, detail: "Cannot read the original medication history.")
        }
        var object: [String: Any] = [:]
        if let metadata {
            guard let data = metadata.data(using: .utf8), let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw MedicationStorageInjectedFailure(code: .precondition, detail: "Medication metadata is invalid; history was not changed.")
            }
            object = decoded
        }
        if !previous.isEmpty {
            object["correction"] = [
                "previous_events": previous,
                "corrected_at_utc": object["recorded_at_utc"] ?? isoFormatter.string(from: nowProvider()),
                "source": object["source"] ?? object["surface"] ?? "user_record_correction"
            ]
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }

    func loadWorkWakeSchedule() throws -> WorkWakeSchedule {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM work_wake_schedule WHERE id = 1", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw MedicationStorageInjectedFailure(code: .statement, detail: "Work schedule could not be loaded.")
        }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return WorkWakeSchedule() }
        guard result == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else {
            throw MedicationStorageInjectedFailure(code: .statement, detail: "Work schedule is unavailable.")
        }
        let plan = try JSONDecoder().decode(WorkWakeSchedule.self, from: Data(String(cString: text).utf8))
        guard plan.isValid else { throw MedicationStorageInjectedFailure(code: .precondition, detail: "Work schedule needs review.") }
        return plan
    }

    func saveWorkWakeSchedule(_ schedule: WorkWakeSchedule, expectedRevision: UUID? = nil) -> MedicationMutationResult {
        guard schedule.isValid, let data = try? JSONEncoder().encode(schedule), let payload = String(data: data, encoding: .utf8) else {
            return .failed(MedicationMutationFailure(operation: .workSchedule, code: .precondition, stage: .preflight, detail: "Check the work schedule times and timezone."))
        }
        let now = nowProvider()
        return performMedicationTransaction(operation: .workSchedule, sessionId: "work-schedule", sessionDate: "", timestamp: now) {
            try executeMedicationStatement("INSERT INTO work_wake_schedule (id, payload, updated_at) VALUES (1, ?, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at WHERE ? IS NULL OR json_extract(work_wake_schedule.payload, '$.revision') = ?", at: .update, requireChanges: true) { statement in
                sqlite3_bind_text(statement, 1, payload, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, isoFormatter.string(from: now), -1, SQLITE_TRANSIENT)
                if let expectedRevision {
                    sqlite3_bind_text(statement, 3, expectedRevision.uuidString, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 4, expectedRevision.uuidString, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(statement, 3)
                    sqlite3_bind_null(statement, 4)
                }
            }
        }
    }

    private func medicationDose1Exists(
        sessionId: String,
        sessionDate: String
    ) throws -> Bool {
        guard let db else {
            throw MedicationStorageInjectedFailure(
                code: .databaseUnavailable,
                detail: "SQLite database handle is unavailable"
            )
        }
        let sql = """
        SELECT COUNT(*) FROM dose_events
        WHERE event_type = ? AND (session_id = ? OR ((session_id IS NULL OR session_id = session_date) AND session_date = ?))
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw Self.prefixedMedicationFailure(
                medicationStorageFailure(
                    sqliteCode: sqlite3_extended_errcode(db),
                    detail: String(cString: sqlite3_errmsg(db))
                ),
                point: .update
            )
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, CanonicalDoseEventType.dose1.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, sessionId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, sessionDate, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw Self.prefixedMedicationFailure(
                medicationStorageFailure(
                    sqliteCode: sqlite3_extended_errcode(db),
                    detail: String(cString: sqlite3_errmsg(db))
                ),
                point: .update
            )
        }
        return sqlite3_column_int(statement, 0) > 0
    }

    private func medicationDose2Exists(
        sessionId: String,
        sessionDate: String
    ) throws -> Bool {
        guard let db else {
            throw MedicationStorageInjectedFailure(
                code: .databaseUnavailable,
                detail: "SQLite database handle is unavailable"
            )
        }
        let sql = """
        SELECT EXISTS(
            SELECT 1 FROM dose_events
            WHERE event_type = ?
              AND (session_id = ? OR ((session_id IS NULL OR session_id = session_date) AND session_date = ?))
        )
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw Self.prefixedMedicationFailure(
                medicationStorageFailure(
                    sqliteCode: sqlite3_extended_errcode(db),
                    detail: String(cString: sqlite3_errmsg(db))
                ),
                point: .preflight
            )
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, CanonicalDoseEventType.dose2.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, sessionId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, sessionDate, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw Self.prefixedMedicationFailure(
                medicationStorageFailure(
                    sqliteCode: sqlite3_extended_errcode(db),
                    detail: String(cString: sqlite3_errmsg(db))
                ),
                point: .preflight
            )
        }
        return sqlite3_column_int(statement, 0) == 1
    }

    private func medicationDose1HasDependentEvents(
        sessionId: String,
        sessionDate: String
    ) throws -> Bool {
        guard let db else {
            throw Self.prefixedMedicationFailure(
                MedicationStorageInjectedFailure(
                    code: .databaseUnavailable,
                    detail: "SQLite database handle is unavailable"
                ),
                point: .preflight
            )
        }

        let sql = """
        SELECT EXISTS(
            SELECT 1 FROM dose_events
            WHERE (session_id = ? OR ((session_id IS NULL OR session_id = session_date) AND session_date = ?))
              AND event_type IN ('dose2', 'extra_dose', 'dose2_skipped', 'snooze')
        )
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw Self.prefixedMedicationFailure(
                medicationStorageFailure(
                    sqliteCode: sqlite3_extended_errcode(db),
                    detail: String(cString: sqlite3_errmsg(db))
                ),
                point: .preflight
            )
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, sessionId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, sessionDate, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw Self.prefixedMedicationFailure(
                medicationStorageFailure(
                    sqliteCode: sqlite3_extended_errcode(db),
                    detail: String(cString: sqlite3_errmsg(db))
                ),
                point: .preflight
            )
        }
        return sqlite3_column_int(statement, 0) == 1
    }

    // MARK: - Dose Event Operations

    /// Atomically replace Dose 1 before any dependent outcome is recorded.
    /// Completed or snoozed sequences must use the explicit history-edit APIs;
    /// this capture path is not allowed to erase downstream medication events.
    @discardableResult
    public func saveDose1(
        timestamp: Date,
        sessionId: String? = nil,
        sessionDateOverride: String? = nil,
        sessionStart: Date? = nil
    ) -> MedicationMutationResult {
        let sessionDate = sessionDateOverride ?? sessionDateString(for: timestamp)
        let resolvedSessionId = sessionId ?? sessionDate
        let timestampString = isoFormatter.string(from: timestamp)
        let startString = isoFormatter.string(from: sessionStart ?? timestamp)
        let eventId = UUID().uuidString

        return performMedicationTransaction(
            operation: .dose1,
            sessionId: resolvedSessionId,
            sessionDate: sessionDate,
            timestamp: timestamp
        ) {
            if try medicationDose1HasDependentEvents(
                sessionId: resolvedSessionId,
                sessionDate: sessionDate
            ) {
                throw Self.prefixedMedicationFailure(
                    MedicationStorageInjectedFailure(
                        code: .precondition,
                        detail: "Dose 1 cannot be replaced after a Dose 2, skip, extra dose, or snooze is recorded. Edit the history entry instead."
                    ),
                    point: .preflight
                )
            }

            try executeMedicationStatement(
                """
                DELETE FROM dose_events
                WHERE session_id = ?
                   OR ((session_id IS NULL OR session_id = session_date) AND session_date = ? AND event_type IN ('dose1','dose2','extra_dose','dose2_skipped','snooze'))
                """,
                at: .delete
            ) { statement in
                sqlite3_bind_text(statement, 1, resolvedSessionId, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, sessionDate, -1, SQLITE_TRANSIENT)
            }

            try executeMedicationStatement(
                """
                INSERT INTO dose_events (id, event_type, timestamp, session_date, session_id, metadata)
                VALUES (?, ?, ?, ?, ?, NULL)
                """,
                at: .insert
            ) { statement in
                sqlite3_bind_text(statement, 1, eventId, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, CanonicalDoseEventType.dose1.rawValue, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 3, timestampString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 4, sessionDate, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 5, resolvedSessionId, -1, SQLITE_TRANSIENT)
            }

            try executeMedicationStatement(
                """
                INSERT INTO current_session (
                    id, session_date, session_id, session_start_utc, session_end_utc,
                    terminal_state, dose1_time, dose2_time, snooze_count,
                    dose2_skipped, updated_at
                ) VALUES (1, ?, ?, ?, NULL, NULL, ?, NULL, 0, 0, CURRENT_TIMESTAMP)
                ON CONFLICT(id) DO UPDATE SET
                    session_date = excluded.session_date,
                    session_id = excluded.session_id,
                    session_start_utc = excluded.session_start_utc,
                    session_end_utc = NULL,
                    terminal_state = NULL,
                    dose1_time = excluded.dose1_time,
                    dose2_time = NULL,
                    snooze_count = 0,
                    dose2_skipped = 0,
                    updated_at = CURRENT_TIMESTAMP
                """,
                at: .update
            ) { statement in
                sqlite3_bind_text(statement, 1, sessionDate, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, resolvedSessionId, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 3, startString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 4, timestampString, -1, SQLITE_TRANSIENT)
            }

            try executeMedicationStatement(
                """
                INSERT INTO sleep_sessions (
                    session_id, session_date, start_utc, end_utc, terminal_state,
                    created_at, updated_at
                ) VALUES (?, ?, ?, NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                ON CONFLICT(session_id) DO UPDATE SET
                    session_date = excluded.session_date,
                    start_utc = COALESCE(sleep_sessions.start_utc, excluded.start_utc),
                    end_utc = NULL,
                    terminal_state = NULL,
                    updated_at = CURRENT_TIMESTAMP
                """,
                at: .update
            ) { statement in
                sqlite3_bind_text(statement, 1, resolvedSessionId, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, sessionDate, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 3, startString, -1, SQLITE_TRANSIENT)
            }
        }
    }

    /// Save dose 2 taken
    /// - Parameters:
    ///   - timestamp: When dose 2 was taken
    ///   - isEarly: True if taken before window opened (user override)
    ///   - isExtraDose: True if this is a second attempt at dose 2 (confirmed by user)
    @discardableResult
    public func saveDose2(
        timestamp: Date,
        isEarly: Bool = false,
        isExtraDose: Bool = false,
        isLate: Bool = false,
        entryMode: DoseEntryMode? = nil,
        workWarning: WorkWakeWarning? = nil,
        recordedAt: Date? = nil,
        surface: RegistrationSurface? = nil,
        reason: String? = nil,
        reasonNotes: String? = nil,
        sessionId: String? = nil,
        sessionDateOverride: String? = nil
    ) -> MedicationMutationResult {
        var metadata: [String: Any] = [:]
        if isEarly { metadata["is_early"] = true }
        if isExtraDose { metadata["is_extra_dose"] = true }
        if isLate { metadata["is_late"] = true }
        if let entryMode { metadata["entry_mode"] = entryMode.rawValue }
        if let recordedAt { metadata["recorded_at_utc"] = isoFormatter.string(from: recordedAt) }
        if let surface { metadata["surface"] = surface.rawValue }
        if let reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata["reason"] = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let reasonNotes, !reasonNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata["reason_notes"] = reasonNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let workWarning, let data = try? JSONEncoder().encode(workWarning), let json = try? JSONSerialization.jsonObject(with: data) {
            metadata["work_warning_acknowledgement"] = json
        }
        let eventType: CanonicalDoseEventType = isExtraDose ? .extraDose : .dose2
        let metadataStr = metadata.isEmpty ? nil : (try? JSONSerialization.data(withJSONObject: metadata)).flatMap { String(data: $0, encoding: .utf8) }
        let sessionDate = sessionDateOverride ?? sessionDateString(for: timestamp)
        let resolvedSessionId = sessionId ?? sessionDate
        let timestampString = isoFormatter.string(from: timestamp)
        let eventId = UUID().uuidString
        let operation: MedicationMutationOperation = isExtraDose ? .extraDose : .dose2

        return performMedicationTransaction(
            operation: operation,
            sessionId: resolvedSessionId,
            sessionDate: sessionDate,
            timestamp: timestamp
        ) {
            if let workWarning {
                guard workWarning.sessionId == resolvedSessionId, try loadWorkWakeSchedule().revision == workWarning.revision else {
                    throw MedicationStorageInjectedFailure(code: .precondition, detail: "Your work schedule changed before the dose was saved. Review the warning again.")
                }
            }
            guard try medicationDose1Exists(
                sessionId: resolvedSessionId,
                sessionDate: sessionDate
            ) else {
                throw Self.prefixedMedicationFailure(
                    MedicationStorageInjectedFailure(
                        code: .precondition,
                        detail: "Take Dose 1 before recording Dose 2."
                    ),
                    point: .preflight
                )
            }

            let hasDose2 = try medicationDose2Exists(
                sessionId: resolvedSessionId,
                sessionDate: sessionDate
            )
            if hasDose2 && !isExtraDose {
                throw Self.prefixedMedicationFailure(
                    MedicationStorageInjectedFailure(
                        code: .precondition,
                        detail: "Dose 2 is already recorded. Use the explicit extra-dose confirmation or Edit to correct it."
                    ),
                    point: .preflight
                )
            }
            if !hasDose2 && isExtraDose {
                throw Self.prefixedMedicationFailure(
                    MedicationStorageInjectedFailure(
                        code: .precondition,
                        detail: "Record Dose 2 before adding an extra dose."
                    ),
                    point: .preflight
                )
            }

            let preservedMetadata = try correctionMetadata(metadataStr, sessionId: resolvedSessionId, sessionDate: sessionDate, eventTypes: isExtraDose ? "''" : "'dose2_skipped'")
            if !isExtraDose {
                try executeMedicationStatement(
                    "DELETE FROM dose_events WHERE (session_id = ? OR ((session_id IS NULL OR session_id = session_date) AND session_date = ?)) AND event_type = ?",
                    at: .delete
                ) { statement in
                    sqlite3_bind_text(statement, 1, resolvedSessionId, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 2, sessionDate, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 3, CanonicalDoseEventType.dose2Skipped.rawValue, -1, SQLITE_TRANSIENT)
                }
            }

            try executeMedicationStatement(
                """
                INSERT INTO dose_events (id, event_type, timestamp, session_date, session_id, metadata)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                at: .insert
            ) { statement in
                sqlite3_bind_text(statement, 1, eventId, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, eventType.rawValue, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 3, timestampString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 4, sessionDate, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 5, resolvedSessionId, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 6, preservedMetadata, -1, SQLITE_TRANSIENT)
            }

            if !isExtraDose {
                try executeMedicationStatement(
                    """
                    UPDATE current_session
                    SET dose2_time = ?,
                        dose2_skipped = 0,
                        terminal_state = CASE
                            WHEN terminal_state = 'incomplete_slept_through' THEN NULL
                            ELSE terminal_state
                        END,
                        updated_at = CURRENT_TIMESTAMP
                    WHERE id = 1 AND session_id = ?
                    """,
                    at: .update,
                    requireChanges: true
                ) { statement in
                    sqlite3_bind_text(statement, 1, timestampString, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 2, resolvedSessionId, -1, SQLITE_TRANSIENT)
                }

                // Older builds could infer "slept through" from elapsed time.
                // A user-confirmed actual occurrence repairs that legacy terminal
                // marker while preserving the diagnostic trail and all other data.
                try executeMedicationStatement(
                    """
                    UPDATE sleep_sessions
                    SET terminal_state = NULL, updated_at = CURRENT_TIMESTAMP
                    WHERE session_id = ? AND terminal_state = 'incomplete_slept_through'
                    """,
                    at: .update
                ) { statement in
                    sqlite3_bind_text(statement, 1, resolvedSessionId, -1, SQLITE_TRANSIENT)
                }
            }
        }
    }

    /// Save dose skipped with optional reason
    @discardableResult
    public func saveDoseSkipped(
        reason: String? = nil,
        reasonNotes: String? = nil,
        surface: RegistrationSurface? = nil,
        sessionId: String? = nil,
        sessionDateOverride: String? = nil
    ) -> MedicationMutationResult {
        let metadata: String?
        var object: [String: String] = [:]
        if let reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            object["reason"] = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let reasonNotes, !reasonNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            object["reason_notes"] = reasonNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let surface {
            object["surface"] = surface.rawValue
        }
        if object.isEmpty {
            metadata = nil
        } else {
            metadata = (try? JSONSerialization.data(withJSONObject: object)).flatMap { String(data: $0, encoding: .utf8) }
        }
        let now = nowProvider()
        let sessionDate = sessionDateOverride ?? sessionDateString(for: now)
        let resolvedSessionId = sessionId ?? sessionDate
        let timestampString = isoFormatter.string(from: now)
        let eventId = UUID().uuidString

        return performMedicationTransaction(
            operation: .skipDose2,
            sessionId: resolvedSessionId,
            sessionDate: sessionDate,
            timestamp: now
        ) {
            guard try medicationDose1Exists(
                sessionId: resolvedSessionId,
                sessionDate: sessionDate
            ) else {
                throw Self.prefixedMedicationFailure(
                    MedicationStorageInjectedFailure(
                        code: .precondition,
                        detail: "Take Dose 1 before skipping Dose 2."
                    ),
                    point: .preflight
                )
            }
            try executeMedicationStatement(
                "DELETE FROM dose_events WHERE session_date = ? AND event_type = ?",
                at: .delete
            ) { statement in
                sqlite3_bind_text(statement, 1, sessionDate, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, CanonicalDoseEventType.dose2Skipped.rawValue, -1, SQLITE_TRANSIENT)
            }
            try executeMedicationStatement(
                """
                INSERT INTO dose_events (id, event_type, timestamp, session_date, session_id, metadata)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                at: .insert
            ) { statement in
                sqlite3_bind_text(statement, 1, eventId, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, CanonicalDoseEventType.dose2Skipped.rawValue, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 3, timestampString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 4, sessionDate, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 5, resolvedSessionId, -1, SQLITE_TRANSIENT)
                if let metadata {
                    sqlite3_bind_text(statement, 6, metadata, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(statement, 6)
                }
            }
            try executeMedicationStatement(
                """
                UPDATE current_session
                SET dose2_time = NULL, dose2_skipped = 1, updated_at = CURRENT_TIMESTAMP
                WHERE id = 1 AND session_id = ?
                """,
                at: .update,
                requireChanges: true
            ) { statement in
                sqlite3_bind_text(statement, 1, resolvedSessionId, -1, SQLITE_TRANSIENT)
            }
        }
    }

    /// Save snooze
    @discardableResult
    public func saveSnooze(
        count: Int,
        sessionId: String? = nil,
        sessionDateOverride: String? = nil
    ) -> MedicationMutationResult {
        let now = nowProvider()
        let sessionDate = sessionDateOverride ?? sessionDateString(for: now)
        let resolvedSessionId = sessionId ?? sessionDate
        let timestampString = isoFormatter.string(from: now)
        let eventId = UUID().uuidString

        return performMedicationTransaction(
            operation: .snooze,
            sessionId: resolvedSessionId,
            sessionDate: sessionDate,
            timestamp: now
        ) {
            guard try medicationDose1Exists(
                sessionId: resolvedSessionId,
                sessionDate: sessionDate
            ) else {
                throw Self.prefixedMedicationFailure(
                    MedicationStorageInjectedFailure(
                        code: .precondition,
                        detail: "Take Dose 1 before snoozing."
                    ),
                    point: .preflight
                )
            }
            try executeMedicationStatement(
                """
                INSERT INTO dose_events (id, event_type, timestamp, session_date, session_id, metadata)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                at: .insert
            ) { statement in
                sqlite3_bind_text(statement, 1, eventId, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, CanonicalDoseEventType.snooze.rawValue, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 3, timestampString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 4, sessionDate, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 5, resolvedSessionId, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 6, "{\"count\":\(count)}", -1, SQLITE_TRANSIENT)
            }
            try executeMedicationStatement(
                """
                UPDATE current_session
                SET snooze_count = ?, updated_at = CURRENT_TIMESTAMP
                WHERE id = 1 AND session_id = ?
                  AND dose1_time IS NOT NULL AND dose2_time IS NULL AND dose2_skipped = 0
                """,
                at: .update,
                requireChanges: true
            ) { statement in
                sqlite3_bind_int(statement, 1, Int32(max(0, count)))
                sqlite3_bind_text(statement, 2, resolvedSessionId, -1, SQLITE_TRANSIENT)
            }
        }
    }

    /// Atomically reconcile a canonical medication outcome captured after the
    /// overnight session. Historical sessions update their event ledger only;
    /// an active matching snapshot is updated in the same transaction.
    @discardableResult
    func reconcileDoseEvent(
        eventType: CanonicalDoseEventType,
        timestamp: Date,
        sessionDate: String,
        sessionId: String? = nil,
        metadata: String?,
        expectedDose1Time: Date? = nil,
        onlyIfDose2Missing: Bool = false,
        workWarning: WorkWakeWarning? = nil
    ) -> MedicationMutationResult {
        guard eventType == .dose1 || eventType == .dose2 || eventType == .dose2Skipped else {
            return .failed(MedicationMutationFailure(
                operation: .reconcileDoseState,
                code: .precondition,
                stage: .preflight,
                detail: "Morning reconciliation supports Dose 1, Dose 2, or a Dose 2 skip."
            ))
        }

        let resolvedSessionId = sessionId ?? fetchSessionId(forSessionDate: sessionDate) ?? sessionDate
        let timestampString = isoFormatter.string(from: timestamp)
        let eventId = UUID().uuidString

        return performMedicationTransaction(
            operation: .reconcileDoseState,
            sessionId: resolvedSessionId,
            sessionDate: sessionDate,
            timestamp: timestamp
        ) {
            if let workWarning {
                guard workWarning.sessionId == resolvedSessionId, try loadWorkWakeSchedule().revision == workWarning.revision else {
                    throw MedicationStorageInjectedFailure(code: .precondition, detail: "Your work schedule changed. Review the updated warning before saving.")
                }
            }
            if eventType == .dose2 || eventType == .dose2Skipped {
                guard try medicationDose1Exists(
                    sessionId: resolvedSessionId,
                    sessionDate: sessionDate
                ) else {
                    throw Self.prefixedMedicationFailure(
                        MedicationStorageInjectedFailure(
                            code: .precondition,
                            detail: "Reconcile Dose 1 before recording the Dose 2 outcome."
                        ),
                        point: .preflight
                    )
                }
            }

            if onlyIfDose2Missing, try medicationDose2Exists(sessionId: resolvedSessionId, sessionDate: sessionDate) {
                throw MedicationStorageInjectedFailure(code: .precondition, detail: "Dose 2 has already been recorded. Reload this session.")
            }
            if let expectedDose1Time {
                let originals = fetchDoseEvents(sessionId: resolvedSessionId, sessionDate: sessionDate).filter { $0.eventType == "dose1" }
                guard originals.count == 1, originals.first?.timestamp == expectedDose1Time else {
                    throw MedicationStorageInjectedFailure(code: .precondition, detail: "Dose 1 changed. Reload before correcting this session.")
                }
            }
            let eventTypesToReplace: String
            switch eventType {
            case .dose1:
                eventTypesToReplace = "'dose1'"
            case .dose2, .dose2Skipped:
                eventTypesToReplace = "'dose2','dose2_skipped'"
            case .extraDose, .snooze:
                eventTypesToReplace = "''"
            }
            let preservedMetadata = try correctionMetadata(metadata, sessionId: resolvedSessionId, sessionDate: sessionDate, eventTypes: eventTypesToReplace)
            try executeMedicationStatement(
                "DELETE FROM dose_events WHERE (session_id = ? OR ((session_id IS NULL OR session_id = session_date) AND session_date = ?)) AND event_type IN (\(eventTypesToReplace))",
                at: .delete
            ) { statement in
                sqlite3_bind_text(statement, 1, resolvedSessionId, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, sessionDate, -1, SQLITE_TRANSIENT)
            }

            try executeMedicationStatement(
                """
                INSERT INTO dose_events (id, event_type, timestamp, session_date, session_id, metadata)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                at: .insert
            ) { statement in
                sqlite3_bind_text(statement, 1, eventId, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, eventType.rawValue, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 3, timestampString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 4, sessionDate, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 5, resolvedSessionId, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 6, preservedMetadata, -1, SQLITE_TRANSIENT)
            }

            switch eventType {
            case .dose1:
                try executeMedicationStatement(
                    "UPDATE current_session SET dose1_time = ?, updated_at = CURRENT_TIMESTAMP WHERE session_id = ?",
                    at: .update
                ) { statement in
                    sqlite3_bind_text(statement, 1, timestampString, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 2, resolvedSessionId, -1, SQLITE_TRANSIENT)
                }
            case .dose2:
                try executeMedicationStatement(
                    """
                    UPDATE current_session
                    SET dose2_time = ?, dose2_skipped = 0, updated_at = CURRENT_TIMESTAMP
                    WHERE session_id = ?
                    """,
                    at: .update
                ) { statement in
                    sqlite3_bind_text(statement, 1, timestampString, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 2, resolvedSessionId, -1, SQLITE_TRANSIENT)
                }
            case .dose2Skipped:
                try executeMedicationStatement(
                    """
                    UPDATE current_session
                    SET dose2_time = NULL, dose2_skipped = 1, updated_at = CURRENT_TIMESTAMP
                    WHERE session_id = ?
                    """,
                    at: .update
                ) { statement in
                    sqlite3_bind_text(statement, 1, resolvedSessionId, -1, SQLITE_TRANSIENT)
                }
            case .extraDose, .snooze:
                break
            }
        }
    }

    /// Update existing Dose 2 outcome annotations through the same transaction
    /// boundary used by live dose mutations.
    @discardableResult
    func updateDose2OutcomeAnnotations(
        sessionDate: String,
        dose2Metadata: String?,
        skippedMetadata: String?
    ) -> MedicationMutationResult {
        let resolvedSessionId = fetchSessionId(forSessionDate: sessionDate) ?? sessionDate
        return performMedicationTransaction(
            operation: .reconcileDoseState,
            sessionId: resolvedSessionId,
            sessionDate: sessionDate,
            timestamp: nil
        ) {
            try executeMedicationStatement(
                """
                UPDATE dose_events
                SET metadata = CASE event_type
                    WHEN 'dose2' THEN ?
                    WHEN 'dose2_skipped' THEN ?
                    ELSE metadata
                END
                WHERE session_date = ? AND event_type IN ('dose2','dose2_skipped')
                """,
                at: .update
            ) { statement in
                if let dose2Metadata {
                    sqlite3_bind_text(statement, 1, dose2Metadata, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(statement, 1)
                }
                if let skippedMetadata {
                    sqlite3_bind_text(statement, 2, skippedMetadata, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(statement, 2)
                }
                sqlite3_bind_text(statement, 3, sessionDate, -1, SQLITE_TRANSIENT)
            }
        }
    }

    /// Remove the latest snooze event for undo or rollback, then update the current snapshot count.
    @discardableResult
    public func rollbackLatestSnooze(
        toCount count: Int,
        sessionDateOverride: String? = nil
    ) -> MedicationMutationResult {
        let sessionDate = sessionDateOverride ?? currentSessionDate()
        let sessionId = fetchSessionId(forSessionDate: sessionDate) ?? sessionDate
        let result = performMedicationTransaction(
            operation: .rollbackSnooze,
            sessionId: sessionId,
            sessionDate: sessionDate,
            timestamp: nil
        ) {
            try executeMedicationStatement(
                """
                DELETE FROM dose_events
                WHERE id = (
                    SELECT id FROM dose_events
                    WHERE session_date = ? AND event_type = ?
                    ORDER BY timestamp DESC, rowid DESC
                    LIMIT 1
                )
                """,
                at: .delete,
                requireChanges: true
            ) { statement in
                sqlite3_bind_text(statement, 1, sessionDate, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, CanonicalDoseEventType.snooze.rawValue, -1, SQLITE_TRANSIENT)
            }
            try executeMedicationStatement(
                """
                UPDATE current_session
                SET snooze_count = ?, updated_at = CURRENT_TIMESTAMP
                WHERE id = 1 AND session_date = ?
                """,
                at: .update,
                requireChanges: true
            ) { statement in
                sqlite3_bind_int(statement, 1, Int32(max(0, count)))
                sqlite3_bind_text(statement, 2, sessionDate, -1, SQLITE_TRANSIENT)
            }
        }
        if result.isCommitted {
            storageLog.info("Undo: Rolled back latest snooze for session \(sessionDate)")
        }
        return result
    }

    // MARK: - Undo Support Methods

    /// Clear dose 1 from current session (for undo)
    @discardableResult
    public func clearDose1(
        sessionDateOverride: String? = nil
    ) -> MedicationMutationResult {
        let sessionDate = sessionDateOverride ?? currentSessionDate()
        let sessionId = fetchSessionId(forSessionDate: sessionDate) ?? sessionDate
        let result = performMedicationTransaction(
            operation: .clearDoseSequence,
            sessionId: sessionId,
            sessionDate: sessionDate,
            timestamp: nil
        ) {
            try executeMedicationStatement(
                "DELETE FROM dose_events WHERE session_date = ? AND event_type = ?",
                at: .delete
            ) { statement in
                sqlite3_bind_text(statement, 1, sessionDate, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, CanonicalDoseEventType.dose1.rawValue, -1, SQLITE_TRANSIENT)
            }
            try executeMedicationStatement(
                "UPDATE current_session SET dose1_time = NULL, updated_at = CURRENT_TIMESTAMP WHERE session_date = ?",
                at: .update
            ) { statement in
                sqlite3_bind_text(statement, 1, sessionDate, -1, SQLITE_TRANSIENT)
            }
        }
        if result.isCommitted {
            storageLog.info("Undo: Cleared dose1 for session \(sessionDate)")
        }
        return result
    }

    /// Clear dose 2 from current session (for undo)
    @discardableResult
    public func clearDose2(
        sessionDateOverride: String? = nil
    ) -> MedicationMutationResult {
        let sessionDate = sessionDateOverride ?? currentSessionDate()
        let sessionId = fetchSessionId(forSessionDate: sessionDate) ?? sessionDate
        let result = performMedicationTransaction(
            operation: .clearDose2,
            sessionId: sessionId,
            sessionDate: sessionDate,
            timestamp: nil
        ) {
            try executeMedicationStatement(
                "DELETE FROM dose_events WHERE session_date = ? AND event_type = ?",
                at: .delete
            ) { statement in
                sqlite3_bind_text(statement, 1, sessionDate, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, CanonicalDoseEventType.dose2.rawValue, -1, SQLITE_TRANSIENT)
            }
            try executeMedicationStatement(
                "UPDATE current_session SET dose2_time = NULL, updated_at = CURRENT_TIMESTAMP WHERE session_date = ?",
                at: .update
            ) { statement in
                sqlite3_bind_text(statement, 1, sessionDate, -1, SQLITE_TRANSIENT)
            }
        }
        if result.isCommitted {
            storageLog.info("Undo: Cleared dose2 for session \(sessionDate)")
        }
        return result
    }

    /// Clear skip status from current session (for undo)
    @discardableResult
    public func clearSkip(
        sessionDateOverride: String? = nil
    ) -> MedicationMutationResult {
        let sessionDate = sessionDateOverride ?? currentSessionDate()
        let sessionId = fetchSessionId(forSessionDate: sessionDate) ?? sessionDate
        let result = performMedicationTransaction(
            operation: .clearSkip,
            sessionId: sessionId,
            sessionDate: sessionDate,
            timestamp: nil
        ) {
            try executeMedicationStatement(
                "DELETE FROM dose_events WHERE session_date = ? AND event_type = ?",
                at: .delete
            ) { statement in
                sqlite3_bind_text(statement, 1, sessionDate, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, CanonicalDoseEventType.dose2Skipped.rawValue, -1, SQLITE_TRANSIENT)
            }
            try executeMedicationStatement(
                "UPDATE current_session SET dose2_skipped = 0, updated_at = CURRENT_TIMESTAMP WHERE session_date = ?",
                at: .update
            ) { statement in
                sqlite3_bind_text(statement, 1, sessionDate, -1, SQLITE_TRANSIENT)
            }
        }
        if result.isCommitted {
            storageLog.info("Undo: Cleared skip for session \(sessionDate)")
        }
        return result
    }

    /// Clear the full dose sequence for a session while preserving non-dose sleep events.
    /// Dose 2, extra dose, skip, and snooze state are dependent on Dose 1 and cannot remain after Dose 1 undo.
    @discardableResult
    public func clearDoseSequence(
        sessionDateOverride: String? = nil
    ) -> MedicationMutationResult {
        let sessionDate = sessionDateOverride ?? currentSessionDate()
        let sessionId = fetchSessionId(forSessionDate: sessionDate) ?? sessionDate
        let result = performMedicationTransaction(
            operation: .clearDoseSequence,
            sessionId: sessionId,
            sessionDate: sessionDate,
            timestamp: nil
        ) {
            try executeMedicationStatement(
                "DELETE FROM dose_events WHERE session_date = ? AND event_type IN ('dose1','dose2','extra_dose','dose2_skipped','snooze')",
                at: .delete
            ) { statement in
                sqlite3_bind_text(statement, 1, sessionDate, -1, SQLITE_TRANSIENT)
            }
            try executeMedicationStatement(
                """
                UPDATE current_session
                SET dose1_time = NULL, dose2_time = NULL, snooze_count = 0,
                    dose2_skipped = 0, updated_at = CURRENT_TIMESTAMP
                WHERE session_date = ?
                """,
                at: .update
            ) { statement in
                sqlite3_bind_text(statement, 1, sessionDate, -1, SQLITE_TRANSIENT)
            }
        }
        if result.isCommitted {
            storageLog.info("Undo: Cleared dose sequence for session \(sessionDate)")
        }
        return result
    }

    // MARK: - Time Editing Methods (Manual Entry Support)

    /// Update Dose 1 time for a session
    @discardableResult
    public func updateDose1Time(
        newTime: Date,
        sessionDate: String
    ) -> MedicationMutationResult {
        let timestampStr = isoFormatter.string(from: newTime)
        let sessionId = fetchSessionId(forSessionDate: sessionDate) ?? sessionDate
        let result = performMedicationTransaction(
            operation: .updateDose1Time,
            sessionId: sessionId,
            sessionDate: sessionDate,
            timestamp: newTime
        ) {
            try executeMedicationStatement(
                "UPDATE dose_events SET timestamp = ? WHERE session_date = ? AND event_type = ?",
                at: .update,
                requireChanges: true
            ) { statement in
                sqlite3_bind_text(statement, 1, timestampStr, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, sessionDate, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 3, CanonicalDoseEventType.dose1.rawValue, -1, SQLITE_TRANSIENT)
            }
            try executeMedicationStatement(
                "UPDATE current_session SET dose1_time = ?, updated_at = CURRENT_TIMESTAMP WHERE session_date = ?",
                at: .update
            ) { statement in
                sqlite3_bind_text(statement, 1, timestampStr, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, sessionDate, -1, SQLITE_TRANSIENT)
            }
        }
        if result.isCommitted {
            storageLog.info("Edit: Updated dose1 time to \(timestampStr) for session \(sessionDate)")
        }
        return result
    }

    /// Update Dose 2 time for a session
    @discardableResult
    public func updateDose2Time(
        newTime: Date,
        sessionDate: String
    ) -> MedicationMutationResult {
        let timestampStr = isoFormatter.string(from: newTime)
        let sessionId = fetchSessionId(forSessionDate: sessionDate) ?? sessionDate
        let result = performMedicationTransaction(
            operation: .updateDose2Time,
            sessionId: sessionId,
            sessionDate: sessionDate,
            timestamp: newTime
        ) {
            try executeMedicationStatement(
                "UPDATE dose_events SET timestamp = ? WHERE session_date = ? AND event_type = ?",
                at: .update,
                requireChanges: true
            ) { statement in
                sqlite3_bind_text(statement, 1, timestampStr, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, sessionDate, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 3, CanonicalDoseEventType.dose2.rawValue, -1, SQLITE_TRANSIENT)
            }
            try executeMedicationStatement(
                "UPDATE current_session SET dose2_time = ?, updated_at = CURRENT_TIMESTAMP WHERE session_date = ?",
                at: .update
            ) { statement in
                sqlite3_bind_text(statement, 1, timestampStr, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, sessionDate, -1, SQLITE_TRANSIENT)
            }
        }
        if result.isCommitted {
            storageLog.info("Edit: Updated dose2 time to \(timestampStr) for session \(sessionDate)")
        }
        return result
    }

    /// Update sleep event time
    public func updateSleepEventTime(eventId: String, newTime: Date) {
        let timestampStr = isoFormatter.string(from: newTime)

        let updateSQL = "UPDATE sleep_events SET timestamp = ? WHERE id = ?"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, updateSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, timestampStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, eventId, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        storageLog.info("Edit: Updated event \(eventId) time to \(timestampStr)")
    }

    /// Update notes on a sleep event. Pass nil or empty string to clear.
    public func updateSleepEventNotes(eventId: String, notes: String?) {
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNotes: String? = (trimmed?.isEmpty == true) ? nil : trimmed

        let updateSQL = "UPDATE sleep_events SET notes = ? WHERE id = ?"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, updateSQL, -1, &stmt, nil) == SQLITE_OK {
            if let n = finalNotes {
                sqlite3_bind_text(stmt, 1, n, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 1)
            }
            sqlite3_bind_text(stmt, 2, eventId, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        storageLog.info("Edit: Updated event \(eventId) notes (len=\(finalNotes?.count ?? 0))")
    }

    /// Update metadata JSON for a stored dose event.
    public func updateDoseEventMetadata(eventId: String, metadata: String?) {
        let updateSQL = "UPDATE dose_events SET metadata = ? WHERE id = ?"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, updateSQL, -1, &stmt, nil) == SQLITE_OK {
            if let metadata {
                sqlite3_bind_text(stmt, 1, metadata, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 1)
            }
            sqlite3_bind_text(stmt, 2, eventId, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - Internal Dose Helpers

    @discardableResult
    private func insertDoseEventInternal(eventType: CanonicalDoseEventType, timestamp: Date, sessionDate: String? = nil, sessionId: String? = nil, metadata: String? = nil) -> Bool {
        let sql = """
        INSERT INTO dose_events (id, event_type, timestamp, session_date, session_id, metadata)
        VALUES (?, ?, ?, ?, ?, ?)
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(stmt) }

        let id = UUID().uuidString
        let sessionDate = sessionDate ?? sessionDateString(for: timestamp)
        let resolvedSessionId = sessionId ?? sessionDate
        let timestampStr = isoFormatter.string(from: timestamp)

        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, eventType.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, timestampStr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, sessionDate, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, resolvedSessionId, -1, SQLITE_TRANSIENT)

        if let metadata = metadata {
            sqlite3_bind_text(stmt, 6, metadata, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 6)
        }

        if sqlite3_step(stmt) == SQLITE_DONE {
            storageLog.debug("Dose event saved: \(eventType.rawValue, privacy: .public)")
            return true
        }
        return false
    }

    /// Insert a dose event (Dose 1 or Dose 2)
    /// Returns true if successful, false if duplicate (unless force=true)
    public func saveDoseEvent(type: String, timestamp: Date, isHazard: Bool = false) -> Bool {
        guard let eventType = CanonicalDoseEventType(canonicalizing: type), eventType.countsAsTakenDose else {
            storageLog.warning("Rejected non-canonical dose event type: \(type, privacy: .public)")
            return false
        }

        let sessionDate = currentSessionDate()
        let resolvedSessionId = fetchSessionId(forSessionDate: sessionDate) ?? sessionDate

        // Check for existing dose of this type in this session
        if !isHazard && hasDose(type: eventType.rawValue, sessionDate: sessionDate) {
            storageLog.warning("Dose \(eventType.rawValue, privacy: .public) already exists for \(sessionDate). Use isHazard=true to force log.")
            return false
        }

        let metadata = isHazard ? #"{"is_hazard":true}"# : nil
        let timestampStr = isoFormatter.string(from: timestamp)
        let saved = insertDoseEventInternal(eventType: eventType, timestamp: timestamp, sessionDate: sessionDate, sessionId: resolvedSessionId, metadata: metadata)
        storageLog.debug("Dose event save requested: \(eventType.rawValue, privacy: .public) at \(timestampStr, privacy: .public) hazard=\(isHazard)")
        return saved
    }

    /// Check if a dose type already exists for a session
    public func hasDose(type: String, sessionDate: String) -> Bool {
        guard let eventType = CanonicalDoseEventType(canonicalizing: type) else { return false }
        let sql = "SELECT count(*) FROM dose_events WHERE session_date = ? AND event_type = ?"
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, eventType.rawValue, -1, SQLITE_TRANSIENT)

        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_int(stmt, 0) > 0
        }
        return false
    }

    private func deleteDoseEvents(ofType eventType: CanonicalDoseEventType, sessionDate: String) {
        let sql = "DELETE FROM dose_events WHERE session_date = ? AND event_type = ?"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, eventType.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    private func updateDoseEventTime(ofType eventType: CanonicalDoseEventType, timestampStr: String, sessionDate: String) {
        let sql = "UPDATE dose_events SET timestamp = ? WHERE session_date = ? AND event_type = ?"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, timestampStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, eventType.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    public struct DoseStateInvariantViolation: Equatable {
        public let code: String
        public let message: String

        public init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }

    public func validateActiveDoseStateInvariant() -> [DoseStateInvariantViolation] {
        let snapshot = loadCurrentSessionState()
        let hasSnapshotDoseState = snapshot.dose1Time != nil
            || snapshot.dose2Time != nil
            || snapshot.dose2Skipped
            || snapshot.snoozeCount > 0

        guard let sessionDate = snapshot.sessionDate else {
            return hasSnapshotDoseState
                ? [DoseStateInvariantViolation(
                    code: "active_session_missing_date",
                    message: "current_session has dose state without session_date"
                )]
                : []
        }

        guard snapshot.sessionEnd == nil else { return [] }

        let events = fetchDoseEvents(sessionId: snapshot.sessionId, sessionDate: sessionDate)
        let dose1Events = events.filter { CanonicalDoseEventType(canonicalizing: $0.eventType) == .dose1 }
        let dose2Events = events.filter { CanonicalDoseEventType(canonicalizing: $0.eventType) == .dose2 }
        let extraDoseEvents = events.filter { CanonicalDoseEventType(canonicalizing: $0.eventType) == .extraDose }
        let skippedEvents = events.filter { CanonicalDoseEventType(canonicalizing: $0.eventType) == .dose2Skipped }
        let snoozeEvents = events.filter { CanonicalDoseEventType(canonicalizing: $0.eventType) == .snooze }
        let unknownDoseEvents = events.filter { CanonicalDoseEventType(canonicalizing: $0.eventType) == nil }
        let nonCanonicalEvents = events.compactMap { event -> String? in
            guard let canonical = CanonicalDoseEventType(canonicalizing: event.eventType),
                  canonical.rawValue != event.eventType else { return nil }
            return "\(event.eventType)->\(canonical.rawValue)"
        }

        var violations: [DoseStateInvariantViolation] = []

        if !unknownDoseEvents.isEmpty {
            let names = Set(unknownDoseEvents.map(\.eventType)).sorted().joined(separator: ",")
            violations.append(DoseStateInvariantViolation(
                code: "unknown_dose_event_type",
                message: "active session has unknown dose event type(s): \(names)"
            ))
        }

        if !nonCanonicalEvents.isEmpty {
            let names = Set(nonCanonicalEvents).sorted().joined(separator: ",")
            violations.append(DoseStateInvariantViolation(
                code: "non_canonical_dose_event_type",
                message: "active session has non-canonical dose event type(s): \(names)"
            ))
        }

        if dose1Events.count > 1 {
            violations.append(DoseStateInvariantViolation(
                code: "duplicate_dose1_events",
                message: "active session has \(dose1Events.count) dose1 events"
            ))
        }

        if dose2Events.count > 1 {
            violations.append(DoseStateInvariantViolation(
                code: "duplicate_dose2_events",
                message: "active session has \(dose2Events.count) dose2 events"
            ))
        }

        if snapshot.dose1Time == nil, !dose1Events.isEmpty {
            violations.append(DoseStateInvariantViolation(
                code: "dose1_event_without_snapshot",
                message: "dose_events has dose1 but current_session.dose1_time is empty"
            ))
        }

        if snapshot.dose1Time != nil, dose1Events.isEmpty {
            violations.append(DoseStateInvariantViolation(
                code: "dose1_snapshot_without_event",
                message: "current_session.dose1_time is set but dose_events has no dose1"
            ))
        }

        if let snapshotDose1 = snapshot.dose1Time,
           let eventDose1 = dose1Events.first?.timestamp,
           !doseInvariantTimestampsMatch(snapshotDose1, eventDose1) {
            violations.append(DoseStateInvariantViolation(
                code: "dose1_timestamp_mismatch",
                message: "current_session.dose1_time does not match dose_events.dose1 timestamp"
            ))
        }

        if snapshot.dose2Time == nil, !dose2Events.isEmpty {
            violations.append(DoseStateInvariantViolation(
                code: "dose2_event_without_snapshot",
                message: "dose_events has dose2 but current_session.dose2_time is empty"
            ))
        }

        if snapshot.dose2Time != nil, dose2Events.isEmpty {
            violations.append(DoseStateInvariantViolation(
                code: "dose2_snapshot_without_event",
                message: "current_session.dose2_time is set but dose_events has no dose2"
            ))
        }

        if let snapshotDose2 = snapshot.dose2Time,
           let eventDose2 = dose2Events.first?.timestamp,
           !doseInvariantTimestampsMatch(snapshotDose2, eventDose2) {
            violations.append(DoseStateInvariantViolation(
                code: "dose2_timestamp_mismatch",
                message: "current_session.dose2_time does not match dose_events.dose2 timestamp"
            ))
        }

        if !dose2Events.isEmpty, dose1Events.isEmpty {
            violations.append(DoseStateInvariantViolation(
                code: "dose2_without_dose1",
                message: "dose_events has dose2 before a canonical dose1"
            ))
        }

        if !extraDoseEvents.isEmpty, dose2Events.isEmpty {
            violations.append(DoseStateInvariantViolation(
                code: "extra_dose_without_dose2",
                message: "dose_events has extra_dose before a canonical dose2"
            ))
        }

        if (snapshot.snoozeCount > 0 || !snoozeEvents.isEmpty), dose1Events.isEmpty {
            violations.append(DoseStateInvariantViolation(
                code: "snooze_without_dose1",
                message: "active session has snooze state before a canonical dose1"
            ))
        }

        if snapshot.snoozeCount > 0, snoozeEvents.isEmpty {
            violations.append(DoseStateInvariantViolation(
                code: "snooze_snapshot_without_event",
                message: "current_session.snooze_count is set but dose_events has no snooze"
            ))
        }

        if snapshot.snoozeCount == 0, !snoozeEvents.isEmpty {
            violations.append(DoseStateInvariantViolation(
                code: "snooze_event_without_snapshot",
                message: "dose_events has snooze but current_session.snooze_count is zero"
            ))
        }

        if snapshot.dose2Skipped, skippedEvents.isEmpty {
            violations.append(DoseStateInvariantViolation(
                code: "skip_snapshot_without_event",
                message: "current_session.dose2_skipped is set but dose_events has no dose2_skipped"
            ))
        }

        if !snapshot.dose2Skipped, !skippedEvents.isEmpty {
            violations.append(DoseStateInvariantViolation(
                code: "skip_event_without_snapshot",
                message: "dose_events has dose2_skipped but current_session.dose2_skipped is false"
            ))
        }

        if snapshot.dose2Skipped, snapshot.dose2Time != nil {
            violations.append(DoseStateInvariantViolation(
                code: "dose2_time_and_skip_snapshot",
                message: "current_session has both dose2_time and dose2_skipped"
            ))
        }

        if !dose2Events.isEmpty, !skippedEvents.isEmpty {
            violations.append(DoseStateInvariantViolation(
                code: "dose2_event_and_skip_event",
                message: "dose_events has both dose2 and dose2_skipped"
            ))
        }

        return violations
    }

    private func doseInvariantTimestampsMatch(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) <= 0.001
    }
}
