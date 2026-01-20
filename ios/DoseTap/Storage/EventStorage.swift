import Foundation
import Combine
import SQLite3
import DoseCore

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
    private var nowProvider: () -> Date = { Date() }
    private var timeZoneProvider: () -> TimeZone = { TimeZone.current }
    
    // ISO8601 formatter for date serialization
    private let isoFormatter: ISO8601DateFormatter = {
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
        
        // Enable foreign key enforcement (required for CASCADE to work)
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA foreign_keys = ON", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    /// Check if foreign keys are enabled (for test assertions)
    public func isForeignKeysEnabled() -> Bool {
        var stmt: OpaquePointer?
        var enabled = false
        if sqlite3_prepare_v2(db, "PRAGMA foreign_keys", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                enabled = sqlite3_column_int(stmt, 0) == 1
            }
        }
        sqlite3_finalize(stmt)
        return enabled
    }
    
    private func createTables() {
        let createSQL = """
        -- Sleep events table
        CREATE TABLE IF NOT EXISTS sleep_events (
            id TEXT PRIMARY KEY,
            event_type TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            session_date TEXT NOT NULL,
            session_id TEXT,
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
            session_id TEXT,
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
            session_id TEXT,
            session_start_utc TEXT,
            session_end_utc TEXT,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        );
        
        -- Sleep session metadata (non-calendar lifecycle)
        CREATE TABLE IF NOT EXISTS sleep_sessions (
            session_id TEXT PRIMARY KEY,
            session_date TEXT NOT NULL,
            start_utc TEXT NOT NULL,
            end_utc TEXT,
            terminal_state TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
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
        CREATE INDEX IF NOT EXISTS idx_sleep_events_session_type ON sleep_events(session_date, event_type);
        CREATE INDEX IF NOT EXISTS idx_sleep_events_session_id ON sleep_events(session_id);
        CREATE INDEX IF NOT EXISTS idx_dose_events_session ON dose_events(session_date);
        CREATE INDEX IF NOT EXISTS idx_dose_events_session_type ON dose_events(session_date, event_type);
        CREATE INDEX IF NOT EXISTS idx_dose_events_session_id ON dose_events(session_id);
        CREATE INDEX IF NOT EXISTS idx_morning_checkins_session ON morning_checkins(session_date);
        CREATE INDEX IF NOT EXISTS idx_morning_checkins_session_id ON morning_checkins(session_id);
        CREATE INDEX IF NOT EXISTS idx_pre_sleep_logs_session_id ON pre_sleep_logs(session_id);
        CREATE INDEX IF NOT EXISTS idx_sleep_sessions_date ON sleep_sessions(session_date);
        
        -- Medication events (Adderall, etc.) - local-only, session-linked
        CREATE TABLE IF NOT EXISTS medication_events (
            id TEXT PRIMARY KEY,
            session_id TEXT,
            session_date TEXT NOT NULL,
            medication_id TEXT NOT NULL,
            dose_mg INTEGER NOT NULL,
            dose_unit TEXT NOT NULL DEFAULT 'mg',
            formulation TEXT NOT NULL DEFAULT 'ir',
            taken_at_utc TEXT NOT NULL,
            local_offset_minutes INTEGER NOT NULL DEFAULT 0,
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
        migrateEventTypesIfNeeded()
        migrateSessionIdsToUUIDIfNeeded()
        deduplicateLegacyEntriesIfNeeded()
    }
    
    /// Add new columns if they don't exist (safe migration)
    private func migrateDatabase() {
        let migrations = [
            // Morning check-in sleep therapy columns
            "ALTER TABLE morning_checkins ADD COLUMN used_sleep_therapy INTEGER NOT NULL DEFAULT 0",
            "ALTER TABLE morning_checkins ADD COLUMN sleep_therapy_json TEXT",
            // P0: Session terminal state - distinguishes: completed, skipped, expired, aborted
            "ALTER TABLE current_session ADD COLUMN terminal_state TEXT",
            // Session lifecycle metadata (non-calendar)
            "ALTER TABLE current_session ADD COLUMN session_id TEXT",
            "ALTER TABLE current_session ADD COLUMN session_start_utc TEXT",
            "ALTER TABLE current_session ADD COLUMN session_end_utc TEXT",
            // Session identity on events
            "ALTER TABLE sleep_events ADD COLUMN session_id TEXT",
            "ALTER TABLE dose_events ADD COLUMN session_id TEXT",
            // Sleep Environment feature - captures sleep setup and aids for Morning Check-in
            "ALTER TABLE morning_checkins ADD COLUMN has_sleep_environment INTEGER NOT NULL DEFAULT 0",
            "ALTER TABLE morning_checkins ADD COLUMN sleep_environment_json TEXT",
            // Dose 3 Hazard Safety: Add hazard flag to dose_events
            "ALTER TABLE dose_events ADD COLUMN is_hazard INTEGER DEFAULT 0",
            // Medication events schema v2: Add missing columns
            "ALTER TABLE medication_events ADD COLUMN dose_unit TEXT NOT NULL DEFAULT 'mg'",
            "ALTER TABLE medication_events ADD COLUMN formulation TEXT NOT NULL DEFAULT 'ir'",
            "ALTER TABLE medication_events ADD COLUMN local_offset_minutes INTEGER NOT NULL DEFAULT 0"
        ]
        
        for sql in migrations {
            var errMsg: UnsafeMutablePointer<CChar>?
            // Ignore errors (column already exists)
            sqlite3_exec(db, sql, nil, nil, &errMsg)
            if errMsg != nil {
                sqlite3_free(errMsg)
            }
        }
        
        // Backfill NULL session_id values (P0 data integrity fix)
        backfillNullSessionIds()
    }

    // MARK: - Event Type Normalization Migration

    private func migrateEventTypesIfNeeded() {
        let flagKey = "event_types_normalized_v1"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }

        let updates = [
            // Lights out
            "UPDATE sleep_events SET event_type = 'lights_out' WHERE lower(event_type) IN ('lights out', 'lightsout', 'lights_out', 'lightout')",
            // Brief wake
            "UPDATE sleep_events SET event_type = 'brief_wake' WHERE lower(event_type) IN ('brief wake', 'briefwake', 'brief_wake')",
            // In bed
            "UPDATE sleep_events SET event_type = 'in_bed' WHERE lower(event_type) IN ('in bed', 'inbed', 'in_bed')",
            // Heart racing
            "UPDATE sleep_events SET event_type = 'heart_racing' WHERE lower(event_type) IN ('heart racing', 'heartracing', 'heart_racing')",
            // Nap start/end
            "UPDATE sleep_events SET event_type = 'nap_start' WHERE lower(event_type) IN ('nap start', 'napstart', 'nap_start')",
            "UPDATE sleep_events SET event_type = 'nap_end' WHERE lower(event_type) IN ('nap end', 'napend', 'nap_end')",
            // Wake final variants
            "UPDATE sleep_events SET event_type = 'wake_final' WHERE lower(event_type) IN ('wake final', 'wakefinal', 'wake_final', 'wake up', 'wakeup')",
            // Common canonical lowercase for simple types
            "UPDATE sleep_events SET event_type = lower(event_type) WHERE lower(event_type) IN ('bathroom','water','snack','pain','anxiety','noise','dream','temperature')"
        ]

        let deleteDoseEvents = """
        DELETE FROM sleep_events
        WHERE lower(event_type) IN (
            'dose 1','dose1','dose_1','dose1_taken',
            'dose 2','dose2','dose_2','dose2_taken',
            'dose 2 (early)','dose2 (early)','dose2_early',
            'dose 2 (late)','dose2 (late)','dose2_late',
            'dose 2 skipped','dose2 skipped','dose2_skipped','dose2skipped',
            'extra dose','extra_dose'
        )
        """

        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        for sql in updates {
            sqlite3_exec(db, sql, nil, nil, nil)
        }
        sqlite3_exec(db, deleteDoseEvents, nil, nil, nil)
        sqlite3_exec(db, "COMMIT", nil, nil, nil)

        UserDefaults.standard.set(true, forKey: flagKey)
        print("🔧 EventStorage: Normalized sleep_events types and purged dose rows")
    }

    // MARK: - Session ID UUID Migration

    private func migrateSessionIdsToUUIDIfNeeded() {
        let flagKey = "session_id_uuid_migration_v1"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }

        let legacyIds = fetchLegacySessionIds()
        guard !legacyIds.isEmpty else {
            UserDefaults.standard.set(true, forKey: flagKey)
            return
        }

        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        for legacyId in legacyIds {
            let newId = deterministicSessionUUID(for: legacyId)
            if legacyId == newId { continue }
            updateSessionId(in: "dose_events", oldId: legacyId, newId: newId)
            updateSessionId(in: "sleep_events", oldId: legacyId, newId: newId)
            updateSessionId(in: "sleep_sessions", oldId: legacyId, newId: newId)
            updateSessionId(in: "current_session", oldId: legacyId, newId: newId)
            updateSessionId(in: "morning_checkins", oldId: legacyId, newId: newId)
            updateSessionId(in: "pre_sleep_logs", oldId: legacyId, newId: newId)
            updateSessionId(in: "medication_events", oldId: legacyId, newId: newId)
        }
        sqlite3_exec(db, "COMMIT", nil, nil, nil)

        UserDefaults.standard.set(true, forKey: flagKey)
        print("🔧 EventStorage: Migrated \(legacyIds.count) legacy session IDs to UUIDs")
    }

    private func fetchLegacySessionIds() -> [String] {
        let sql = """
        SELECT DISTINCT session_id FROM dose_events WHERE session_id IS NOT NULL
        UNION SELECT DISTINCT session_id FROM sleep_events WHERE session_id IS NOT NULL
        UNION SELECT DISTINCT session_id FROM sleep_sessions WHERE session_id IS NOT NULL
        UNION SELECT DISTINCT session_id FROM current_session WHERE session_id IS NOT NULL
        UNION SELECT DISTINCT session_id FROM morning_checkins WHERE session_id IS NOT NULL
        UNION SELECT DISTINCT session_id FROM pre_sleep_logs WHERE session_id IS NOT NULL
        UNION SELECT DISTINCT session_id FROM medication_events WHERE session_id IS NOT NULL
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var results: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let valuePtr = sqlite3_column_text(stmt, 0) else { continue }
            let value = String(cString: valuePtr)
            if isLegacySessionKey(value) {
                results.append(value)
            }
        }
        return results
    }

    private func isLegacySessionKey(_ value: String) -> Bool {
        guard value.count == 10 else { return false }
        let chars = Array(value)
        guard chars[4] == "-", chars[7] == "-" else { return false }
        let digitIndices = [0, 1, 2, 3, 5, 6, 8, 9]
        return digitIndices.allSatisfy { chars[$0].isNumber }
    }

    private func updateSessionId(in table: String, oldId: String, newId: String) {
        let sql = "UPDATE \(table) SET session_id = ? WHERE session_id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, newId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, oldId, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    // MARK: - Deduplication

    private func deduplicateLegacyEntriesIfNeeded() {
        let flagKey = "event_deduplication_v1"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }

        let statements = [
            """
            DELETE FROM dose_events
            WHERE rowid NOT IN (
                SELECT MIN(rowid)
                FROM dose_events
                GROUP BY event_type, session_id, SUBSTR(timestamp, 1, 22)
            )
            """,
            """
            DELETE FROM sleep_events
            WHERE rowid NOT IN (
                SELECT MIN(rowid)
                FROM sleep_events
                GROUP BY event_type, session_id, SUBSTR(timestamp, 1, 22)
            )
            """
        ]

        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        for sql in statements {
            sqlite3_exec(db, sql, nil, nil, nil)
        }
        sqlite3_exec(db, "COMMIT", nil, nil, nil)

        UserDefaults.standard.set(true, forKey: flagKey)
        print("🔧 EventStorage: Deduplicated legacy dose/sleep events")
    }
    
    // MARK: - Session ID Backfill Migration
    
    /// Backfill NULL session_id values using canonical SessionKey from timestamps.
    /// This is idempotent - safe to run multiple times.
    /// Fixes the "I logged it and it vanished" bug class by ensuring all rows have session_id.
    public func backfillNullSessionIds() {
        backfillPreSleepLogSessionIds()
        backfillMedicationEventSessionIds()
        backfillDoseEventSessionIds()
        backfillSleepEventSessionIds()
        backfillCurrentSessionIdIfNeeded()
    }
    
    /// Backfill pre_sleep_logs.session_id from created_at_utc
    private func backfillPreSleepLogSessionIds() {
        let selectSQL = "SELECT id, created_at_utc, local_offset_minutes FROM pre_sleep_logs WHERE session_id IS NULL"
        var selectStmt: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(selectStmt) }
        
        var rowsToUpdate: [(id: String, sessionKey: String)] = []
        
        while sqlite3_step(selectStmt) == SQLITE_ROW {
            guard let idPtr = sqlite3_column_text(selectStmt, 0),
                  let timestampPtr = sqlite3_column_text(selectStmt, 1) else { continue }
            
            let id = String(cString: idPtr)
            let timestampStr = String(cString: timestampPtr)
            let offsetMinutes = Int(sqlite3_column_int(selectStmt, 2))
            
            // Parse ISO8601 timestamp and compute session key
            if let date = parseISO8601(timestampStr) {
                // Use the local timezone that was stored with the record
                let tz = TimeZone(secondsFromGMT: offsetMinutes * 60) ?? TimeZone.current
                let key = sessionKey(for: date, timeZone: tz, rolloverHour: 18)
                rowsToUpdate.append((id: id, sessionKey: key))
            }
        }
        
        // Update rows
        let updateSQL = "UPDATE pre_sleep_logs SET session_id = ? WHERE id = ?"
        var updateStmt: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(updateStmt) }
        
        for row in rowsToUpdate {
            sqlite3_reset(updateStmt)
            sqlite3_bind_text(updateStmt, 1, row.sessionKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(updateStmt, 2, row.id, -1, SQLITE_TRANSIENT)
            sqlite3_step(updateStmt)
        }
        
        if !rowsToUpdate.isEmpty {
            print("✅ EventStorage: Backfilled \(rowsToUpdate.count) pre_sleep_logs with session_id")
        }
    }
    
    /// Backfill medication_events.session_id from taken_at_utc
    private func backfillMedicationEventSessionIds() {
        let selectSQL = "SELECT id, taken_at_utc, local_offset_minutes FROM medication_events WHERE session_id IS NULL"
        var selectStmt: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(selectStmt) }
        
        var rowsToUpdate: [(id: String, sessionKey: String)] = []
        
        while sqlite3_step(selectStmt) == SQLITE_ROW {
            guard let idPtr = sqlite3_column_text(selectStmt, 0),
                  let timestampPtr = sqlite3_column_text(selectStmt, 1) else { continue }
            
            let id = String(cString: idPtr)
            let timestampStr = String(cString: timestampPtr)
            let offsetMinutes = Int(sqlite3_column_int(selectStmt, 2))
            
            // Parse ISO8601 timestamp and compute session key
            if let date = parseISO8601(timestampStr) {
                let tz = TimeZone(secondsFromGMT: offsetMinutes * 60) ?? TimeZone.current
                let key = sessionKey(for: date, timeZone: tz, rolloverHour: 18)
                rowsToUpdate.append((id: id, sessionKey: key))
            }
        }
        
        // Update rows
        let updateSQL = "UPDATE medication_events SET session_id = ? WHERE id = ?"
        var updateStmt: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(updateStmt) }
        
        for row in rowsToUpdate {
            sqlite3_reset(updateStmt)
            sqlite3_bind_text(updateStmt, 1, row.sessionKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(updateStmt, 2, row.id, -1, SQLITE_TRANSIENT)
            sqlite3_step(updateStmt)
        }
        
        if !rowsToUpdate.isEmpty {
            print("✅ EventStorage: Backfilled \(rowsToUpdate.count) medication_events with session_id")
        }
    }

    /// Backfill dose_events.session_id from session_date
    private func backfillDoseEventSessionIds() {
        let selectSQL = "SELECT id, session_date FROM dose_events WHERE session_id IS NULL"
        var selectStmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(selectStmt) }

        var rowsToUpdate: [(id: String, sessionId: String)] = []

        while sqlite3_step(selectStmt) == SQLITE_ROW {
            guard let idPtr = sqlite3_column_text(selectStmt, 0),
                  let sessionPtr = sqlite3_column_text(selectStmt, 1) else { continue }
            let id = String(cString: idPtr)
            let sessionId = String(cString: sessionPtr)
            rowsToUpdate.append((id, sessionId))
        }

        let updateSQL = "UPDATE dose_events SET session_id = ? WHERE id = ?"
        var updateStmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(updateStmt) }

        for row in rowsToUpdate {
            sqlite3_reset(updateStmt)
            sqlite3_bind_text(updateStmt, 1, row.sessionId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(updateStmt, 2, row.id, -1, SQLITE_TRANSIENT)
            sqlite3_step(updateStmt)
        }

        if !rowsToUpdate.isEmpty {
            print("✅ EventStorage: Backfilled \(rowsToUpdate.count) dose_events with session_id")
        }
    }

    /// Backfill sleep_events.session_id from session_date
    private func backfillSleepEventSessionIds() {
        let selectSQL = "SELECT id, session_date FROM sleep_events WHERE session_id IS NULL"
        var selectStmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(selectStmt) }

        var rowsToUpdate: [(id: String, sessionId: String)] = []

        while sqlite3_step(selectStmt) == SQLITE_ROW {
            guard let idPtr = sqlite3_column_text(selectStmt, 0),
                  let sessionPtr = sqlite3_column_text(selectStmt, 1) else { continue }
            let id = String(cString: idPtr)
            let sessionId = String(cString: sessionPtr)
            rowsToUpdate.append((id, sessionId))
        }

        let updateSQL = "UPDATE sleep_events SET session_id = ? WHERE id = ?"
        var updateStmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(updateStmt) }

        for row in rowsToUpdate {
            sqlite3_reset(updateStmt)
            sqlite3_bind_text(updateStmt, 1, row.sessionId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(updateStmt, 2, row.id, -1, SQLITE_TRANSIENT)
            sqlite3_step(updateStmt)
        }

        if !rowsToUpdate.isEmpty {
            print("✅ EventStorage: Backfilled \(rowsToUpdate.count) sleep_events with session_id")
        }
    }

    /// Ensure current_session has a session_id when legacy data exists
    private func backfillCurrentSessionIdIfNeeded() {
        let selectSQL = "SELECT session_id, session_date FROM current_session WHERE id = 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            let sessionId = sqlite3_column_text(stmt, 0).map { String(cString: $0) }
            let sessionDate = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
            guard sessionId == nil, let fallback = sessionDate else { return }

            let updateSQL = "UPDATE current_session SET session_id = ? WHERE id = 1"
            var updateStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(updateStmt, 1, fallback, -1, SQLITE_TRANSIENT)
                sqlite3_step(updateStmt)
                sqlite3_finalize(updateStmt)
                print("✅ EventStorage: Backfilled current_session.session_id with \(fallback)")
            }
        }
    }
    
    /// Parse ISO8601 date string
    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
    
    // MARK: - Diagnostic: Count NULL session_id rows
    
    /// Returns count of rows with NULL session_id (for support bundle / diagnostics)
    public func countNullSessionIdRows() -> (preSleepLogs: Int, medicationEvents: Int) {
        var preSleepCount = 0
        var medicationCount = 0
        
        let sql1 = "SELECT COUNT(*) FROM pre_sleep_logs WHERE session_id IS NULL"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql1, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                preSleepCount = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        
        let sql2 = "SELECT COUNT(*) FROM medication_events WHERE session_id IS NULL"
        if sqlite3_prepare_v2(db, sql2, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                medicationCount = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        
        return (preSleepCount, medicationCount)
    }

    /// Override the clock for testing or coordinated time updates.
    public func setNowProvider(_ provider: @escaping () -> Date) {
        nowProvider = provider
    }

    /// Override timezone provider for deterministic behavior.
    public func setTimeZoneProvider(_ provider: @escaping () -> TimeZone) {
        timeZoneProvider = provider
    }
    
    // MARK: - Session Date Calculation
    
    /// Get current session date (tonight)
    /// A "night" starts at 6 PM and ends at 5:59 PM next day (aligns with DoseWindowCalculator)
    public func currentSessionDate() -> String {
        let identity = SessionIdentity(date: nowProvider(), timeZone: timeZoneProvider(), rolloverHour: 18)
        return identity.key
    }
    
    /// Get all distinct session dates from the database
    /// Returns array of session date strings in descending order (newest first)
    public func getAllSessionDates() -> [String] {
        var dates: [String] = []
        
        // Query distinct session dates from current_session, dose_events, and sleep_events
        let sql = """
        SELECT DISTINCT session_date FROM current_session
        UNION
        SELECT DISTINCT session_date FROM dose_events
        UNION
        SELECT DISTINCT session_date FROM sleep_events
        ORDER BY session_date DESC
        """
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cString = sqlite3_column_text(stmt, 0) {
                    dates.append(String(cString: cString))
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return dates
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
            print("❌ Failed to prepare insert statement")
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
        print("✅ Sleep event saved: \(eventType) at \(timestampStr)")
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
        
        print("↩️ EventStorage: Cleared dose1 for session \(sessionDate)")
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
        
        print("↩️ EventStorage: Cleared dose2 for session \(sessionDate)")
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
        
        print("↩️ EventStorage: Cleared skip for session \(sessionDate)")
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
        
        print("✏️ EventStorage: Updated dose1 time to \(timestampStr) for session \(sessionDate)")
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
        
        print("✏️ EventStorage: Updated dose2 time to \(timestampStr) for session \(sessionDate)")
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
        
        print("✏️ EventStorage: Updated event \(eventId) time to \(timestampStr)")
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
    private func updateCurrentSession(
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
            print("🧹 EventStorage: Reset stale current_session for new session_date \(sessionDate)")
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
            print("❌ Failed to prepare terminal state update")
            return
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, state, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, sessionId ?? sessionDate, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_DONE {
            print("✅ Terminal state updated to '\(state)' for session \(sessionDate)")
        } else {
            print("❌ Failed to update terminal state: \(String(cString: sqlite3_errmsg(db)))")
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
        guard let data = try? JSONEncoder().encode(answers),
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
                return StoredPreSleepLog(
                    id: existing.id,
                    sessionId: updatedSessionId,
                    createdAtUtc: existing.createdAtUtc,
                    localOffsetMinutes: existing.localOffsetMinutes,
                    completionState: completionState,
                    answers: answers
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
        
        return StoredPreSleepLog(
            id: id,
            sessionId: sessionId,
            createdAtUtc: createdAtUtc,
            localOffsetMinutes: localOffsetMinutes,
            completionState: completionState,
            answers: answers
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
            print("✅ Pre-sleep log saved")
        } catch {
            print("❌ Failed to save pre-sleep log: \(error.localizedDescription)")
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
        let tables = ["sleep_events", "dose_events", "current_session", "sleep_sessions", "pre_sleep_logs", "morning_checkins", "medication_events"]
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
    
    /// Fetch row count for a table filtered by session_date (for test assertions)
    /// Returns 0 if table doesn't exist or query fails
    public func fetchRowCount(table: String, sessionDate: String) -> Int {
        // Sanitize table name to prevent SQL injection (only allow known tables)
        let allowedTables = ["sleep_events", "dose_events", "current_session", "sleep_sessions", "pre_sleep_logs", "morning_checkins", "medication_events"]
        guard allowedTables.contains(table) else {
            print("⚠️ fetchRowCount: Unknown table '\(table)'")
            return 0
        }
        
        let sql = "SELECT COUNT(*) FROM \(table) WHERE session_date = ?"
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
        print("🗑️ All sleep events cleared")
    }
    
    /// Clear data older than specified days
    public func clearOldData(olderThanDays days: Int) {
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -days, to: Date()) else { return }
        let cutoffStr = sessionDateString(for: cutoffDate)
        
        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        
        let tables = ["sleep_events", "dose_events", "sleep_sessions", "pre_sleep_logs", "morning_checkins", "medication_events"]
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
        
        let tables = ["sleep_events", "dose_events", "sleep_sessions", "pre_sleep_logs", "morning_checkins", "medication_events"]
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
    public func clearTonightsEvents(sessionDateOverride: String? = nil) {
        let sessionDate = sessionDateOverride ?? currentSessionDate()
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
    }

    /// Legacy helper for EventStore protocol (session key only).
    public func linkPreSleepLogToSession(sessionKey: String) {
        linkPreSleepLogToSession(sessionId: sessionKey, sessionDate: sessionKey)
    }
    
    /// Fetch recent sessions as summaries (internal - use protocol method externally)
    func fetchRecentSessionsLocal(days: Int = 7) -> [SessionSummary] {
        var sessions: [SessionSummary] = []
        var sessionDates = Set<String>()
        
        // Step 1: Get session dates from sleep_sessions table (most comprehensive)
        let sleepSessionsSql = """
            SELECT DISTINCT session_date FROM sleep_sessions
            ORDER BY session_date DESC
            LIMIT ?
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sleepSessionsSql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(days * 2)) // Get more to account for duplicates
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let datePtr = sqlite3_column_text(stmt, 0) {
                    sessionDates.insert(String(cString: datePtr))
                }
            }
            sqlite3_finalize(stmt)
        }
        
        // Step 2: Also get dates from dose_events (in case sleep_sessions is incomplete)
        let doseEventsSql = """
            SELECT DISTINCT session_date FROM dose_events
            ORDER BY session_date DESC
            LIMIT ?
        """
        if sqlite3_prepare_v2(db, doseEventsSql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(days * 2))
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let datePtr = sqlite3_column_text(stmt, 0) {
                    sessionDates.insert(String(cString: datePtr))
                }
            }
            sqlite3_finalize(stmt)
        }
        
        // Step 3: Also include current_session date
        let currentSessionSql = "SELECT session_date FROM current_session LIMIT 1"
        if sqlite3_prepare_v2(db, currentSessionSql, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                if let datePtr = sqlite3_column_text(stmt, 0) {
                    sessionDates.insert(String(cString: datePtr))
                }
            }
            sqlite3_finalize(stmt)
        }
        
        // Step 4: For each session date, aggregate dose data from dose_events
        let sortedDates = sessionDates.sorted().reversed().prefix(days)
        
        for sessionDate in sortedDates {
            var dose1Time: Date? = nil
            var dose2Time: Date? = nil
            var dose2Skipped = false
            var snoozeCount = 0
            
            // Get dose times from dose_events
            let dosesSql = """
                SELECT event_type, timestamp, metadata FROM dose_events
                WHERE session_date = ?
                ORDER BY timestamp ASC
            """
            if sqlite3_prepare_v2(db, dosesSql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let typePtr = sqlite3_column_text(stmt, 0),
                          let timestampPtr = sqlite3_column_text(stmt, 1) else { continue }
                    let eventType = String(cString: typePtr)
                    let timestamp = isoFormatter.date(from: String(cString: timestampPtr))
                    
                    switch eventType {
                    case "dose1":
                        if dose1Time == nil { dose1Time = timestamp }
                    case "dose2":
                        if dose2Time == nil { dose2Time = timestamp }
                    case "dose2_skipped":
                        dose2Skipped = true
                    case "snooze":
                        snoozeCount += 1
                    default:
                        break
                    }
                }
                sqlite3_finalize(stmt)
            }
            
            // Get event count from sleep_events
            var eventCount = 0
            let eventCountSql = "SELECT COUNT(*) FROM sleep_events WHERE session_date = ?"
            if sqlite3_prepare_v2(db, eventCountSql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    eventCount = Int(sqlite3_column_int(stmt, 0))
                }
                sqlite3_finalize(stmt)
            }
            
            sessions.append(SessionSummary(
                sessionDate: sessionDate,
                dose1Time: dose1Time,
                dose2Time: dose2Time,
                dose2Skipped: dose2Skipped,
                snoozeCount: snoozeCount,
                sleepEvents: [],
                eventCount: eventCount
            ))
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
        do {
            _ = try savePreSleepLogOrThrow(
                sessionId: log.sessionId,
                answers: log.answers,
                completionState: log.completionState,
                now: log.createdAt,
                timeZone: .current
            )
        } catch {
            print("❌ Failed to save pre-sleep log: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Additional Utility Methods
    
    /// Fetch all sleep events with optional limit (internal - use protocol method externally)
    func fetchAllSleepEventsLocal(limit: Int = 500) -> [StoredSleepEvent] {
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
        return fetchAllSleepEventsLocal(limit: limit)
    }
    
    /// Get all events (alias)
    public func getAllEvents(limit: Int = 500) -> [StoredSleepEvent] {
        return fetchAllSleepEventsLocal(limit: limit)
    }
    
    // MARK: - Pain Snapshot Storage
    
    /// Save a pain snapshot as a sleep event.
    /// Event type: "pain.pre_sleep" or "pain.wake"
    /// Notes field contains JSON payload with 0-10 level, detailed locations, radiation, flags.
    public func savePainSnapshot(_ snapshot: PainSnapshot) {
        // Encode snapshot data to JSON for notes field
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var notesJson: String? = nil
        
        struct LocationPayload: Encodable {
            let region: String
            let side: String
        }
        
        struct PainPayload: Encodable {
            let overallLevel: Int
            let locations: [LocationPayload]
            let primaryLocation: LocationPayload?
            let radiation: String?
            let painWokeUser: Bool
            let delta: String?
        }
        
        let payload = PainPayload(
            overallLevel: snapshot.overallLevel,
            locations: snapshot.locations.map { LocationPayload(region: $0.region.rawValue, side: $0.side.rawValue) },
            primaryLocation: snapshot.primaryLocation.map { LocationPayload(region: $0.region.rawValue, side: $0.side.rawValue) },
            radiation: snapshot.radiation?.rawValue,
            painWokeUser: snapshot.painWokeUser,
            delta: snapshot.delta?.rawValue
        )
        
        if let data = try? encoder.encode(payload) {
            notesJson = String(data: data, encoding: .utf8)
        }
        
        insertSleepEvent(
            id: snapshot.id,
            eventType: snapshot.context.eventType,
            timestamp: snapshot.timestamp,
            sessionDate: snapshot.sessionId, // session_date = session_id for linking
            sessionId: snapshot.sessionId,
            colorHex: nil,
            notes: notesJson
        )
        
        print("💊 Saved pain snapshot: \(snapshot.context.eventType) - \(snapshot.summary)")
    }
    
    /// Retrieve pain snapshot for a session (pre-sleep or wake).
    /// Returns nil if no pain snapshot exists for that context.
    public func getPainSnapshot(sessionId: String, context: PainSnapshot.Context) -> PainSnapshot? {
        let sql = """
        SELECT id, event_type, timestamp, session_id, notes
        FROM sleep_events
        WHERE session_id = ? AND event_type = ?
        ORDER BY timestamp DESC LIMIT 1
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, sessionId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, context.eventType, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }
        
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let timestampStr = String(cString: sqlite3_column_text(stmt, 2))
        let sessionIdResult = String(cString: sqlite3_column_text(stmt, 3))
        let notesJson = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
        
        guard let timestamp = isoFormatter.date(from: timestampStr) else {
            return nil
        }
        
        // Parse notes JSON
        var overallLevel = 0
        var locations: [PainLocationDetail] = []
        var primaryLocation: PainLocationDetail? = nil
        var radiation: PainRadiation? = nil
        var painWokeUser = false
        var delta: PainSnapshot.Delta? = nil
        
        if let json = notesJson, let data = json.data(using: .utf8) {
            struct LocationPayload: Decodable {
                let region: String
                let side: String
            }
            
            struct PainPayload: Decodable {
                let overallLevel: Int
                let locations: [LocationPayload]
                let primaryLocation: LocationPayload?
                let radiation: String?
                let painWokeUser: Bool
                let delta: String?
            }
            
            if let payload = try? JSONDecoder().decode(PainPayload.self, from: data) {
                overallLevel = payload.overallLevel
                locations = payload.locations.compactMap { loc in
                    guard let region = PainRegion(rawValue: loc.region),
                          let side = PainSide(rawValue: loc.side) else {
                        return nil
                    }
                    return PainLocationDetail(region: region, side: side)
                }
                if let primary = payload.primaryLocation,
                   let region = PainRegion(rawValue: primary.region),
                   let side = PainSide(rawValue: primary.side) {
                    primaryLocation = PainLocationDetail(region: region, side: side)
                }
                if let rad = payload.radiation {
                    radiation = PainRadiation(rawValue: rad)
                }
                painWokeUser = payload.painWokeUser
                if let d = payload.delta {
                    delta = PainSnapshot.Delta(rawValue: d)
                }
            }
        }
        
        return PainSnapshot(
            id: id,
            context: context,
            overallLevel: overallLevel,
            locations: locations,
            primaryLocation: primaryLocation,
            radiation: radiation,
            painWokeUser: painWokeUser,
            timestamp: timestamp,
            sessionId: sessionIdResult,
            delta: delta
        )
    }
    
    /// Check if a pre-sleep pain snapshot exists for the given session.
    public func hasPreSleepPain(sessionId: String) -> Bool {
        return getPainSnapshot(sessionId: sessionId, context: .preSleep) != nil
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
        let schemaVersion = getSchemaVersion()
        // Keep in sync with docs/SSOT/constants.json version field
        let constantsVersion = EventStorage.constantsVersion
        var csv = "# schema_version=\(schemaVersion) constants_version=\(constantsVersion)\n"
        csv += "type,timestamp,session_date,details\n"
        
        // Export sleep events
        let events = fetchAllSleepEventsLocal(limit: 10000)
        for event in events {
            let line = "\(event.eventType),\(isoFormatter.string(from: event.timestamp)),\(event.sessionDate),\(event.notes ?? "")"
            csv += line + "\n"
        }
        
        // Export dose sessions
        let sessions = fetchRecentSessionsLocal(days: 365)
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
    
    // MARK: - Comprehensive Export V2
    
    /// Export all data to comprehensive CSV (V2 format with all tables)
    public func exportToCSVv2() -> String {
        let schemaVersion = getSchemaVersion()
        var csv = "# DoseTap Export V2 | schema_version=\(schemaVersion) | constants_version=\(EventStorage.constantsVersion)\n"
        csv += "# Export timestamp: \(isoFormatter.string(from: Date()))\n"
        csv += "\n"
        
        // Section 1: Sleep Events (with full details)
        csv += "# === SLEEP EVENTS ===\n"
        csv += "table,id,event_type,timestamp,session_date,color_hex,notes\n"
        let events = fetchAllSleepEventsLocal(limit: 10000)
        for event in events {
            let escapedNotes = escapeCSV(event.notes ?? "")
            csv += "sleep_event,\(event.id),\(event.eventType),\(isoFormatter.string(from: event.timestamp)),\(event.sessionDate),\(event.colorHex ?? ""),\(escapedNotes)\n"
        }
        csv += "\n"
        
        // Section 2: Dose Events (from dose_events table)
        csv += "# === DOSE EVENTS ===\n"
        csv += "table,id,event_type,timestamp,session_date,metadata\n"
        let doseEvents = fetchAllDoseEventsLocal(limit: 10000)
        for dose in doseEvents {
            let escapedMeta = escapeCSV(dose.metadata ?? "")
            csv += "dose_event,\(dose.id),\(dose.eventType),\(isoFormatter.string(from: dose.timestamp)),\(dose.sessionDate),\(escapedMeta)\n"
        }
        csv += "\n"
        
        // Section 3: Sessions (comprehensive session data)
        // Note: SessionSummary has dose times, snooze, skipped, event count
        // Session start/end/terminal_state come from sleep_sessions table (Section 7)
        csv += "# === SESSIONS ===\n"
        csv += "table,session_date,dose1_time,dose2_time,snooze_count,dose2_skipped,interval_minutes,event_count\n"
        let sessions = fetchRecentSessionsLocal(days: 365)
        for session in sessions {
            let d1 = session.dose1Time.map { isoFormatter.string(from: $0) } ?? ""
            let d2 = session.dose2Time.map { isoFormatter.string(from: $0) } ?? ""
            let interval = session.intervalMinutes.map { String($0) } ?? ""
            csv += "session,\(session.sessionDate),\(d1),\(d2),\(session.snoozeCount),\(session.dose2Skipped ? 1 : 0),\(interval),\(session.eventCount)\n"
        }
        csv += "\n"
        
        // Section 4: Morning Check-ins (full health data)
        csv += "# === MORNING CHECK-INS ===\n"
        csv += "table,session_date,timestamp,sleep_quality,feel_rested,grogginess,sleep_inertia_duration,dream_recall,mental_clarity,mood,anxiety_level,readiness_for_day,had_sleep_paralysis,had_hallucinations,had_automatic_behavior,fell_out_of_bed,had_confusion_on_waking,physical_symptoms,respiratory_symptoms,sleep_therapy,sleep_environment,notes\n"
        let checkIns = fetchAllMorningCheckInsLocal(limit: 1000)
        for checkIn in checkIns {
            let physicalSymptoms = escapeCSV(checkIn.physicalSymptomsJson ?? "")
            let respiratorySymptoms = escapeCSV(checkIn.respiratorySymptomsJson ?? "")
            let sleepTherapy = escapeCSV(checkIn.sleepTherapyJson ?? "")
            let sleepEnv = escapeCSV(checkIn.sleepEnvironmentJson ?? "")
            let notes = escapeCSV(checkIn.notes ?? "")
            csv += "morning_checkin,\(checkIn.sessionDate),\(isoFormatter.string(from: checkIn.timestamp)),\(checkIn.sleepQuality),\(checkIn.feelRested),\(checkIn.grogginess),\(checkIn.sleepInertiaDuration),\(checkIn.dreamRecall),\(checkIn.mentalClarity),\(checkIn.mood),\(checkIn.anxietyLevel),\(checkIn.readinessForDay),\(checkIn.hadSleepParalysis ? 1 : 0),\(checkIn.hadHallucinations ? 1 : 0),\(checkIn.hadAutomaticBehavior ? 1 : 0),\(checkIn.fellOutOfBed ? 1 : 0),\(checkIn.hadConfusionOnWaking ? 1 : 0),\(physicalSymptoms),\(respiratorySymptoms),\(sleepTherapy),\(sleepEnv),\(notes)\n"
        }
        csv += "\n"
        
        // Section 5: Pre-Sleep Logs
        csv += "# === PRE-SLEEP LOGS ===\n"
        csv += "table,id,session_id,created_at,completion_state,answers_json\n"
        let preSleepLogs = fetchAllPreSleepLogsLocal(limit: 1000)
        for log in preSleepLogs {
            // StoredPreSleepLog uses createdAtUtc (String) and answers (PreSleepLogAnswers?)
            let answersJson = log.answers.flatMap { encodeAnswersToJson($0) } ?? "{}"
            let escapedAnswers = escapeCSV(answersJson)
            csv += "pre_sleep_log,\(log.id),\(log.sessionId ?? ""),\(log.createdAtUtc),\(log.completionState),\(escapedAnswers)\n"
        }
        csv += "\n"
        
        // Section 6: Medication Events
        csv += "# === MEDICATION EVENTS ===\n"
        csv += "table,id,session_date,medication_id,dose_mg,dose_unit,formulation,taken_at,notes\n"
        let medications = fetchAllMedicationEvents(limit: 10000)
        for med in medications {
            let notes = escapeCSV(med.notes ?? "")
            csv += "medication,\(med.id),\(med.sessionDate),\(med.medicationId),\(med.doseMg),\(med.doseUnit),\(med.formulation),\(isoFormatter.string(from: med.takenAtUTC)),\(notes)\n"
        }
        csv += "\n"
        
        // Section 7: Sleep Sessions (from sleep_sessions table)
        csv += "# === SLEEP SESSIONS (Boundaries) ===\n"
        csv += "table,session_id,session_date,start_utc,end_utc,terminal_state\n"
        let sleepSessions = fetchAllSleepSessionsLocal(limit: 1000)
        for ss in sleepSessions {
            let startTime = isoFormatter.string(from: ss.startUTC)
            let endTime = ss.endUTC.map { isoFormatter.string(from: $0) } ?? ""
            csv += "sleep_session,\(ss.sessionId),\(ss.sessionDate),\(startTime),\(endTime),\(ss.terminalState ?? "")\n"
        }
        
        return csv
    }
    
    /// Helper to escape CSV fields with quotes and special characters
    private func escapeCSV(_ value: String) -> String {
        if value.isEmpty { return "" }
        // If contains comma, newline, or quote, wrap in quotes and escape internal quotes
        if value.contains(",") || value.contains("\n") || value.contains("\"") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
    
    /// Helper to encode PreSleepLogAnswers to JSON string for export
    private func encodeAnswersToJson(_ answers: PreSleepLogAnswers) -> String? {
        guard let data = try? JSONEncoder().encode(answers) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    /// Fetch all dose events (from dose_events table)
    private func fetchAllDoseEventsLocal(limit: Int) -> [StoredDoseEvent] {
        var events: [StoredDoseEvent] = []
        let sql = """
        SELECT id, event_type, timestamp, session_date, session_id, metadata
        FROM dose_events
        ORDER BY timestamp DESC
        LIMIT ?
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return events }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int(stmt, 1, Int32(limit))
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idPtr = sqlite3_column_text(stmt, 0),
                  let typePtr = sqlite3_column_text(stmt, 1),
                  let timestampPtr = sqlite3_column_text(stmt, 2),
                  let sessionDatePtr = sqlite3_column_text(stmt, 3) else { continue }
            
            let timestamp = isoFormatter.date(from: String(cString: timestampPtr)) ?? Date()
            let metadata = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
            
            events.append(StoredDoseEvent(
                id: String(cString: idPtr),
                eventType: String(cString: typePtr),
                timestamp: timestamp,
                sessionDate: String(cString: sessionDatePtr),
                metadata: metadata
            ))
        }
        return events
    }
    
    /// Fetch all morning check-ins for export
    private func fetchAllMorningCheckInsLocal(limit: Int) -> [StoredMorningCheckIn] {
        var checkIns: [StoredMorningCheckIn] = []
        let sql = """
        SELECT id, session_id, timestamp, session_date, sleep_quality, feel_rested, grogginess,
               sleep_inertia_duration, dream_recall, has_physical_symptoms, physical_symptoms_json,
               has_respiratory_symptoms, respiratory_symptoms_json, mental_clarity, mood, anxiety_level,
               readiness_for_day, had_sleep_paralysis, had_hallucinations, had_automatic_behavior,
               fell_out_of_bed, had_confusion_on_waking, used_sleep_therapy, sleep_therapy_json,
               has_sleep_environment, sleep_environment_json, notes
        FROM morning_checkins
        ORDER BY timestamp DESC
        LIMIT ?
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return checkIns }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int(stmt, 1, Int32(limit))
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idPtr = sqlite3_column_text(stmt, 0),
                  let sessionIdPtr = sqlite3_column_text(stmt, 1),
                  let timestampPtr = sqlite3_column_text(stmt, 2),
                  let sessionDatePtr = sqlite3_column_text(stmt, 3) else { continue }
            
            let timestamp = isoFormatter.date(from: String(cString: timestampPtr)) ?? Date()
            
            checkIns.append(StoredMorningCheckIn(
                id: String(cString: idPtr),
                sessionId: String(cString: sessionIdPtr),
                timestamp: timestamp,
                sessionDate: String(cString: sessionDatePtr),
                sleepQuality: Int(sqlite3_column_int(stmt, 4)),
                feelRested: sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? "moderate",
                grogginess: sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? "mild",
                sleepInertiaDuration: sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? "fiveToFifteen",
                dreamRecall: sqlite3_column_text(stmt, 8).map { String(cString: $0) } ?? "none",
                hasPhysicalSymptoms: sqlite3_column_int(stmt, 9) != 0,
                physicalSymptomsJson: sqlite3_column_text(stmt, 10).map { String(cString: $0) },
                hasRespiratorySymptoms: sqlite3_column_int(stmt, 11) != 0,
                respiratorySymptomsJson: sqlite3_column_text(stmt, 12).map { String(cString: $0) },
                mentalClarity: Int(sqlite3_column_int(stmt, 13)),
                mood: sqlite3_column_text(stmt, 14).map { String(cString: $0) } ?? "neutral",
                anxietyLevel: sqlite3_column_text(stmt, 15).map { String(cString: $0) } ?? "none",
                readinessForDay: Int(sqlite3_column_int(stmt, 16)),
                hadSleepParalysis: sqlite3_column_int(stmt, 17) != 0,
                hadHallucinations: sqlite3_column_int(stmt, 18) != 0,
                hadAutomaticBehavior: sqlite3_column_int(stmt, 19) != 0,
                fellOutOfBed: sqlite3_column_int(stmt, 20) != 0,
                hadConfusionOnWaking: sqlite3_column_int(stmt, 21) != 0,
                usedSleepTherapy: sqlite3_column_int(stmt, 22) != 0,
                sleepTherapyJson: sqlite3_column_text(stmt, 23).map { String(cString: $0) },
                hasSleepEnvironment: sqlite3_column_int(stmt, 24) != 0,
                sleepEnvironmentJson: sqlite3_column_text(stmt, 25).map { String(cString: $0) },
                notes: sqlite3_column_text(stmt, 26).map { String(cString: $0) }
            ))
        }
        return checkIns
    }
    
    /// Fetch all pre-sleep logs for export
    private func fetchAllPreSleepLogsLocal(limit: Int) -> [StoredPreSleepLog] {
        var logs: [StoredPreSleepLog] = []
        let sql = """
        SELECT id, session_id, created_at_utc, local_offset_minutes, completion_state, answers_json
        FROM pre_sleep_logs
        ORDER BY created_at_utc DESC
        LIMIT ?
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return logs }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int(stmt, 1, Int32(limit))
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idPtr = sqlite3_column_text(stmt, 0),
                  let createdAtPtr = sqlite3_column_text(stmt, 2) else { continue }
            
            let sessionId = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
            let createdAtUtc = String(cString: createdAtPtr)
            let localOffset = Int(sqlite3_column_int(stmt, 3))
            let completionState = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? "partial"
            let answersJson = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
            
            // Parse answersJson into PreSleepLogAnswers if present
            let answers: PreSleepLogAnswers? = answersJson.flatMap { json in
                guard let data = json.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(PreSleepLogAnswers.self, from: data)
            }
            
            logs.append(StoredPreSleepLog(
                id: String(cString: idPtr),
                sessionId: sessionId,
                createdAtUtc: createdAtUtc,
                localOffsetMinutes: localOffset,
                completionState: completionState,
                answers: answers
            ))
        }
        return logs
    }
    
    /// Fetch all sleep sessions (from sleep_sessions table) for export
    private func fetchAllSleepSessionsLocal(limit: Int) -> [SleepSessionRecord] {
        var sessions: [SleepSessionRecord] = []
        let sql = """
        SELECT session_id, session_date, start_utc, end_utc, terminal_state
        FROM sleep_sessions
        ORDER BY start_utc DESC
        LIMIT ?
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return sessions }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int(stmt, 1, Int32(limit))
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let sessionIdPtr = sqlite3_column_text(stmt, 0),
                  let sessionDatePtr = sqlite3_column_text(stmt, 1),
                  let startUtcPtr = sqlite3_column_text(stmt, 2) else { continue }
            
            let startUTC = isoFormatter.date(from: String(cString: startUtcPtr)) ?? Date()
            let endUTC = sqlite3_column_text(stmt, 3).flatMap { isoFormatter.date(from: String(cString: $0)) }
            let terminalState = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
            
            sessions.append(SleepSessionRecord(
                sessionId: String(cString: sessionIdPtr),
                sessionDate: String(cString: sessionDatePtr),
                startUTC: startUTC,
                endUTC: endUTC,
                terminalState: terminalState
            ))
        }
        return sessions
    }
    
    /// Sleep session record for export
    private struct SleepSessionRecord {
        let sessionId: String
        let sessionDate: String
        let startUTC: Date
        let endUTC: Date?
        let terminalState: String?
    }

    /// SSOT constants version (mirrors docs/SSOT/constants.json)
    static let constantsVersion = "1.0.0"
    
    /// Export sleep events to CSV
    private func exportSleepEventsToCSV() -> String {
        var csv = "id,event_type,timestamp,session_date,color_hex,notes\n"
        let events = fetchAllSleepEventsLocal(limit: 10000)
        for event in events {
            let escapedNotes = (event.notes ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\(event.id),\(event.eventType),\(isoFormatter.string(from: event.timestamp)),\(event.sessionDate),\(event.colorHex ?? ""),\"\(escapedNotes)\"\n"
        }
        return csv
    }
    
    /// Export dose events to CSV
    private func exportDoseEventsToCSV() -> String {
        var csv = "session_date,dose1_time,dose2_time,snooze_count,dose2_skipped\n"
        let sessions = fetchRecentSessionsLocal(days: 365)
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
        INSERT INTO medication_events (id, session_id, session_date, medication_id, dose_mg, dose_unit, formulation, taken_at_utc, local_offset_minutes, notes, confirmed_duplicate)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
        sqlite3_bind_text(stmt, 6, entry.doseUnit, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 7, entry.formulation, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 8, isoFormatter.string(from: entry.takenAtUTC), -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 9, Int32(entry.localOffsetMinutes))
        
        if let notes = entry.notes {
            sqlite3_bind_text(stmt, 10, notes, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 10)
        }
        
        sqlite3_bind_int(stmt, 11, entry.confirmedDuplicate ? 1 : 0)
        
        if sqlite3_step(stmt) != SQLITE_DONE {
            print("❌ Failed to insert medication event: \(String(cString: sqlite3_errmsg(db)))")
        } else {
            print("💊 Medication event inserted: \(entry.medicationId) \(entry.doseMg)\(entry.doseUnit)")
        }
    }
    
    /// Fetch medication events for a session date
    public func fetchMedicationEvents(sessionDate: String) -> [StoredMedicationEntry] {
        var entries: [StoredMedicationEntry] = []
        let sql = """
        SELECT id, session_id, session_date, medication_id, dose_mg, dose_unit, formulation, taken_at_utc, local_offset_minutes, notes, confirmed_duplicate, created_at
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
        SELECT id, session_id, session_date, medication_id, dose_mg, dose_unit, formulation, taken_at_utc, local_offset_minutes, notes, confirmed_duplicate, created_at
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
    /// Column order: id, session_id, session_date, medication_id, dose_mg, dose_unit, formulation, taken_at_utc, local_offset_minutes, notes, confirmed_duplicate, created_at
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
        
        let doseUnit: String
        if sqlite3_column_type(stmt, 5) != SQLITE_NULL {
            doseUnit = String(cString: sqlite3_column_text(stmt, 5))
        } else {
            doseUnit = "mg"
        }
        
        let formulation: String
        if sqlite3_column_type(stmt, 6) != SQLITE_NULL {
            formulation = String(cString: sqlite3_column_text(stmt, 6))
        } else {
            formulation = "ir"
        }
        
        let takenAtStr = String(cString: sqlite3_column_text(stmt, 7))
        guard let takenAtUTC = isoFormatter.date(from: takenAtStr) else { return nil }
        
        let localOffsetMinutes: Int
        if sqlite3_column_type(stmt, 8) != SQLITE_NULL {
            localOffsetMinutes = Int(sqlite3_column_int(stmt, 8))
        } else {
            localOffsetMinutes = 0
        }
        
        let notes: String?
        if sqlite3_column_type(stmt, 9) != SQLITE_NULL {
            notes = String(cString: sqlite3_column_text(stmt, 9))
        } else {
            notes = nil
        }
        
        let confirmedDuplicate = sqlite3_column_int(stmt, 10) == 1
        
        let createdAtStr = String(cString: sqlite3_column_text(stmt, 11))
        let createdAt = isoFormatter.date(from: createdAtStr) ?? Date()
        
        return StoredMedicationEntry(
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
        
        let entries = fetchAllMedicationEvents(limit: 10000)
        for entry in entries {
            let escapedNotes = (entry.notes ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\(entry.id),\(entry.sessionId ?? ""),\(entry.sessionDate),\(entry.medicationId),\(entry.doseMg),\(entry.doseUnit),\(entry.formulation),\(isoFormatter.string(from: entry.takenAtUTC)),\(entry.localOffsetMinutes),\"\(escapedNotes)\",\(entry.confirmedDuplicate ? 1 : 0),\(isoFormatter.string(from: entry.createdAt))\n"
        }
        
        return csv
    }
}

/// Minimal support bundle exporter that emits metadata headers using EventStorage.
@MainActor
struct SupportBundleExporter {
    private let storage: EventStorage
    
    init(storage: EventStorage) {
        self.storage = storage
    }
    
    init() {
        self.storage = EventStorage.shared
    }
    
    func makeBundleSummary() -> String {
        let schemaVersion = storage.getSchemaVersion()
        let constantsVersion = EventStorage.constantsVersion
        let sessionCount = storage.getAllSessionDates().count
        return """
        DoseTap Support Bundle
        schema_version=\(schemaVersion)
        constants_version=\(constantsVersion)
        session_count=\(sessionCount)
        """
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
public typealias StoredMedicationEntry = SQLiteStoredMedicationEntry

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
    return TimeIntervalMath.minutesBetween(start: dose1Time, end: d2)
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
            self.intervalMinutes = TimeIntervalMath.minutesBetween(start: d1, end: d2)
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

// MARK: - Pain Tracking Types (Top-Level for cross-file visibility)

/// Pain region categories for structured location tracking
public enum PainRegion: String, Codable, CaseIterable, Identifiable {
    // Head and Neck
    case head = "head"
    case jaw = "jaw"
    case face = "face"
    case neck = "neck"
    
    // Shoulder and Arms
    case shoulder = "shoulder"
    case upperArm = "upper_arm"
    case elbow = "elbow"
    case forearm = "forearm"
    case wrist = "wrist"
    case hand = "hand"
    
    // Torso and Back
    case upperBack = "upper_back"
    case midBack = "mid_back"
    case lowBack = "low_back"
    case chest = "chest"
    case abdomen = "abdomen"
    
    // Hips and Legs
    case hip = "hip"
    case thigh = "thigh"
    case knee = "knee"
    case shin = "shin"
    case ankle = "ankle"
    case foot = "foot"
    
    // General
    case jointsWidespread = "joints_widespread"
    case muscleWidespread = "muscle_widespread"
    case other = "other"
    
    public var id: String { rawValue }
    
    public var displayText: String {
        switch self {
        case .head: return "Head"
        case .jaw: return "Jaw/TMJ"
        case .face: return "Face/Sinuses"
        case .neck: return "Neck"
        case .shoulder: return "Shoulder"
        case .upperArm: return "Upper arm"
        case .elbow: return "Elbow"
        case .forearm: return "Forearm"
        case .wrist: return "Wrist"
        case .hand: return "Hand"
        case .upperBack: return "Upper back"
        case .midBack: return "Mid back"
        case .lowBack: return "Low back"
        case .chest: return "Chest"
        case .abdomen: return "Abdomen"
        case .hip: return "Hip"
        case .thigh: return "Thigh"
        case .knee: return "Knee"
        case .shin: return "Shin/Calf"
        case .ankle: return "Ankle"
        case .foot: return "Foot"
        case .jointsWidespread: return "Joints (widespread)"
        case .muscleWidespread: return "Muscle (widespread)"
        case .other: return "Other"
        }
    }
    
    public var category: String {
        switch self {
        case .head, .jaw, .face, .neck:
            return "Head & Neck"
        case .shoulder, .upperArm, .elbow, .forearm, .wrist, .hand:
            return "Shoulder & Arms"
        case .upperBack, .midBack, .lowBack, .chest, .abdomen:
            return "Torso & Back"
        case .hip, .thigh, .knee, .shin, .ankle, .foot:
            return "Hips & Legs"
        case .jointsWidespread, .muscleWidespread, .other:
            return "General"
        }
    }
    
    public var supportsLaterality: Bool {
        switch self {
        case .head, .face, .neck, .chest, .abdomen, .jointsWidespread, .muscleWidespread, .other:
            return false
        default:
            return true
        }
    }
    
    public var supportsRadiation: Bool {
        switch self {
        case .neck, .upperBack, .midBack, .lowBack, .hip, .thigh:
            return true
        default:
            return false
        }
    }
}

/// Laterality for pain location
public enum PainSide: String, Codable, CaseIterable {
    case left = "left"
    case right = "right"
    case both = "both"
    case center = "center"
    
    public var displayText: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .both: return "Both"
        case .center: return "Center"
        }
    }
    
    public var emoji: String {
        switch self {
        case .left: return "⬅️"
        case .right: return "➡️"
        case .both: return "↔️"
        case .center: return "•"
        }
    }
}

/// Radiation pattern for back/neck/leg pain
public enum PainRadiation: String, Codable, CaseIterable {
    case none = "none"
    case downLeft = "down_left"
    case downRight = "down_right"
    case intoShoulders = "into_shoulders"
    case intoHip = "into_hip"
    case intoLeg = "into_leg"
    
    public var displayText: String {
        switch self {
        case .none: return "None"
        case .downLeft: return "Down left"
        case .downRight: return "Down right"
        case .intoShoulders: return "Into shoulders"
        case .intoHip: return "Into hip"
        case .intoLeg: return "Into leg"
        }
    }
}

/// Detailed pain location with region + side
public struct PainLocationDetail: Codable, Equatable, Hashable {
    public let region: PainRegion
    public let side: PainSide
    
    public init(region: PainRegion, side: PainSide) {
        self.region = region
        self.side = side
    }
    
    public var displayText: String {
        if region.supportsLaterality {
            return "\(region.displayText) \(side.displayText.lowercased())"
        } else {
            return region.displayText
        }
    }
    
    public var compactText: String {
        if region.supportsLaterality {
            return "\(region.displayText) \(side.emoji)"
        } else {
            return region.displayText
        }
    }
}

/// Pre-sleep log answers model with nested enums for type-safe options
public struct PreSleepLogAnswers: Codable {
    
    // Note: PainRegion, PainSide, PainRadiation, and PainLocationDetail are now
    // top-level types for cross-file visibility. Use them directly without
    // PreSleepLogAnswers prefix.
    
    // MARK: - Nested Enums for Question Options
    
    public enum IntendedSleepTime: String, Codable, CaseIterable {
        case now = "now"
        case fifteenMin = "15min"
        case thirtyMin = "30min"
        case hour = "1hr"
        case twoHours = "2hr"
        case threeHours = "3hr"
        case notSure = "not_sure"
        
        public var displayText: String {
            switch self {
            case .now: return "Now"
            case .fifteenMin: return "~15 min"
            case .thirtyMin: return "~30 min"
            case .hour: return "~1 hour"
            case .twoHours: return "~2 hours"
            case .threeHours: return "~3 hours"
            case .notSure: return "Not sure"
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
    
    // MARK: - Legacy Pain Enums (Deprecated, kept for backwards compatibility)
    
    @available(*, deprecated, message: "Use 0-10 pain scale instead")
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
        
        /// Convert to 0-10 scale
        public var numericEquivalent: Int {
            switch self {
            case .none: return 0
            case .mild: return 2
            case .moderate: return 5
            case .severe: return 8
            }
        }
    }
    
    @available(*, deprecated, message: "Use PainLocationDetail instead")
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
        
        public var displayText: String {
            switch self {
            case .none: return "None"
            case .coffee: return "Coffee"
            case .tea: return "Tea"
            case .soda: return "Soda"
            case .energyDrink: return "Energy Drink"
            }
        }
        
        /// Exclude 'none' from multi-select options
        public static var multiSelectOptions: [Stimulants] {
            allCases.filter { $0 != .none }
        }
    }
    
    /// Time bucket for when stimulant was consumed
    public enum StimulantTime: String, Codable, CaseIterable {
        case before2pm = "before_2pm"
        case twoPM = "2pm"
        case fourPM = "4pm"
        case sixPM = "6pm"
        case eightPM = "8pm"
        case afterEight = "after_8pm"
        
        public var displayText: String {
            switch self {
            case .before2pm: return "Before 2pm"
            case .twoPM: return "2pm"
            case .fourPM: return "4pm"
            case .sixPM: return "6pm"
            case .eightPM: return "8pm"
            case .afterEight: return "After 8pm"
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
    
    public enum SleepAid: String, Codable, CaseIterable {
        case eyeMask = "eye_mask"
        case earplugs = "earplugs"
        case whiteNoise = "white_noise"
        case fan = "fan"
        case blackoutCurtains = "blackout_curtains"
        case weightedBlanket = "weighted_blanket"
        case coolingSleep = "cooling"
        
        public var displayText: String {
            switch self {
            case .eyeMask: return "Eye Mask"
            case .earplugs: return "Earplugs"
            case .whiteNoise: return "White Noise"
            case .fan: return "Fan"
            case .blackoutCurtains: return "Blackout"
            case .weightedBlanket: return "Weighted"
            case .coolingSleep: return "Cooling"
            }
        }
        
        public var icon: String {
            switch self {
            case .eyeMask: return "eye"
            case .earplugs: return "ear"
            case .whiteNoise: return "waveform"
            case .fan: return "wind"
            case .blackoutCurtains: return "curtains.closed"
            case .weightedBlanket: return "bed.double"
            case .coolingSleep: return "snowflake"
            }
        }
    }
    
    // MARK: - Properties
    
    // Card 1: Timing + Stress + Sleepiness
    public var intendedSleepTime: IntendedSleepTime?
    public var stressLevel: Int?
    public var stressDriver: StressDriver?
    public var sleepinessLevel: Int?  // 1-5 for narcolepsy tracking
    public var alarmSet: Bool?
    public var alarmTime: Date?
    
    // Card 2: Body + Substances
    // New pain tracking (0-10 scale)
    public var painLevel010: Int?  // 0-10 numeric rating scale
    public var painDetailedLocations: [PainLocationDetail]?  // Granular regions with laterality
    public var painPrimaryLocation: PainLocationDetail?  // Main area if multiple selected
    public var painRadiation: PainRadiation?  // For back/neck/leg pain
    
    // Legacy pain fields (internal storage for Codable, use legacyBodyPain/legacyPainLocations accessors)
    private var _bodyPain: PainLevel?
    private var _painLocations: [PainLocation]?
    private var _painType: PainType?
    
    @available(*, deprecated, message: "Use painLevel010 instead")
    public var bodyPain: PainLevel? {
        get { _bodyPain }
        set { _bodyPain = newValue }
    }
    @available(*, deprecated, message: "Use painDetailedLocations instead")
    public var painLocations: [PainLocation]? {
        get { _painLocations }
        set { _painLocations = newValue }
    }
    @available(*, deprecated, message: "Radiation tracking moved to painRadiation")
    public var painType: PainType? {
        get { _painType }
        set { _painType = newValue }
    }
    
    // MARK: - Legacy Pain Accessors (for backward compatibility without warnings)
    
    /// Access legacy bodyPain without triggering deprecation warning.
    /// Use only for backward compatibility with old data.
    public var legacyBodyPain: PainLevel? {
        get { _bodyPain }
    }
    
    /// Access legacy painLocations without triggering deprecation warning.
    /// Use only for backward compatibility with old data.
    public var legacyPainLocations: [PainLocation]? {
        get { _painLocations }
    }
    
    public var stimulantsConsumed: [Stimulants]?  // Multi-select (replaces single stimulants)
    public var lastCaffeineTime: StimulantTime?   // Time bucket for last caffeine
    public var alcohol: AlcoholLevel?
    public var lastAlcoholTime: StimulantTime?    // Time bucket for last alcohol
    
    // Card 3: Activity + Naps
    public var exercise: ExerciseLevel?
    public var napToday: NapDuration?
    public var napLoggedMinutes: Int?  // From actual nap events (readonly display)
    
    // Optional details (Advanced mode)
    public var lateMeal: LateMeal?
    public var lastMealTime: StimulantTime?       // Time bucket for last meal
    public var screensInBed: ScreensInBed?
    public var roomTemp: RoomTemp?
    public var noiseLevel: NoiseLevel?
    public var sleepAidsUsed: [SleepAid]?         // Multi-select (replaces single sleepAids)
    
    // Legacy fields (for backwards compatibility)
    public var stimulants: Stimulants?            // Deprecated: use stimulantsConsumed
    public var sleepAids: SleepAid?               // Deprecated: use sleepAidsUsed
    public var laterReason: LaterReason?          // Deprecated: removed with new time options
    public var notes: String?
    
    public init(
        intendedSleepTime: IntendedSleepTime? = nil,
        stressLevel: Int? = nil,
        stressDriver: StressDriver? = nil,
        sleepinessLevel: Int? = nil,
        alarmSet: Bool? = nil,
        alarmTime: Date? = nil,
        // New pain tracking
        painLevel010: Int? = nil,
        painDetailedLocations: [PainLocationDetail]? = nil,
        painPrimaryLocation: PainLocationDetail? = nil,
        painRadiation: PainRadiation? = nil,
        // Legacy pain (internal storage for Codable decoding of old data)
        _bodyPain: PainLevel? = nil,
        _painLocations: [PainLocation]? = nil,
        _painType: PainType? = nil,
        stimulantsConsumed: [Stimulants]? = nil,
        lastCaffeineTime: StimulantTime? = nil,
        alcohol: AlcoholLevel? = nil,
        lastAlcoholTime: StimulantTime? = nil,
        exercise: ExerciseLevel? = nil,
        napToday: NapDuration? = nil,
        napLoggedMinutes: Int? = nil,
        lateMeal: LateMeal? = nil,
        lastMealTime: StimulantTime? = nil,
        screensInBed: ScreensInBed? = nil,
        roomTemp: RoomTemp? = nil,
        noiseLevel: NoiseLevel? = nil,
        sleepAidsUsed: [SleepAid]? = nil,
        stimulants: Stimulants? = nil,
        sleepAids: SleepAid? = nil,
        laterReason: LaterReason? = nil,
        notes: String? = nil
    ) {
        self.intendedSleepTime = intendedSleepTime
        self.stressLevel = stressLevel
        self.stressDriver = stressDriver
        self.sleepinessLevel = sleepinessLevel
        self.alarmSet = alarmSet
        self.alarmTime = alarmTime
        self.painLevel010 = painLevel010
        self.painDetailedLocations = painDetailedLocations
        self.painPrimaryLocation = painPrimaryLocation
        self.painRadiation = painRadiation
        self._bodyPain = _bodyPain
        self._painLocations = _painLocations
        self._painType = _painType
        self.stimulantsConsumed = stimulantsConsumed
        self.lastCaffeineTime = lastCaffeineTime
        self.alcohol = alcohol
        self.lastAlcoholTime = lastAlcoholTime
        self.exercise = exercise
        self.napToday = napToday
        self.napLoggedMinutes = napLoggedMinutes
        self.lateMeal = lateMeal
        self.lastMealTime = lastMealTime
        self.screensInBed = screensInBed
        self.roomTemp = roomTemp
        self.noiseLevel = noiseLevel
        self.sleepAidsUsed = sleepAidsUsed
        self.stimulants = stimulants
        self.sleepAids = sleepAids
        self.laterReason = laterReason
        self.notes = notes
    }
    
    // Custom CodingKeys to map underscore-prefixed private storage to JSON keys
    private enum CodingKeys: String, CodingKey {
        case intendedSleepTime, stressLevel, stressDriver, sleepinessLevel
        case alarmSet, alarmTime
        case painLevel010, painDetailedLocations, painPrimaryLocation, painRadiation
        case _bodyPain = "bodyPain"
        case _painLocations = "painLocations"
        case _painType = "painType"
        case stimulantsConsumed, lastCaffeineTime, alcohol, lastAlcoholTime
        case exercise, napToday, napLoggedMinutes
        case lateMeal, lastMealTime, screensInBed, roomTemp, noiseLevel
        case sleepAidsUsed, stimulants, sleepAids, laterReason, notes
    }
}

// MARK: - Pain Snapshot Model
/// Represents a pain snapshot captured at pre-sleep or wake time for delta tracking.
/// Uses 0-10 numeric rating scale with detailed location tracking.
/// Stored as sleep_events with event_type "pain.pre_sleep" or "pain.wake".
public struct PainSnapshot: Codable, Equatable {
    
    /// Context: when the pain was recorded
    public enum Context: String, Codable, CaseIterable {
        case preSleep = "pre_sleep"
        case wake = "wake"
        
        public var eventType: String {
            return "pain.\(rawValue)"
        }
    }
    
    /// Pain delta comparison result
    public enum Delta: String, Codable, CaseIterable {
        case same = "same"
        case better = "better"
        case worse = "worse"
        case muchBetter = "much_better"
        case muchWorse = "much_worse"
        
        public var displayText: String {
            switch self {
            case .same: return "Same"
            case .better: return "Better"
            case .worse: return "Worse"
            case .muchBetter: return "Much Better"
            case .muchWorse: return "Much Worse"
            }
        }
        
        public var emoji: String {
            switch self {
            case .same: return "↔️"
            case .better: return "⬆️"
            case .worse: return "⬇️"
            case .muchBetter: return "🎉"
            case .muchWorse: return "😣"
            }
        }
    }
    
    public let id: String
    public let context: Context
    
    // Core pain data (0-10 scale)
    public let overallLevel: Int  // 0-10 numeric rating scale
    public let locations: [PainLocationDetail]
    public let primaryLocation: PainLocationDetail?  // Main pain area if multiple
    public let radiation: PainRadiation?
    
    // Context flags
    public let painWokeUser: Bool  // For wake surveys: did pain interrupt sleep?
    
    // Metadata
    public let timestamp: Date
    public let sessionId: String
    
    /// For wake snapshots: comparison to pre-sleep baseline
    public var delta: Delta?
    
    // Legacy support
    @available(*, deprecated, message: "Use overallLevel instead")
    public var level: PreSleepLogAnswers.PainLevel {
        switch overallLevel {
        case 0: return .none
        case 1...3: return .mild
        case 4...6: return .moderate
        default: return .severe
        }
    }
    
    public init(
        id: String = UUID().uuidString,
        context: Context,
        overallLevel: Int,
        locations: [PainLocationDetail] = [],
        primaryLocation: PainLocationDetail? = nil,
        radiation: PainRadiation? = nil,
        painWokeUser: Bool = false,
        timestamp: Date = Date(),
        sessionId: String,
        delta: Delta? = nil
    ) {
        self.id = id
        self.context = context
        self.overallLevel = max(0, min(10, overallLevel))  // Clamp to 0-10
        self.locations = locations
        self.primaryLocation = primaryLocation
        self.radiation = radiation
        self.painWokeUser = painWokeUser
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.delta = delta
    }
    
    /// Anchor text for 0-10 scale
    public static func anchorText(for level: Int) -> String {
        switch level {
        case 0: return "No pain"
        case 1...3: return "Mild – noticeable but easy to ignore"
        case 4...6: return "Moderate – hard to ignore, interferes with focus"
        case 7...8: return "Severe – limits activity, difficult to sleep"
        case 9...10: return "Very severe – unbearable, cannot function"
        default: return ""
        }
    }
    
    /// Summary for display (e.g., "6/10 – Low back left, radiating down left")
    public var summary: String {
        var parts: [String] = ["\(overallLevel)/10"]
        
        if let primary = primaryLocation {
            parts.append(primary.compactText)
        } else if let first = locations.first {
            if locations.count == 1 {
                parts.append(first.compactText)
            } else {
                parts.append("\(locations.count) areas")
            }
        }
        
        if let rad = radiation, rad != .none {
            parts.append("radiating \(rad.displayText.lowercased())")
        }
        
        return parts.joined(separator: " – ")
    }
    
    /// Compact display: "6 Low back ⬅️"
    public var compactSummary: String {
        var parts: [String] = ["\(overallLevel)"]
        
        if let primary = primaryLocation {
            parts.append(primary.displayText)
        } else if let first = locations.first {
            parts.append(first.displayText)
        }
        
        return parts.joined(separator: " ")
    }
}

// MARK: - EventStore Protocol Conformance
// This extension makes EventStorage the single source of truth for all event operations.
// UI and business logic should ONLY interact through the EventStore protocol.

extension EventStorage: EventStore {
    
    // MARK: - Session Identity
    
    public func currentSessionKey() -> String {
        currentSessionDate()
    }
    
    public func getAllSessionKeys() -> [String] {
        getAllSessionDates()
    }
    
    // MARK: - Sleep Events (Protocol methods with explicit sessionKey parameter)
    
    public func insertSleepEvent(
        id: String,
        eventType: String,
        timestamp: Date,
        sessionKey: String,
        colorHex: String?,
        notes: String?
    ) {
        // Delegate to existing method with sessionDate parameter
        insertSleepEvent(
            id: id,
            eventType: eventType,
            timestamp: timestamp,
            sessionDate: sessionKey,
            colorHex: colorHex,
            notes: notes
        )
    }
    
    public func fetchSleepEvents(sessionKey: String) -> [DoseCore.StoredSleepEvent] {
        // Fetch using local type, convert to DoseCore type
        let localEvents = fetchSleepEvents(forSession: sessionKey)
        return localEvents.map { local in
            DoseCore.StoredSleepEvent(
                id: local.id,
                eventType: local.eventType,
                timestamp: local.timestamp,
                sessionDate: local.sessionDate,
                colorHex: local.colorHex,
                notes: local.notes
            )
        }
    }
    
    public func fetchTonightSleepEvents() -> [DoseCore.StoredSleepEvent] {
        fetchSleepEvents(sessionKey: currentSessionKey())
    }
    
    public func fetchAllSleepEvents(limit: Int) -> [DoseCore.StoredSleepEvent] {
        // Use existing method and convert
        let localEvents = fetchAllSleepEventsLocal(limit: limit)
        return localEvents.map { local in
            DoseCore.StoredSleepEvent(
                id: local.id,
                eventType: local.eventType,
                timestamp: local.timestamp,
                sessionDate: local.sessionDate,
                colorHex: local.colorHex,
                notes: local.notes
            )
        }
    }
    
    // MARK: - Dose Events
    
    public func insertDoseEvent(eventType: String, timestamp: Date, sessionKey: String, metadata: String?) {
        insertDoseEvent(eventType: eventType, timestamp: timestamp, sessionDate: sessionKey, metadata: metadata)
    }
    
    public func fetchDoseEvents(sessionId: String?, sessionDate: String) -> [DoseCore.StoredDoseEvent] {
        var events: [DoseCore.StoredDoseEvent] = []
        let useSessionId = (sessionId != nil)
        let sql = """
        SELECT id, event_type, timestamp, session_date, metadata
        FROM dose_events
        WHERE \(useSessionId ? "session_id = ?" : "session_date = ?")
        ORDER BY timestamp ASC
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        
        if let sessionId = sessionId {
            sqlite3_bind_text(stmt, 1, sessionId, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
        }
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let idPtr = sqlite3_column_text(stmt, 0),
               let typePtr = sqlite3_column_text(stmt, 1),
               let timestampPtr = sqlite3_column_text(stmt, 2),
               let sessionPtr = sqlite3_column_text(stmt, 3) {
                let id = String(cString: idPtr)
                let eventType = String(cString: typePtr)
                let timestampStr = String(cString: timestampPtr)
                let sessionDate = String(cString: sessionPtr)
                let metadata = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
                
                if let timestamp = isoFormatter.date(from: timestampStr) {
                    events.append(DoseCore.StoredDoseEvent(
                        id: id,
                        eventType: eventType,
                        timestamp: timestamp,
                        sessionDate: sessionDate,
                        metadata: metadata
                    ))
                }
            }
        }
        return events
    }
    
    public func fetchDoseEvents(sessionKey: String) -> [DoseCore.StoredDoseEvent] {
        fetchDoseEvents(sessionId: nil, sessionDate: sessionKey)
    }
    
    public func hasDose(type: String, sessionKey: String) -> Bool {
        hasDose(type: type, sessionDate: sessionKey)
    }
    
    // MARK: - Session State (current_session table)
    
    public func saveDose1(timestamp: Date) {
        saveDose1(timestamp: timestamp, sessionId: nil, sessionDateOverride: nil)
    }
    
    public func saveDose2(timestamp: Date, isEarly: Bool, isExtraDose: Bool) {
        saveDose2(timestamp: timestamp, isEarly: isEarly, isExtraDose: isExtraDose, isLate: false, sessionId: nil, sessionDateOverride: nil)
    }
    
    public func saveDoseSkipped(reason: String?) {
        saveDoseSkipped(reason: reason, sessionId: nil, sessionDateOverride: nil)
    }
    
    public func saveSnooze(count: Int) {
        saveSnooze(count: count, sessionId: nil, sessionDateOverride: nil)
    }
    
    public func clearDose1() {
        // Clear dose 1 from current_session
        let sql = """
        UPDATE current_session
        SET dose1_time = NULL
        WHERE id = 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_step(stmt)
    }
    
    public func clearDose2() {
        // Clear dose 2 from current_session
        let sql = """
        UPDATE current_session
        SET dose2_time = NULL, dose2_skipped = 0
        WHERE id = 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_step(stmt)
    }
    
    public func clearSkip() {
        // Clear skip from current_session
        let sql = """
        UPDATE current_session
        SET dose2_skipped = 0
        WHERE id = 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_step(stmt)
    }
    
    // MARK: - Pre-Sleep Logs
    
    public func savePreSleepLogOrThrow(sessionKey: String, answers: DoseCore.PreSleepLogAnswers, completionState: String) throws {
        // Convert DoseCore.PreSleepLogAnswers to local PreSleepLogAnswers
        // For now, use the JSON encoding approach since the local type has more fields
        let encoder = JSONEncoder()
        let answersJson = try String(data: encoder.encode(answers), encoding: .utf8) ?? "{}"
        
        let sql = """
        INSERT INTO pre_sleep_logs (id, session_id, created_at_utc, local_offset_minutes, completion_state, answers_json)
        VALUES (?, ?, ?, ?, ?, ?)
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "EventStorage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare pre-sleep log insert"])
        }
        defer { sqlite3_finalize(stmt) }
        
        let id = UUID().uuidString
        let now = nowProvider()
        let offset = timeZoneProvider().secondsFromGMT() / 60
        
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, sessionKey, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, isoFormatter.string(from: now), -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 4, Int32(offset))
        sqlite3_bind_text(stmt, 5, completionState, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 6, answersJson, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            let error = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "EventStorage", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to insert pre-sleep log: \(error)"])
        }
    }
    
    public func fetchPreSleepLog(sessionKey: String) -> DoseCore.StoredPreSleepLog? {
        guard let local = fetchMostRecentPreSleepLog(sessionId: sessionKey) else { return nil }
        // Convert local type to DoseCore type
        // local.createdAtUtc is String, DoseCore.createdAtUTC is Date
        // local.answers is PreSleepLogAnswers?, DoseCore.answersJson is String
        let createdDate = isoFormatter.date(from: local.createdAtUtc) ?? Date()
        let answersJsonStr: String
        if let answers = local.answers {
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(answers), let str = String(data: data, encoding: .utf8) {
                answersJsonStr = str
            } else {
                answersJsonStr = "{}"
            }
        } else {
            answersJsonStr = "{}"
        }
        return DoseCore.StoredPreSleepLog(
            id: local.id,
            sessionId: local.sessionId,
            createdAtUTC: createdDate,
            localOffsetMinutes: local.localOffsetMinutes,
            completionState: local.completionState,
            answersJson: answersJsonStr
        )
    }
    
    // MARK: - Morning Check-Ins
    
    public func saveMorningCheckIn(_ checkIn: DoseCore.StoredMorningCheckIn, sessionKey: String) {
        // Convert DoseCore type to local type and save
        let local = StoredMorningCheckIn(
            id: checkIn.id,
            sessionId: checkIn.sessionId,
            timestamp: checkIn.timestamp,
            sessionDate: checkIn.sessionDate,
            sleepQuality: checkIn.sleepQuality,
            feelRested: checkIn.feelRested,
            grogginess: checkIn.grogginess,
            sleepInertiaDuration: checkIn.sleepInertiaDuration,
            dreamRecall: checkIn.dreamRecall,
            hasPhysicalSymptoms: checkIn.hasPhysicalSymptoms,
            physicalSymptomsJson: checkIn.physicalSymptomsJson,
            hasRespiratorySymptoms: checkIn.hasRespiratorySymptoms,
            respiratorySymptomsJson: checkIn.respiratorySymptomsJson,
            mentalClarity: checkIn.mentalClarity,
            mood: checkIn.mood,
            anxietyLevel: checkIn.anxietyLevel,
            readinessForDay: checkIn.readinessForDay,
            hadSleepParalysis: checkIn.hadSleepParalysis,
            hadHallucinations: checkIn.hadHallucinations,
            hadAutomaticBehavior: checkIn.hadAutomaticBehavior,
            fellOutOfBed: checkIn.fellOutOfBed,
            hadConfusionOnWaking: checkIn.hadConfusionOnWaking,
            usedSleepTherapy: checkIn.usedSleepTherapy,
            sleepTherapyJson: checkIn.sleepTherapyJson,
            hasSleepEnvironment: checkIn.hasSleepEnvironment,
            sleepEnvironmentJson: checkIn.sleepEnvironmentJson,
            notes: checkIn.notes
        )
        saveMorningCheckIn(local, forSession: sessionKey)
    }
    
    public func fetchMorningCheckIn(sessionKey: String) -> DoseCore.StoredMorningCheckIn? {
        guard let local = fetchMorningCheckInInternal(sessionKey: sessionKey) else { return nil }
        return DoseCore.StoredMorningCheckIn(
            id: local.id,
            sessionId: local.sessionId,
            timestamp: local.timestamp,
            sessionDate: local.sessionDate,
            sleepQuality: local.sleepQuality,
            feelRested: local.feelRested,
            grogginess: local.grogginess,
            sleepInertiaDuration: local.sleepInertiaDuration,
            dreamRecall: local.dreamRecall,
            hasPhysicalSymptoms: local.hasPhysicalSymptoms,
            physicalSymptomsJson: local.physicalSymptomsJson,
            hasRespiratorySymptoms: local.hasRespiratorySymptoms,
            respiratorySymptomsJson: local.respiratorySymptomsJson,
            mentalClarity: local.mentalClarity,
            mood: local.mood,
            anxietyLevel: local.anxietyLevel,
            readinessForDay: local.readinessForDay,
            hadSleepParalysis: local.hadSleepParalysis,
            hadHallucinations: local.hadHallucinations,
            hadAutomaticBehavior: local.hadAutomaticBehavior,
            fellOutOfBed: local.fellOutOfBed,
            hadConfusionOnWaking: local.hadConfusionOnWaking,
            usedSleepTherapy: local.usedSleepTherapy,
            sleepTherapyJson: local.sleepTherapyJson,
            hasSleepEnvironment: local.hasSleepEnvironment,
            sleepEnvironmentJson: local.sleepEnvironmentJson,
            notes: local.notes
        )
    }
    
    private func fetchMorningCheckInInternal(sessionKey: String) -> StoredMorningCheckIn? {
        let sql = """
        SELECT id, session_id, timestamp, session_date, sleep_quality, feel_rested, grogginess,
               sleep_inertia_duration, dream_recall, has_physical_symptoms, physical_symptoms_json,
               has_respiratory_symptoms, respiratory_symptoms_json, mental_clarity, mood, anxiety_level,
               readiness_for_day, had_sleep_paralysis, had_hallucinations, had_automatic_behavior,
               fell_out_of_bed, had_confusion_on_waking, used_sleep_therapy, sleep_therapy_json,
               has_sleep_environment, sleep_environment_json, notes
        FROM morning_checkins
        WHERE session_id = ? OR session_date = ?
        ORDER BY timestamp DESC
        LIMIT 1
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, sessionKey, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, sessionKey, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        
        guard let idPtr = sqlite3_column_text(stmt, 0),
              let sessionIdPtr = sqlite3_column_text(stmt, 1),
              let timestampPtr = sqlite3_column_text(stmt, 2),
              let sessionDatePtr = sqlite3_column_text(stmt, 3) else { return nil }
        
        let timestamp = isoFormatter.date(from: String(cString: timestampPtr)) ?? Date()
        
        return StoredMorningCheckIn(
            id: String(cString: idPtr),
            sessionId: String(cString: sessionIdPtr),
            timestamp: timestamp,
            sessionDate: String(cString: sessionDatePtr),
            sleepQuality: Int(sqlite3_column_int(stmt, 4)),
            feelRested: sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? "moderate",
            grogginess: sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? "mild",
            sleepInertiaDuration: sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? "fiveToFifteen",
            dreamRecall: sqlite3_column_text(stmt, 8).map { String(cString: $0) } ?? "none",
            hasPhysicalSymptoms: sqlite3_column_int(stmt, 9) != 0,
            physicalSymptomsJson: sqlite3_column_text(stmt, 10).map { String(cString: $0) },
            hasRespiratorySymptoms: sqlite3_column_int(stmt, 11) != 0,
            respiratorySymptomsJson: sqlite3_column_text(stmt, 12).map { String(cString: $0) },
            mentalClarity: Int(sqlite3_column_int(stmt, 13)),
            mood: sqlite3_column_text(stmt, 14).map { String(cString: $0) } ?? "neutral",
            anxietyLevel: sqlite3_column_text(stmt, 15).map { String(cString: $0) } ?? "none",
            readinessForDay: Int(sqlite3_column_int(stmt, 16)),
            hadSleepParalysis: sqlite3_column_int(stmt, 17) != 0,
            hadHallucinations: sqlite3_column_int(stmt, 18) != 0,
            hadAutomaticBehavior: sqlite3_column_int(stmt, 19) != 0,
            fellOutOfBed: sqlite3_column_int(stmt, 20) != 0,
            hadConfusionOnWaking: sqlite3_column_int(stmt, 21) != 0,
            usedSleepTherapy: sqlite3_column_int(stmt, 22) != 0,
            sleepTherapyJson: sqlite3_column_text(stmt, 23).map { String(cString: $0) },
            hasSleepEnvironment: sqlite3_column_int(stmt, 24) != 0,
            sleepEnvironmentJson: sqlite3_column_text(stmt, 25).map { String(cString: $0) },
            notes: sqlite3_column_text(stmt, 26).map { String(cString: $0) }
        )
    }
    
    // MARK: - Session Management
    
    public func fetchRecentSessions(days: Int) -> [DoseCore.SessionSummary] {
        let localSessions = fetchRecentSessionsInternal(days: days)
        return localSessions.map { local in
            DoseCore.SessionSummary(
                sessionDate: local.sessionDate,
                dose1Time: local.dose1Time,
                dose2Time: local.dose2Time,
                dose2Skipped: local.dose2Skipped,
                snoozeCount: local.snoozeCount,
                sleepEvents: local.sleepEvents.map { event in
                    DoseCore.StoredSleepEvent(
                        id: event.id,
                        eventType: event.eventType,
                        timestamp: event.timestamp,
                        sessionDate: event.sessionDate,
                        colorHex: event.colorHex,
                        notes: event.notes
                    )
                },
                eventCount: local.eventCount
            )
        }
    }
    
    private func fetchRecentSessionsInternal(days: Int) -> [SessionSummary] {
        fetchRecentSessionsLocal(days: days)
    }
    
    public func deleteSession(sessionKey: String) {
        deleteSession(sessionDate: sessionKey)
    }
}
