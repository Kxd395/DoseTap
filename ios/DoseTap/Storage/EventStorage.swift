import Foundation
import Combine
import SQLite3
import DoseCore
import CryptoKit
import os.log

let storageLog = Logger(subsystem: "com.dosetap.app", category: "EventStorage")

// MARK: - SQLite Helpers
// SQLITE_TRANSIENT is a C macro that doesn't exist in Swift
// We use unsafeBitCast to create the equivalent behavior
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - Event Storage (SQLite)
/// Persists sleep events and dose logs to local SQLite database
@MainActor
public class EventStorage {
    public static let shared = EventStorage()
    public enum CheckInType: String, CaseIterable {
        case preNight = "pre_night"
        case morning = "morning"
    }

    private enum CheckInQuestionnaireVersion {
        static let preNight = "pre_night.v2.2026-02-13"
        static let morning = "morning.v2.2026-02-13"
    }
    static let localUserIdentifierDefaultsKey = "dosetap.local.user_identifier"
    
    var db: OpaquePointer?
    let dbPath: String
    var nowProvider: () -> Date = { Date() }
    var timeZoneProvider: () -> TimeZone = { TimeZone.current }
    
    // ISO8601 formatter for date serialization
    let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public struct CurrentSessionState {
        public let sessionId: String?
        public let sessionDate: String?
        public let sessionStart: Date?
        public let sessionEnd: Date?
        public let dose1Time: Date?
        public let dose2Time: Date?
        public let snoozeCount: Int
        public let dose2Skipped: Bool
        public let terminalState: String?
    }
    
    public static let constantsVersion = "1.0.0"

    public init(dbPath: String) {
        self.dbPath = dbPath
        openDatabase()
        createTables()
        storageLog.info("EventStorage initialized at: \(self.dbPath)")
    }

    private convenience init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.init(dbPath: documentsPath.appendingPathComponent("dosetap_events.sqlite").path)
    }

    #if DEBUG
    public static func inMemory() -> EventStorage {
        EventStorage(dbPath: ":memory:")
    }
    #endif
    
    deinit {
        sqlite3_close(db)
    }
    
    // MARK: - Sleep Event Operations
    
    /// Insert a sleep event
    public func insertSleepEvent(
        id: String,
        eventType: String,
        timestamp: Date,
        colorHex: String?,
        notes: String? = nil,
        sessionId: String? = nil,
        sessionDate: String? = nil
    ) {
        let resolvedSessionDate = sessionDate ?? currentSessionDate()
        insertSleepEvent(
            id: id,
            eventType: eventType,
            timestamp: timestamp,
            sessionDate: resolvedSessionDate,
            sessionId: sessionId,
            colorHex: colorHex,
            notes: notes
        )
        #if DEBUG
        let timestampStr = isoFormatter.string(from: timestamp)
        storageLog.debug("Sleep event saved: \(eventType, privacy: .public) at \(timestampStr, privacy: .public)")
        #endif
    }
    
    /// Fetch sleep events for current session (tonight)
    public func fetchTonightsSleepEvents() -> [StoredSleepEvent] {
        let sessionDate = currentSessionDate()
        return fetchSleepEvents(forSession: sessionDate)
    }
    
    /// Fetch sleep events for a specific session date
    public func fetchSleepEvents(forSession sessionDate: String) -> [StoredSleepEvent] {
        let sql = """
        SELECT id, event_type, timestamp, session_date, color_hex, notes
        FROM sleep_events
        WHERE session_date = ?
        ORDER BY timestamp DESC
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
        
        var events: [StoredSleepEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let eventType = String(cString: sqlite3_column_text(stmt, 1))
            let timestampStr = String(cString: sqlite3_column_text(stmt, 2))
            let timestamp = isoFormatter.date(from: timestampStr) ?? Date()
            
            var colorHex: String? = nil
            if let colorText = sqlite3_column_text(stmt, 4) {
                colorHex = String(cString: colorText)
            }
            
            var notes: String? = nil
            if let notesText = sqlite3_column_text(stmt, 5) {
                notes = String(cString: notesText)
            }
            
            events.append(StoredSleepEvent(
                id: id,
                eventType: eventType,
                timestamp: timestamp,
                sessionDate: sessionDate,
                colorHex: colorHex,
                notes: notes
            ))
        }
        
        return events
    }

    /// Fetch sleep events for a specific session id (preferred for active sessions)
    public func fetchSleepEvents(forSessionId sessionId: String) -> [StoredSleepEvent] {
        let sql = """
        SELECT id, event_type, timestamp, session_date, color_hex, notes
        FROM sleep_events
        WHERE session_id = ?
        ORDER BY timestamp DESC
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, sessionId, -1, SQLITE_TRANSIENT)
        
        var events: [StoredSleepEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let eventType = String(cString: sqlite3_column_text(stmt, 1))
            let timestampStr = String(cString: sqlite3_column_text(stmt, 2))
            let timestamp = isoFormatter.date(from: timestampStr) ?? Date()
            let sessionDate = String(cString: sqlite3_column_text(stmt, 3))
            
            var colorHex: String? = nil
            if let colorText = sqlite3_column_text(stmt, 4) {
                colorHex = String(cString: colorText)
            }
            
            var notes: String? = nil
            if let notesText = sqlite3_column_text(stmt, 5) {
                notes = String(cString: notesText)
            }
            
            events.append(StoredSleepEvent(
                id: id,
                eventType: eventType,
                timestamp: timestamp,
                sessionDate: sessionDate,
                colorHex: colorHex,
                notes: notes
            ))
        }
        
        return events
    }
    
    /// Get count of events for tonight
    public func tonightsEventCount() -> Int {
        let sessionDate = currentSessionDate()
        let sql = "SELECT COUNT(*) FROM sleep_events WHERE session_date = ?"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }
    
    /// Get all events grouped by session for history view
    public func fetchAllSessions(limit: Int = 30) -> [String: [StoredSleepEvent]] {
        let sql = """
        SELECT id, event_type, timestamp, session_date, color_hex, notes
        FROM sleep_events
        ORDER BY timestamp DESC
        LIMIT ?
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return [:]
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int(stmt, 1, Int32(limit * 20)) // Assume ~20 events per session
        
        var sessionEvents: [String: [StoredSleepEvent]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let eventType = String(cString: sqlite3_column_text(stmt, 1))
            let timestampStr = String(cString: sqlite3_column_text(stmt, 2))
            let sessionDate = String(cString: sqlite3_column_text(stmt, 3))
            let timestamp = isoFormatter.date(from: timestampStr) ?? Date()
            
            var colorHex: String? = nil
            if let colorText = sqlite3_column_text(stmt, 4) {
                colorHex = String(cString: colorText)
            }
            
            let event = StoredSleepEvent(
                id: id,
                eventType: eventType,
                timestamp: timestamp,
                sessionDate: sessionDate,
                colorHex: colorHex,
                notes: nil
            )
            
            if sessionEvents[sessionDate] == nil {
                sessionEvents[sessionDate] = []
            }
            sessionEvents[sessionDate]?.append(event)
        }
        
        return sessionEvents
    }
    
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
    
    private func mergedPreSleepPainEntries(_ answers: PreSleepLogAnswers) -> [PreSleepLogAnswers.PainEntry] {
        if let entries = answers.painEntries, !entries.isEmpty {
            var keyed: [String: PreSleepLogAnswers.PainEntry] = [:]
            for entry in entries {
                keyed[entry.entryKey] = entry
            }
            return keyed.values.sorted { $0.entryKey < $1.entryKey }
        }

        guard
            let locations = answers.painLocations,
            !locations.isEmpty,
            let bodyPain = answers.bodyPain,
            bodyPain != .none
        else {
            return []
        }

        let intensity = preSleepPainScore(bodyPain)
        let sensation = answers.painType.map { [PreSleepLogAnswers.PainSensation(rawValue: $0.rawValue) ?? .aching] } ?? [.aching]

        return locations.map { location in
            PreSleepLogAnswers.PainEntry(
                area: PreSleepLogAnswers.PainArea(legacyLocation: location),
                side: .na,
                intensity: intensity,
                sensations: sensation,
                pattern: nil,
                notes: nil
            )
        }
    }

    private func normalizedPreSleepAnswers(_ answers: PreSleepLogAnswers) -> PreSleepLogAnswers {
        var normalized = answers

        if let entries = normalized.painEntries {
            var keyed: [String: PreSleepLogAnswers.PainEntry] = [:]
            for entry in entries {
                let safeSensations = entry.sensations.isEmpty ? [PreSleepLogAnswers.PainSensation.aching] : entry.sensations
                let safeNotes = entry.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
                keyed[entry.entryKey] = PreSleepLogAnswers.PainEntry(
                    area: entry.area,
                    side: entry.side,
                    intensity: entry.intensity,
                    sensations: safeSensations,
                    pattern: entry.pattern,
                    notes: safeNotes?.isEmpty == true ? nil : safeNotes
                )
            }
            normalized.painEntries = keyed.values.sorted { $0.entryKey < $1.entryKey }
        }

        let hasCaffeine = (normalized.stimulants ?? .none) != .none
        if hasCaffeine {
            if let value = normalized.caffeineLastAmountMg {
                normalized.caffeineLastAmountMg = max(0, value)
            }
            if let value = normalized.caffeineDailyTotalMg {
                normalized.caffeineDailyTotalMg = max(0, value)
            }
            if let last = normalized.caffeineLastAmountMg,
               let total = normalized.caffeineDailyTotalMg,
               total < last {
                normalized.caffeineDailyTotalMg = last
            }
        } else {
            normalized.caffeineLastIntakeAt = nil
            normalized.caffeineLastAmountMg = nil
            normalized.caffeineDailyTotalMg = nil
        }

        let hasAlcohol = (normalized.alcohol ?? .none) != .none
        if hasAlcohol {
            if let value = normalized.alcoholLastAmountDrinks {
                normalized.alcoholLastAmountDrinks = max(0, value)
            }
            if let value = normalized.alcoholDailyTotalDrinks {
                normalized.alcoholDailyTotalDrinks = max(0, value)
            }
            if let last = normalized.alcoholLastAmountDrinks,
               let total = normalized.alcoholDailyTotalDrinks,
               total < last {
                normalized.alcoholDailyTotalDrinks = last
            }
        } else {
            normalized.alcoholLastDrinkAt = nil
            normalized.alcoholLastAmountDrinks = nil
            normalized.alcoholDailyTotalDrinks = nil
        }

        let hasExercise = (normalized.exercise ?? .none) != .none
        if hasExercise {
            if let duration = normalized.exerciseDurationMinutes {
                normalized.exerciseDurationMinutes = max(5, min(600, duration))
            }
        } else {
            normalized.exerciseType = nil
            normalized.exerciseLastAt = nil
            normalized.exerciseDurationMinutes = nil
        }

        let hasNap = (normalized.napToday ?? .none) != .none
        if hasNap {
            if let count = normalized.napCount {
                normalized.napCount = max(1, min(6, count))
            }
            if let total = normalized.napTotalMinutes {
                normalized.napTotalMinutes = max(5, min(360, total))
            }
        } else {
            normalized.napCount = nil
            normalized.napTotalMinutes = nil
            normalized.napLastEndAt = nil
        }

        return normalized
    }

    private func preSleepResponsesByQuestionID(_ answers: PreSleepLogAnswers) -> [String: Any] {
        let normalized = normalizedPreSleepAnswers(answers)
        var responses: [String: Any] = [:]
        if let value = normalized.intendedSleepTime?.rawValue { responses["pre.sleep.intended_time"] = value }
        if let value = normalized.stressLevel { responses["overall.stress"] = value }
        if let value = normalized.stressDriver?.rawValue { responses["pre.stress.driver"] = value }
        if let value = normalized.laterReason?.rawValue { responses["pre.sleep.later_reason"] = value }
        if let value = normalized.bodyPain?.rawValue {
            responses["pain.level"] = value
            responses["pain.any"] = value != PreSleepLogAnswers.PainLevel.none.rawValue
        }
        let painEntries = mergedPreSleepPainEntries(normalized)
        if !painEntries.isEmpty {
            responses["pain.any"] = true
            responses["pain.entries"] = preSleepPainEntryDictionaries(painEntries)
            responses["pain.locations"] = Array(Set(painEntries.map { $0.area.rawValue })).sorted()
            responses["pain.sensations"] = Array(Set(painEntries.flatMap { $0.sensations.map(\.rawValue) })).sorted()
            responses["pain.overall_intensity"] = painEntries.map(\.intensity).max() ?? 0
        } else if let pain = normalized.bodyPain {
            responses["pain.overall_intensity"] = preSleepPainScore(pain)
        }
        if let value = normalized.painLocations?.map(\.rawValue), !value.isEmpty, responses["pain.locations"] == nil { responses["pain.locations"] = value }
        if let value = normalized.painType?.rawValue { responses["pain.type"] = value }
        if let value = normalized.stimulants?.rawValue { responses["pre.substances.stimulants_after_2pm"] = value }
        if let value = normalized.stimulants?.rawValue { responses["pre.substances.caffeine.source"] = value }
        if let value = normalized.caffeineLastIntakeAt { responses["pre.substances.caffeine.last_time_utc"] = isoFormatter.string(from: value) }
        if let value = normalized.caffeineLastAmountMg { responses["pre.substances.caffeine.last_amount_mg"] = value }
        if let value = normalized.caffeineDailyTotalMg { responses["pre.substances.caffeine.daily_total_mg"] = value }
        if normalized.stimulants != nil || normalized.caffeineLastIntakeAt != nil || normalized.caffeineLastAmountMg != nil || normalized.caffeineDailyTotalMg != nil {
            responses["pre.substances.caffeine.any"] = (normalized.stimulants ?? .none) != .none
        }
        if let value = normalized.alcohol?.rawValue { responses["pre.substances.alcohol"] = value }
        if let value = normalized.alcoholLastDrinkAt { responses["pre.substances.alcohol.last_time_utc"] = isoFormatter.string(from: value) }
        if let value = normalized.alcoholLastAmountDrinks { responses["pre.substances.alcohol.last_amount_drinks"] = value }
        if let value = normalized.alcoholDailyTotalDrinks { responses["pre.substances.alcohol.daily_total_drinks"] = value }
        if normalized.alcohol != nil || normalized.alcoholLastDrinkAt != nil || normalized.alcoholLastAmountDrinks != nil || normalized.alcoholDailyTotalDrinks != nil {
            responses["pre.substances.alcohol.any"] = (normalized.alcohol ?? .none) != .none
        }
        if let value = normalized.exercise?.rawValue { responses["pre.day.exercise_level"] = value }
        if normalized.exercise != nil || normalized.exerciseType != nil || normalized.exerciseLastAt != nil || normalized.exerciseDurationMinutes != nil {
            responses["pre.day.exercise.any"] = (normalized.exercise ?? .none) != .none
        }
        if let value = normalized.exerciseType?.rawValue { responses["pre.day.exercise.type"] = value }
        if let value = normalized.exerciseLastAt { responses["pre.day.exercise.last_time_utc"] = isoFormatter.string(from: value) }
        if let value = normalized.exerciseDurationMinutes { responses["pre.day.exercise.duration_minutes"] = value }
        if let value = normalized.napToday?.rawValue { responses["pre.day.nap_duration"] = value }
        if normalized.napToday != nil || normalized.napCount != nil || normalized.napTotalMinutes != nil || normalized.napLastEndAt != nil {
            responses["pre.day.nap.any"] = (normalized.napToday ?? .none) != .none
        }
        if let value = normalized.napCount { responses["pre.day.nap.count"] = value }
        if let value = normalized.napTotalMinutes { responses["pre.day.nap.total_minutes"] = value }
        if let value = normalized.napLastEndAt { responses["pre.day.nap.last_end_time_utc"] = isoFormatter.string(from: value) }
        if let value = normalized.lateMeal?.rawValue { responses["pre.day.late_meal"] = value }
        if let value = normalized.screensInBed?.rawValue { responses["pre.sleep.screens_in_bed"] = value }
        if let value = normalized.roomTemp?.rawValue { responses["pre.environment.room_temp"] = value }
        if let value = normalized.noiseLevel?.rawValue { responses["pre.environment.noise_level"] = value }
        if let value = normalized.sleepAids?.rawValue { responses["pre.sleep.aids"] = value }
        if let value = normalized.notes, !value.isEmpty { responses["notes.anything_else"] = value }
        return responses
    }

    private func morningResponsesByQuestionID(_ checkIn: StoredMorningCheckIn) -> [String: Any] {
        var responses: [String: Any] = [
            "sleep.quality": checkIn.sleepQuality,
            "sleep.rested": checkIn.feelRested,
            "sleep.grogginess": checkIn.grogginess,
            "sleep.inertia_duration": checkIn.sleepInertiaDuration,
            "sleep.dream_recall": checkIn.dreamRecall,
            "overall.mood": checkIn.mood,
            "overall.stress": checkIn.anxietyLevel,
            "overall.energy": checkIn.readinessForDay,
            "mental.clarity": checkIn.mentalClarity,
            "pain.any": checkIn.hasPhysicalSymptoms,
            "respiratory.any": checkIn.hasRespiratorySymptoms,
            "narcolepsy.sleep_paralysis": checkIn.hadSleepParalysis,
            "narcolepsy.hallucinations": checkIn.hadHallucinations,
            "narcolepsy.automatic_behavior": checkIn.hadAutomaticBehavior,
            "narcolepsy.fell_out_of_bed": checkIn.fellOutOfBed,
            "narcolepsy.confusion_on_waking": checkIn.hadConfusionOnWaking,
            "sleep_therapy.used": checkIn.usedSleepTherapy
        ]

        let physical = jsonDictionary(from: checkIn.physicalSymptomsJson)
        if let entries = physical["painEntries"] as? [[String: Any]], !entries.isEmpty {
            responses["pain.entries"] = entries

            let locations = entries.compactMap { $0["area"] as? String }
            if !locations.isEmpty {
                responses["pain.locations"] = Array(Set(locations)).sorted()
            }

            let intensities = entries.compactMap { item -> Int? in
                if let value = item["intensity"] as? Int { return value }
                if let value = item["intensity"] as? Double { return Int(value) }
                return nil
            }
            if let maxIntensity = intensities.max() {
                responses["pain.overall_intensity"] = maxIntensity
            }

            let sensations = entries.flatMap { item -> [String] in
                guard let values = item["sensations"] as? [String] else { return [] }
                return values
            }
            if !sensations.isEmpty {
                responses["pain.sensations"] = Array(Set(sensations)).sorted()
            }
        }
        if let value = physical["painLocations"] as? [String], !value.isEmpty, responses["pain.locations"] == nil { responses["pain.locations"] = value }
        if let value = physical["painSeverity"] as? Int, responses["pain.overall_intensity"] == nil { responses["pain.overall_intensity"] = value }
        if let value = physical["painType"] as? String { responses["pain.type"] = value }
        if let value = physical["muscleStiffness"] as? String { responses["stiffness.level"] = value }
        if let value = physical["muscleSoreness"] as? String { responses["soreness.level"] = value }
        if let value = physical["hasHeadache"] as? Bool { responses["headache.any"] = value }
        if let value = physical["headacheSeverity"] as? String { responses["headache.severity"] = value }
        if let value = physical["headacheLocation"] as? String { responses["headache.location"] = value }
        if let value = physical["notes"] as? String, !value.isEmpty { responses["pain.notes"] = value }

        let respiratory = jsonDictionary(from: checkIn.respiratorySymptomsJson)
        if let value = respiratory["congestion"] as? String { responses["respiratory.congestion"] = value }
        if let value = respiratory["throatCondition"] as? String { responses["respiratory.throat"] = value }
        if let value = respiratory["coughType"] as? String { responses["respiratory.cough"] = value }
        if let value = respiratory["sinusPressure"] as? String { responses["respiratory.sinus_pressure"] = value }
        if let value = respiratory["feelingFeverish"] as? Bool { responses["respiratory.feverish"] = value }
        if let value = respiratory["sicknessLevel"] as? String { responses["respiratory.sickness_level"] = value }
        if let value = respiratory["notes"] as? String, !value.isEmpty { responses["respiratory.notes"] = value }

        let therapy = jsonDictionary(from: checkIn.sleepTherapyJson)
        if let value = therapy["device"] as? String { responses["sleep_therapy.device"] = value }
        if let value = therapy["compliance"] as? Int { responses["sleep_therapy.compliance"] = value }
        if let value = therapy["notes"] as? String, !value.isEmpty { responses["sleep_therapy.notes"] = value }

        if let value = checkIn.notes, !value.isEmpty { responses["notes.anything_else"] = value }
        return responses
    }

    private func upsertCheckInSubmission(
        sourceRecordId: String,
        sessionId: String?,
        sessionDate: String,
        checkInType: CheckInType,
        questionnaireVersion: String,
        submittedAt: Date,
        responsesByQuestionID: [String: Any]
    ) {
        guard let responsesJson = jsonString(from: responsesByQuestionID) else {
            storageLog.warning("Failed to encode check-in responses for \(sourceRecordId)")
            return
        }

        let id = "\(checkInType.rawValue):\(sourceRecordId)"
        let sql = """
            INSERT OR REPLACE INTO checkin_submissions (
                id, source_record_id, session_id, session_date, checkin_type, questionnaire_version,
                user_id, submitted_at_utc, local_offset_minutes, responses_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            storageLog.error("Failed to prepare check-in submission upsert: \(String(cString: sqlite3_errmsg(self.db)))")
            return
        }
        defer { sqlite3_finalize(stmt) }

        let submittedAtUTC = isoFormatter.string(from: submittedAt)
        let offsetMinutes = timeZoneProvider().secondsFromGMT(for: submittedAt) / 60

        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, sourceRecordId, -1, SQLITE_TRANSIENT)
        if let sessionId {
            sqlite3_bind_text(stmt, 3, sessionId, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        sqlite3_bind_text(stmt, 4, sessionDate, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, checkInType.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 6, questionnaireVersion, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 7, localUserIdentifier(), -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 8, submittedAtUTC, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 9, Int32(offsetMinutes))
        sqlite3_bind_text(stmt, 10, responsesJson, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            storageLog.error("Failed to upsert check-in submission: \(String(cString: sqlite3_errmsg(self.db)))")
            return
        }
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
    
    /// Fetch the most recent pre-sleep log for loading defaults
    public func fetchMostRecentPreSleepLog() -> StoredPreSleepLog? {
        let sql = "SELECT id, session_id, created_at_utc, local_offset_minutes, completion_state, answers_json FROM pre_sleep_logs ORDER BY created_at DESC LIMIT 1"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let sessionId = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
            let createdAtUtc = String(cString: sqlite3_column_text(stmt, 2))
            let localOffsetMinutes = Int(sqlite3_column_int(stmt, 3))
            let completionState = String(cString: sqlite3_column_text(stmt, 4))
            let answersJson = String(cString: sqlite3_column_text(stmt, 5))
            
            // Parse answers JSON
            var answers: PreSleepLogAnswers? = nil
            if let data = answersJson.data(using: .utf8) {
                answers = try? JSONDecoder().decode(PreSleepLogAnswers.self, from: data)
            }
            
            return StoredPreSleepLog(
                id: id,
                sessionId: sessionId,
                createdAtUtc: createdAtUtc,
                localOffsetMinutes: localOffsetMinutes,
                completionState: completionState,
                answers: answers
            )
        }
        
        return nil
    }

    /// Fetch the most recent pre-sleep log for a specific session
    public func fetchMostRecentPreSleepLog(sessionId: String) -> StoredPreSleepLog? {
        let sql = """
            SELECT id, session_id, created_at_utc, local_offset_minutes, completion_state, answers_json
            FROM pre_sleep_logs
            WHERE session_id = ?
            ORDER BY created_at DESC
            LIMIT 1
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, sessionId, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let sessionId = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
            let createdAtUtc = String(cString: sqlite3_column_text(stmt, 2))
            let localOffsetMinutes = Int(sqlite3_column_int(stmt, 3))
            let completionState = String(cString: sqlite3_column_text(stmt, 4))
            let answersJson = String(cString: sqlite3_column_text(stmt, 5))
            
            var answers: PreSleepLogAnswers? = nil
            if let data = answersJson.data(using: .utf8) {
                answers = try? JSONDecoder().decode(PreSleepLogAnswers.self, from: data)
            }
            
            return StoredPreSleepLog(
                id: id,
                sessionId: sessionId,
                createdAtUtc: createdAtUtc,
                localOffsetMinutes: localOffsetMinutes,
                completionState: completionState,
                answers: answers
            )
        }
        
        return nil
    }

    /// Count pre-sleep logs for a session (used in tests/debug)
    public func fetchPreSleepLogCount(sessionId: String) -> Int {
        let sql = "SELECT COUNT(*) FROM pre_sleep_logs WHERE session_id = ?"
        var stmt: OpaquePointer?
        var count = 0
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sessionId, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        
        return count
    }
    
    public enum PreSleepLogStoreError: Error, LocalizedError {
        case encodeFailed
        case prepareFailed(String)
        case bindFailed(String)
        case stepFailed(String)
        
        public var errorDescription: String? {
            switch self {
            case .encodeFailed: return "Failed to encode pre-sleep answers"
            case .prepareFailed(let message): return "Failed to prepare pre-sleep save: \(message)"
            case .bindFailed(let message): return "Failed to bind pre-sleep save: \(message)"
            case .stepFailed(let message): return "Failed to save pre-sleep log: \(message)"
            }
        }
    }

    private func updatePreSleepLog(
        id: String,
        sessionId: String?,
        completionState: String,
        answersJson: String
    ) throws -> Bool {
        let sql = """
            UPDATE pre_sleep_logs
            SET session_id = ?, completion_state = ?, answers_json = ?
            WHERE id = ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw PreSleepLogStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        if let sessionId = sessionId {
            guard sqlite3_bind_text(stmt, 1, sessionId, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
                throw PreSleepLogStoreError.bindFailed(String(cString: sqlite3_errmsg(db)))
            }
        } else {
            guard sqlite3_bind_null(stmt, 1) == SQLITE_OK else {
                throw PreSleepLogStoreError.bindFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
        guard sqlite3_bind_text(stmt, 2, completionState, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw PreSleepLogStoreError.bindFailed(String(cString: sqlite3_errmsg(db)))
        }
        guard sqlite3_bind_text(stmt, 3, answersJson, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw PreSleepLogStoreError.bindFailed(String(cString: sqlite3_errmsg(db)))
        }
        guard sqlite3_bind_text(stmt, 4, id, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw PreSleepLogStoreError.bindFailed(String(cString: sqlite3_errmsg(db)))
        }

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw PreSleepLogStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }

        return sqlite3_changes(db) > 0
    }
    
    /// Save a pre-sleep log (throws on failure)
    @discardableResult
    public func savePreSleepLogOrThrow(
        sessionId: String?,
        answers: PreSleepLogAnswers,
        completionState: String = "complete",
        now: Date = Date(),
        timeZone: TimeZone = .current,
        existingLog: StoredPreSleepLog? = nil
    ) throws -> StoredPreSleepLog {
        let normalizedAnswers = normalizedPreSleepAnswers(answers)

        guard let data = try? JSONEncoder().encode(normalizedAnswers),
              let answersJson = String(data: data, encoding: .utf8) else {
            throw PreSleepLogStoreError.encodeFailed
        }

        var logToUpdate = existingLog
        if logToUpdate == nil, let sessionId = sessionId {
            logToUpdate = fetchMostRecentPreSleepLog(sessionId: sessionId)
        }

        if let existing = logToUpdate {
            let updatedSessionId = sessionId ?? existing.sessionId
            if try updatePreSleepLog(
                id: existing.id,
                sessionId: updatedSessionId,
                completionState: completionState,
                answersJson: answersJson
            ) {
                upsertCheckInSubmission(
                    sourceRecordId: existing.id,
                    sessionId: updatedSessionId,
                    sessionDate: resolvedSessionDate(sessionId: updatedSessionId, fallbackDate: now),
                    checkInType: .preNight,
                    questionnaireVersion: CheckInQuestionnaireVersion.preNight,
                    submittedAt: now,
                    responsesByQuestionID: preSleepResponsesByQuestionID(normalizedAnswers)
                )
                return StoredPreSleepLog(
                    id: existing.id,
                    sessionId: updatedSessionId,
                    createdAtUtc: existing.createdAtUtc,
                    localOffsetMinutes: existing.localOffsetMinutes,
                    completionState: completionState,
                    answers: normalizedAnswers
                )
            }
        }

        let id = UUID().uuidString
        let createdAtUtc = isoFormatter.string(from: now)
        let localOffsetMinutes = timeZone.secondsFromGMT(for: now) / 60
        
        let sql = """
            INSERT INTO pre_sleep_logs (id, session_id, created_at_utc, local_offset_minutes, completion_state, answers_json)
            VALUES (?, ?, ?, ?, ?, ?)
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw PreSleepLogStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw PreSleepLogStoreError.bindFailed(String(cString: sqlite3_errmsg(db)))
        }
        if let sessionId = sessionId {
            guard sqlite3_bind_text(stmt, 2, sessionId, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
                throw PreSleepLogStoreError.bindFailed(String(cString: sqlite3_errmsg(db)))
            }
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        guard sqlite3_bind_text(stmt, 3, createdAtUtc, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw PreSleepLogStoreError.bindFailed(String(cString: sqlite3_errmsg(db)))
        }
        guard sqlite3_bind_int(stmt, 4, Int32(localOffsetMinutes)) == SQLITE_OK else {
            throw PreSleepLogStoreError.bindFailed(String(cString: sqlite3_errmsg(db)))
        }
        guard sqlite3_bind_text(stmt, 5, completionState, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw PreSleepLogStoreError.bindFailed(String(cString: sqlite3_errmsg(db)))
        }
        guard sqlite3_bind_text(stmt, 6, answersJson, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw PreSleepLogStoreError.bindFailed(String(cString: sqlite3_errmsg(db)))
        }
        
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw PreSleepLogStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }

        upsertCheckInSubmission(
            sourceRecordId: id,
            sessionId: sessionId,
            sessionDate: resolvedSessionDate(sessionId: sessionId, fallbackDate: now),
            checkInType: .preNight,
            questionnaireVersion: CheckInQuestionnaireVersion.preNight,
            submittedAt: now,
            responsesByQuestionID: preSleepResponsesByQuestionID(normalizedAnswers)
        )
        
        return StoredPreSleepLog(
            id: id,
            sessionId: sessionId,
            createdAtUtc: createdAtUtc,
            localOffsetMinutes: localOffsetMinutes,
            completionState: completionState,
            answers: normalizedAnswers
        )
    }
    
    /// Save a pre-sleep log (non-throwing convenience)
    public func savePreSleepLog(sessionId: String?, answers: PreSleepLogAnswers, completionState: String = "complete") {
        do {
            _ = try savePreSleepLogOrThrow(
                sessionId: sessionId,
                answers: answers,
                completionState: completionState,
                now: Date(),
                timeZone: .current
            )
            storageLog.debug("Pre-sleep log saved")
        } catch {
            storageLog.error("Failed to save pre-sleep log: \(error.localizedDescription)")
        }
    }
    
    /// Save a morning check-in to the database
    public func saveMorningCheckIn(_ checkIn: StoredMorningCheckIn, forSession sessionDate: String? = nil) {
        let effectiveSessionDate = sessionDate ?? currentSessionDate()
        
        let sql = """
            INSERT OR REPLACE INTO morning_checkins (
                id, session_id, timestamp, session_date,
                sleep_quality, feel_rested, grogginess, sleep_inertia_duration, dream_recall,
                has_physical_symptoms, physical_symptoms_json,
                has_respiratory_symptoms, respiratory_symptoms_json,
                mental_clarity, mood, anxiety_level, readiness_for_day,
                had_sleep_paralysis, had_hallucinations, had_automatic_behavior,
                fell_out_of_bed, had_confusion_on_waking,
                used_sleep_therapy, sleep_therapy_json,
                has_sleep_environment, sleep_environment_json,
                notes
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            storageLog.error("Failed to prepare morning check-in insert: \(String(cString: sqlite3_errmsg(self.db)))")
            return
        }
        defer { sqlite3_finalize(stmt) }
        
        let timestampStr = isoFormatter.string(from: checkIn.timestamp)
        
        sqlite3_bind_text(stmt, 1, checkIn.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, checkIn.sessionId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, timestampStr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, effectiveSessionDate, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 5, Int32(checkIn.sleepQuality))
        sqlite3_bind_text(stmt, 6, checkIn.feelRested, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 7, checkIn.grogginess, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 8, checkIn.sleepInertiaDuration, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 9, checkIn.dreamRecall, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 10, checkIn.hasPhysicalSymptoms ? 1 : 0)
        if let json = checkIn.physicalSymptomsJson {
            sqlite3_bind_text(stmt, 11, json, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 11)
        }
        sqlite3_bind_int(stmt, 12, checkIn.hasRespiratorySymptoms ? 1 : 0)
        if let json = checkIn.respiratorySymptomsJson {
            sqlite3_bind_text(stmt, 13, json, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 13)
        }
        sqlite3_bind_int(stmt, 14, Int32(checkIn.mentalClarity))
        sqlite3_bind_text(stmt, 15, checkIn.mood, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 16, checkIn.anxietyLevel, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 17, Int32(checkIn.readinessForDay))
        sqlite3_bind_int(stmt, 18, checkIn.hadSleepParalysis ? 1 : 0)
        sqlite3_bind_int(stmt, 19, checkIn.hadHallucinations ? 1 : 0)
        sqlite3_bind_int(stmt, 20, checkIn.hadAutomaticBehavior ? 1 : 0)
        sqlite3_bind_int(stmt, 21, checkIn.fellOutOfBed ? 1 : 0)
        sqlite3_bind_int(stmt, 22, checkIn.hadConfusionOnWaking ? 1 : 0)
        sqlite3_bind_int(stmt, 23, checkIn.usedSleepTherapy ? 1 : 0)
        if let json = checkIn.sleepTherapyJson {
            sqlite3_bind_text(stmt, 24, json, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 24)
        }
        sqlite3_bind_int(stmt, 25, checkIn.hasSleepEnvironment ? 1 : 0)
        if let json = checkIn.sleepEnvironmentJson {
            sqlite3_bind_text(stmt, 26, json, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 26)
        }
        if let notes = checkIn.notes {
            sqlite3_bind_text(stmt, 27, notes, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 27)
        }
        
        if sqlite3_step(stmt) == SQLITE_DONE {
            upsertCheckInSubmission(
                sourceRecordId: checkIn.id,
                sessionId: checkIn.sessionId,
                sessionDate: effectiveSessionDate,
                checkInType: .morning,
                questionnaireVersion: CheckInQuestionnaireVersion.morning,
                submittedAt: checkIn.timestamp,
                responsesByQuestionID: morningResponsesByQuestionID(checkIn)
            )
            storageLog.debug("Morning check-in saved: \(checkIn.id)")
        } else {
            storageLog.error("Failed to save morning check-in: \(String(cString: sqlite3_errmsg(self.db)))")
        }
    }

    /// Fetch normalized questionnaire submissions.
    public func fetchCheckInSubmissions(
        sessionDate: String? = nil,
        checkInType: CheckInType? = nil
    ) -> [StoredCheckInSubmission] {
        var conditions: [String] = []
        if sessionDate != nil {
            conditions.append("session_date = ?")
        }
        if checkInType != nil {
            conditions.append("checkin_type = ?")
        }
        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        let sql = """
            SELECT id, source_record_id, session_id, session_date, checkin_type, questionnaire_version,
                   user_id, submitted_at_utc, local_offset_minutes, responses_json
            FROM checkin_submissions
            \(whereClause)
            ORDER BY submitted_at_utc DESC
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var bindIndex: Int32 = 1
        if let sessionDate {
            sqlite3_bind_text(stmt, bindIndex, sessionDate, -1, SQLITE_TRANSIENT)
            bindIndex += 1
        }
        if let checkInType {
            sqlite3_bind_text(stmt, bindIndex, checkInType.rawValue, -1, SQLITE_TRANSIENT)
        }

        var rows: [StoredCheckInSubmission] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard
                let idPtr = sqlite3_column_text(stmt, 0),
                let sourcePtr = sqlite3_column_text(stmt, 1),
                let sessionDatePtr = sqlite3_column_text(stmt, 3),
                let typePtr = sqlite3_column_text(stmt, 4),
                let versionPtr = sqlite3_column_text(stmt, 5),
                let userPtr = sqlite3_column_text(stmt, 6),
                let submittedAtPtr = sqlite3_column_text(stmt, 7),
                let responsesPtr = sqlite3_column_text(stmt, 9)
            else { continue }

            let typeRaw = String(cString: typePtr)
            guard let type = CheckInType(rawValue: typeRaw) else { continue }
            let submittedAtUTC = isoFormatter.date(from: String(cString: submittedAtPtr)) ?? Date()
            rows.append(
                StoredCheckInSubmission(
                    id: String(cString: idPtr),
                    sourceRecordId: String(cString: sourcePtr),
                    sessionId: sqlite3_column_text(stmt, 2).map { String(cString: $0) },
                    sessionDate: String(cString: sessionDatePtr),
                    checkInType: type,
                    questionnaireVersion: String(cString: versionPtr),
                    userId: String(cString: userPtr),
                    submittedAtUTC: submittedAtUTC,
                    localOffsetMinutes: Int(sqlite3_column_int(stmt, 8)),
                    responsesJson: String(cString: responsesPtr)
                )
            )
        }
        return rows
    }

    /// Count normalized questionnaire submissions.
    public func fetchCheckInSubmissionCount(
        sessionDate: String? = nil,
        checkInType: CheckInType? = nil
    ) -> Int {
        var conditions: [String] = []
        if sessionDate != nil {
            conditions.append("session_date = ?")
        }
        if checkInType != nil {
            conditions.append("checkin_type = ?")
        }
        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        let sql = "SELECT COUNT(*) FROM checkin_submissions \(whereClause)"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }

        var bindIndex: Int32 = 1
        if let sessionDate {
            sqlite3_bind_text(stmt, bindIndex, sessionDate, -1, SQLITE_TRANSIENT)
            bindIndex += 1
        }
        if let checkInType {
            sqlite3_bind_text(stmt, bindIndex, checkInType.rawValue, -1, SQLITE_TRANSIENT)
        }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }
    
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
    
    // MARK: - Additional Methods Required by ContentView
    
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

    private func enqueueCloudKitTombstone(recordType: String, recordName: String) {
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
        let allowedTables = Set(["sleep_events", "dose_events", "morning_checkins"])
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
        let sql = """
            UPDATE pre_sleep_logs
            SET session_id = ?
            WHERE session_id IS NULL OR session_id = ?
            ORDER BY created_at DESC
            LIMIT 1
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

        // Collect all distinct session_dates from sleep_sessions, dose_events,
        // and sleep_events — not from current_session (which is single-row).
        let sql = """
            SELECT session_date FROM sleep_sessions
            UNION
            SELECT session_date FROM dose_events
            UNION
            SELECT session_date FROM sleep_events
            ORDER BY session_date DESC
            LIMIT ?
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return sessions }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(days))

        var sessionDates: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            sessionDates.append(String(cString: sqlite3_column_text(stmt, 0)))
        }

        for sessionDate in sessionDates {
            let doseEvents = fetchDoseEvents(sessionId: nil, sessionDate: sessionDate)
            let dose1 = doseEvents.first { isDose1EventType($0.eventType) }
            let dose2 = doseEvents.first { isDose2EventType($0.eventType) }
            let dose2Skipped = doseEvents.contains { isDose2SkippedEventType($0.eventType) }
            let snoozeCount = doseEvents.filter { $0.eventType.lowercased().hasPrefix("snooze") }.count

            let eventCount = countSleepEvents(for: sessionDate)

            sessions.append(SessionSummary(
                sessionDate: sessionDate,
                dose1Time: dose1?.timestamp,
                dose2Time: dose2?.timestamp,
                dose2Skipped: dose2Skipped,
                snoozeCount: snoozeCount,
                sleepEvents: [],
                eventCount: eventCount
            ))
        }

        return sessions
    }

    // MARK: - Dose event type helpers

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
    
    /// Save a pre-sleep log from PreSleepLog model
    public func savePreSleepLog(_ log: PreSleepLog) {
        do {
            _ = try savePreSleepLogOrThrow(
                sessionId: log.sessionId,
                answers: log.answers,
                completionState: log.completionState,
                now: log.createdAt,
                timeZone: .current
            )
        } catch {
            storageLog.error("Failed to save pre-sleep log: \(error.localizedDescription)")
        }
    }
    

}
