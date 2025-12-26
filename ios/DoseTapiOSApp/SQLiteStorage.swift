// ⛔️ DISABLED: SQLiteStorage is banned. Use SessionRepository.shared → EventStorage.
// This file is wrapped in #if false to prevent compilation errors from @available(*, unavailable).
// See docs/SSOT/README.md for the unified storage architecture.
// CI enforces: grep -R "SQLiteStorage" ios | grep -v SQLiteStorage.swift must return empty.

#if false
import Foundation
import Combine
import SQLite3
#if canImport(DoseCore)
import DoseCore
#endif

// MARK: - SQLite Storage Manager
/// Single-user SQLite database for persisting dose tracking data
/// ⛔️ UNAVAILABLE: Use EventStorage (via SessionRepository) instead.
/// This class is kept for reference only. All production code must use
/// SessionRepository → EventStorage (EventStore protocol).
/// See docs/SSOT/README.md for the unified storage architecture.
///
/// CI enforces this: `grep -R "SQLiteStorage" ios | grep -v SQLiteStorage.swift` must return empty.
@available(*, unavailable, message: "SQLiteStorage is banned. Use SessionRepository.shared which routes to EventStorage.")
@MainActor
public class SQLiteStorage: ObservableObject {
    public static let shared = SQLiteStorage()
    
    private var db: OpaquePointer?
    private let dbPath: String
    private var nowProvider: () -> Date = { Date() }
    private var timeZoneProvider: () -> TimeZone = { TimeZone.current }
    
    // Published state for UI binding
    @Published public private(set) var isReady: Bool = false
    @Published public private(set) var lastError: String?
    
    private init() {
        // Store in Documents directory for persistence
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dbPath = documentsPath.appendingPathComponent("dosetap.sqlite").path
        
        openDatabase()
        createTables()
        isReady = true
        
        print("SQLite database initialized at: \(dbPath)")
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    // MARK: - Database Setup
    
    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            lastError = "Failed to open database: \(String(cString: sqlite3_errmsg(db)))"
            print(lastError!)
        }
    }
    
    private func createTables() {
        let createSQL = """
        -- Current night session state
        CREATE TABLE IF NOT EXISTS current_session (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            dose1_time TEXT,
            dose2_time TEXT,
            snooze_count INTEGER DEFAULT 0,
            dose2_skipped INTEGER DEFAULT 0,
            session_date TEXT NOT NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        );
        
        -- Historical dose events
        CREATE TABLE IF NOT EXISTS dose_events (
            id TEXT PRIMARY KEY,
            event_type TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            session_date TEXT NOT NULL,
            metadata TEXT,
            synced INTEGER DEFAULT 0,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        );
        
        -- User configuration
        CREATE TABLE IF NOT EXISTS user_config (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        );
        
        -- Create indexes for common queries
        CREATE INDEX IF NOT EXISTS idx_events_session ON dose_events(session_date);
        CREATE INDEX IF NOT EXISTS idx_events_type ON dose_events(event_type);
        CREATE INDEX IF NOT EXISTS idx_events_timestamp ON dose_events(timestamp);
        
        -- Sleep events (bathroom, lights_out, wake_final, etc.)
        CREATE TABLE IF NOT EXISTS sleep_events (
            id TEXT PRIMARY KEY,
            event_type TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            session_id TEXT,
            notes TEXT,
            source TEXT DEFAULT 'manual',
            synced INTEGER DEFAULT 0,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        );
        
        -- Create indexes for sleep events
        CREATE INDEX IF NOT EXISTS idx_sleep_events_session ON sleep_events(session_id);
        CREATE INDEX IF NOT EXISTS idx_sleep_events_type ON sleep_events(event_type);
        CREATE INDEX IF NOT EXISTS idx_sleep_events_timestamp ON sleep_events(timestamp);
        
        -- Morning check-in data
        CREATE TABLE IF NOT EXISTS morning_checkins (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            session_date TEXT NOT NULL,
            sleep_quality INTEGER NOT NULL,
            feel_rested TEXT NOT NULL,
            grogginess TEXT NOT NULL,
            sleep_inertia_duration TEXT NOT NULL,
            dream_recall TEXT,
            has_physical_symptoms INTEGER DEFAULT 0,
            physical_symptoms_json TEXT,
            has_respiratory_symptoms INTEGER DEFAULT 0,
            respiratory_symptoms_json TEXT,
            mental_clarity INTEGER,
            mood TEXT,
            anxiety_level TEXT,
            readiness_for_day INTEGER,
            had_sleep_paralysis INTEGER DEFAULT 0,
            had_hallucinations INTEGER DEFAULT 0,
            had_automatic_behavior INTEGER DEFAULT 0,
            fell_out_of_bed INTEGER DEFAULT 0,
            had_confusion_on_waking INTEGER DEFAULT 0,
            used_sleep_therapy INTEGER DEFAULT 0,
            sleep_therapy_json TEXT,
            notes TEXT,
            synced INTEGER DEFAULT 0,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        );
        
        -- Create indexes for morning checkins
        CREATE INDEX IF NOT EXISTS idx_morning_checkins_session ON morning_checkins(session_id);
        CREATE INDEX IF NOT EXISTS idx_morning_checkins_date ON morning_checkins(session_date);
        
        -- Medication events (Adderall, etc.) - local-only, session-linked
        CREATE TABLE IF NOT EXISTS medication_events (
            id TEXT PRIMARY KEY,
            session_id TEXT,
            session_date TEXT NOT NULL,
            medication_id TEXT NOT NULL,
            dose_mg INTEGER NOT NULL,
            dose_unit TEXT NOT NULL DEFAULT 'mg',
            formulation TEXT NOT NULL DEFAULT 'IR',
            taken_at_utc TEXT NOT NULL,
            local_offset_minutes INTEGER DEFAULT 0,
            notes TEXT,
            confirmed_duplicate INTEGER DEFAULT 0,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (session_id) REFERENCES current_session(id) ON DELETE CASCADE
        );
        
        -- Create indexes for medication events
        CREATE INDEX IF NOT EXISTS idx_medication_events_session ON medication_events(session_id);
        CREATE INDEX IF NOT EXISTS idx_medication_events_session_date ON medication_events(session_date);
        CREATE INDEX IF NOT EXISTS idx_medication_events_medication ON medication_events(medication_id);
        CREATE INDEX IF NOT EXISTS idx_medication_events_taken_at ON medication_events(taken_at_utc);
        """
        
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, createSQL, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                lastError = "Failed to create tables: \(String(cString: errMsg))"
                print(lastError!)
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
            "ALTER TABLE morning_checkins ADD COLUMN used_sleep_therapy INTEGER DEFAULT 0",
            "ALTER TABLE morning_checkins ADD COLUMN sleep_therapy_json TEXT",
            // P0: Session terminal state - distinguishes: completed, skipped, expired, aborted
            "ALTER TABLE current_session ADD COLUMN terminal_state TEXT",
            // Sleep Environment feature - captures sleep setup and aids for Morning Check-in
            "ALTER TABLE morning_checkins ADD COLUMN has_sleep_environment INTEGER DEFAULT 0",
            "ALTER TABLE morning_checkins ADD COLUMN sleep_environment_json TEXT",
            // Medication entry updates
            "ALTER TABLE medication_events ADD COLUMN dose_unit TEXT DEFAULT 'mg'",
            "ALTER TABLE medication_events ADD COLUMN formulation TEXT DEFAULT 'IR'",
            "ALTER TABLE medication_events ADD COLUMN local_offset_minutes INTEGER DEFAULT 0"
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

    public func setNowProvider(_ provider: @escaping () -> Date) {
        nowProvider = provider
    }

    public func setTimeZoneProvider(_ provider: @escaping () -> TimeZone) {
        timeZoneProvider = provider
    }
    
    // MARK: - Current Session (Tonight's Dose Tracking)
    
    /// Get current session date (tonight)
    private func currentSessionDate() -> String {
        let now = nowProvider()
        #if canImport(DoseCore)
        return sessionKey(for: now, timeZone: timeZoneProvider(), rolloverHour: 18)
        #else
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now)
        #endif
    }
    
    /// Load current session state
    public func loadCurrentSession() -> (dose1Time: Date?, dose2Time: Date?, snoozeCount: Int, dose2Skipped: Bool)? {
        let sessionDate = currentSessionDate()
        let sql = "SELECT dose1_time, dose2_time, snooze_count, dose2_skipped FROM current_session WHERE session_date = ? LIMIT 1"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            let dose1Time = getDateFromColumn(stmt, column: 0)
            let dose2Time = getDateFromColumn(stmt, column: 1)
            let snoozeCount = Int(sqlite3_column_int(stmt, 2))
            let dose2Skipped = sqlite3_column_int(stmt, 3) != 0
            
            return (dose1Time, dose2Time, snoozeCount, dose2Skipped)
        }
        
        return nil
    }
    
    /// Save/update current session
    public func saveCurrentSession(dose1Time: Date?, dose2Time: Date?, snoozeCount: Int, dose2Skipped: Bool) {
        let sessionDate = currentSessionDate()
        
        // Use UPSERT (INSERT OR REPLACE)
        let sql = """
        INSERT OR REPLACE INTO current_session (id, dose1_time, dose2_time, snooze_count, dose2_skipped, session_date, updated_at)
        VALUES (1, ?, ?, ?, ?, ?, datetime('now'))
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            lastError = "Failed to prepare save statement"
            return
        }
        defer { sqlite3_finalize(stmt) }
        
        bindDateToColumn(stmt, column: 1, date: dose1Time)
        bindDateToColumn(stmt, column: 2, date: dose2Time)
        sqlite3_bind_int(stmt, 3, Int32(snoozeCount))
        sqlite3_bind_int(stmt, 4, dose2Skipped ? 1 : 0)
        sqlite3_bind_text(stmt, 5, sessionDate, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) != SQLITE_DONE {
            lastError = "Failed to save session: \(String(cString: sqlite3_errmsg(db)))"
        }
    }
    
    // MARK: - Dose Events
    
    /// Log a dose event
    public func logEvent(id: UUID = UUID(), type: String, timestamp: Date, metadata: [String: String]? = nil) {
        let sessionDate = currentSessionDate()
        let sql = "INSERT INTO dose_events (id, event_type, timestamp, session_date, metadata) VALUES (?, ?, ?, ?, ?)"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            lastError = "Failed to prepare event statement"
            return
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, type, -1, SQLITE_TRANSIENT)
        bindDateToColumn(stmt, column: 3, date: timestamp)
        sqlite3_bind_text(stmt, 4, sessionDate, -1, SQLITE_TRANSIENT)
        
        if let metadata = metadata {
            let jsonData = try? JSONSerialization.data(withJSONObject: metadata)
            let jsonString = jsonData.flatMap { String(data: $0, encoding: .utf8) }
            sqlite3_bind_text(stmt, 5, jsonString, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        
        if sqlite3_step(stmt) != SQLITE_DONE {
            lastError = "Failed to log event: \(String(cString: sqlite3_errmsg(db)))"
        }
    }
    
    /// Log a dose event for a specific session date (used by integration tests/importers)
    public func logEvent(sessionDate: String, id: UUID = UUID(), type: String, timestamp: Date, metadata: [String: String]? = nil) {
        let sql = "INSERT INTO dose_events (id, event_type, timestamp, session_date, metadata) VALUES (?, ?, ?, ?, ?)"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            lastError = "Failed to prepare event statement"
            return
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, type, -1, SQLITE_TRANSIENT)
        bindDateToColumn(stmt, column: 3, date: timestamp)
        sqlite3_bind_text(stmt, 4, sessionDate, -1, SQLITE_TRANSIENT)
        
        if let metadata = metadata {
            let jsonData = try? JSONSerialization.data(withJSONObject: metadata)
            let jsonString = jsonData.flatMap { String(data: $0, encoding: .utf8) }
            sqlite3_bind_text(stmt, 5, jsonString, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        
        if sqlite3_step(stmt) != SQLITE_DONE {
            lastError = "Failed to log event: \(String(cString: sqlite3_errmsg(db)))"
        }
    }
    
    /// Get events for current session
    public func getEventsForCurrentSession() -> [SQLiteStoredDoseEvent] {
        return getEvents(forSessionDate: currentSessionDate())
    }
    
    /// Get events for a specific session date
    public func getEvents(forSessionDate sessionDate: String) -> [SQLiteStoredDoseEvent] {
        let sql = "SELECT id, event_type, timestamp, metadata FROM dose_events WHERE session_date = ? ORDER BY timestamp DESC"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
        
        var events: [SQLiteStoredDoseEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let eventType = String(cString: sqlite3_column_text(stmt, 1))
            let timestamp = getDateFromColumn(stmt, column: 2) ?? Date()
            
            var metadata: [String: String]?
            if let metadataText = sqlite3_column_text(stmt, 3) {
                let jsonString = String(cString: metadataText)
                if let data = jsonString.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                    metadata = dict
                }
            }
            
            events.append(SQLiteStoredDoseEvent(id: id, eventType: eventType, timestamp: timestamp, metadata: metadata))
        }
        
        return events
    }
    
    /// Get all events (for history/export)
    public func getAllEvents(limit: Int = 1000) -> [SQLiteStoredDoseEvent] {
        let sql = "SELECT id, event_type, timestamp, session_date, metadata FROM dose_events ORDER BY timestamp DESC LIMIT ?"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int(stmt, 1, Int32(limit))
        
        var events: [SQLiteStoredDoseEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let eventType = String(cString: sqlite3_column_text(stmt, 1))
            let timestamp = getDateFromColumn(stmt, column: 2) ?? Date()
            
            events.append(SQLiteStoredDoseEvent(id: id, eventType: eventType, timestamp: timestamp, metadata: nil))
        }
        
        return events
    }
    
    // MARK: - User Configuration
    
    public func setConfig(key: String, value: String) {
        let sql = "INSERT OR REPLACE INTO user_config (key, value, updated_at) VALUES (?, ?, datetime('now'))"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, value, -1, SQLITE_TRANSIENT)
        
        sqlite3_step(stmt)
    }
    
    public func getConfig(key: String) -> String? {
        let sql = "SELECT value FROM user_config WHERE key = ?"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return String(cString: sqlite3_column_text(stmt, 0))
        }
        return nil
    }
    
    // MARK: - Statistics
    
    public func getStatistics() -> DoseStatistics {
        var stats = DoseStatistics()
        
        // Total nights tracked
        let countSQL = "SELECT COUNT(DISTINCT session_date) FROM dose_events WHERE event_type = 'dose1'"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, countSQL, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                stats.totalNights = Int(sqlite3_column_int(stmt, 0))
            }
            sqlite3_finalize(stmt)
        }
        
        // Dose 2 completion rate
        let completionSQL = """
        SELECT 
            COUNT(DISTINCT d1.session_date) as dose1_count,
            COUNT(DISTINCT d2.session_date) as dose2_count
        FROM dose_events d1
        LEFT JOIN dose_events d2 ON d1.session_date = d2.session_date AND d2.event_type = 'dose2'
        WHERE d1.event_type = 'dose1'
        """
        if sqlite3_prepare_v2(db, completionSQL, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                let dose1Count = Int(sqlite3_column_int(stmt, 0))
                let dose2Count = Int(sqlite3_column_int(stmt, 1))
                if dose1Count > 0 {
                    stats.completionRate = Double(dose2Count) / Double(dose1Count) * 100
                }
            }
            sqlite3_finalize(stmt)
        }
        
        // Average interval (minutes between dose1 and dose2)
        let intervalSQL = """
        SELECT AVG((julianday(d2.timestamp) - julianday(d1.timestamp)) * 24 * 60) as avg_interval
        FROM dose_events d1
        JOIN dose_events d2 ON d1.session_date = d2.session_date
        WHERE d1.event_type = 'dose1' AND d2.event_type = 'dose2'
        """
        if sqlite3_prepare_v2(db, intervalSQL, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_type(stmt, 0) != SQLITE_NULL {
                stats.averageIntervalMinutes = sqlite3_column_double(stmt, 0)
            }
            sqlite3_finalize(stmt)
        }
        
        return stats
    }
    
    // MARK: - Data Management
    
    /// Clear all data (for testing or reset)
    public func clearAllData() {
        let sql = """
        DELETE FROM current_session;
        DELETE FROM dose_events;
        DELETE FROM user_config;
        DELETE FROM sleep_events;
        DELETE FROM morning_checkins;
        """
        
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                lastError = "Failed to clear data: \(String(cString: errMsg))"
                sqlite3_free(errMsg)
            }
        }
        
        print("✅ SQLiteStorage: Cleared all data from all tables")
    }
    
    /// Clear only sleep events (preserves dose events and settings)
    public func clearSleepEvents() {
        let sql = "DELETE FROM sleep_events;"
        
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                lastError = "Failed to clear sleep events: \(String(cString: errMsg))"
                sqlite3_free(errMsg)
            }
        }
        
        print("✅ SQLiteStorage: Cleared sleep_events table")
    }
    
    /// Clear only morning check-ins (preserves other data)
    public func clearMorningCheckIns() {
        let sql = "DELETE FROM morning_checkins;"
        
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                lastError = "Failed to clear morning check-ins: \(String(cString: errMsg))"
                sqlite3_free(errMsg)
            }
        }
        
        print("✅ SQLiteStorage: Cleared morning_checkins table")
    }
    
    /// Delete a session by date string (yyyy-MM-dd format)
    /// This deletes all dose_events for that session_date and associated sleep events
    /// P0-4 FIX: Wrapped in transaction to ensure atomic deletion
    public func deleteSession(date: Date) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let sessionDate = dateFormatter.string(from: date)
        
        // Begin transaction for atomic deletion
        if sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil) != SQLITE_OK {
            lastError = "Failed to begin transaction for session deletion"
            return
        }
        
        var success = true
        var stmt: OpaquePointer?
        
        // Delete dose events for this session
        let deleteDosesSQL = "DELETE FROM dose_events WHERE session_date = ?"
        
        if sqlite3_prepare_v2(db, deleteDosesSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) != SQLITE_DONE {
                lastError = "Failed to delete dose events for session \(sessionDate)"
                success = false
            }
            sqlite3_finalize(stmt)
        } else {
            success = false
        }
        
        // Delete sleep events by matching timestamp within the session date range
        // Sleep events don't have session_date, so we delete by timestamp range using 6PM rollover
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZoneProvider()
        let startOfSession = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: date) ?? date
        let endOfSession = calendar.date(byAdding: .day, value: 1, to: startOfSession) ?? startOfSession
        
        let deleteSleepSQL = "DELETE FROM sleep_events WHERE timestamp >= ? AND timestamp < ?"
        
        if success && sqlite3_prepare_v2(db, deleteSleepSQL, -1, &stmt, nil) == SQLITE_OK {
            bindDateToColumn(stmt, column: 1, date: startOfSession)
            bindDateToColumn(stmt, column: 2, date: endOfSession)
            if sqlite3_step(stmt) != SQLITE_DONE {
                lastError = "Failed to delete sleep events for session \(sessionDate)"
                success = false
            }
            sqlite3_finalize(stmt)
        }
        
        // Delete morning check-ins for this session
        let deleteCheckInsSQL = "DELETE FROM morning_checkins WHERE session_date = ?"
        
        if success && sqlite3_prepare_v2(db, deleteCheckInsSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) != SQLITE_DONE {
                lastError = "Failed to delete morning check-ins for session \(sessionDate)"
                success = false
            }
            sqlite3_finalize(stmt)
        }
        
        // Commit or rollback transaction
        if success {
            if sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK {
                print("✅ SQLiteStorage: Deleted session for \(sessionDate) (transaction committed)")
            } else {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                lastError = "Failed to commit session deletion transaction"
                print("❌ SQLiteStorage: Failed to commit deletion for \(sessionDate)")
            }
        } else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            print("❌ SQLiteStorage: Rolled back deletion for \(sessionDate) due to error")
        }
    }
    
    /// Export data as CSV
    public func exportToCSV() -> String {
        var csv = "session_date,event_type,timestamp\n"
        
        let sql = "SELECT session_date, event_type, timestamp FROM dose_events ORDER BY timestamp"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return csv }
        defer { sqlite3_finalize(stmt) }
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let sessionDate = String(cString: sqlite3_column_text(stmt, 0))
            let eventType = String(cString: sqlite3_column_text(stmt, 1))
            let timestamp = String(cString: sqlite3_column_text(stmt, 2))
            csv += "\(sessionDate),\(eventType),\(timestamp)\n"
        }
        
        return csv
    }
    
    /// Get database file size
    public func getDatabaseSize() -> String {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: dbPath)
            let size = attrs[.size] as? Int64 ?? 0
            return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        } catch {
            return "Unknown"
        }
    }
    
    // MARK: - Legacy Fetch/Insert
    
    public func fetchEvents(limit: Int) -> [SQLiteEventRecord] {
        let sql = "SELECT event_type, timestamp, metadata FROM dose_events ORDER BY timestamp DESC LIMIT ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int(stmt, 1, Int32(limit))
        
        var results: [SQLiteEventRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let type = String(cString: sqlite3_column_text(stmt, 0))
            let timestamp = getDateFromColumn(stmt, column: 1) ?? Date()
            let metadata: String?
            if sqlite3_column_type(stmt, 2) != SQLITE_NULL {
                metadata = String(cString: sqlite3_column_text(stmt, 2))
            } else {
                metadata = nil
            }
            results.append(SQLiteEventRecord(type: type, timestamp: timestamp, metadata: metadata))
        }
        return results
    }
    
    public func insertEvent(_ record: SQLiteEventRecord) {
        let sql = "INSERT INTO dose_events (id, event_type, timestamp, session_date, metadata) VALUES (?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        
        let id = UUID().uuidString
        let sessionDate = isoFormatter.string(from: record.timestamp).prefix(10) // Simple day string
        
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, record.type, -1, SQLITE_TRANSIENT)
        bindDateToColumn(stmt, column: 3, date: record.timestamp)
        sqlite3_bind_text(stmt, 4, String(sessionDate), -1, SQLITE_TRANSIENT)
        if let meta = record.metadata {
            sqlite3_bind_text(stmt, 5, meta, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        sqlite3_step(stmt)
    }

    // MARK: - Helper Methods
    
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    private func bindDateToColumn(_ stmt: OpaquePointer?, column: Int32, date: Date?) {
        if let date = date {
            let dateString = isoFormatter.string(from: date)
            sqlite3_bind_text(stmt, column, dateString, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, column)
        }
    }
    
    private func getDateFromColumn(_ stmt: OpaquePointer?, column: Int32) -> Date? {
        guard sqlite3_column_type(stmt, column) != SQLITE_NULL,
              let text = sqlite3_column_text(stmt, column) else {
            return nil
        }
        let dateString = String(cString: text)
        return isoFormatter.date(from: dateString)
    }
    
    // MARK: - Sleep Events
    
    /// Insert a sleep event
    public func insertSleepEvent(_ event: SQLiteStoredSleepEvent) {
        let sql = """
        INSERT INTO sleep_events (id, event_type, timestamp, session_id, notes, source)
        VALUES (?, ?, ?, ?, ?, ?)
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            lastError = "Failed to prepare sleep event insert"
            return
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, event.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, event.eventType, -1, SQLITE_TRANSIENT)
        bindDateToColumn(stmt, column: 3, date: event.timestamp)
        
        if let sessionId = event.sessionId {
            sqlite3_bind_text(stmt, 4, sessionId, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        
        if let notes = event.notes {
            sqlite3_bind_text(stmt, 5, notes, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        
        sqlite3_bind_text(stmt, 6, event.source, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) != SQLITE_DONE {
            lastError = "Failed to insert sleep event: \(String(cString: sqlite3_errmsg(db)))"
        }
    }
    
    /// Convenience method to insert from SleepEvent model
    #if canImport(DoseCore)
    public func insertSleepEvent(_ event: SleepEvent) {
        insertSleepEvent(SQLiteStoredSleepEvent(
            id: event.id.uuidString,
            eventType: event.type.rawValue,
            timestamp: event.timestamp,
            sessionId: event.sessionId?.uuidString,
            notes: event.notes,
            source: event.source.rawValue
        ))
    }
    #endif
    
    /// Fetch sleep events for a session
    public func fetchSleepEvents(sessionId: String) -> [SQLiteStoredSleepEvent] {
        let sql = """
        SELECT id, event_type, timestamp, session_id, notes, source
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
        
        var events: [SQLiteStoredSleepEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            events.append(parseSleepEventRow(stmt))
        }
        
        return events
    }
    
    /// Fetch sleep events within a date range
    public func fetchSleepEvents(from startDate: Date, to endDate: Date) -> [SQLiteStoredSleepEvent] {
        let sql = """
        SELECT id, event_type, timestamp, session_id, notes, source
        FROM sleep_events
        WHERE timestamp BETWEEN ? AND ?
        ORDER BY timestamp DESC
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        
        bindDateToColumn(stmt, column: 1, date: startDate)
        bindDateToColumn(stmt, column: 2, date: endDate)
        
        var events: [SQLiteStoredSleepEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            events.append(parseSleepEventRow(stmt))
        }
        
        return events
    }
    
    /// Fetch all sleep events (for history/export)
    public func fetchAllSleepEvents(limit: Int = 500) -> [SQLiteStoredSleepEvent] {
        let sql = """
        SELECT id, event_type, timestamp, session_id, notes, source
        FROM sleep_events
        ORDER BY timestamp DESC
        LIMIT ?
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int(stmt, 1, Int32(limit))
        
        var events: [SQLiteStoredSleepEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            events.append(parseSleepEventRow(stmt))
        }
        
        return events
    }
    
    /// Fetch sleep events for tonight's session (using 6PM rollover boundary)
    /// This is the canonical method for getting current session's events.
    public func fetchTonightSleepEvents() -> [SQLiteStoredSleepEvent] {
        let sessionDate = currentSessionDate()
        return fetchSleepEvents(forSessionId: sessionDate)
    }
    
    /// Fetch sleep events for a specific session ID/date
    public func fetchSleepEvents(forSessionId sessionId: String) -> [SQLiteStoredSleepEvent] {
        let sql = """
        SELECT id, event_type, timestamp, session_id, notes, source
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
        
        var events: [SQLiteStoredSleepEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            events.append(parseSleepEventRow(stmt))
        }
        
        return events
    }
    
    /// Count events by type for a session
    public func sleepEventCounts(sessionId: String) -> [String: Int] {
        let sql = """
        SELECT event_type, COUNT(*) as count
        FROM sleep_events
        WHERE session_id = ?
        GROUP BY event_type
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return [:]
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, sessionId, -1, SQLITE_TRANSIENT)
        
        var counts: [String: Int] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let eventType = String(cString: sqlite3_column_text(stmt, 0))
            let count = Int(sqlite3_column_int(stmt, 1))
            counts[eventType] = count
        }
        
        return counts
    }
    
    /// Delete a sleep event by ID
    public func deleteSleepEvent(id: String) {
        let sql = "DELETE FROM sleep_events WHERE id = ?"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }
    
    /// Get last event of a specific type (for checking cooldowns on app restart)
    public func lastSleepEvent(ofType eventType: String) -> SQLiteStoredSleepEvent? {
        let sql = """
        SELECT id, event_type, timestamp, session_id, notes, source
        FROM sleep_events
        WHERE event_type = ?
        ORDER BY timestamp DESC
        LIMIT 1
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, eventType, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return parseSleepEventRow(stmt)
        }
        return nil
    }
    
    /// Helper to parse sleep event row
    private func parseSleepEventRow(_ stmt: OpaquePointer?) -> SQLiteStoredSleepEvent {
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let eventType = String(cString: sqlite3_column_text(stmt, 1))
        let timestamp = getDateFromColumn(stmt, column: 2) ?? Date()
        
        var sessionId: String?
        if sqlite3_column_type(stmt, 3) != SQLITE_NULL {
            sessionId = String(cString: sqlite3_column_text(stmt, 3))
        }
        
        var notes: String?
        if sqlite3_column_type(stmt, 4) != SQLITE_NULL {
            notes = String(cString: sqlite3_column_text(stmt, 4))
        }
        
        let source = String(cString: sqlite3_column_text(stmt, 5))
        
        return SQLiteStoredSleepEvent(
            id: id,
            eventType: eventType,
            timestamp: timestamp,
            sessionId: sessionId,
            notes: notes,
            source: source
        )
    }
    
    /// Export sleep events to CSV
    public func exportSleepEventsToCSV() -> String {
        var csv = "id,event_type,timestamp,session_id,notes,source\n"
        
        let sql = "SELECT id, event_type, timestamp, session_id, notes, source FROM sleep_events ORDER BY timestamp"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return csv }
        defer { sqlite3_finalize(stmt) }
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let event = parseSleepEventRow(stmt)
            let escapedNotes = (event.notes ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\(event.id),\(event.eventType),\(isoFormatter.string(from: event.timestamp)),\(event.sessionId ?? ""),\"\(escapedNotes)\",\(event.source)\n"
        }
        
        return csv
    }
    
    // MARK: - Medication Events
    
    /// Insert a medication event (Adderall, etc.)
    public func insertMedicationEvent(_ entry: SQLiteStoredMedicationEntry) {
        let sql = """
        INSERT INTO medication_events (
            id, session_id, session_date, medication_id, dose_mg, dose_unit, formulation,
            taken_at_utc, local_offset_minutes, notes, confirmed_duplicate
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            lastError = "Failed to prepare medication event insert"
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
        sqlite3_bind_text(stmt, 6, entry.doseUnit, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 7, entry.formulation, -1, SQLITE_TRANSIENT)
        bindDateToColumn(stmt, column: 8, date: entry.takenAtUTC)
        sqlite3_bind_int(stmt, 9, Int32(entry.localOffsetMinutes))
        
        if let notes = entry.notes {
            sqlite3_bind_text(stmt, 10, notes, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 10)
        }
        
        sqlite3_bind_int(stmt, 11, entry.confirmedDuplicate ? 1 : 0)
        
        if sqlite3_step(stmt) != SQLITE_DONE {
            lastError = "Failed to insert medication event: \(String(cString: sqlite3_errmsg(db)))"
        }
    }
    
    /// Fetch medication events for a session date
    public func fetchMedicationEvents(sessionDate: String) -> [SQLiteStoredMedicationEntry] {
        let sql = """
        SELECT id, session_id, session_date, medication_id, dose_mg, dose_unit, formulation, taken_at_utc, local_offset_minutes, notes, confirmed_duplicate, created_at
        FROM medication_events
        WHERE session_date = ?
        ORDER BY taken_at_utc DESC
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
        
        var entries: [SQLiteStoredMedicationEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            entries.append(parseMedicationEventRow(stmt))
        }
        
        return entries
    }
    
    /// Fetch all medication events (for export)
    public func fetchAllMedicationEvents(limit: Int = 1000) -> [SQLiteStoredMedicationEntry] {
        let sql = """
        SELECT id, session_id, session_date, medication_id, dose_mg, dose_unit, formulation, taken_at_utc, local_offset_minutes, notes, confirmed_duplicate, created_at
        FROM medication_events
        ORDER BY taken_at_utc DESC
        LIMIT ?
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int(stmt, 1, Int32(limit))
        
        var entries: [SQLiteStoredMedicationEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            entries.append(parseMedicationEventRow(stmt))
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
            lastError = "Failed to delete medication event"
        }
    }
    
    /// Check for duplicate medication entry within guard window (used for duplicate guard)
    public func findRecentMedicationEntry(medicationId: String, sessionDate: String, withinMinutes: Int, ofTime takenAt: Date) -> SQLiteStoredMedicationEntry? {
        // Fetch all entries for this medication + session_date, check time delta in Swift
        // (SQLite datetime math is tricky across timezones)
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
    
    /// Parse a medication event row
    private func parseMedicationEventRow(_ stmt: OpaquePointer?) -> SQLiteStoredMedicationEntry {
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
        let doseUnit = String(cString: sqlite3_column_text(stmt, 5))
        let formulation = String(cString: sqlite3_column_text(stmt, 6))
        let takenAtUTC = getDateFromColumn(stmt, column: 7) ?? Date()
        let localOffsetMinutes = Int(sqlite3_column_int(stmt, 8))
        
        let notes: String?
        if sqlite3_column_type(stmt, 9) != SQLITE_NULL {
            notes = String(cString: sqlite3_column_text(stmt, 9))
        } else {
            notes = nil
        }
        
        let confirmedDuplicate = sqlite3_column_int(stmt, 10) == 1
        let createdAt = getDateFromColumn(stmt, column: 11) ?? Date()
        
        return SQLiteStoredMedicationEntry(
            id: id,
            sessionId: sessionId,
            sessionDate: sessionDate,
            medicationId: medicationId,
            doseMg: doseMg,
            takenAtUTC: takenAtUTC,
            doseUnit: doseUnit,
            formulation: formulation,
            localOffsetMinutes: localOffsetMinutes,
            notes: notes,
            confirmedDuplicate: confirmedDuplicate,
            createdAt: createdAt
        )
    }
    
    /// Export medication events to CSV
    public func exportMedicationEventsToCSV() -> String {
        var csv = "id,session_id,session_date,medication_id,dose_mg,dose_unit,formulation,taken_at_utc,local_offset_minutes,notes,confirmed_duplicate,created_at\n"
        
        let sql = """
        SELECT id, session_id, session_date, medication_id, dose_mg, dose_unit, formulation, taken_at_utc, local_offset_minutes, notes, confirmed_duplicate, created_at
        FROM medication_events
        ORDER BY taken_at_utc DESC
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return csv }
        defer { sqlite3_finalize(stmt) }
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let entry = parseMedicationEventRow(stmt)
            let escapedNotes = (entry.notes ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\(entry.id),\(entry.sessionId ?? ""),\(entry.sessionDate),\(entry.medicationId),\(entry.doseMg),\(entry.doseUnit),\(entry.formulation),\(isoFormatter.string(from: entry.takenAtUTC)),\(entry.localOffsetMinutes),\"\(escapedNotes)\",\(entry.confirmedDuplicate ? 1 : 0),\(isoFormatter.string(from: entry.createdAt))\n"
        }
        
        return csv
    }
    
    // MARK: - Morning Check-In
    
    /// Save morning check-in data
    public func saveMorningCheckIn(_ checkIn: SQLiteStoredMorningCheckIn) {
        let sessionDate = currentSessionDate()
        
        let sql = """
        INSERT OR REPLACE INTO morning_checkins (
            id, session_id, timestamp, session_date, sleep_quality, feel_rested,
            grogginess, sleep_inertia_duration, dream_recall, has_physical_symptoms,
            physical_symptoms_json, has_respiratory_symptoms, respiratory_symptoms_json,
            mental_clarity, mood, anxiety_level, readiness_for_day, had_sleep_paralysis,
            had_hallucinations, had_automatic_behavior, fell_out_of_bed,
            had_confusion_on_waking, used_sleep_therapy, sleep_therapy_json, notes
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            lastError = "Failed to prepare morning check-in insert"
            return
        }
        defer { sqlite3_finalize(stmt) }
        
        let timestamp = isoFormatter.string(from: checkIn.timestamp)
        
        sqlite3_bind_text(stmt, 1, checkIn.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, checkIn.sessionId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, timestamp, -1, SQLITE_TRANSIENT)
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
        
        if sqlite3_step(stmt) != SQLITE_DONE {
            lastError = "Failed to save morning check-in: \(String(cString: sqlite3_errmsg(db)))"
            print(lastError!)
        } else {
            print("Morning check-in saved for session: \(checkIn.sessionId)")
        }
    }
    
    /// Fetch morning check-in for a session
    public func fetchMorningCheckIn(sessionDate: String) -> SQLiteStoredMorningCheckIn? {
        let sql = "SELECT * FROM morning_checkins WHERE session_date = ? ORDER BY timestamp DESC LIMIT 1"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        
        return parseMorningCheckInRow(stmt)
    }
    
    /// Parse a morning check-in row from SQLite
    private func parseMorningCheckInRow(_ stmt: OpaquePointer?) -> SQLiteStoredMorningCheckIn? {
        guard let stmt = stmt else { return nil }
        
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let sessionId = String(cString: sqlite3_column_text(stmt, 1))
        let timestampStr = String(cString: sqlite3_column_text(stmt, 2))
        let sessionDate = String(cString: sqlite3_column_text(stmt, 3))
        let sleepQuality = Int(sqlite3_column_int(stmt, 4))
        let feelRested = String(cString: sqlite3_column_text(stmt, 5))
        let grogginess = String(cString: sqlite3_column_text(stmt, 6))
        let sleepInertiaDuration = String(cString: sqlite3_column_text(stmt, 7))
        
        var dreamRecall: String = ""
        if sqlite3_column_type(stmt, 8) != SQLITE_NULL {
            dreamRecall = String(cString: sqlite3_column_text(stmt, 8))
        }
        
        let hasPhysicalSymptoms = sqlite3_column_int(stmt, 9) != 0
        var physicalSymptomsJson: String?
        if sqlite3_column_type(stmt, 10) != SQLITE_NULL {
            physicalSymptomsJson = String(cString: sqlite3_column_text(stmt, 10))
        }
        
        let hasRespiratorySymptoms = sqlite3_column_int(stmt, 11) != 0
        var respiratorySymptomsJson: String?
        if sqlite3_column_type(stmt, 12) != SQLITE_NULL {
            respiratorySymptomsJson = String(cString: sqlite3_column_text(stmt, 12))
        }
        
        let mentalClarity = Int(sqlite3_column_int(stmt, 13))
        let mood = String(cString: sqlite3_column_text(stmt, 14))
        let anxietyLevel = String(cString: sqlite3_column_text(stmt, 15))
        let readinessForDay = Int(sqlite3_column_int(stmt, 16))
        
        let hadSleepParalysis = sqlite3_column_int(stmt, 17) != 0
        let hadHallucinations = sqlite3_column_int(stmt, 18) != 0
        let hadAutomaticBehavior = sqlite3_column_int(stmt, 19) != 0
        let fellOutOfBed = sqlite3_column_int(stmt, 20) != 0
        let hadConfusionOnWaking = sqlite3_column_int(stmt, 21) != 0
        
        // Sleep Therapy (NEW)
        let usedSleepTherapy = sqlite3_column_int(stmt, 22) != 0
        var sleepTherapyJson: String?
        if sqlite3_column_type(stmt, 23) != SQLITE_NULL {
            sleepTherapyJson = String(cString: sqlite3_column_text(stmt, 23))
        }
        
        // Notes (column 24)
        var notes: String?
        if sqlite3_column_type(stmt, 24) != SQLITE_NULL {
            notes = String(cString: sqlite3_column_text(stmt, 24))
        }
        
        guard let timestamp = isoFormatter.date(from: timestampStr) else { return nil }
        
        return SQLiteStoredMorningCheckIn(
            id: id,
            sessionId: sessionId,
            timestamp: timestamp,
            sessionDate: sessionDate,
            sleepQuality: sleepQuality,
            feelRested: feelRested,
            grogginess: grogginess,
            sleepInertiaDuration: sleepInertiaDuration,
            dreamRecall: dreamRecall,
            hasPhysicalSymptoms: hasPhysicalSymptoms,
            physicalSymptomsJson: physicalSymptomsJson,
            hasRespiratorySymptoms: hasRespiratorySymptoms,
            respiratorySymptomsJson: respiratorySymptomsJson,
            mentalClarity: mentalClarity,
            mood: mood,
            anxietyLevel: anxietyLevel,
            readinessForDay: readinessForDay,
            hadSleepParalysis: hadSleepParalysis,
            hadHallucinations: hadHallucinations,
            hadAutomaticBehavior: hadAutomaticBehavior,
            fellOutOfBed: fellOutOfBed,
            hadConfusionOnWaking: hadConfusionOnWaking,
            usedSleepTherapy: usedSleepTherapy,
            sleepTherapyJson: sleepTherapyJson,
            notes: notes
        )
    }
}

// MARK: - Supporting Types

public struct SQLiteStoredDoseEvent: Identifiable {
    public let id: String
    public let eventType: String
    public let timestamp: Date
    public let metadata: [String: String]?
}

public struct SQLiteStoredSleepEvent: Identifiable {
    public let id: String
    public let eventType: String
    public let timestamp: Date
    public let sessionId: String?
    public let notes: String?
    public let source: String
    
    public init(id: String, eventType: String, timestamp: Date, sessionId: String? = nil, notes: String? = nil, source: String = "manual") {
        self.id = id
        self.eventType = eventType
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.notes = notes
        self.source = source
    }
}

public struct DoseStatistics {
    public var totalNights: Int = 0
    public var completionRate: Double = 0.0
    public var averageIntervalMinutes: Double = 0.0
    
    public var averageIntervalFormatted: String {
        let hours = Int(averageIntervalMinutes) / 60
        let minutes = Int(averageIntervalMinutes) % 60
        return "\(hours)h \(minutes)m"
    }
}

// MARK: - Medication Entry Storage Model


// SQLite transient constant
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
#endif // #if false - SQLiteStorage banned
