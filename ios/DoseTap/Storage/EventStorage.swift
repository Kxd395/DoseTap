import Foundation
import SQLite3

// MARK: - SQLite Helpers
// SQLITE_TRANSIENT is a C macro that doesn't exist in Swift
// We use unsafeBitCast to create the equivalent behavior
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - Event Storage (SQLite)
/// Persists sleep events and dose logs to local SQLite database
@MainActor
public class EventStorage {
    public static let shared = EventStorage()
    
    private var db: OpaquePointer?
    private let dbPath: String
    
    // ISO8601 formatter for date serialization
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    private init() {
        // Store in Documents directory for persistence
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dbPath = documentsPath.appendingPathComponent("dosetap_events.sqlite").path
        
        openDatabase()
        createTables()
        
        print("📦 EventStorage initialized at: \(dbPath)")
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    // MARK: - Database Setup
    
    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("❌ Failed to open database: \(String(cString: sqlite3_errmsg(db)))")
        }
    }
    
    private func createTables() {
        let createSQL = """
        -- Sleep events table
        CREATE TABLE IF NOT EXISTS sleep_events (
            id TEXT PRIMARY KEY,
            event_type TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            session_date TEXT NOT NULL,
            color_hex TEXT,
            notes TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        );
        
        -- Dose events table
        CREATE TABLE IF NOT EXISTS dose_events (
            id TEXT PRIMARY KEY,
            event_type TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            session_date TEXT NOT NULL,
            metadata TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        );
        
        -- Current session state
        CREATE TABLE IF NOT EXISTS current_session (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            dose1_time TEXT,
            dose2_time TEXT,
            snooze_count INTEGER DEFAULT 0,
            dose2_skipped INTEGER DEFAULT 0,
            session_date TEXT NOT NULL,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        );
        
        -- Pre-sleep log table (context capture before session)
        CREATE TABLE IF NOT EXISTS pre_sleep_logs (
            id TEXT PRIMARY KEY,
            session_id TEXT,
            created_at_utc TEXT NOT NULL,
            local_offset_minutes INTEGER NOT NULL,
            completion_state TEXT NOT NULL DEFAULT 'partial',
            answers_json TEXT NOT NULL DEFAULT '{}',
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        );
        
        -- Morning check-in table (Phase 2: comprehensive morning questionnaire)
        CREATE TABLE IF NOT EXISTS morning_checkins (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            session_date TEXT NOT NULL,
            
            -- Core sleep assessment (always captured)
            sleep_quality INTEGER NOT NULL DEFAULT 3,
            feel_rested TEXT NOT NULL DEFAULT 'moderate',
            grogginess TEXT NOT NULL DEFAULT 'mild',
            sleep_inertia_duration TEXT NOT NULL DEFAULT 'fiveToFifteen',
            dream_recall TEXT NOT NULL DEFAULT 'none',
            
            -- Physical symptoms (optional - JSON blob for flexibility, includes painNotes)
            has_physical_symptoms INTEGER NOT NULL DEFAULT 0,
            physical_symptoms_json TEXT,
            
            -- Respiratory symptoms (optional - JSON blob, includes respiratoryNotes)
            has_respiratory_symptoms INTEGER NOT NULL DEFAULT 0,
            respiratory_symptoms_json TEXT,
            
            -- Mental state (always captured)
            mental_clarity INTEGER NOT NULL DEFAULT 5,
            mood TEXT NOT NULL DEFAULT 'neutral',
            anxiety_level TEXT NOT NULL DEFAULT 'none',
            readiness_for_day INTEGER NOT NULL DEFAULT 3,
            
            -- Narcolepsy-specific flags
            had_sleep_paralysis INTEGER NOT NULL DEFAULT 0,
            had_hallucinations INTEGER NOT NULL DEFAULT 0,
            had_automatic_behavior INTEGER NOT NULL DEFAULT 0,
            fell_out_of_bed INTEGER NOT NULL DEFAULT 0,
            had_confusion_on_waking INTEGER NOT NULL DEFAULT 0,
            
            -- Sleep Therapy Device (NEW)
            used_sleep_therapy INTEGER NOT NULL DEFAULT 0,
            sleep_therapy_json TEXT,
            
            -- Notes
            notes TEXT,
            
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        );
        
        -- Indexes for performance
        CREATE INDEX IF NOT EXISTS idx_sleep_events_session ON sleep_events(session_date);
        CREATE INDEX IF NOT EXISTS idx_sleep_events_timestamp ON sleep_events(timestamp);
        CREATE INDEX IF NOT EXISTS idx_dose_events_session ON dose_events(session_date);
        CREATE INDEX IF NOT EXISTS idx_morning_checkins_session ON morning_checkins(session_date);
        CREATE INDEX IF NOT EXISTS idx_morning_checkins_session_id ON morning_checkins(session_id);
        
        -- Medication events (Adderall, etc.) - local-only, session-linked
        CREATE TABLE IF NOT EXISTS medication_events (
            id TEXT PRIMARY KEY,
            session_id TEXT,
            session_date TEXT NOT NULL,
            medication_id TEXT NOT NULL,
            dose_mg INTEGER NOT NULL,
            taken_at_utc TEXT NOT NULL,
            notes TEXT,
            confirmed_duplicate INTEGER DEFAULT 0,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        );
        
        -- Indexes for medication events
        CREATE INDEX IF NOT EXISTS idx_medication_events_session ON medication_events(session_id);
        CREATE INDEX IF NOT EXISTS idx_medication_events_session_date ON medication_events(session_date);
        CREATE INDEX IF NOT EXISTS idx_medication_events_medication ON medication_events(medication_id);
        CREATE INDEX IF NOT EXISTS idx_medication_events_taken_at ON medication_events(taken_at_utc);
        """
        
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, createSQL, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                print("❌ Failed to create tables: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
        }
        
        // Migration: Add new columns to existing tables (safe to run multiple times)
        migrateDatabase()
    }
    
    /// Add new columns if they don't exist (safe migration)
    private func migrateDatabase() {
        let migrations = [
            // Morning check-in sleep therapy columns
            "ALTER TABLE morning_checkins ADD COLUMN used_sleep_therapy INTEGER NOT NULL DEFAULT 0",
            "ALTER TABLE morning_checkins ADD COLUMN sleep_therapy_json TEXT",
            // P0: Session terminal state - distinguishes: completed, skipped, expired, aborted
            "ALTER TABLE current_session ADD COLUMN terminal_state TEXT",
            // Sleep Environment feature - captures sleep setup and aids for Morning Check-in
            "ALTER TABLE morning_checkins ADD COLUMN has_sleep_environment INTEGER NOT NULL DEFAULT 0",
            "ALTER TABLE morning_checkins ADD COLUMN sleep_environment_json TEXT",
            // Dose 3 Hazard Safety: Add hazard flag to dose_events
            "ALTER TABLE dose_events ADD COLUMN is_hazard INTEGER DEFAULT 0"
        ]
        
        for sql in migrations {
            var errMsg: UnsafeMutablePointer<CChar>?
            // Ignore errors (column already exists)
            sqlite3_exec(db, sql, nil, nil, &errMsg)
            if errMsg != nil {
                sqlite3_free(errMsg)
            }
        }
    }
    
    // MARK: - Session Date Calculation
    
    /// Get current session date (tonight)
    /// A "night" starts at 6 PM and ends at 6 AM next day
    public func currentSessionDate() -> String {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        
        // If before 6 AM, session belongs to previous day
        let sessionDate: Date
        if hour < 6 {
            sessionDate = calendar.date(byAdding: .day, value: -1, to: now)!
        } else {
            sessionDate = now
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: sessionDate)
    }
    
    // MARK: - Sleep Event Operations
    
    /// Insert a sleep event
    public func insertSleepEvent(id: String, eventType: String, timestamp: Date, colorHex: String?, notes: String? = nil) {
        let sql = """
        INSERT OR REPLACE INTO sleep_events (id, event_type, timestamp, session_date, color_hex, notes)
        VALUES (?, ?, ?, ?, ?, ?)
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("❌ Failed to prepare insert statement")
            return
        }
        defer { sqlite3_finalize(stmt) }
        
        let sessionDate = currentSessionDate()
        let timestampStr = isoFormatter.string(from: timestamp)
        
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, eventType, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, timestampStr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, sessionDate, -1, SQLITE_TRANSIENT)
        
        if let colorHex = colorHex {
            sqlite3_bind_text(stmt, 5, colorHex, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        
        if let notes = notes {
            sqlite3_bind_text(stmt, 6, notes, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        
        if sqlite3_step(stmt) == SQLITE_DONE {
            print("✅ Sleep event saved: \(eventType) at \(timestampStr)")
        } else {
            print("❌ Failed to insert sleep event: \(String(cString: sqlite3_errmsg(db)))")
        }
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
    public func saveDose1(timestamp: Date) {
        insertDoseEvent(eventType: "dose1", timestamp: timestamp)
        updateCurrentSession(dose1Time: timestamp)
    }
    
    /// Save dose 2 taken
    /// - Parameters:
    ///   - timestamp: When dose 2 was taken
    ///   - isEarly: True if taken before window opened (user override)
    ///   - isExtraDose: True if this is a second attempt at dose 2 (confirmed by user)
    public func saveDose2(timestamp: Date, isEarly: Bool = false, isExtraDose: Bool = false) {
        var metadata: [String: Any] = [:]
        if isEarly { metadata["is_early"] = true }
        if isExtraDose { metadata["is_extra_dose"] = true }
        
        let eventType = isExtraDose ? "extra_dose" : "dose2"
        let metadataStr = metadata.isEmpty ? nil : (try? JSONSerialization.data(withJSONObject: metadata)).flatMap { String(data: $0, encoding: .utf8) }
        
        insertDoseEvent(eventType: eventType, timestamp: timestamp, metadata: metadataStr)
        
        // Only update session dose2_time for first dose2 (not extra doses)
        if !isExtraDose {
            updateCurrentSession(dose2Time: timestamp)
        }
    }
    
    /// Save dose skipped
    public func saveDoseSkipped() {
        insertDoseEvent(eventType: "dose2_skipped", timestamp: Date())
        updateCurrentSession(dose2Skipped: true)
    }
    
    /// Save snooze
    public func saveSnooze(count: Int) {
        insertDoseEvent(eventType: "snooze", timestamp: Date(), metadata: "{\"count\":\(count)}")
        updateCurrentSession(snoozeCount: count)
    }
    
    private func insertDoseEvent(eventType: String, timestamp: Date, metadata: String? = nil) {
        let sql = """
        INSERT INTO dose_events (id, event_type, timestamp, session_date, metadata)
        VALUES (?, ?, ?, ?, ?)
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }
        
        let id = UUID().uuidString
        let sessionDate = currentSessionDate()
        let timestampStr = isoFormatter.string(from: timestamp)
        
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, eventType, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, timestampStr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, sessionDate, -1, SQLITE_TRANSIENT)
        
        if let metadata = metadata {
            sqlite3_bind_text(stmt, 5, metadata, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        
        if sqlite3_step(stmt) == SQLITE_DONE {
            print("✅ Dose event saved: \(eventType)")
        }
    }
    
    /// Insert a dose event (Dose 1 or Dose 2)
    /// Returns true if successful, false if duplicate (unless force=true)
    public func saveDoseEvent(type: String, timestamp: Date, isHazard: Bool = false) -> Bool {
        let sessionDate = currentSessionDate()
        
        // Check for existing dose of this type in this session
        if !isHazard && hasDose(type: type, sessionDate: sessionDate) {
            print("⚠️ Dose \(type) already exists for \(sessionDate). Use isHazard=true to force log.")
            return false
        }
        
        let id = UUID().uuidString
        let sql = """
        INSERT INTO dose_events (id, event_type, timestamp, session_date, is_hazard)
        VALUES (?, ?, ?, ?, ?)
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("❌ Failed to prepare dose insert statement")
            return false
        }
        defer { sqlite3_finalize(stmt) }
        
        let timestampStr = isoFormatter.string(from: timestamp)
        
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, type, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, timestampStr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, sessionDate, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 5, isHazard ? 1 : 0)
        
        if sqlite3_step(stmt) == SQLITE_DONE {
            print("✅ Dose event saved: \(type) at \(timestampStr) (Hazard: \(isHazard))")
            return true
        } else {
            print("❌ Failed to insert dose event: \(String(cString: sqlite3_errmsg(db)))")
            return false
        }
    }
    
    /// Check if a dose type already exists for a session
    public func hasDose(type: String, sessionDate: String) -> Bool {
        let sql = "SELECT count(*) FROM dose_events WHERE session_date = ? AND event_type = ? AND is_hazard = 0"
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
    
    // MARK: - Current Session State
    
    /// Update current session state in database
    /// Uses UPSERT pattern to ensure single row exists
    private func updateCurrentSession(dose1Time: Date? = nil, dose2Time: Date? = nil, snoozeCount: Int? = nil, dose2Skipped: Bool? = nil) {
        let sessionDate = currentSessionDate()
        
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
            print("❌ Failed to prepare session update")
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
            print("✅ Current session updated")
        } else {
            print("❌ Failed to update session: \(String(cString: sqlite3_errmsg(db)))")
        }
    }
    
    /// Load current session state from database
    public func loadCurrentSession() -> (dose1Time: Date?, dose2Time: Date?, snoozeCount: Int, dose2Skipped: Bool) {
        let sessionDate = currentSessionDate()
        let sql = "SELECT dose1_time, dose2_time, snooze_count, dose2_skipped FROM current_session WHERE id = 1 AND session_date = ?"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return (nil, nil, 0, false)
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            var dose1Time: Date? = nil
            var dose2Time: Date? = nil
            
            if let dose1Str = sqlite3_column_text(stmt, 0) {
                dose1Time = isoFormatter.date(from: String(cString: dose1Str))
            }
            
            if let dose2Str = sqlite3_column_text(stmt, 1) {
                dose2Time = isoFormatter.date(from: String(cString: dose2Str))
            }
            
            let snoozeCount = Int(sqlite3_column_int(stmt, 2))
            let dose2Skipped = sqlite3_column_int(stmt, 3) != 0
            
            return (dose1Time, dose2Time, snoozeCount, dose2Skipped)
        }
        
        return (nil, nil, 0, false)
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
    
    /// Save a pre-sleep log
    public func savePreSleepLog(sessionId: String?, answers: PreSleepLogAnswers, completionState: String = "complete") {
        let id = UUID().uuidString
        let now = Date()
        let createdAtUtc = isoFormatter.string(from: now)
        let localOffsetMinutes = TimeZone.current.secondsFromGMT() / 60
        
        // Encode answers to JSON
        let answersJson: String
        if let data = try? JSONEncoder().encode(answers),
           let json = String(data: data, encoding: .utf8) {
            answersJson = json
        } else {
            answersJson = "{}"
        }
        
        let sql = """
            INSERT INTO pre_sleep_logs (id, session_id, created_at_utc, local_offset_minutes, completion_state, answers_json)
            VALUES (?, ?, ?, ?, ?, ?)
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("❌ Failed to prepare pre-sleep log insert")
            return
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        if let sessionId = sessionId {
            sqlite3_bind_text(stmt, 2, sessionId, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        sqlite3_bind_text(stmt, 3, createdAtUtc, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 4, Int32(localOffsetMinutes))
        sqlite3_bind_text(stmt, 5, completionState, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 6, answersJson, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_DONE {
            print("✅ Pre-sleep log saved: \(id)")
        } else {
            print("❌ Failed to save pre-sleep log: \(String(cString: sqlite3_errmsg(db)))")
        }
    }
    
    /// Save a morning check-in to the database
    public func saveMorningCheckIn(_ checkIn: StoredMorningCheckIn, forSession sessionDate: String? = nil) {
        let effectiveSessionDate = sessionDate ?? currentSessionDate()
        
        let sql = """
            INSERT INTO morning_checkins (
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
            print("❌ Failed to prepare morning check-in insert: \(String(cString: sqlite3_errmsg(db)))")
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
            print("✅ Morning check-in saved: \(checkIn.id)")
        } else {
            print("❌ Failed to save morning check-in: \(String(cString: sqlite3_errmsg(db)))")
        }
    }
    
    /// Clear all data (for testing/debug)
    public func clearAllData() {
        let tables = ["sleep_events", "dose_events", "current_session", "pre_sleep_logs", "morning_checkins"]
        for table in tables {
            let sql = "DELETE FROM \(table)"
            var errMsg: UnsafeMutablePointer<CChar>?
            sqlite3_exec(db, sql, nil, nil, &errMsg)
            if errMsg != nil {
                sqlite3_free(errMsg)
            }
        }
        print("🗑️ All EventStorage data cleared")
    }
    
    /// Clear all sleep events only
    public func clearAllSleepEvents() {
        let sql = "DELETE FROM sleep_events"
        var errMsg: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, sql, nil, nil, &errMsg)
        if errMsg != nil {
            sqlite3_free(errMsg)
        }
        print("🗑️ All sleep events cleared")
    }
    
    /// Clear data older than specified days
    public func clearOldData(olderThanDays days: Int) {
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -days, to: Date()) else { return }
        let cutoffStr = sessionDateString(for: cutoffDate)
        
        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        
        let tables = ["sleep_events", "dose_events", "pre_sleep_logs", "morning_checkins"]
        for table in tables {
            let sql = "DELETE FROM \(table) WHERE session_date < ?"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, cutoffStr, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
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
        print("🗑️ Data older than \(days) days cleared")
    }
    
    /// Delete a session by date
    public func deleteSession(sessionDate: String) {
        // Use transaction for atomicity
        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        
        let tables = ["sleep_events", "dose_events", "pre_sleep_logs", "morning_checkins"]
        for table in tables {
            let sql = "DELETE FROM \(table) WHERE session_date = ?"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
        }
        
        // Clear current_session if it matches
        let clearCurrentSQL = "UPDATE current_session SET dose1_time = NULL, dose2_time = NULL, snooze_count = 0, dose2_skipped = 0 WHERE session_date = ?"
        var clearStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, clearCurrentSQL, -1, &clearStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(clearStmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_step(clearStmt)
            sqlite3_finalize(clearStmt)
        }
        
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
        print("🗑️ Session \(sessionDate) deleted from EventStorage")
    }
    
    // MARK: - Additional Methods Required by ContentView
    
    /// Delete a specific sleep event by ID
    public func deleteSleepEvent(id: String) {
        let sql = "DELETE FROM sleep_events WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_DONE {
            print("🗑️ Sleep event deleted: \(id)")
        }
    }
    
    /// Clear all events for tonight's session
    public func clearTonightsEvents() {
        let sessionDate = currentSessionDate()
        let sql = "DELETE FROM sleep_events WHERE session_date = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
        print("🗑️ Tonight's events cleared")
    }
    
    /// Get session date string for a given Date
    public func sessionDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    /// Find the most recent incomplete session (has dose1 but no dose2 and not skipped)
    public func mostRecentIncompleteSession() -> String? {
        let sql = """
            SELECT session_date FROM current_session 
            WHERE dose1_time IS NOT NULL 
            AND dose2_time IS NULL 
            AND dose2_skipped = 0
            AND session_date != ?
            ORDER BY session_date DESC LIMIT 1
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        
        let today = currentSessionDate()
        sqlite3_bind_text(stmt, 1, today, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return String(cString: sqlite3_column_text(stmt, 0))
        }
        return nil
    }
    
    /// Link a pre-sleep log to a session
    public func linkPreSleepLogToSession(sessionId: String) {
        // Find the most recent unlinked pre-sleep log and link it
        let sql = "UPDATE pre_sleep_logs SET session_id = ? WHERE session_id IS NULL ORDER BY created_at DESC LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, sessionId, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }
    
    /// Fetch recent sessions as summaries
    public func fetchRecentSessions(days: Int = 7) -> [SessionSummary] {
        var sessions: [SessionSummary] = []
        
        // Get unique session dates from current_session and sleep_events
        let sql = """
            SELECT DISTINCT cs.session_date, cs.dose1_time, cs.dose2_time, cs.dose2_skipped, cs.snooze_count,
                   (SELECT COUNT(*) FROM sleep_events se WHERE se.session_date = cs.session_date) as event_count
            FROM current_session cs
            ORDER BY cs.session_date DESC
            LIMIT ?
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return sessions }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int(stmt, 1, Int32(days))
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let sessionDate = String(cString: sqlite3_column_text(stmt, 0))
            
            var dose1Time: Date? = nil
            var dose2Time: Date? = nil
            
            if let d1Str = sqlite3_column_text(stmt, 1) {
                dose1Time = isoFormatter.date(from: String(cString: d1Str))
            }
            if let d2Str = sqlite3_column_text(stmt, 2) {
                dose2Time = isoFormatter.date(from: String(cString: d2Str))
            }
            
            let dose2Skipped = sqlite3_column_int(stmt, 3) != 0
            let snoozeCount = Int(sqlite3_column_int(stmt, 4))
            let eventCount = Int(sqlite3_column_int(stmt, 5))
            
            let summary = SessionSummary(
                sessionDate: sessionDate,
                dose1Time: dose1Time,
                dose2Time: dose2Time,
                dose2Skipped: dose2Skipped,
                snoozeCount: snoozeCount,
                sleepEvents: [],
                eventCount: eventCount
            )
            sessions.append(summary)
        }
        
        return sessions
    }
    
    /// Fetch dose log for a specific session
    public func fetchDoseLog(forSession sessionDate: String) -> StoredDoseLog? {
        let sql = "SELECT dose1_time, dose2_time, dose2_skipped, snooze_count FROM current_session WHERE session_date = ?"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
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
            
            // Only return if there's at least dose1
            guard dose1Time != nil else { return nil }
            
            return StoredDoseLog(
                id: sessionDate,
                sessionDate: sessionDate,
                dose1Time: dose1Time!,
                dose2Time: dose2Time,
                dose2Skipped: dose2Skipped,
                snoozeCount: snoozeCount
            )
        }
        
        return nil
    }
    
    /// Save a pre-sleep log from PreSleepLog model
    public func savePreSleepLog(_ log: PreSleepLog) {
        savePreSleepLog(sessionId: log.sessionId, answers: log.answers, completionState: log.completionState)
    }
    
    // MARK: - Additional Utility Methods
    
    /// Fetch all sleep events with optional limit
    public func fetchAllSleepEvents(limit: Int = 500) -> [StoredSleepEvent] {
        var events: [StoredSleepEvent] = []
        let sql = "SELECT id, event_type, timestamp, session_date, color_hex, notes FROM sleep_events ORDER BY timestamp DESC LIMIT ?"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return events }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int(stmt, 1, Int32(limit))
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let eventType = String(cString: sqlite3_column_text(stmt, 1))
            let timestampStr = String(cString: sqlite3_column_text(stmt, 2))
            let sessionDate = String(cString: sqlite3_column_text(stmt, 3))
            let colorHex = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
            let notes = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
            
            if let timestamp = isoFormatter.date(from: timestampStr) {
                events.append(StoredSleepEvent(
                    id: id,
                    eventType: eventType,
                    timestamp: timestamp,
                    sessionDate: sessionDate,
                    colorHex: colorHex,
                    notes: notes
                ))
            }
        }
        
        return events
    }
    
    /// Alias for fetchTonightsSleepEvents (handles typo variants)
    public func fetchTonightSleepEvents() -> [StoredSleepEvent] {
        return fetchTonightsSleepEvents()
    }
    
    /// Fetch events with limit (generic)
    public func fetchEvents(limit: Int = 50) -> [StoredSleepEvent] {
        return fetchAllSleepEvents(limit: limit)
    }
    
    /// Get all events (alias)
    public func getAllEvents(limit: Int = 500) -> [StoredSleepEvent] {
        return fetchAllSleepEvents(limit: limit)
    }
    
    /// Insert an event record (for compatibility)
    public func insertEvent(_ record: EventRecord) {
        insertSleepEvent(
            id: record.id.uuidString,
            eventType: record.type,
            timestamp: record.timestamp,
            colorHex: nil
        )
    }
    
    /// Export all data to CSV string
    public func exportToCSV() -> String {
        var csv = "type,timestamp,session_date,details\n"
        
        // Export sleep events
        let events = fetchAllSleepEvents(limit: 10000)
        for event in events {
            let line = "\(event.eventType),\(isoFormatter.string(from: event.timestamp)),\(event.sessionDate),\(event.notes ?? "")"
            csv += line + "\n"
        }
        
        // Export dose sessions
        let sessions = fetchRecentSessions(days: 365)
        for session in sessions {
            if let d1 = session.dose1Time {
                csv += "dose1,\(isoFormatter.string(from: d1)),\(session.sessionDate),\n"
            }
            if let d2 = session.dose2Time {
                csv += "dose2,\(isoFormatter.string(from: d2)),\(session.sessionDate),\n"
            }
            if session.dose2Skipped {
                csv += "dose2_skipped,,\(session.sessionDate),\n"
            }
        }
        
        // Export medication events
        let medications = fetchAllMedicationEvents(limit: 10000)
        for med in medications {
            let details = "\(med.medicationId)|\(med.doseMg)mg|\(med.notes ?? "")"
            csv += "medication,\(isoFormatter.string(from: med.takenAtUTC)),\(med.sessionDate),\(details)\n"
        }
        
        return csv
    }
    
    /// Export combined data with separate CSV files (for advanced export)
    public func exportCombinedData() -> (events: String, doses: String, medications: String) {
        let eventsCSV = exportSleepEventsToCSV()
        let dosesCSV = exportDoseEventsToCSV()
        let medicationsCSV = exportMedicationEventsToCSV()
        return (eventsCSV, dosesCSV, medicationsCSV)
    }
    
    /// Export sleep events to CSV
    private func exportSleepEventsToCSV() -> String {
        var csv = "id,event_type,timestamp,session_date,color_hex,notes\n"
        let events = fetchAllSleepEvents(limit: 10000)
        for event in events {
            let escapedNotes = (event.notes ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\(event.id),\(event.eventType),\(isoFormatter.string(from: event.timestamp)),\(event.sessionDate),\(event.colorHex ?? ""),\"\(escapedNotes)\"\n"
        }
        return csv
    }
    
    /// Export dose events to CSV
    private func exportDoseEventsToCSV() -> String {
        var csv = "session_date,dose1_time,dose2_time,snooze_count,dose2_skipped\n"
        let sessions = fetchRecentSessions(days: 365)
        for session in sessions {
            let d1 = session.dose1Time.map { isoFormatter.string(from: $0) } ?? ""
            let d2 = session.dose2Time.map { isoFormatter.string(from: $0) } ?? ""
            csv += "\(session.sessionDate),\(d1),\(d2),\(session.snoozeCount),\(session.dose2Skipped ? 1 : 0)\n"
        }
        return csv
    }
    
    // MARK: - Medication Event Operations
    
    /// Insert a medication event (Adderall, etc.)
    public func insertMedicationEvent(_ entry: StoredMedicationEntry) {
        let sql = """
        INSERT INTO medication_events (id, session_id, session_date, medication_id, dose_mg, taken_at_utc, notes, confirmed_duplicate)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("❌ Failed to prepare medication event insert")
            return
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, entry.id, -1, SQLITE_TRANSIENT)
        
        if let sessionId = entry.sessionId {
            sqlite3_bind_text(stmt, 2, sessionId, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        
        sqlite3_bind_text(stmt, 3, entry.sessionDate, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, entry.medicationId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 5, Int32(entry.doseMg))
        sqlite3_bind_text(stmt, 6, isoFormatter.string(from: entry.takenAtUTC), -1, SQLITE_TRANSIENT)
        
        if let notes = entry.notes {
            sqlite3_bind_text(stmt, 7, notes, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        
        sqlite3_bind_int(stmt, 8, entry.confirmedDuplicate ? 1 : 0)
        
        if sqlite3_step(stmt) != SQLITE_DONE {
            print("❌ Failed to insert medication event: \(String(cString: sqlite3_errmsg(db)))")
        } else {
            print("💊 Medication event inserted: \(entry.medicationId) \(entry.doseMg)mg")
        }
    }
    
    /// Fetch medication events for a session date
    public func fetchMedicationEvents(sessionDate: String) -> [StoredMedicationEntry] {
        var entries: [StoredMedicationEntry] = []
        let sql = """
        SELECT id, session_id, session_date, medication_id, dose_mg, taken_at_utc, notes, confirmed_duplicate, created_at
        FROM medication_events
        WHERE session_date = ?
        ORDER BY taken_at_utc DESC
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return entries }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let entry = parseMedicationRow(stmt) {
                entries.append(entry)
            }
        }
        
        return entries
    }
    
    /// Fetch all medication events (for export)
    public func fetchAllMedicationEvents(limit: Int = 1000) -> [StoredMedicationEntry] {
        var entries: [StoredMedicationEntry] = []
        let sql = """
        SELECT id, session_id, session_date, medication_id, dose_mg, taken_at_utc, notes, confirmed_duplicate, created_at
        FROM medication_events
        ORDER BY taken_at_utc DESC
        LIMIT ?
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return entries }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int(stmt, 1, Int32(limit))
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let entry = parseMedicationRow(stmt) {
                entries.append(entry)
            }
        }
        
        return entries
    }
    
    /// Delete a medication event
    public func deleteMedicationEvent(id: String) {
        let sql = "DELETE FROM medication_events WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) != SQLITE_DONE {
            print("❌ Failed to delete medication event")
        }
    }
    
    /// Find recent medication entry for duplicate guard
    public func findRecentMedicationEntry(medicationId: String, sessionDate: String, withinMinutes: Int, ofTime takenAt: Date) -> StoredMedicationEntry? {
        let entries = fetchMedicationEvents(sessionDate: sessionDate)
        
        for entry in entries where entry.medicationId == medicationId {
            let deltaSeconds = abs(takenAt.timeIntervalSince(entry.takenAtUTC))
            let deltaMinutes = Int(deltaSeconds / 60)
            if deltaMinutes < withinMinutes {
                return entry
            }
        }
        
        return nil
    }
    
    /// Parse a medication row from SQLite result
    private func parseMedicationRow(_ stmt: OpaquePointer?) -> StoredMedicationEntry? {
        guard let stmt = stmt else { return nil }
        
        let id = String(cString: sqlite3_column_text(stmt, 0))
        
        let sessionId: String?
        if sqlite3_column_type(stmt, 1) != SQLITE_NULL {
            sessionId = String(cString: sqlite3_column_text(stmt, 1))
        } else {
            sessionId = nil
        }
        
        let sessionDate = String(cString: sqlite3_column_text(stmt, 2))
        let medicationId = String(cString: sqlite3_column_text(stmt, 3))
        let doseMg = Int(sqlite3_column_int(stmt, 4))
        
        let takenAtStr = String(cString: sqlite3_column_text(stmt, 5))
        guard let takenAtUTC = isoFormatter.date(from: takenAtStr) else { return nil }
        
        let notes: String?
        if sqlite3_column_type(stmt, 6) != SQLITE_NULL {
            notes = String(cString: sqlite3_column_text(stmt, 6))
        } else {
            notes = nil
        }
        
        let confirmedDuplicate = sqlite3_column_int(stmt, 7) == 1
        
        let createdAtStr = String(cString: sqlite3_column_text(stmt, 8))
        let createdAt = isoFormatter.date(from: createdAtStr) ?? Date()
        
        return StoredMedicationEntry(
            id: id,
            sessionId: sessionId,
            sessionDate: sessionDate,
            medicationId: medicationId,
            doseMg: doseMg,
            takenAtUTC: takenAtUTC,
            notes: notes,
            confirmedDuplicate: confirmedDuplicate,
            createdAt: createdAt
        )
    }
    
    /// Export medication events to CSV
    public func exportMedicationEventsToCSV() -> String {
        var csv = "id,session_id,session_date,medication_id,dose_mg,taken_at_utc,notes,confirmed_duplicate,created_at\n"
        
        let entries = fetchAllMedicationEvents(limit: 10000)
        for entry in entries {
            let escapedNotes = (entry.notes ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\(entry.id),\(entry.sessionId ?? ""),\(entry.sessionDate),\(entry.medicationId),\(entry.doseMg),\(isoFormatter.string(from: entry.takenAtUTC)),\"\(escapedNotes)\",\(entry.confirmedDuplicate ? 1 : 0),\(isoFormatter.string(from: entry.createdAt))\n"
        }
        
        return csv
    }
}

/// Event record for compatibility with legacy code
public struct EventRecord: Identifiable {
    public let id: UUID
    public let type: String
    public let timestamp: Date
    public let metadata: String?
    
    public init(type: String, timestamp: Date, metadata: String? = nil) {
        self.id = UUID()
        self.type = type
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

// MARK: - Storage Data Models

/// Stored medication entry model for EventStorage
public struct StoredMedicationEntry: Identifiable {
    public let id: String
    public let sessionId: String?
    public let sessionDate: String
    public let medicationId: String
    public let doseMg: Int
    public let takenAtUTC: Date
    public let notes: String?
    public let confirmedDuplicate: Bool
    public let createdAt: Date
    
    public init(
        id: String = UUID().uuidString,
        sessionId: String?,
        sessionDate: String,
        medicationId: String,
        doseMg: Int,
        takenAtUTC: Date,
        notes: String? = nil,
        confirmedDuplicate: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.sessionDate = sessionDate
        self.medicationId = medicationId
        self.doseMg = doseMg
        self.takenAtUTC = takenAtUTC
        self.notes = notes
        self.confirmedDuplicate = confirmedDuplicate
        self.createdAt = createdAt
    }
}

/// Stored pre-sleep log model for EventStorage
public struct StoredPreSleepLog: Identifiable {
    public let id: String
    public let sessionId: String?
    public let createdAtUtc: String
    public let localOffsetMinutes: Int
    public let completionState: String
    public let answers: PreSleepLogAnswers?
    
    public init(id: String, sessionId: String?, createdAtUtc: String, localOffsetMinutes: Int, completionState: String, answers: PreSleepLogAnswers?) {
        self.id = id
        self.sessionId = sessionId
        self.createdAtUtc = createdAtUtc
        self.localOffsetMinutes = localOffsetMinutes
        self.completionState = completionState
        self.answers = answers
    }
}

/// Pre-sleep log model for creating new logs (input model)
public struct PreSleepLog: Identifiable {
    public let id: String
    public let sessionId: String?
    public let answers: PreSleepLogAnswers
    public let completionState: String
    public let createdAt: Date
    
    public init(answers: PreSleepLogAnswers, completionState: String = "complete", sessionId: String? = nil) {
        self.id = UUID().uuidString
        self.sessionId = sessionId
        self.answers = answers
        self.completionState = completionState
        self.createdAt = Date()
    }
}

/// Stored sleep event model for EventStorage
public struct StoredSleepEvent: Identifiable {
    public let id: String
    public let eventType: String
    public let timestamp: Date
    public let sessionDate: String
    public let colorHex: String?
    public let notes: String?
    
    public init(id: String, eventType: String, timestamp: Date, sessionDate: String, colorHex: String? = nil, notes: String? = nil) {
        self.id = id
        self.eventType = eventType
        self.timestamp = timestamp
        self.sessionDate = sessionDate
        self.colorHex = colorHex
        self.notes = notes
    }
}

/// Stored dose log model
/// Stored dose log model - represents a complete session's dose data
public struct StoredDoseLog: Identifiable {
    public let id: String
    public let sessionDate: String
    public let dose1Time: Date
    public let dose2Time: Date?
    public let dose2Skipped: Bool
    public let snoozeCount: Int
    
    public init(id: String, sessionDate: String, dose1Time: Date, dose2Time: Date? = nil, dose2Skipped: Bool = false, snoozeCount: Int = 0) {
        self.id = id
        self.sessionDate = sessionDate
        self.dose1Time = dose1Time
        self.dose2Time = dose2Time
        self.dose2Skipped = dose2Skipped
        self.snoozeCount = snoozeCount
    }
    
    /// Interval in minutes between doses (nil if dose2 not taken)
    public var intervalMinutes: Int? {
        guard let d2 = dose2Time else { return nil }
        return Int(d2.timeIntervalSince(dose1Time) / 60)
    }
    
    /// Alias for dose2Skipped for UI convenience
    public var skipped: Bool { dose2Skipped }
}

/// Session summary for history views
public struct SessionSummary: Identifiable {
    public let id: String
    public let sessionDate: String
    public let dose1Time: Date?
    public let dose2Time: Date?
    public let dose2Skipped: Bool
    public let snoozeCount: Int
    public let intervalMinutes: Int?
    public let sleepEvents: [StoredSleepEvent]
    public let eventCount: Int
    
    /// Alias for dose2Skipped for UI convenience
    public var skipped: Bool { dose2Skipped }
    
    public init(sessionDate: String, dose1Time: Date? = nil, dose2Time: Date? = nil, dose2Skipped: Bool = false, snoozeCount: Int = 0, sleepEvents: [StoredSleepEvent] = [], eventCount: Int? = nil) {
        self.id = sessionDate
        self.sessionDate = sessionDate
        self.dose1Time = dose1Time
        self.dose2Time = dose2Time
        self.dose2Skipped = dose2Skipped
        self.snoozeCount = snoozeCount
        self.sleepEvents = sleepEvents
        self.eventCount = eventCount ?? sleepEvents.count
        
        // Calculate interval if both doses exist
        if let d1 = dose1Time, let d2 = dose2Time {
            self.intervalMinutes = Int(d2.timeIntervalSince(d1) / 60)
        } else {
            self.intervalMinutes = nil
        }
    }
}

/// Stored morning check-in model for EventStorage
public struct StoredMorningCheckIn: Identifiable {
    public let id: String
    public let sessionId: String
    public let timestamp: Date
    public let sessionDate: String
    
    // Core assessment
    public let sleepQuality: Int
    public let feelRested: String
    public let grogginess: String
    public let sleepInertiaDuration: String
    public let dreamRecall: String
    
    // Physical symptoms
    public let hasPhysicalSymptoms: Bool
    public let physicalSymptomsJson: String?
    
    // Respiratory symptoms
    public let hasRespiratorySymptoms: Bool
    public let respiratorySymptomsJson: String?
    
    // Mental state
    public let mentalClarity: Int
    public let mood: String
    public let anxietyLevel: String
    public let readinessForDay: Int
    
    // Narcolepsy flags
    public let hadSleepParalysis: Bool
    public let hadHallucinations: Bool
    public let hadAutomaticBehavior: Bool
    public let fellOutOfBed: Bool
    public let hadConfusionOnWaking: Bool
    
    // Sleep Therapy
    public let usedSleepTherapy: Bool
    public let sleepTherapyJson: String?
    
    // Sleep Environment
    public let hasSleepEnvironment: Bool
    public let sleepEnvironmentJson: String?
    
    // Notes
    public let notes: String?
    
    /// Computed: any narcolepsy symptoms reported
    public var hasNarcolepsySymptoms: Bool {
        hadSleepParalysis || hadHallucinations || hadAutomaticBehavior || fellOutOfBed || hadConfusionOnWaking
    }
    
    public init(
        id: String,
        sessionId: String,
        timestamp: Date,
        sessionDate: String,
        sleepQuality: Int = 3,
        feelRested: String = "moderate",
        grogginess: String = "mild",
        sleepInertiaDuration: String = "fiveToFifteen",
        dreamRecall: String = "none",
        hasPhysicalSymptoms: Bool = false,
        physicalSymptomsJson: String? = nil,
        hasRespiratorySymptoms: Bool = false,
        respiratorySymptomsJson: String? = nil,
        mentalClarity: Int = 5,
        mood: String = "neutral",
        anxietyLevel: String = "none",
        readinessForDay: Int = 3,
        hadSleepParalysis: Bool = false,
        hadHallucinations: Bool = false,
        hadAutomaticBehavior: Bool = false,
        fellOutOfBed: Bool = false,
        hadConfusionOnWaking: Bool = false,
        usedSleepTherapy: Bool = false,
        sleepTherapyJson: String? = nil,
        hasSleepEnvironment: Bool = false,
        sleepEnvironmentJson: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.sessionDate = sessionDate
        self.sleepQuality = sleepQuality
        self.feelRested = feelRested
        self.grogginess = grogginess
        self.sleepInertiaDuration = sleepInertiaDuration
        self.dreamRecall = dreamRecall
        self.hasPhysicalSymptoms = hasPhysicalSymptoms
        self.physicalSymptomsJson = physicalSymptomsJson
        self.hasRespiratorySymptoms = hasRespiratorySymptoms
        self.respiratorySymptomsJson = respiratorySymptomsJson
        self.mentalClarity = mentalClarity
        self.mood = mood
        self.anxietyLevel = anxietyLevel
        self.readinessForDay = readinessForDay
        self.hadSleepParalysis = hadSleepParalysis
        self.hadHallucinations = hadHallucinations
        self.hadAutomaticBehavior = hadAutomaticBehavior
        self.fellOutOfBed = fellOutOfBed
        self.hadConfusionOnWaking = hadConfusionOnWaking
        self.usedSleepTherapy = usedSleepTherapy
        self.sleepTherapyJson = sleepTherapyJson
        self.hasSleepEnvironment = hasSleepEnvironment
        self.sleepEnvironmentJson = sleepEnvironmentJson
        self.notes = notes
    }
}

/// Pre-sleep log answers model with nested enums for type-safe options
public struct PreSleepLogAnswers: Codable {
    
    // MARK: - Nested Enums for Question Options
    
    public enum IntendedSleepTime: String, Codable, CaseIterable {
        case now = "now"
        case fifteenMin = "15min"
        case thirtyMin = "30min"
        case hour = "1hr"
        case later = "later"
        
        public var displayText: String {
            switch self {
            case .now: return "Now"
            case .fifteenMin: return "~15 min"
            case .thirtyMin: return "~30 min"
            case .hour: return "~1 hour"
            case .later: return "Later"
            }
        }
    }
    
    public enum StressDriver: String, Codable, CaseIterable {
        case work = "work"
        case family = "family"
        case health = "health"
        case financial = "financial"
        case relationship = "relationship"
        case other = "other"
        
        public var displayText: String {
            switch self {
            case .work: return "Work"
            case .family: return "Family"
            case .health: return "Health"
            case .financial: return "Financial"
            case .relationship: return "Relationship"
            case .other: return "Other"
            }
        }
    }
    
    public enum PainLevel: String, Codable, CaseIterable {
        case none = "none"
        case mild = "mild"
        case moderate = "moderate"
        case severe = "severe"
        
        public var displayText: String {
            switch self {
            case .none: return "None"
            case .mild: return "Mild"
            case .moderate: return "Moderate"
            case .severe: return "Severe"
            }
        }
    }
    
    public enum PainLocation: String, Codable, CaseIterable {
        case head = "head"
        case neck = "neck"
        case back = "back"
        case shoulders = "shoulders"
        case legs = "legs"
        case joints = "joints"
        case stomach = "stomach"
        case other = "other"
        
        public var displayText: String {
            switch self {
            case .head: return "Head"
            case .neck: return "Neck"
            case .back: return "Back"
            case .shoulders: return "Shoulders"
            case .legs: return "Legs"
            case .joints: return "Joints"
            case .stomach: return "Stomach"
            case .other: return "Other"
            }
        }
    }
    
    public enum PainType: String, Codable, CaseIterable {
        case aching = "aching"
        case sharp = "sharp"
        case burning = "burning"
        case throbbing = "throbbing"
        case cramping = "cramping"
        
        public var displayText: String {
            switch self {
            case .aching: return "Aching"
            case .sharp: return "Sharp"
            case .burning: return "Burning"
            case .throbbing: return "Throbbing"
            case .cramping: return "Cramping"
            }
        }
    }
    
    public enum Stimulants: String, Codable, CaseIterable {
        case none = "none"
        case coffee = "coffee"
        case tea = "tea"
        case soda = "soda"
        case energyDrink = "energy_drink"
        case multiple = "multiple"
        
        public var displayText: String {
            switch self {
            case .none: return "None"
            case .coffee: return "Coffee"
            case .tea: return "Tea"
            case .soda: return "Soda"
            case .energyDrink: return "Energy Drink"
            case .multiple: return "Multiple"
            }
        }
    }
    
    public enum AlcoholLevel: String, Codable, CaseIterable {
        case none = "none"
        case one = "1"
        case twoThree = "2-3"
        case fourPlus = "4+"
        
        public var displayText: String {
            switch self {
            case .none: return "None"
            case .one: return "1 drink"
            case .twoThree: return "2-3 drinks"
            case .fourPlus: return "4+ drinks"
            }
        }
    }
    
    public enum ExerciseLevel: String, Codable, CaseIterable {
        case none = "none"
        case light = "light"
        case moderate = "moderate"
        case intense = "intense"
        
        public var displayText: String {
            switch self {
            case .none: return "None"
            case .light: return "Light"
            case .moderate: return "Moderate"
            case .intense: return "Intense"
            }
        }
    }
    
    public enum NapDuration: String, Codable, CaseIterable {
        case none = "none"
        case short = "short"
        case medium = "medium"
        case long = "long"
        
        public var displayText: String {
            switch self {
            case .none: return "No nap"
            case .short: return "<30 min"
            case .medium: return "30-60 min"
            case .long: return ">1 hour"
            }
        }
    }
    
    public enum LaterReason: String, Codable, CaseIterable {
        case notTired = "not_tired"
        case workToDo = "work"
        case socialPlans = "social"
        case entertainment = "entertainment"
        case other = "other"
        
        public var displayText: String {
            switch self {
            case .notTired: return "Not tired"
            case .workToDo: return "Work to do"
            case .socialPlans: return "Social plans"
            case .entertainment: return "Entertainment"
            case .other: return "Other"
            }
        }
    }
    
    public enum LateMeal: String, Codable, CaseIterable {
        case none = "none"
        case snack = "snack"
        case lightMeal = "light"
        case heavyMeal = "heavy"
        
        public var displayText: String {
            switch self {
            case .none: return "None"
            case .snack: return "Snack"
            case .lightMeal: return "Light meal"
            case .heavyMeal: return "Heavy meal"
            }
        }
    }
    
    public enum ScreensInBed: String, Codable, CaseIterable {
        case none = "none"
        case briefly = "briefly"
        case thirtyMin = "30min"
        case hourPlus = "1hr+"
        
        public var displayText: String {
            switch self {
            case .none: return "None"
            case .briefly: return "Briefly"
            case .thirtyMin: return "~30 min"
            case .hourPlus: return "1+ hour"
            }
        }
    }
    
    public enum RoomTemp: String, Codable, CaseIterable {
        case cold = "cold"
        case cool = "cool"
        case comfortable = "comfortable"
        case warm = "warm"
        case hot = "hot"
        
        public var displayText: String {
            switch self {
            case .cold: return "Cold"
            case .cool: return "Cool"
            case .comfortable: return "Comfortable"
            case .warm: return "Warm"
            case .hot: return "Hot"
            }
        }
    }
    
    public enum NoiseLevel: String, Codable, CaseIterable {
        case silent = "silent"
        case quiet = "quiet"
        case moderate = "moderate"
        case noisy = "noisy"
        
        public var displayText: String {
            switch self {
            case .silent: return "Silent"
            case .quiet: return "Quiet"
            case .moderate: return "Moderate"
            case .noisy: return "Noisy"
            }
        }
    }
    
    // MARK: - Properties
    
    // Card 1: Timing + Stress
    public var intendedSleepTime: IntendedSleepTime?
    public var stressLevel: Int?
    public var stressDriver: StressDriver?
    public var laterReason: LaterReason?
    
    // Card 2: Body + Substances
    public var bodyPain: PainLevel?
    public var painLocations: [PainLocation]?
    public var painType: PainType?
    public var stimulants: Stimulants?
    public var alcohol: AlcoholLevel?
    
    // Card 3: Activity + Naps
    public var exercise: ExerciseLevel?
    public var napToday: NapDuration?
    
    // Optional details
    public var lateMeal: LateMeal?
    public var screensInBed: ScreensInBed?
    public var roomTemp: RoomTemp?
    public var noiseLevel: NoiseLevel?
    
    // Legacy fields (for backwards compatibility)
    public var notes: String?
    
    public init(
        intendedSleepTime: IntendedSleepTime? = nil,
        stressLevel: Int? = nil,
        stressDriver: StressDriver? = nil,
        laterReason: LaterReason? = nil,
        bodyPain: PainLevel? = nil,
        painLocations: [PainLocation]? = nil,
        painType: PainType? = nil,
        stimulants: Stimulants? = nil,
        alcohol: AlcoholLevel? = nil,
        exercise: ExerciseLevel? = nil,
        napToday: NapDuration? = nil,
        lateMeal: LateMeal? = nil,
        screensInBed: ScreensInBed? = nil,
        roomTemp: RoomTemp? = nil,
        noiseLevel: NoiseLevel? = nil,
        notes: String? = nil
    ) {
        self.intendedSleepTime = intendedSleepTime
        self.stressLevel = stressLevel
        self.stressDriver = stressDriver
        self.laterReason = laterReason
        self.bodyPain = bodyPain
        self.painLocations = painLocations
        self.painType = painType
        self.stimulants = stimulants
        self.alcohol = alcohol
        self.exercise = exercise
        self.napToday = napToday
        self.lateMeal = lateMeal
        self.screensInBed = screensInBed
        self.roomTemp = roomTemp
        self.noiseLevel = noiseLevel
        self.notes = notes
    }
}
