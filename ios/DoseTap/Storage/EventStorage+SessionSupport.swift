import Foundation
import SQLite3
import DoseCore

@MainActor
extension EventStorage {
    // MARK: - Session Date Calculation

    /// Get current session date (tonight)
    /// A "night" starts at 6 PM and ends at 5:59 PM next day (aligns with DoseWindowCalculator)
    public func currentSessionDate() -> String {
        let identity = SessionIdentity(date: nowProvider(), timeZone: timeZoneProvider(), rolloverHour: 18)
        return identity.key
    }

    /// Discover session dates from every table that can currently anchor session-scoped data.
    func discoveredSessionDates(limit: Int? = nil) -> [String] {
        var dates: [String] = []
        var sql = """
        SELECT DISTINCT session_date FROM current_session
        UNION
        SELECT DISTINCT session_date FROM sleep_sessions
        UNION
        SELECT DISTINCT session_date FROM dose_events
        UNION
        SELECT DISTINCT session_date FROM sleep_events
        UNION
        SELECT DISTINCT session_date FROM morning_checkins
        UNION
        SELECT DISTINCT session_date FROM checkin_submissions
        UNION
        SELECT DISTINCT session_date FROM medication_events
        ORDER BY session_date DESC
        """

        if limit != nil {
            sql += "\nLIMIT ?"
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return dates }
        defer { sqlite3_finalize(stmt) }

        if let limit {
            sqlite3_bind_int(stmt, 1, Int32(limit))
        }

        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cString = sqlite3_column_text(stmt, 0) {
                dates.append(String(cString: cString))
            }
        }

        return dates
    }

    /// Get all distinct session dates from the database
    /// Returns array of session date strings in descending order (newest first)
    public func getAllSessionDates() -> [String] {
        discoveredSessionDates()
    }

    /// Fetch session_id for a given session_date (prefers current_session)
    public func fetchSessionId(forSessionDate sessionDate: String) -> String? {
        let currentSQL = "SELECT session_id FROM current_session WHERE id = 1 AND session_date = ?"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, currentSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                let sessionId = sqlite3_column_text(stmt, 0).map { String(cString: $0) }
                sqlite3_finalize(stmt)
                if let sessionId = sessionId { return sessionId }
            }
        }
        sqlite3_finalize(stmt)

        let sql = """
            SELECT session_id FROM sleep_sessions
            WHERE session_date = ?
            ORDER BY start_utc DESC
            LIMIT 1
        """
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                let sessionId = sqlite3_column_text(stmt, 0).map { String(cString: $0) }
                sqlite3_finalize(stmt)
                return sessionId
            }
        }
        sqlite3_finalize(stmt)
        return nil
    }

    /// Filter a list of session_date strings to those that still exist in storage.
    /// Used by timeline/export to drop deleted sessions that might still linger in other stores.
    public func filterExistingSessionDates(_ sessionDates: [String]) -> [String] {
        let existing = Set(getAllSessionDates())
        return sessionDates.filter { existing.contains($0) }
    }

    /// Insert a sleep event for a specific session date (used by tests/importers).
    public func insertSleepEvent(
        id: String = UUID().uuidString,
        eventType: String,
        timestamp: Date,
        sessionDate: String,
        sessionId: String? = nil,
        colorHex: String? = nil,
        notes: String? = nil
    ) {
        let sql = """
        INSERT OR REPLACE INTO sleep_events (id, event_type, timestamp, session_date, session_id, color_hex, notes)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            storageLog.error("Failed to prepare insert statement")
            return
        }
        defer { sqlite3_finalize(stmt) }

        let timestampStr = isoFormatter.string(from: timestamp)

        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, eventType, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, timestampStr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, sessionDate, -1, SQLITE_TRANSIENT)

        let resolvedSessionId = sessionId ?? sessionDate
        sqlite3_bind_text(stmt, 5, resolvedSessionId, -1, SQLITE_TRANSIENT)

        if let colorHex = colorHex {
            sqlite3_bind_text(stmt, 6, colorHex, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 6)
        }

        if let notes = notes {
            sqlite3_bind_text(stmt, 7, notes, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 7)
        }

        sqlite3_step(stmt)
    }

    /// Insert a dose event for a specific session date (used by tests/importers).
    public func insertDoseEvent(eventType: String, timestamp: Date, sessionDate: String, sessionId: String? = nil, metadata: String? = nil) {
        upsertDoseEvent(
            id: UUID().uuidString,
            eventType: eventType,
            timestamp: timestamp,
            sessionDate: sessionDate,
            sessionId: sessionId,
            metadata: metadata
        )
    }

    /// Upsert a dose event with explicit id (used by sync import).
    public func upsertDoseEvent(id: String, eventType: String, timestamp: Date, sessionDate: String, sessionId: String? = nil, metadata: String? = nil) {
        let sql = """
        INSERT OR REPLACE INTO dose_events (id, event_type, timestamp, session_date, session_id, metadata)
        VALUES (?, ?, ?, ?, ?, ?)
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }

        let timestampStr = isoFormatter.string(from: timestamp)

        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, eventType, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, timestampStr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, sessionDate, -1, SQLITE_TRANSIENT)

        let resolvedSessionId = sessionId ?? sessionDate
        sqlite3_bind_text(stmt, 5, resolvedSessionId, -1, SQLITE_TRANSIENT)

        if let metadata = metadata {
            sqlite3_bind_text(stmt, 6, metadata, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 6)
        }

        sqlite3_step(stmt)
    }

    /// Count total dose events (for export/import tests).
    public func countDoseEvents() -> Int {
        let sql = "SELECT COUNT(*) FROM dose_events"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }

    /// Get current schema version (using SQLite user_version pragma)
    /// Returns 0 if not set
    public func getSchemaVersion() -> Int {
        var version = 0
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                version = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)

        return version
    }

    func localUserIdentifier() -> String {
        if let existing = UserDefaults.standard.string(forKey: Self.localUserIdentifierDefaultsKey), !existing.isEmpty {
            return existing
        }
        let created = "local_\(UUID().uuidString.lowercased())"
        UserDefaults.standard.set(created, forKey: Self.localUserIdentifierDefaultsKey)
        return created
    }

    func resolvedSessionDate(sessionId: String?, fallbackDate: Date) -> String {
        guard let sessionId else { return sessionDateString(for: fallbackDate) }
        if isSessionDateString(sessionId) {
            return sessionId
        }
        if let mapped = findSessionDate(for: sessionId) {
            return mapped
        }
        return sessionDateString(for: fallbackDate)
    }

    func jsonDictionary(from jsonString: String?) -> [String: Any] {
        guard
            let jsonString,
            let data = jsonString.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else {
            return [:]
        }
        return dictionary
    }

    func jsonString(from dictionary: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]),
              let output = String(data: data, encoding: .utf8) else {
            return nil
        }
        return output
    }

    func preSleepPainScore(_ pain: PreSleepLogAnswers.PainLevel) -> Int {
        switch pain {
        case .none: return 0
        case .mild: return 3
        case .moderate: return 6
        case .severe: return 8
        }
    }

    func preSleepPainEntryDictionaries(_ entries: [PreSleepLogAnswers.PainEntry]) -> [[String: Any]] {
        entries.map { entry in
            var payload: [String: Any] = [
                "entry_key": entry.entryKey,
                "area": entry.area.rawValue,
                "side": entry.side.rawValue,
                "intensity": entry.intensity,
                "sensations": entry.sensations.map(\.rawValue)
            ]
            if let pattern = entry.pattern {
                payload["pattern"] = pattern.rawValue
            }
            if let notes = entry.notes, !notes.isEmpty {
                payload["notes"] = notes
            }
            return payload
        }
    }

    private func isSessionDateString(_ value: String) -> Bool {
        guard value.count == 10 else { return false }
        let chars = Array(value)
        guard chars[4] == "-", chars[7] == "-" else { return false }
        return chars.enumerated().allSatisfy { index, char in
            if index == 4 || index == 7 { return true }
            return char.isNumber
        }
    }

    private func findSessionDate(for sessionId: String) -> String? {
        let sql = """
            SELECT session_date
            FROM sleep_sessions
            WHERE session_id = ?
            UNION
            SELECT session_date
            FROM current_session
            WHERE session_id = ?
            LIMIT 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, sessionId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, sessionId, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW, let ptr = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: ptr)
    }
}
