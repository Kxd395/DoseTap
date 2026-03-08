import Foundation
import SQLite3
import DoseCore
import os.log

// MARK: - Dose Event Operations, Undo, and Time Editing

extension EventStorage {

    // MARK: - Dose Event Operations

    /// Save dose 1 taken
    public func saveDose1(timestamp: Date, sessionId: String? = nil, sessionDateOverride: String? = nil) {
        let sessionDate = sessionDateOverride ?? sessionDateString(for: timestamp)
        let resolvedSessionId = sessionId ?? sessionDate
        insertDoseEventInternal(eventType: "dose1", timestamp: timestamp, sessionDate: sessionDate, sessionId: resolvedSessionId)
        updateCurrentSession(sessionDate: sessionDate, sessionId: resolvedSessionId, dose1Time: timestamp)
    }

    /// Save dose 2 taken
    /// - Parameters:
    ///   - timestamp: When dose 2 was taken
    ///   - isEarly: True if taken before window opened (user override)
    ///   - isExtraDose: True if this is a second attempt at dose 2 (confirmed by user)
    public func saveDose2(timestamp: Date, isEarly: Bool = false, isExtraDose: Bool = false, isLate: Bool = false, sessionId: String? = nil, sessionDateOverride: String? = nil) {
        var metadata: [String: Any] = [:]
        if isEarly { metadata["is_early"] = true }
        if isExtraDose { metadata["is_extra_dose"] = true }
        if isLate { metadata["is_late"] = true }

        let eventType = isExtraDose ? "extra_dose" : "dose2"
        let metadataStr = metadata.isEmpty ? nil : (try? JSONSerialization.data(withJSONObject: metadata)).flatMap { String(data: $0, encoding: .utf8) }
        let sessionDate = sessionDateOverride ?? sessionDateString(for: timestamp)
        let resolvedSessionId = sessionId ?? sessionDate
        insertDoseEventInternal(eventType: eventType, timestamp: timestamp, sessionDate: sessionDate, sessionId: resolvedSessionId, metadata: metadataStr)

        // Only update session dose2_time for first dose2 (not extra doses)
        if !isExtraDose {
            updateCurrentSession(sessionDate: sessionDate, sessionId: resolvedSessionId, dose2Time: timestamp)
        }
    }

    /// Save dose skipped with optional reason
    public func saveDoseSkipped(reason: String? = nil, sessionId: String? = nil, sessionDateOverride: String? = nil) {
        let metadata: String?
        if let reason = reason {
            metadata = "{\"reason\":\"\(reason)\"}"
        } else {
            metadata = nil
        }
        let now = nowProvider()
        let sessionDate = sessionDateOverride ?? sessionDateString(for: now)
        let resolvedSessionId = sessionId ?? sessionDate
        insertDoseEventInternal(eventType: "dose2_skipped", timestamp: now, sessionDate: sessionDate, sessionId: resolvedSessionId, metadata: metadata)
        updateCurrentSession(sessionDate: sessionDate, sessionId: resolvedSessionId, dose2Skipped: true)
    }

    /// Save snooze
    public func saveSnooze(count: Int, sessionId: String? = nil, sessionDateOverride: String? = nil) {
        let now = nowProvider()
        let sessionDate = sessionDateOverride ?? sessionDateString(for: now)
        let resolvedSessionId = sessionId ?? sessionDate
        insertDoseEventInternal(eventType: "snooze", timestamp: now, sessionDate: sessionDate, sessionId: resolvedSessionId, metadata: "{\"count\":\(count)}")
        updateCurrentSession(sessionDate: sessionDate, sessionId: resolvedSessionId, snoozeCount: count)
    }

    // MARK: - Undo Support Methods

    /// Clear dose 1 from current session (for undo)
    public func clearDose1(sessionDateOverride: String? = nil) {
        let sessionDate = sessionDateOverride ?? currentSessionDate()

        // Delete dose1 event from dose_events
        let deleteSQL = "DELETE FROM dose_events WHERE session_date = ? AND event_type = 'dose1'"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        // Clear dose1_time in current_session
        let updateSQL = "UPDATE current_session SET dose1_time = NULL WHERE session_date = ?"
        if sqlite3_prepare_v2(db, updateSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        storageLog.info("Undo: Cleared dose1 for session \(sessionDate)")
    }

    /// Clear dose 2 from current session (for undo)
    public func clearDose2(sessionDateOverride: String? = nil) {
        let sessionDate = sessionDateOverride ?? currentSessionDate()

        // Delete dose2 event from dose_events
        let deleteSQL = "DELETE FROM dose_events WHERE session_date = ? AND event_type = 'dose2'"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        // Clear dose2_time in current_session
        let updateSQL = "UPDATE current_session SET dose2_time = NULL WHERE session_date = ?"
        if sqlite3_prepare_v2(db, updateSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        storageLog.info("Undo: Cleared dose2 for session \(sessionDate)")
    }

    /// Clear skip status from current session (for undo)
    public func clearSkip(sessionDateOverride: String? = nil) {
        let sessionDate = sessionDateOverride ?? currentSessionDate()

        // Delete skip event from dose_events
        let deleteSQL = "DELETE FROM dose_events WHERE session_date = ? AND event_type = 'dose2_skipped'"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        // Clear dose2_skipped in current_session
        let updateSQL = "UPDATE current_session SET dose2_skipped = 0 WHERE session_date = ?"
        if sqlite3_prepare_v2(db, updateSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        storageLog.info("Undo: Cleared skip for session \(sessionDate)")
    }

    // MARK: - Time Editing Methods (Manual Entry Support)

    /// Update Dose 1 time for a session
    public func updateDose1Time(newTime: Date, sessionDate: String) {
        let timestampStr = isoFormatter.string(from: newTime)

        // Update dose_events table
        let updateEventSQL = "UPDATE dose_events SET timestamp = ? WHERE session_date = ? AND event_type = 'dose1'"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, updateEventSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, timestampStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        // Update current_session table
        let updateSessionSQL = "UPDATE current_session SET dose1_time = ? WHERE session_date = ?"
        if sqlite3_prepare_v2(db, updateSessionSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, timestampStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        storageLog.info("Edit: Updated dose1 time to \(timestampStr) for session \(sessionDate)")
    }

    /// Update Dose 2 time for a session
    public func updateDose2Time(newTime: Date, sessionDate: String) {
        let timestampStr = isoFormatter.string(from: newTime)

        // Update dose_events table
        let updateEventSQL = "UPDATE dose_events SET timestamp = ? WHERE session_date = ? AND event_type = 'dose2'"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, updateEventSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, timestampStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        // Update current_session table
        let updateSessionSQL = "UPDATE current_session SET dose2_time = ? WHERE session_date = ?"
        if sqlite3_prepare_v2(db, updateSessionSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, timestampStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        storageLog.info("Edit: Updated dose2 time to \(timestampStr) for session \(sessionDate)")
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

    private func insertDoseEventInternal(eventType: String, timestamp: Date, sessionDate: String? = nil, sessionId: String? = nil, metadata: String? = nil) {
        let sql = """
        INSERT INTO dose_events (id, event_type, timestamp, session_date, session_id, metadata)
        VALUES (?, ?, ?, ?, ?, ?)
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }

        let id = UUID().uuidString
        let sessionDate = sessionDate ?? sessionDateString(for: timestamp)
        let resolvedSessionId = sessionId ?? sessionDate
        let timestampStr = isoFormatter.string(from: timestamp)

        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, eventType, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, timestampStr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, sessionDate, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, resolvedSessionId, -1, SQLITE_TRANSIENT)

        if let metadata = metadata {
            sqlite3_bind_text(stmt, 6, metadata, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 6)
        }

        if sqlite3_step(stmt) == SQLITE_DONE {
            storageLog.debug("Dose event saved: \(eventType, privacy: .public)")
        }
    }

    /// Insert a dose event (Dose 1 or Dose 2)
    /// Returns true if successful, false if duplicate (unless force=true)
    public func saveDoseEvent(type: String, timestamp: Date, isHazard: Bool = false) -> Bool {
        let sessionDate = currentSessionDate()
        let resolvedSessionId = fetchSessionId(forSessionDate: sessionDate) ?? sessionDate

        // Check for existing dose of this type in this session
        if !isHazard && hasDose(type: type, sessionDate: sessionDate) {
            storageLog.warning("Dose \(type, privacy: .public) already exists for \(sessionDate). Use isHazard=true to force log.")
            return false
        }

        let id = UUID().uuidString
        let metadata = isHazard ? #"{"is_hazard":true}"# : nil
        let sql = """
        INSERT INTO dose_events (id, event_type, timestamp, session_date, session_id, metadata)
        VALUES (?, ?, ?, ?, ?, ?)
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            storageLog.error("Failed to prepare dose insert statement")
            return false
        }
        defer { sqlite3_finalize(stmt) }

        let timestampStr = isoFormatter.string(from: timestamp)

        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, type, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, timestampStr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, sessionDate, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, resolvedSessionId, -1, SQLITE_TRANSIENT)
        if let metadata {
            sqlite3_bind_text(stmt, 6, metadata, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 6)
        }

        if sqlite3_step(stmt) == SQLITE_DONE {
            storageLog.debug("Dose event saved: \(type, privacy: .public) at \(timestampStr, privacy: .public) hazard=\(isHazard)")
            return true
        } else {
            storageLog.error("Failed to insert dose event: \(String(cString: sqlite3_errmsg(self.db)))")
            return false
        }
    }

    /// Check if a dose type already exists for a session
    public func hasDose(type: String, sessionDate: String) -> Bool {
        let sql = "SELECT count(*) FROM dose_events WHERE session_date = ? AND event_type = ?"
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, type, -1, SQLITE_TRANSIENT)

        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_int(stmt, 0) > 0
        }
        return false
    }
}
