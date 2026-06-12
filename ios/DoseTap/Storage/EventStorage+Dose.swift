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

    // MARK: - Dose Event Operations

    /// Save dose 1 taken
    public func saveDose1(timestamp: Date, sessionId: String? = nil, sessionDateOverride: String? = nil) {
        let sessionDate = sessionDateOverride ?? sessionDateString(for: timestamp)
        let resolvedSessionId = sessionId ?? sessionDate
        insertDoseEventInternal(eventType: .dose1, timestamp: timestamp, sessionDate: sessionDate, sessionId: resolvedSessionId)
        updateCurrentSession(sessionDate: sessionDate, sessionId: resolvedSessionId, dose1Time: timestamp)
    }

    /// Save dose 2 taken
    /// - Parameters:
    ///   - timestamp: When dose 2 was taken
    ///   - isEarly: True if taken before window opened (user override)
    ///   - isExtraDose: True if this is a second attempt at dose 2 (confirmed by user)
    public func saveDose2(
        timestamp: Date,
        isEarly: Bool = false,
        isExtraDose: Bool = false,
        isLate: Bool = false,
        reason: String? = nil,
        reasonNotes: String? = nil,
        sessionId: String? = nil,
        sessionDateOverride: String? = nil
    ) {
        var metadata: [String: Any] = [:]
        if isEarly { metadata["is_early"] = true }
        if isExtraDose { metadata["is_extra_dose"] = true }
        if isLate { metadata["is_late"] = true }
        if let reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata["reason"] = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let reasonNotes, !reasonNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata["reason_notes"] = reasonNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let eventType: CanonicalDoseEventType = isExtraDose ? .extraDose : .dose2
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
    public func saveDoseSkipped(
        reason: String? = nil,
        reasonNotes: String? = nil,
        sessionId: String? = nil,
        sessionDateOverride: String? = nil
    ) {
        let metadata: String?
        var object: [String: String] = [:]
        if let reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            object["reason"] = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let reasonNotes, !reasonNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            object["reason_notes"] = reasonNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if object.isEmpty {
            metadata = nil
        } else {
            metadata = (try? JSONSerialization.data(withJSONObject: object)).flatMap { String(data: $0, encoding: .utf8) }
        }
        let now = nowProvider()
        let sessionDate = sessionDateOverride ?? sessionDateString(for: now)
        let resolvedSessionId = sessionId ?? sessionDate
        insertDoseEventInternal(eventType: .dose2Skipped, timestamp: now, sessionDate: sessionDate, sessionId: resolvedSessionId, metadata: metadata)
        updateCurrentSession(sessionDate: sessionDate, sessionId: resolvedSessionId, dose2Skipped: true)
    }

    /// Save snooze
    public func saveSnooze(count: Int, sessionId: String? = nil, sessionDateOverride: String? = nil) {
        let now = nowProvider()
        let sessionDate = sessionDateOverride ?? sessionDateString(for: now)
        let resolvedSessionId = sessionId ?? sessionDate
        insertDoseEventInternal(eventType: .snooze, timestamp: now, sessionDate: sessionDate, sessionId: resolvedSessionId, metadata: "{\"count\":\(count)}")
        updateCurrentSession(sessionDate: sessionDate, sessionId: resolvedSessionId, snoozeCount: count)
    }

    /// Remove the latest snooze event for undo or rollback, then update the current snapshot count.
    public func rollbackLatestSnooze(toCount count: Int, sessionDateOverride: String? = nil) {
        let sessionDate = sessionDateOverride ?? currentSessionDate()
        let deleteSQL = """
        DELETE FROM dose_events
        WHERE id = (
            SELECT id
            FROM dose_events
            WHERE session_date = ?
              AND event_type = ?
            ORDER BY timestamp DESC, rowid DESC
            LIMIT 1
        )
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, CanonicalDoseEventType.snooze.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)

        updateCurrentSession(sessionDate: sessionDate, sessionId: fetchSessionId(forSessionDate: sessionDate) ?? sessionDate, snoozeCount: max(0, count))
        storageLog.info("Undo: Rolled back latest snooze for session \(sessionDate)")
    }

    // MARK: - Undo Support Methods

    /// Clear dose 1 from current session (for undo)
    public func clearDose1(sessionDateOverride: String? = nil) {
        let sessionDate = sessionDateOverride ?? currentSessionDate()

        deleteDoseEvents(ofType: .dose1, sessionDate: sessionDate)

        // Clear dose1_time in current_session
        let updateSQL = "UPDATE current_session SET dose1_time = NULL WHERE session_date = ?"
        var stmt: OpaquePointer?
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

        deleteDoseEvents(ofType: .dose2, sessionDate: sessionDate)

        // Clear dose2_time in current_session
        let updateSQL = "UPDATE current_session SET dose2_time = NULL WHERE session_date = ?"
        var stmt: OpaquePointer?
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

        deleteDoseEvents(ofType: .dose2Skipped, sessionDate: sessionDate)

        // Clear dose2_skipped in current_session
        let updateSQL = "UPDATE current_session SET dose2_skipped = 0 WHERE session_date = ?"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, updateSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        storageLog.info("Undo: Cleared skip for session \(sessionDate)")
    }

    /// Clear the full dose sequence for a session while preserving non-dose sleep events.
    /// Dose 2, extra dose, skip, and snooze state are dependent on Dose 1 and cannot remain after Dose 1 undo.
    public func clearDoseSequence(sessionDateOverride: String? = nil) {
        let sessionDate = sessionDateOverride ?? currentSessionDate()

        for eventType in CanonicalDoseEventType.allCases {
            deleteDoseEvents(ofType: eventType, sessionDate: sessionDate)
        }

        let updateSQL = """
        UPDATE current_session
        SET dose1_time = NULL,
            dose2_time = NULL,
            snooze_count = 0,
            dose2_skipped = 0,
            updated_at = CURRENT_TIMESTAMP
        WHERE session_date = ?
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, updateSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        storageLog.info("Undo: Cleared dose sequence for session \(sessionDate)")
    }

    // MARK: - Time Editing Methods (Manual Entry Support)

    /// Update Dose 1 time for a session
    public func updateDose1Time(newTime: Date, sessionDate: String) {
        let timestampStr = isoFormatter.string(from: newTime)

        updateDoseEventTime(ofType: .dose1, timestampStr: timestampStr, sessionDate: sessionDate)

        // Update current_session table
        let updateSessionSQL = "UPDATE current_session SET dose1_time = ? WHERE session_date = ?"
        var stmt: OpaquePointer?
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

        updateDoseEventTime(ofType: .dose2, timestampStr: timestampStr, sessionDate: sessionDate)

        // Update current_session table
        let updateSessionSQL = "UPDATE current_session SET dose2_time = ? WHERE session_date = ?"
        var stmt: OpaquePointer?
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
