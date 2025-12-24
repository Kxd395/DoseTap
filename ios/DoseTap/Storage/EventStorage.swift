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
            "ALTER TABLE morning_checkins ADD COLUMN used_sleep_therapy INTEGER NOT NULL DEFAULT 0",
            "ALTER TABLE morning_checkins ADD COLUMN sleep_therapy_json TEXT"
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
    
    // MARK: - Current Session State
    
    private func updateCurrentSession(dose1Time: Date? = nil, dose2Time: Date? = nil, snoozeCount: Int? = nil, dose2Skipped: Bool? = nil) {
        let sessionDate = currentSessionDate()
        
        // First, ensure session row exists
        let insertSQL = """
        INSERT OR IGNORE INTO current_session (id, session_date) VALUES (1, ?)
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        
        // Build update SQL dynamically
        var updates: [String] = ["updated_at = datetime('now')", "session_date = ?"]
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
        
        if sqlite3_prepare_v2(db, updateSQL, -1, &stmt, nil) == SQLITE_OK {
            for (index, value) in values.enumerated() {
                let col = Int32(index + 1)
                if let str = value as? String {
                    sqlite3_bind_text(stmt, col, str, -1, SQLITE_TRANSIENT)
                } else if let int = value as? Int {
                    sqlite3_bind_int(stmt, col, Int32(int))
                }
            }
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }
    
    /// Load current session state
    public func loadCurrentSession() -> (dose1Time: Date?, dose2Time: Date?, snoozeCount: Int, dose2Skipped: Bool) {
        let sessionDate = currentSessionDate()
        let sql = "SELECT dose1_time, dose2_time, snooze_count, dose2_skipped FROM current_session WHERE session_date = ?"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return (nil, nil, 0, false)
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            var dose1Time: Date? = nil
            var dose2Time: Date? = nil
            
            if let text = sqlite3_column_text(stmt, 0) {
                dose1Time = isoFormatter.date(from: String(cString: text))
            }
            if let text = sqlite3_column_text(stmt, 1) {
                dose2Time = isoFormatter.date(from: String(cString: text))
            }
            
            let snoozeCount = Int(sqlite3_column_int(stmt, 2))
            let dose2Skipped = sqlite3_column_int(stmt, 3) != 0
            
            return (dose1Time, dose2Time, snoozeCount, dose2Skipped)
        }
        
        return (nil, nil, 0, false)
    }
    
    // MARK: - Clear Data
    
    /// Clear tonight's events (for testing)
    public func clearTonightsEvents() {
        let sessionDate = currentSessionDate()
        let sql = "DELETE FROM sleep_events WHERE session_date = ?"
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }
    
    /// Clear all data (for reset)
    public func clearAllData() {
        let sql = """
        DELETE FROM sleep_events;
        DELETE FROM dose_events;
        DELETE FROM current_session;
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }
    
    // MARK: - Morning Check-In Operations
    
    /// Save a morning check-in
    public func saveMorningCheckIn(_ checkIn: StoredMorningCheckIn) {
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
            notes
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("❌ Failed to prepare morning check-in insert")
            return
        }
        defer { sqlite3_finalize(stmt) }
        
        let sessionDate = currentSessionDate()
        let timestampStr = isoFormatter.string(from: checkIn.timestamp)
        
        sqlite3_bind_text(stmt, 1, checkIn.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, checkIn.sessionId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, timestampStr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, sessionDate, -1, SQLITE_TRANSIENT)
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
        
        if let notes = checkIn.notes {
            sqlite3_bind_text(stmt, 25, notes, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 25)
        }
        
        if sqlite3_step(stmt) == SQLITE_DONE {
            print("✅ Morning check-in saved for session: \(sessionDate)")
        } else {
            print("❌ Failed to save morning check-in: \(String(cString: sqlite3_errmsg(db)))")
        }
    }
    
    /// Fetch morning check-in for a specific session
    public func fetchMorningCheckIn(forSession sessionDate: String) -> StoredMorningCheckIn? {
        let sql = """
        SELECT 
            id, session_id, timestamp, session_date,
            sleep_quality, feel_rested, grogginess, sleep_inertia_duration, dream_recall,
            has_physical_symptoms, physical_symptoms_json,
            has_respiratory_symptoms, respiratory_symptoms_json,
            mental_clarity, mood, anxiety_level, readiness_for_day,
            had_sleep_paralysis, had_hallucinations, had_automatic_behavior,
            fell_out_of_bed, had_confusion_on_waking,
            used_sleep_therapy, sleep_therapy_json,
            notes
        FROM morning_checkins
        WHERE session_date = ?
        ORDER BY timestamp DESC
        LIMIT 1
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return parseMorningCheckInRow(stmt)
        }
        
        return nil
    }
    
    /// Fetch today's morning check-in
    public func fetchTodaysMorningCheckIn() -> StoredMorningCheckIn? {
        return fetchMorningCheckIn(forSession: currentSessionDate())
    }
    
    /// Fetch all morning check-ins for analytics (limited)
    public func fetchRecentMorningCheckIns(limit: Int = 30) -> [StoredMorningCheckIn] {
        let sql = """
        SELECT 
            id, session_id, timestamp, session_date,
            sleep_quality, feel_rested, grogginess, sleep_inertia_duration, dream_recall,
            has_physical_symptoms, physical_symptoms_json,
            has_respiratory_symptoms, respiratory_symptoms_json,
            mental_clarity, mood, anxiety_level, readiness_for_day,
            had_sleep_paralysis, had_hallucinations, had_automatic_behavior,
            fell_out_of_bed, had_confusion_on_waking, notes
        FROM morning_checkins
        ORDER BY timestamp DESC
        LIMIT ?
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int(stmt, 1, Int32(limit))
        
        var checkIns: [StoredMorningCheckIn] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let checkIn = parseMorningCheckInRow(stmt) {
                checkIns.append(checkIn)
            }
        }
        
        return checkIns
    }
    
    /// Helper to parse morning check-in row
    private func parseMorningCheckInRow(_ stmt: OpaquePointer?) -> StoredMorningCheckIn? {
        guard let stmt = stmt else { return nil }
        
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let sessionId = String(cString: sqlite3_column_text(stmt, 1))
        let timestampStr = String(cString: sqlite3_column_text(stmt, 2))
        let sessionDate = String(cString: sqlite3_column_text(stmt, 3))
        let timestamp = isoFormatter.date(from: timestampStr) ?? Date()
        
        var physicalSymptomsJson: String? = nil
        if let text = sqlite3_column_text(stmt, 10) {
            physicalSymptomsJson = String(cString: text)
        }
        
        var respiratorySymptomsJson: String? = nil
        if let text = sqlite3_column_text(stmt, 12) {
            respiratorySymptomsJson = String(cString: text)
        }
        
        // Sleep therapy JSON (NEW - column 23)
        var sleepTherapyJson: String? = nil
        if let text = sqlite3_column_text(stmt, 23) {
            sleepTherapyJson = String(cString: text)
        }
        
        // Notes (NEW - column 24, was 22)
        var notes: String? = nil
        if let text = sqlite3_column_text(stmt, 24) {
            notes = String(cString: text)
        }
        
        return StoredMorningCheckIn(
            id: id,
            sessionId: sessionId,
            timestamp: timestamp,
            sessionDate: sessionDate,
            sleepQuality: Int(sqlite3_column_int(stmt, 4)),
            feelRested: String(cString: sqlite3_column_text(stmt, 5)),
            grogginess: String(cString: sqlite3_column_text(stmt, 6)),
            sleepInertiaDuration: String(cString: sqlite3_column_text(stmt, 7)),
            dreamRecall: String(cString: sqlite3_column_text(stmt, 8)),
            hasPhysicalSymptoms: sqlite3_column_int(stmt, 9) != 0,
            physicalSymptomsJson: physicalSymptomsJson,
            hasRespiratorySymptoms: sqlite3_column_int(stmt, 11) != 0,
            respiratorySymptomsJson: respiratorySymptomsJson,
            mentalClarity: Int(sqlite3_column_int(stmt, 13)),
            mood: String(cString: sqlite3_column_text(stmt, 14)),
            anxietyLevel: String(cString: sqlite3_column_text(stmt, 15)),
            readinessForDay: Int(sqlite3_column_int(stmt, 16)),
            hadSleepParalysis: sqlite3_column_int(stmt, 17) != 0,
            hadHallucinations: sqlite3_column_int(stmt, 18) != 0,
            hadAutomaticBehavior: sqlite3_column_int(stmt, 19) != 0,
            fellOutOfBed: sqlite3_column_int(stmt, 20) != 0,
            hadConfusionOnWaking: sqlite3_column_int(stmt, 21) != 0,
            usedSleepTherapy: sqlite3_column_int(stmt, 22) != 0,  // NEW
            sleepTherapyJson: sleepTherapyJson,  // NEW
            notes: notes
        )
    }
    
    /// Check if morning check-in exists for current session
    public func hasTodaysMorningCheckIn() -> Bool {
        let sessionDate = currentSessionDate()
        let sql = "SELECT COUNT(*) FROM morning_checkins WHERE session_date = ?"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_int(stmt, 0) > 0
        }
        return false
    }
    
    /// Delete morning check-in for a session
    public func deleteMorningCheckIn(forSession sessionDate: String) {
        let sql = "DELETE FROM morning_checkins WHERE session_date = ?"
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        
        print("🗑️ Deleted morning check-in for: \(sessionDate)")
    }
    
    // MARK: - Pre-Sleep Log Operations
    
    /// Save a pre-sleep log
    public func savePreSleepLog(_ log: PreSleepLog) {
        let sql = """
        INSERT OR REPLACE INTO pre_sleep_logs 
        (id, session_id, created_at_utc, local_offset_minutes, completion_state, answers_json)
        VALUES (?, ?, ?, ?, ?, ?)
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("❌ Failed to prepare pre-sleep log insert")
            return
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, log.id, -1, SQLITE_TRANSIENT)
        
        if let sessionId = log.sessionId {
            sqlite3_bind_text(stmt, 2, sessionId, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        
        sqlite3_bind_text(stmt, 3, log.createdAtUTC, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 4, Int32(log.localOffsetMinutes))
        sqlite3_bind_text(stmt, 5, log.completionState, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 6, log.answersJson, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_DONE {
            print("✅ Pre-sleep log saved: \(log.id)")
        }
    }
    
    /// Link a pre-sleep log to a session (called when Dose 1 taken)
    /// Links the most recent unlinked log created within 2 hours
    public func linkPreSleepLogToSession(sessionId: String) {
        let now = Date()
        let twoHoursAgo = now.addingTimeInterval(-2 * 60 * 60)
        let twoHoursAgoStr = isoFormatter.string(from: twoHoursAgo)
        
        // Find most recent unlinked log within 2 hours
        let findSQL = """
        SELECT id FROM pre_sleep_logs 
        WHERE session_id IS NULL 
        AND created_at_utc > ? 
        ORDER BY created_at_utc DESC 
        LIMIT 1
        """
        
        var findStmt: OpaquePointer?
        var logId: String?
        
        if sqlite3_prepare_v2(db, findSQL, -1, &findStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(findStmt, 1, twoHoursAgoStr, -1, SQLITE_TRANSIENT)
            if sqlite3_step(findStmt) == SQLITE_ROW {
                if let idPtr = sqlite3_column_text(findStmt, 0) {
                    logId = String(cString: idPtr)
                }
            }
            sqlite3_finalize(findStmt)
        }
        
        guard let id = logId else {
            print("📋 No unlinked pre-sleep log found within 2 hours")
            return
        }
        
        // Link it
        let updateSQL = "UPDATE pre_sleep_logs SET session_id = ? WHERE id = ?"
        var updateStmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(updateStmt, 1, sessionId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(updateStmt, 2, id, -1, SQLITE_TRANSIENT)
            sqlite3_step(updateStmt)
            sqlite3_finalize(updateStmt)
            print("✅ Linked pre-sleep log \(id) to session \(sessionId)")
        }
    }
    
    /// Fetch pre-sleep log for a session
    public func fetchPreSleepLog(forSession sessionId: String) -> PreSleepLog? {
        let sql = """
        SELECT id, session_id, created_at_utc, local_offset_minutes, completion_state, answers_json
        FROM pre_sleep_logs
        WHERE session_id = ?
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, sessionId, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return parsePreSleepLogRow(stmt)
        }
        
        return nil
    }
    
    /// Fetch all unlinked pre-sleep logs
    public func fetchUnlinkedPreSleepLogs() -> [PreSleepLog] {
        let sql = """
        SELECT id, session_id, created_at_utc, local_offset_minutes, completion_state, answers_json
        FROM pre_sleep_logs
        WHERE session_id IS NULL
        ORDER BY created_at_utc DESC
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        
        var logs: [PreSleepLog] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let log = parsePreSleepLogRow(stmt) {
                logs.append(log)
            }
        }
        
        return logs
    }
    
    /// Fetch most recent pre-sleep log (for "use last answers")
    public func fetchMostRecentPreSleepLog() -> PreSleepLog? {
        let sql = """
        SELECT id, session_id, created_at_utc, local_offset_minutes, completion_state, answers_json
        FROM pre_sleep_logs
        WHERE completion_state = 'complete'
        ORDER BY created_at_utc DESC
        LIMIT 1
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return parsePreSleepLogRow(stmt)
        }
        
        return nil
    }
    
    private func parsePreSleepLogRow(_ stmt: OpaquePointer?) -> PreSleepLog? {
        guard let idPtr = sqlite3_column_text(stmt, 0),
              let createdPtr = sqlite3_column_text(stmt, 2),
              let statePtr = sqlite3_column_text(stmt, 4),
              let answersPtr = sqlite3_column_text(stmt, 5) else {
            return nil
        }
        
        var sessionId: String? = nil
        if let sessionPtr = sqlite3_column_text(stmt, 1) {
            sessionId = String(cString: sessionPtr)
        }
        
        return PreSleepLog(
            id: String(cString: idPtr),
            sessionId: sessionId,
            createdAtUTC: String(cString: createdPtr),
            localOffsetMinutes: Int(sqlite3_column_int(stmt, 3)),
            completionState: String(cString: statePtr),
            answersJson: String(cString: answersPtr)
        )
    }
    
    // MARK: - Session Correlation Queries
    
    /// Fetch complete session data for specialist reports
    public func fetchCompleteSession(forDate sessionDate: String) -> CompleteSessionData? {
        let doseLog = fetchDoseLog(forSession: sessionDate)
        let sleepEvents = fetchSleepEvents(forSession: sessionDate)
        let morningCheckIn = fetchMorningCheckIn(forSession: sessionDate)
        
        // Must have at least dose data
        guard let dose = doseLog else { return nil }
        
        return CompleteSessionData(
            sessionDate: sessionDate,
            doseLog: dose,
            sleepEvents: sleepEvents,
            morningCheckIn: morningCheckIn
        )
    }
    
    /// Fetch wellness score trend
    public func fetchWellnessScoreTrend(days: Int = 30) -> [(date: String, score: Double)] {
        let checkIns = fetchRecentMorningCheckIns(limit: days)
        
        return checkIns.map { checkIn in
            // Calculate wellness score from stored data
            var score = 0.0
            
            // Sleep quality (30%)
            score += Double(checkIn.sleepQuality) / 5.0 * 30
            
            // Mental clarity (20%)
            score += Double(checkIn.mentalClarity) / 10.0 * 20
            
            // Readiness (10%)
            score += Double(checkIn.readinessForDay) / 5.0 * 10
            
            // Deductions
            if checkIn.hasPhysicalSymptoms { score -= 10 }
            if checkIn.hasRespiratorySymptoms { score -= 5 }
            
            // Add 40 base for rested/mood (simplified)
            score += 40
            
            return (checkIn.sessionDate, max(0, min(100, score)))
        }
    }
    
    /// Fetch narcolepsy symptom frequency
    public func fetchNarcolepsySymptomFrequency(days: Int = 30) -> NarcolepsySymptomReport {
        let checkIns = fetchRecentMorningCheckIns(limit: days)
        
        var report = NarcolepsySymptomReport(
            totalNights: checkIns.count,
            sleepParalysisCount: 0,
            hallucinationsCount: 0,
            automaticBehaviorCount: 0,
            fellOutOfBedCount: 0,
            confusionOnWakingCount: 0
        )
        
        for checkIn in checkIns {
            if checkIn.hadSleepParalysis { report.sleepParalysisCount += 1 }
            if checkIn.hadHallucinations { report.hallucinationsCount += 1 }
            if checkIn.hadAutomaticBehavior { report.automaticBehaviorCount += 1 }
            if checkIn.fellOutOfBed { report.fellOutOfBedCount += 1 }
            if checkIn.hadConfusionOnWaking { report.confusionOnWakingCount += 1 }
        }
        
        return report
    }

    // MARK: - History Methods
    
    /// Get session date string for a given date
    public func sessionDateString(for date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        
        let sessionDate: Date
        if hour < 6 {
            sessionDate = calendar.date(byAdding: .day, value: -1, to: date)!
        } else {
            sessionDate = date
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: sessionDate)
    }
    
    /// Fetch dose log for a specific session
    public func fetchDoseLog(forSession sessionDate: String) -> StoredDoseLog? {
        // Query current_session table which has the correct schema
        let sql = """
        SELECT dose1_time, dose2_time, snooze_count, dose2_skipped
        FROM current_session
        WHERE session_date = ?
        LIMIT 1
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            var dose1Time: Date? = nil
            if let d1Text = sqlite3_column_text(stmt, 0) {
                dose1Time = isoFormatter.date(from: String(cString: d1Text))
            }
            
            var dose2Time: Date? = nil
            if let d2Text = sqlite3_column_text(stmt, 1) {
                dose2Time = isoFormatter.date(from: String(cString: d2Text))
            }
            
            let snoozeCount = Int(sqlite3_column_int(stmt, 2))
            let skipped = sqlite3_column_int(stmt, 3) == 1
            
            return StoredDoseLog(
                sessionDate: sessionDate,
                dose1Time: dose1Time ?? Date(),
                dose2Time: dose2Time,
                snoozeCount: snoozeCount,
                skipped: skipped
            )
        }
        
        return nil
    }
    
    /// Fetch recent sessions summary
    /// Note: current_session is a singleton table (id=1 only), so we aggregate from dose_events for history
    public func fetchRecentSessions(days: Int = 7) -> [SessionSummary] {
        // Aggregate sessions from dose_events table, which stores all historical data
        // current_session is a singleton that only holds the current night
        let sql = """
        SELECT 
            d.session_date,
            MAX(CASE WHEN d.event_type = 'dose1' THEN d.timestamp END) as dose1_time,
            MAX(CASE WHEN d.event_type = 'dose2' THEN d.timestamp END) as dose2_time,
            COALESCE(MAX(CASE WHEN d.event_type = 'snooze' THEN 
                CAST(json_extract(d.metadata, '$.count') AS INTEGER) END), 0) as snooze_count,
            MAX(CASE WHEN d.event_type = 'dose2_skipped' THEN 1 ELSE 0 END) as dose2_skipped,
            (SELECT COUNT(*) FROM sleep_events WHERE session_date = d.session_date) as event_count
        FROM dose_events d
        GROUP BY d.session_date
        ORDER BY d.session_date DESC
        LIMIT ?
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("❌ fetchRecentSessions: Failed to prepare statement")
            return []
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int(stmt, 1, Int32(days))
        
        var sessions: [SessionSummary] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let sessionDatePtr = sqlite3_column_text(stmt, 0) else { continue }
            let sessionDate = String(cString: sessionDatePtr)
            
            var dose1Time: Date? = nil
            if let d1Text = sqlite3_column_text(stmt, 1) {
                dose1Time = isoFormatter.date(from: String(cString: d1Text))
            }
            
            var dose2Time: Date? = nil
            if let d2Text = sqlite3_column_text(stmt, 2) {
                dose2Time = isoFormatter.date(from: String(cString: d2Text))
            }
            
            let snoozeCount = Int(sqlite3_column_int(stmt, 3))
            let skipped = sqlite3_column_int(stmt, 4) == 1
            let eventCount = Int(sqlite3_column_int(stmt, 5))
            
            sessions.append(SessionSummary(
                sessionDate: sessionDate,
                dose1Time: dose1Time,
                dose2Time: dose2Time,
                snoozeCount: snoozeCount,
                skipped: skipped,
                eventCount: eventCount
            ))
        }
        
        print("✅ fetchRecentSessions: Found \(sessions.count) sessions")
        return sessions
    }
    
    // MARK: - Delete Methods
    
    /// Delete a specific session and all its events
    public func deleteSession(sessionDate: String) {
        let sql1 = "DELETE FROM sleep_events WHERE session_date = ?"
        let sql2 = "DELETE FROM dose_events WHERE session_date = ?"
        let sql3 = "DELETE FROM current_session WHERE session_date = ?"
        
        var stmt: OpaquePointer?
        
        // Delete sleep events
        if sqlite3_prepare_v2(db, sql1, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        
        // Delete dose events
        if sqlite3_prepare_v2(db, sql2, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        
        // Delete from current_session table
        if sqlite3_prepare_v2(db, sql3, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        
        print("🗑️ Deleted session: \(sessionDate)")
    }
    
    /// Delete a single sleep event by ID
    public func deleteSleepEvent(id: String) {
        let sql = "DELETE FROM sleep_events WHERE id = ?"
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
            print("🗑️ Deleted sleep event: \(id)")
        }
    }
    
    /// Delete the most recent sleep event of a specific type (for undo)
    public func deleteLastSleepEvent(ofType eventType: String) -> Bool {
        // Find the most recent event of this type
        let findSQL = "SELECT id FROM sleep_events WHERE event_type = ? ORDER BY timestamp DESC LIMIT 1"
        var findStmt: OpaquePointer?
        var eventId: String?
        
        if sqlite3_prepare_v2(db, findSQL, -1, &findStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(findStmt, 1, eventType, -1, SQLITE_TRANSIENT)
            if sqlite3_step(findStmt) == SQLITE_ROW {
                if let idPtr = sqlite3_column_text(findStmt, 0) {
                    eventId = String(cString: idPtr)
                }
            }
            sqlite3_finalize(findStmt)
        }
        
        guard let id = eventId else { return false }
        
        // Delete it
        deleteSleepEvent(id: id)
        return true
    }
    
    /// Update a sleep event's timestamp (for editing)
    public func updateSleepEventTimestamp(id: String, newTimestamp: Date) {
        let sql = "UPDATE sleep_events SET timestamp = ? WHERE id = ?"
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let timestampStr = isoFormatter.string(from: newTimestamp)
            sqlite3_bind_text(stmt, 1, timestampStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, id, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
            print("✏️ Updated sleep event timestamp: \(id)")
        }
    }
    
    /// Update a sleep event's notes
    public func updateSleepEventNotes(id: String, notes: String?) {
        let sql = "UPDATE sleep_events SET notes = ? WHERE id = ?"
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            if let notes = notes {
                sqlite3_bind_text(stmt, 1, notes, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 1)
            }
            sqlite3_bind_text(stmt, 2, id, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
            print("✏️ Updated sleep event notes: \(id)")
        }
    }
    
    /// Clear all sleep events (preserves dose logs)
    public func clearAllSleepEvents() {
        let sql = "DELETE FROM sleep_events"
        sqlite3_exec(db, sql, nil, nil, nil)
        print("🗑️ Cleared all sleep events")
    }
    
    /// Clear data older than specified days
    public func clearOldData(olderThanDays days: Int) {
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -days, to: Date()) else { return }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let cutoffString = formatter.string(from: cutoffDate)
        
        let sql1 = "DELETE FROM sleep_events WHERE session_date < ?"
        let sql2 = "DELETE FROM dose_events WHERE session_date < ?"
        let sql3 = "DELETE FROM current_session WHERE session_date < ?"
        
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql1, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, cutoffString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        
        if sqlite3_prepare_v2(db, sql2, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, cutoffString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        
        if sqlite3_prepare_v2(db, sql3, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, cutoffString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        
        print("🗑️ Cleared data older than \(days) days (before \(cutoffString))")
    }
}

// MARK: - Stored Models
public struct StoredSleepEvent: Identifiable {
    public let id: String
    public let eventType: String
    public let timestamp: Date
    public let sessionDate: String
    public let colorHex: String?
    public let notes: String?
}

public struct StoredDoseLog {
    public let sessionDate: String
    public let dose1Time: Date
    public let dose2Time: Date?
    public let snoozeCount: Int
    public let skipped: Bool
}

public struct SessionSummary {
    public let sessionDate: String
    public let dose1Time: Date?
    public let dose2Time: Date?
    public let snoozeCount: Int
    public let skipped: Bool
    public let eventCount: Int
}

// MARK: - Morning Check-In Storage Model
public struct StoredMorningCheckIn {
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
    public let physicalSymptomsJson: String?  // Includes painNotes
    
    // Respiratory symptoms
    public let hasRespiratorySymptoms: Bool
    public let respiratorySymptomsJson: String?  // Includes respiratoryNotes
    
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
    
    // Sleep Therapy (NEW)
    public let usedSleepTherapy: Bool
    public let sleepTherapyJson: String?  // device, compliance, notes
    
    // Notes
    public let notes: String?
    
    /// Computed: any narcolepsy symptoms reported
    public var hasNarcolepsySymptoms: Bool {
        hadSleepParalysis || hadHallucinations || hadAutomaticBehavior || fellOutOfBed || hadConfusionOnWaking
    }
}

// MARK: - Pre-Sleep Log Storage Model
/// Raw storage model for pre-sleep logs (matches SQLite schema)
public struct PreSleepLog {
    public let id: String
    public var sessionId: String?
    public let createdAtUTC: String
    public let localOffsetMinutes: Int
    public let completionState: String  // "partial", "complete", "skipped"
    public let answersJson: String
    
    public init(
        id: String = UUID().uuidString,
        sessionId: String? = nil,
        createdAtUTC: String,
        localOffsetMinutes: Int,
        completionState: String,
        answersJson: String
    ) {
        self.id = id
        self.sessionId = sessionId
        self.createdAtUTC = createdAtUTC
        self.localOffsetMinutes = localOffsetMinutes
        self.completionState = completionState
        self.answersJson = answersJson
    }
    
    /// Create from PreSleepLogAnswers
    public init(answers: PreSleepLogAnswers, completionState: String) {
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        self.id = UUID().uuidString
        self.sessionId = nil
        self.createdAtUTC = formatter.string(from: now)
        self.localOffsetMinutes = TimeZone.current.secondsFromGMT() / 60
        self.completionState = completionState
        
        if let jsonData = try? JSONEncoder().encode(answers),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            self.answersJson = jsonString
        } else {
            self.answersJson = "{}"
        }
    }
    
    /// Decode answers from JSON
    public var answers: PreSleepLogAnswers? {
        guard let data = answersJson.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PreSleepLogAnswers.self, from: data)
    }
    
    /// Check if this is linked to a session
    public var isLinked: Bool {
        sessionId != nil
    }
}

// MARK: - Pre-Sleep Log Answers (Typed Model)
/// Strongly-typed answers for the pre-sleep log questionnaire
public struct PreSleepLogAnswers: Codable {
    // Card 1: Timing + Stress
    public var intendedSleepTime: IntendedSleepTime?
    public var stressLevel: Int?  // 1-5
    public var stressDriver: StressDriver?  // Only if stress >= 4
    
    // Card 2: Body + Substances  
    public var bodyPain: PainLevel?
    public var painLocations: [PainLocation]?  // Only if pain != none
    public var painType: PainType?  // Only if pain != none
    public var stimulants: Stimulants?
    public var alcohol: AlcoholLevel?
    
    // Card 3: Activity + Naps
    public var exercise: ExerciseLevel?
    public var napToday: NapDuration?
    
    // Optional Smart Expander: More Details (user toggles)
    public var laterReason: LaterReason?  // Only if intendedSleepTime == later
    public var lateMeal: LateMeal?
    public var screensInBed: ScreensInBed?
    public var roomTemp: RoomTemp?
    public var noiseLevel: NoiseLevel?
    
    public init() {}
    
    // MARK: - Enums for type-safe answers
    
    public enum IntendedSleepTime: String, Codable, CaseIterable {
        case now = "now"
        case within30 = "within_30"
        case thirtyTo60 = "30_to_60"
        case later = "later"
        
        public var displayText: String {
            switch self {
            case .now: return "Now"
            case .within30: return "Within 30 min"
            case .thirtyTo60: return "30-60 min"
            case .later: return "Later"
            }
        }
    }
    
    public enum StressDriver: String, Codable, CaseIterable {
        case work = "work"
        case family = "family"
        case health = "health"
        case money = "money"
        case other = "other"
        
        public var displayText: String {
            rawValue.capitalized
        }
    }
    
    public enum PainLevel: String, Codable, CaseIterable {
        case none = "none"
        case mild = "mild"
        case moderate = "moderate"
        case severe = "severe"
        
        public var displayText: String {
            rawValue.capitalized
        }
    }
    
    public enum PainLocation: String, Codable, CaseIterable {
        case head = "head"
        case neck = "neck"
        case shoulders = "shoulders"
        case upperBack = "upper_back"
        case lowerBack = "lower_back"
        case hips = "hips"
        case legs = "legs"
        case other = "other"
        
        public var displayText: String {
            switch self {
            case .upperBack: return "Upper Back"
            case .lowerBack: return "Lower Back"
            default: return rawValue.capitalized
            }
        }
    }
    
    public enum PainType: String, Codable, CaseIterable {
        case aching = "aching"
        case sharp = "sharp"
        case throbbing = "throbbing"
        case burning = "burning"
        case tingling = "tingling"
        
        public var displayText: String {
            rawValue.capitalized
        }
    }
    
    public enum Stimulants: String, Codable, CaseIterable {
        case none = "none"
        case caffeine = "caffeine"
        case nicotine = "nicotine"
        case both = "both"
        
        public var displayText: String {
            switch self {
            case .none: return "None"
            case .caffeine: return "Caffeine"
            case .nicotine: return "Nicotine"
            case .both: return "Both"
            }
        }
    }
    
    public enum AlcoholLevel: String, Codable, CaseIterable {
        case none = "none"
        case oneToTwo = "1_to_2"
        case threePlus = "3_plus"
        
        public var displayText: String {
            switch self {
            case .none: return "None"
            case .oneToTwo: return "1-2 drinks"
            case .threePlus: return "3+ drinks"
            }
        }
    }
    
    public enum ExerciseLevel: String, Codable, CaseIterable {
        case none = "none"
        case light = "light"
        case moderate = "moderate"
        case hard = "hard"
        
        public var displayText: String {
            rawValue.capitalized
        }
    }
    
    public enum NapDuration: String, Codable, CaseIterable {
        case none = "none"
        case short = "short"  // < 30 min
        case medium = "medium"  // 30-90 min
        case long = "long"  // 90+ min
        
        public var displayText: String {
            switch self {
            case .none: return "None"
            case .short: return "Short (<30 min)"
            case .medium: return "Medium (30-90 min)"
            case .long: return "Long (90+ min)"
            }
        }
    }
    
    public enum LaterReason: String, Codable, CaseIterable {
        case social = "social"
        case work = "work"
        case screenTime = "screen_time"
        case restless = "restless"
        case other = "other"
        
        public var displayText: String {
            switch self {
            case .screenTime: return "Screen Time"
            default: return rawValue.capitalized
            }
        }
    }
    
    public enum LateMeal: String, Codable, CaseIterable {
        case none = "none"
        case within2Hours = "within_2_hours"
        case within1Hour = "within_1_hour"
        
        public var displayText: String {
            switch self {
            case .none: return "None"
            case .within2Hours: return "Within 2 hours"
            case .within1Hour: return "Within 1 hour"
            }
        }
    }
    
    public enum ScreensInBed: String, Codable, CaseIterable {
        case none = "none"
        case some = "some"
        case aLot = "a_lot"
        
        public var displayText: String {
            switch self {
            case .none: return "None"
            case .some: return "Some"
            case .aLot: return "A lot"
            }
        }
    }
    
    public enum RoomTemp: String, Codable, CaseIterable {
        case cool = "cool"
        case ok = "ok"
        case warm = "warm"
        
        public var displayText: String {
            switch self {
            case .cool: return "Cool"
            case .ok: return "OK"
            case .warm: return "Warm"
            }
        }
    }
    
    public enum NoiseLevel: String, Codable, CaseIterable {
        case quiet = "quiet"
        case some = "some"
        case loud = "loud"
        
        public var displayText: String {
            rawValue.capitalized
        }
    }
}

// MARK: - Complete Session Data (for specialist reports)
public struct CompleteSessionData {
    public let sessionDate: String
    public let doseLog: StoredDoseLog
    public let sleepEvents: [StoredSleepEvent]
    public let morningCheckIn: StoredMorningCheckIn?
    
    /// Calculate interval between doses
    public var doseInterval: TimeInterval? {
        guard let dose2Time = doseLog.dose2Time else { return nil }
        return dose2Time.timeIntervalSince(doseLog.dose1Time)
    }
    
    /// Format dose interval as "Xh Ym"
    public var formattedDoseInterval: String? {
        guard let interval = doseInterval else { return nil }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}

// MARK: - Narcolepsy Symptom Report
public struct NarcolepsySymptomReport {
    public var totalNights: Int
    public var sleepParalysisCount: Int
    public var hallucinationsCount: Int
    public var automaticBehaviorCount: Int
    public var fellOutOfBedCount: Int
    public var confusionOnWakingCount: Int
    
    /// Percentage of nights with any symptom
    public var symptomNightsPercentage: Double {
        guard totalNights > 0 else { return 0 }
        let symptomatic = sleepParalysisCount + hallucinationsCount + automaticBehaviorCount + fellOutOfBedCount + confusionOnWakingCount
        return Double(symptomatic) / Double(totalNights * 5) * 100
    }
}

// MARK: - Color Extension
import SwiftUI

extension Color {
    /// Convert Color to hex string
    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components else { return nil }
        
        let r = Int(components[0] * 255)
        let g = Int(components.count > 1 ? components[1] * 255 : components[0] * 255)
        let b = Int(components.count > 2 ? components[2] * 255 : components[0] * 255)
        
        return String(format: "#%02X%02X%02X", r, g, b)
    }
    
    /// Create Color from hex string
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        guard hexSanitized.count == 6 else { return nil }
        
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255
        let g = Double((rgb & 0x00FF00) >> 8) / 255
        let b = Double(rgb & 0x0000FF) / 255
        
        self.init(red: r, green: g, blue: b)
    }
}
