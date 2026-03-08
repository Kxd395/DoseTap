import Foundation
import SQLite3
import DoseCore
import os.log

// MARK: - Data Management, Deletes, CloudKit Tombstones, Session Utilities

extension EventStorage {

    // MARK: - Bulk Data Management

    /// Clear all data (for testing/debug)
    public func clearAllData() {
        let tables = [
            "sleep_events", "dose_events", "current_session", "sleep_sessions", "pre_sleep_logs",
            "morning_checkins", "checkin_submissions", "medication_events"
        ]
        for table in tables {
            let sql = "DELETE FROM \(table)"
            var errMsg: UnsafeMutablePointer<CChar>?
            sqlite3_exec(db, sql, nil, nil, &errMsg)
            if errMsg != nil {
                sqlite3_free(errMsg)
            }
        }
        storageLog.info("All EventStorage data cleared")
    }

    /// Fetch row count for a table filtered by session_date (for test assertions)
    /// Returns 0 if table doesn't exist or query fails
    public func fetchRowCount(table: String, sessionDate: String) -> Int {
        // Sanitize table name to prevent SQL injection (only allow known tables)
        let allowedTables = [
            "sleep_events", "dose_events", "current_session", "sleep_sessions", "pre_sleep_logs",
            "morning_checkins", "checkin_submissions", "medication_events"
        ]
        guard allowedTables.contains(table) else {
            storageLog.warning("fetchRowCount: Unknown table '\(table)'")
            return 0
        }

        let sql: String
        if table == "pre_sleep_logs" {
            sql = "SELECT COUNT(*) FROM pre_sleep_logs WHERE session_id = ?"
        } else {
            sql = "SELECT COUNT(*) FROM \(table) WHERE session_date = ?"
        }
        var stmt: OpaquePointer?
        var count = 0

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)

        return count
    }

    /// Clear all sleep events only
    public func clearAllSleepEvents() {
        let sql = "DELETE FROM sleep_events"
        var errMsg: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, sql, nil, nil, &errMsg)
        if errMsg != nil {
            sqlite3_free(errMsg)
        }
        storageLog.info("All sleep events cleared")
    }

    /// Clear data older than specified days
    public func clearOldData(olderThanDays days: Int) {
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -days, to: Date()) else { return }
        let cutoffStr = sessionDateString(for: cutoffDate)

        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)

        let tables = ["sleep_events", "dose_events", "sleep_sessions", "morning_checkins", "checkin_submissions", "medication_events"]
        for table in tables {
            let sql = "DELETE FROM \(table) WHERE session_date < ?"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, cutoffStr, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
        }

        // pre_sleep_logs does not include session_date; clear by created timestamp instead.
        let cutoffTimestamp = isoFormatter.string(from: cutoffDate)
        let preSleepSQL = "DELETE FROM pre_sleep_logs WHERE created_at_utc < ?"
        var preSleepStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, preSleepSQL, -1, &preSleepStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(preSleepStmt, 1, cutoffTimestamp, -1, SQLITE_TRANSIENT)
            sqlite3_step(preSleepStmt)
            sqlite3_finalize(preSleepStmt)
        }

        // Also clean current_session entries
        let sessionSQL = "DELETE FROM current_session WHERE session_date < ?"
        var sessionStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sessionSQL, -1, &sessionStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(sessionStmt, 1, cutoffStr, -1, SQLITE_TRANSIENT)
            sqlite3_step(sessionStmt)
            sqlite3_finalize(sessionStmt)
        }

        sqlite3_exec(db, "COMMIT", nil, nil, nil)
        storageLog.info("Data older than \(days) days cleared")
    }

    /// Delete a session by date
    public func deleteSession(sessionDate: String, recordCloudKitDeletion: Bool = true) {
        if recordCloudKitDeletion {
            enqueueCloudKitTombstone(recordType: "DoseTapSession", recordName: sessionDate)

            for id in fetchRecordIDsForSession(table: "sleep_events", sessionDate: sessionDate) {
                enqueueCloudKitTombstone(recordType: "DoseTapSleepEvent", recordName: id)
            }
            for id in fetchRecordIDsForSession(table: "dose_events", sessionDate: sessionDate) {
                enqueueCloudKitTombstone(recordType: "DoseTapDoseEvent", recordName: id)
            }
            for id in fetchRecordIDsForSession(table: "morning_checkins", sessionDate: sessionDate) {
                enqueueCloudKitTombstone(recordType: "DoseTapMorningCheckIn", recordName: id)
            }
            for id in fetchRecordIDsForSession(table: "medication_events", sessionDate: sessionDate) {
                enqueueCloudKitTombstone(recordType: "DoseTapMedicationEvent", recordName: id)
            }
            for id in fetchPreSleepLogIDsForSession(sessionDate: sessionDate) {
                enqueueCloudKitTombstone(recordType: "DoseTapPreSleepLog", recordName: id)
            }
        }

        // Use transaction for atomicity
        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)

        let preSleepSQL = """
            DELETE FROM pre_sleep_logs
            WHERE session_id = ?
               OR session_id IN (SELECT session_id FROM sleep_sessions WHERE session_date = ?)
        """
        var preSleepStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, preSleepSQL, -1, &preSleepStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(preSleepStmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(preSleepStmt, 2, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_step(preSleepStmt)
            sqlite3_finalize(preSleepStmt)
        }

        let tables = ["sleep_events", "dose_events", "sleep_sessions", "morning_checkins", "checkin_submissions", "medication_events"]
        for table in tables {
            let sql = "DELETE FROM \(table) WHERE session_date = ?"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
        }

        // Remove current_session row for this session to prevent ghost entries in exports/timeline
        let deleteCurrentSQL = "DELETE FROM current_session WHERE session_date = ?"
        var clearStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteCurrentSQL, -1, &clearStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(clearStmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_step(clearStmt)
            sqlite3_finalize(clearStmt)
        }

        sqlite3_exec(db, "COMMIT", nil, nil, nil)
        storageLog.info("Session \(sessionDate, privacy: .public) deleted")
    }

    // MARK: - Individual Record Deletes

    /// Delete a specific sleep event by ID
    public func deleteSleepEvent(id: String) {
        deleteSleepEvent(id: id, recordCloudKitDeletion: true)
    }

    /// Delete a specific sleep event by ID with optional outbound CloudKit tombstone.
    public func deleteSleepEvent(id: String, recordCloudKitDeletion: Bool = true) {
        if recordCloudKitDeletion {
            enqueueCloudKitTombstone(recordType: "DoseTapSleepEvent", recordName: id)
        }
        let sql = "DELETE FROM sleep_events WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)

        if sqlite3_step(stmt) == SQLITE_DONE {
            storageLog.debug("Sleep event deleted: \(id, privacy: .private)")
        }
    }

    /// Delete a specific dose event by ID
    public func deleteDoseEvent(id: String) {
        deleteDoseEvent(id: id, recordCloudKitDeletion: true)
    }

    /// Delete a specific dose event by ID with optional outbound CloudKit tombstone.
    public func deleteDoseEvent(id: String, recordCloudKitDeletion: Bool = true) {
        if recordCloudKitDeletion {
            enqueueCloudKitTombstone(recordType: "DoseTapDoseEvent", recordName: id)
        }
        let sql = "DELETE FROM dose_events WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)

        if sqlite3_step(stmt) == SQLITE_DONE {
            storageLog.debug("Dose event deleted: \(id, privacy: .private)")
        }
    }

    /// Delete a specific morning check-in by ID
    public func deleteMorningCheckIn(id: String) {
        deleteMorningCheckIn(id: id, recordCloudKitDeletion: true)
    }

    /// Delete a specific morning check-in by ID with optional outbound CloudKit tombstone.
    public func deleteMorningCheckIn(id: String, recordCloudKitDeletion: Bool = true) {
        if recordCloudKitDeletion {
            enqueueCloudKitTombstone(recordType: "DoseTapMorningCheckIn", recordName: id)
        }
        let sql = "DELETE FROM morning_checkins WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)

        if sqlite3_step(stmt) == SQLITE_DONE {
            deleteCheckInSubmission(sourceRecordId: id, checkInType: .morning)
            storageLog.debug("Morning check-in deleted: \(id, privacy: .private)")
        }
    }

    // MARK: - CloudKit Tombstones

    /// Fetch pending CloudKit tombstones for outbound delete sync.
    public func fetchCloudKitTombstones(limit: Int = 500) -> [CloudKitTombstone] {
        let sql = """
        SELECT key, record_type, record_name, created_at
        FROM cloudkit_tombstones
        ORDER BY created_at ASC
        LIMIT ?
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(max(1, limit)))

        var rows: [CloudKitTombstone] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard
                let keyPtr = sqlite3_column_text(stmt, 0),
                let typePtr = sqlite3_column_text(stmt, 1),
                let namePtr = sqlite3_column_text(stmt, 2),
                let createdAtPtr = sqlite3_column_text(stmt, 3)
            else { continue }

            let createdAtRaw = String(cString: createdAtPtr)
            let createdAt = isoFormatter.date(from: createdAtRaw) ?? Date()
            rows.append(
                CloudKitTombstone(
                    key: String(cString: keyPtr),
                    recordType: String(cString: typePtr),
                    recordName: String(cString: namePtr),
                    createdAt: createdAt
                )
            )
        }

        return rows
    }

    /// Remove delivered CloudKit tombstones after successful remote delete.
    public func clearCloudKitTombstones(keys: [String]) {
        guard !keys.isEmpty else { return }

        let sql = "DELETE FROM cloudkit_tombstones WHERE key = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        for key in keys {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
    }

    func enqueueCloudKitTombstone(recordType: String, recordName: String) {
        let key = "\(recordType):\(recordName)"
        let createdAt = isoFormatter.string(from: Date())
        let sql = """
        INSERT OR REPLACE INTO cloudkit_tombstones (key, record_type, record_name, created_at)
        VALUES (?, ?, ?, ?)
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, recordType, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, recordName, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, createdAt, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    private func fetchRecordIDsForSession(table: String, sessionDate: String) -> [String] {
        let allowedTables = Set(["sleep_events", "dose_events", "morning_checkins", "medication_events"])
        guard allowedTables.contains(table) else { return [] }

        let sql = "SELECT id FROM \(table) WHERE session_date = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
        var ids: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let idPtr = sqlite3_column_text(stmt, 0) {
                ids.append(String(cString: idPtr))
            }
        }
        return ids
    }

    private func fetchPreSleepLogIDsForSession(sessionDate: String) -> [String] {
        let sql = """
            SELECT id
            FROM pre_sleep_logs
            WHERE session_id = ?
               OR session_id IN (SELECT session_id FROM sleep_sessions WHERE session_date = ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, sessionDate, -1, SQLITE_TRANSIENT)

        var ids: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let idPtr = sqlite3_column_text(stmt, 0) {
                ids.append(String(cString: idPtr))
            }
        }
        return ids
    }

    private func deleteCheckInSubmission(sourceRecordId: String, checkInType: CheckInType) {
        let sql = "DELETE FROM checkin_submissions WHERE source_record_id = ? AND checkin_type = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, sourceRecordId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, checkInType.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    // MARK: - Session Utilities

    /// Clear all events for tonight's session
    public func clearTonightsEvents(sessionDateOverride: String? = nil) {
        let sessionDate = sessionDateOverride ?? currentSessionDate()
        let sql = "DELETE FROM sleep_events WHERE session_date = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
        storageLog.info("Tonight events cleared")
    }

    /// Get session date string for a given Date
    public func sessionDateString(for date: Date) -> String {
        sessionKey(for: date, timeZone: timeZoneProvider(), rolloverHour: 18)
    }

    /// Find the most recent incomplete session (has dose1 but no dose2 and not skipped)
    public func mostRecentIncompleteSession(excluding sessionDate: String? = nil) -> String? {
        let sql = """
            SELECT ss.session_date
            FROM sleep_sessions ss
            LEFT JOIN morning_checkins mc ON mc.session_id = ss.session_id
            WHERE ss.end_utc IS NOT NULL
            AND mc.id IS NULL
            AND ss.session_date != ?
            ORDER BY ss.start_utc DESC
            LIMIT 1
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        let excluded = sessionDate ?? currentSessionDate()
        sqlite3_bind_text(stmt, 1, excluded, -1, SQLITE_TRANSIENT)

        if sqlite3_step(stmt) == SQLITE_ROW {
            return String(cString: sqlite3_column_text(stmt, 0))
        }
        return nil
    }

    /// Link the most recent pre-sleep log to a session id.
    public func linkPreSleepLogToSession(sessionId: String, sessionDate: String) {
        // Link either unassigned logs or logs stored under the session date placeholder.
        // Use a subquery to find the target row — avoids UPDATE...ORDER BY...LIMIT which
        // requires SQLITE_ENABLE_UPDATE_DELETE_LIMIT (not guaranteed on iOS).
        let sql = """
            UPDATE pre_sleep_logs
            SET session_id = ?
            WHERE id = (
                SELECT id FROM pre_sleep_logs
                WHERE session_id IS NULL OR session_id = ?
                ORDER BY created_at DESC
                LIMIT 1
            )
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, sessionId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, sessionDate, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)

        let submissionSQL = """
            UPDATE checkin_submissions
            SET session_id = ?, session_date = ?
            WHERE checkin_type = ?
              AND (session_id IS NULL OR session_id = ?)
        """
        var submissionStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, submissionSQL, -1, &submissionStmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(submissionStmt) }

        sqlite3_bind_text(submissionStmt, 1, sessionId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(submissionStmt, 2, sessionDate, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(submissionStmt, 3, CheckInType.preNight.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(submissionStmt, 4, sessionDate, -1, SQLITE_TRANSIENT)
        sqlite3_step(submissionStmt)
    }

    /// Legacy helper for EventStore protocol (session key only).
    public func linkPreSleepLogToSession(sessionKey: String) {
        linkPreSleepLogToSession(sessionId: sessionKey, sessionDate: sessionKey)
    }

    /// Fetch recent sessions as summaries (internal - use protocol method externally)
    func fetchRecentSessionsLocal(days: Int = 7) -> [SessionSummary] {
        var sessions: [SessionSummary] = []
        let sessionDates = discoveredSessionDates(limit: days)

        for sessionDate in sessionDates {
            let doseEvents = fetchDoseEvents(sessionId: nil, sessionDate: sessionDate)
            let dose1 = doseEvents.first { isDose1EventType($0.eventType) }
            let dose2 = doseEvents.first { isDose2EventType($0.eventType) }
            let dose2Skipped = doseEvents.contains { isDose2SkippedEventType($0.eventType) }
            let snoozeCount = doseEvents.filter { $0.eventType.lowercased().hasPrefix("snooze") }.count
            let sleepEvents = fetchSleepEvents(forSession: sessionDate)
            let eventCount = sleepEvents.count

            sessions.append(SessionSummary(
                sessionDate: sessionDate,
                dose1Time: dose1?.timestamp,
                dose2Time: dose2?.timestamp,
                dose2Skipped: dose2Skipped,
                snoozeCount: snoozeCount,
                sleepEvents: sleepEvents,
                eventCount: eventCount
            ))
        }

        return sessions
    }

    // MARK: - Dose Event Type Helpers

    private func isDose1EventType(_ raw: String) -> Bool {
        let t = raw.lowercased().replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "-", with: "_")
        return t == "dose1" || t == "dose_1" || t == "dose1_taken" || t == "dose_1_taken"
    }

    private func isDose2EventType(_ raw: String) -> Bool {
        let t = raw.lowercased().replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "-", with: "_")
        return t == "dose2" || t == "dose_2" || t == "dose2_taken" || t == "dose_2_taken"
            || t == "dose2_early" || t == "dose_2_early" || t == "dose2_late" || t == "dose_2_late"
            || t == "dose_2_(early)" || t == "dose_2_(late)"
    }

    private func isDose2SkippedEventType(_ raw: String) -> Bool {
        let t = raw.lowercased().replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "-", with: "_")
        return t == "dose2_skipped" || t == "dose_2_skipped" || t == "skip" || t == "skipped"
    }

    private func countSleepEvents(for sessionDate: String) -> Int {
        let sql = "SELECT COUNT(*) FROM sleep_events WHERE session_date = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    // MARK: - Dose Log Fetch

    /// Fetch dose log for a specific session.
    /// Tries `current_session` first (fast path for the active session), then
    /// falls back to reconstructing from `dose_events` for historical sessions.
    public func fetchDoseLog(forSession sessionDate: String) -> StoredDoseLog? {
        // --- Fast path: current_session (single-row table, only matches active session) ---
        let sql = "SELECT dose1_time, dose2_time, dose2_skipped, snooze_count FROM current_session WHERE session_date = ?"

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)

            if sqlite3_step(stmt) == SQLITE_ROW {
                var dose1Time: Date? = nil
                var dose2Time: Date? = nil

                if let d1Str = sqlite3_column_text(stmt, 0) {
                    dose1Time = isoFormatter.date(from: String(cString: d1Str))
                }
                if let d2Str = sqlite3_column_text(stmt, 1) {
                    dose2Time = isoFormatter.date(from: String(cString: d2Str))
                }

                let dose2Skipped = sqlite3_column_int(stmt, 2) != 0
                let snoozeCount = Int(sqlite3_column_int(stmt, 3))

                if let d1 = dose1Time {
                    return StoredDoseLog(
                        id: sessionDate,
                        sessionDate: sessionDate,
                        dose1Time: d1,
                        dose2Time: dose2Time,
                        dose2Skipped: dose2Skipped,
                        snoozeCount: snoozeCount
                    )
                }
            }
        } else {
            sqlite3_finalize(stmt)
        }

        // --- Fallback: reconstruct from dose_events for historical sessions ---
        let doseEvents = fetchDoseEvents(sessionId: nil, sessionDate: sessionDate)
        guard !doseEvents.isEmpty else { return nil }

        var dose1Time: Date? = nil
        var dose2Time: Date? = nil
        var dose2Skipped = false
        var snoozeCount = 0

        for event in doseEvents {
            if isDose1EventType(event.eventType) {
                dose1Time = event.timestamp
            } else if isDose2EventType(event.eventType) {
                dose2Time = event.timestamp
            } else if isDose2SkippedEventType(event.eventType) {
                dose2Skipped = true
            } else if event.eventType.lowercased() == "snooze" {
                snoozeCount += 1
            }
        }

        guard let d1 = dose1Time else { return nil }

        return StoredDoseLog(
            id: sessionDate,
            sessionDate: sessionDate,
            dose1Time: d1,
            dose2Time: dose2Time,
            dose2Skipped: dose2Skipped,
            snoozeCount: snoozeCount
        )
    }
}
