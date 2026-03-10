import Foundation
import SQLite3
import DoseCore

@MainActor
extension EventStorage {
    // MARK: - Current Session State
    
    /// Start a new sleep session and reset current_session fields.
    public func startSession(sessionId: String, sessionDate: String, start: Date) {
        let insertSQL = """
        INSERT OR IGNORE INTO current_session (id, session_date, dose1_time, dose2_time, snooze_count, dose2_skipped, updated_at)
        VALUES (1, ?, NULL, NULL, 0, 0, CURRENT_TIMESTAMP)
        """
        
        var insertStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(insertStmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_step(insertStmt)
            sqlite3_finalize(insertStmt)
        }
        
        let startStr = isoFormatter.string(from: start)
        let updateSQL = """
        UPDATE current_session
        SET session_date = ?,
            session_id = ?,
            session_start_utc = ?,
            session_end_utc = NULL,
            terminal_state = NULL,
            dose1_time = NULL,
            dose2_time = NULL,
            snooze_count = 0,
            dose2_skipped = 0,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = 1
        """
        
        var updateStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(updateStmt) }
        
        sqlite3_bind_text(updateStmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(updateStmt, 2, sessionId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(updateStmt, 3, startStr, -1, SQLITE_TRANSIENT)
        sqlite3_step(updateStmt)
        
        upsertSleepSession(sessionId: sessionId, sessionDate: sessionDate, start: start, end: nil, terminalState: nil)
    }
    
    /// Close an active sleep session and persist terminal state.
    public func closeSession(sessionId: String, sessionDate: String, end: Date, terminalState: String) {
        let endStr = isoFormatter.string(from: end)
        let updateSQL = """
        UPDATE current_session
        SET session_end_utc = ?,
            terminal_state = ?,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = 1 AND session_id = ?
        """
        
        var updateStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(updateStmt) }
        
        sqlite3_bind_text(updateStmt, 1, endStr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(updateStmt, 2, terminalState, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(updateStmt, 3, sessionId, -1, SQLITE_TRANSIENT)
        sqlite3_step(updateStmt)
        
        upsertSleepSession(sessionId: sessionId, sessionDate: sessionDate, start: nil, end: end, terminalState: terminalState)
    }

    /// Close a historical session without touching current_session state.
    public func closeHistoricalSession(sessionId: String, sessionDate: String, end: Date, terminalState: String) {
        let endStr = isoFormatter.string(from: end)
        let updateSQL = """
        UPDATE sleep_sessions
        SET end_utc = ?, terminal_state = ?, updated_at = CURRENT_TIMESTAMP
        WHERE session_id = ?
        """
        
        var updateStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(updateStmt, 1, endStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(updateStmt, 2, terminalState, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(updateStmt, 3, sessionId, -1, SQLITE_TRANSIENT)
            sqlite3_step(updateStmt)
            sqlite3_finalize(updateStmt)
        }
        
        if sqlite3_changes(db) == 0 {
            let insertSQL = """
            INSERT OR IGNORE INTO sleep_sessions (session_id, session_date, start_utc, end_utc, terminal_state, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
            """
            
            var insertStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(insertStmt, 1, sessionId, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(insertStmt, 2, sessionDate, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(insertStmt, 3, endStr, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(insertStmt, 4, endStr, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(insertStmt, 5, terminalState, -1, SQLITE_TRANSIENT)
                sqlite3_step(insertStmt)
                sqlite3_finalize(insertStmt)
            }
        }
        
        let currentSQL = """
        UPDATE current_session
        SET session_end_utc = ?, terminal_state = ?, updated_at = CURRENT_TIMESTAMP
        WHERE session_id = ?
        """
        var currentStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, currentSQL, -1, &currentStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(currentStmt, 1, endStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(currentStmt, 2, terminalState, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(currentStmt, 3, sessionId, -1, SQLITE_TRANSIENT)
            sqlite3_step(currentStmt)
            sqlite3_finalize(currentStmt)
        }
    }
    
    private func upsertSleepSession(
        sessionId: String,
        sessionDate: String,
        start: Date?,
        end: Date?,
        terminalState: String?
    ) {
        let sql = """
        INSERT OR IGNORE INTO sleep_sessions (session_id, session_date, start_utc, end_utc, terminal_state, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        """
        
        var insertStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &insertStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(insertStmt, 1, sessionId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(insertStmt, 2, sessionDate, -1, SQLITE_TRANSIENT)
            if let start = start {
                sqlite3_bind_text(insertStmt, 3, isoFormatter.string(from: start), -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(insertStmt, 3)
            }
            if let end = end {
                sqlite3_bind_text(insertStmt, 4, isoFormatter.string(from: end), -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(insertStmt, 4)
            }
            if let terminalState = terminalState {
                sqlite3_bind_text(insertStmt, 5, terminalState, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(insertStmt, 5)
            }
            sqlite3_step(insertStmt)
            sqlite3_finalize(insertStmt)
        }
        
        let updateSQL = """
        UPDATE sleep_sessions
        SET start_utc = COALESCE(start_utc, ?),
            end_utc = ?,
            terminal_state = ?,
            updated_at = CURRENT_TIMESTAMP
        WHERE session_id = ?
        """
        
        var updateStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(updateStmt) }
        
        if let start = start {
            sqlite3_bind_text(updateStmt, 1, isoFormatter.string(from: start), -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(updateStmt, 1)
        }
        if let end = end {
            sqlite3_bind_text(updateStmt, 2, isoFormatter.string(from: end), -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(updateStmt, 2)
        }
        if let terminalState = terminalState {
            sqlite3_bind_text(updateStmt, 3, terminalState, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(updateStmt, 3)
        }
        sqlite3_bind_text(updateStmt, 4, sessionId, -1, SQLITE_TRANSIENT)
        
        sqlite3_step(updateStmt)
    }
    
    /// Update current session state in database
    /// Uses UPSERT pattern to ensure single row exists
    func updateCurrentSession(
        sessionDate: String? = nil,
        sessionId: String? = nil,
        dose1Time: Date? = nil,
        dose2Time: Date? = nil,
        snoozeCount: Int? = nil,
        dose2Skipped: Bool? = nil
    ) {
        let sessionDate = sessionDate ?? currentSessionDate()

        var existingSessionDate: String?
        let existingSQL = "SELECT session_date FROM current_session WHERE id = 1"
        var existingStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, existingSQL, -1, &existingStmt, nil) == SQLITE_OK {
            if sqlite3_step(existingStmt) == SQLITE_ROW {
                existingSessionDate = sqlite3_column_text(existingStmt, 0).map { String(cString: $0) }
            }
        }
        sqlite3_finalize(existingStmt)

        let needsReset = (existingSessionDate != nil && existingSessionDate != sessionDate)
        if needsReset {
            let resetSQL = """
            UPDATE current_session
            SET dose1_time = NULL,
                dose2_time = NULL,
                snooze_count = 0,
                dose2_skipped = 0,
                session_start_utc = NULL,
                session_end_utc = NULL,
                terminal_state = NULL,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = 1
            """
            var resetStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, resetSQL, -1, &resetStmt, nil) == SQLITE_OK {
                sqlite3_step(resetStmt)
            }
            sqlite3_finalize(resetStmt)
            storageLog.info("EventStorage: Reset stale current_session for new session_date \(sessionDate)")
        }
        
        // First, ensure a row exists for this session
        let insertSQL = """
        INSERT OR IGNORE INTO current_session (id, session_date, dose1_time, dose2_time, snooze_count, dose2_skipped, updated_at)
        VALUES (1, ?, NULL, NULL, 0, 0, CURRENT_TIMESTAMP)
        """
        
        var insertStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(insertStmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_step(insertStmt)
            sqlite3_finalize(insertStmt)
        }
        
        // Build dynamic update based on provided parameters
        var updates: [String] = ["session_date = ?", "updated_at = CURRENT_TIMESTAMP"]
        var values: [Any] = [sessionDate]
        
        if let sessionId = sessionId {
            updates.append("session_id = ?")
            values.append(sessionId)
        }
        
        if let dose1Time = dose1Time {
            updates.append("dose1_time = ?")
            values.append(isoFormatter.string(from: dose1Time))
        }
        
        if let dose2Time = dose2Time {
            updates.append("dose2_time = ?")
            values.append(isoFormatter.string(from: dose2Time))
        }
        
        if let snoozeCount = snoozeCount {
            updates.append("snooze_count = ?")
            values.append(snoozeCount)
        }
        
        if let dose2Skipped = dose2Skipped {
            updates.append("dose2_skipped = ?")
            values.append(dose2Skipped ? 1 : 0)
        }
        
        let updateSQL = "UPDATE current_session SET \(updates.joined(separator: ", ")) WHERE id = 1"
        
        var updateStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil) == SQLITE_OK else {
            storageLog.error("Failed to prepare session update")
            return
        }
        defer { sqlite3_finalize(updateStmt) }
        
        // Bind values
        for (index, value) in values.enumerated() {
            let bindIndex = Int32(index + 1)
            if let stringValue = value as? String {
                sqlite3_bind_text(updateStmt, bindIndex, stringValue, -1, SQLITE_TRANSIENT)
            } else if let intValue = value as? Int {
                sqlite3_bind_int(updateStmt, bindIndex, Int32(intValue))
            }
        }
        
        if sqlite3_step(updateStmt) == SQLITE_DONE {
            storageLog.debug("Current session updated")
        } else {
            storageLog.error("Failed to update session: \(String(cString: sqlite3_errmsg(self.db)))")
        }
    }
    
    /// Load current session state from database (includes session metadata).
    public func loadCurrentSessionState() -> CurrentSessionState {
        let sql = """
            SELECT session_id, session_date, session_start_utc, session_end_utc,
                   dose1_time, dose2_time, snooze_count, dose2_skipped, terminal_state
            FROM current_session WHERE id = 1
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return CurrentSessionState(
                sessionId: nil,
                sessionDate: nil,
                sessionStart: nil,
                sessionEnd: nil,
                dose1Time: nil,
                dose2Time: nil,
                snoozeCount: 0,
                dose2Skipped: false,
                terminalState: nil
            )
        }
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            let sessionId = sqlite3_column_text(stmt, 0).map { String(cString: $0) }
            let sessionDate = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
            let sessionStart = sqlite3_column_text(stmt, 2).flatMap { isoFormatter.date(from: String(cString: $0)) }
            let sessionEnd = sqlite3_column_text(stmt, 3).flatMap { isoFormatter.date(from: String(cString: $0)) }
            
            let dose1Time = sqlite3_column_text(stmt, 4).flatMap { isoFormatter.date(from: String(cString: $0)) }
            let dose2Time = sqlite3_column_text(stmt, 5).flatMap { isoFormatter.date(from: String(cString: $0)) }
            
            let snoozeCount = Int(sqlite3_column_int(stmt, 6))
            let dose2Skipped = sqlite3_column_int(stmt, 7) != 0
            let terminalState = sqlite3_column_text(stmt, 8).map { String(cString: $0) }
            
            return CurrentSessionState(
                sessionId: sessionId,
                sessionDate: sessionDate,
                sessionStart: sessionStart,
                sessionEnd: sessionEnd,
                dose1Time: dose1Time,
                dose2Time: dose2Time,
                snoozeCount: snoozeCount,
                dose2Skipped: dose2Skipped,
                terminalState: terminalState
            )
        }
        
        return CurrentSessionState(
            sessionId: nil,
            sessionDate: nil,
            sessionStart: nil,
            sessionEnd: nil,
            dose1Time: nil,
            dose2Time: nil,
            snoozeCount: 0,
            dose2Skipped: false,
            terminalState: nil
        )
    }

    /// Load current session state (legacy tuple signature for EventStore protocol).
    public func loadCurrentSession() -> (dose1Time: Date?, dose2Time: Date?, snoozeCount: Int, dose2Skipped: Bool) {
        let state = loadCurrentSessionState()
        return (state.dose1Time, state.dose2Time, state.snoozeCount, state.dose2Skipped)
    }
    
    /// Update the terminal state for a session
    /// Terminal states: completed, skipped, expired, aborted, incomplete_slept_through
    public func updateTerminalState(sessionDate: String, sessionId: String? = nil, state: String) {
        let whereClause = sessionId == nil ? "session_date = ?" : "session_id = ?"
        let sql = "UPDATE current_session SET terminal_state = ?, updated_at = CURRENT_TIMESTAMP WHERE \(whereClause)"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            storageLog.error("Failed to prepare terminal state update")
            return
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, state, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, sessionId ?? sessionDate, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_DONE {
            storageLog.debug("Terminal state updated to '\(state)' for session \(sessionDate)")
        } else {
            storageLog.error("Failed to update terminal state: \(String(cString: sqlite3_errmsg(self.db)))")
        }

        let sessionSQL = "UPDATE sleep_sessions SET terminal_state = ?, updated_at = CURRENT_TIMESTAMP WHERE \(whereClause)"
        var sessionStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sessionSQL, -1, &sessionStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(sessionStmt, 1, state, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(sessionStmt, 2, sessionId ?? sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_step(sessionStmt)
            sqlite3_finalize(sessionStmt)
        }
    }
}
