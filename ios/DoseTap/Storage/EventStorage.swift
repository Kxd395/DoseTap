import Foundation
import Combine
import SQLite3
import DoseCore
import CryptoKit
import os.log

private let storageLog = Logger(subsystem: "com.dosetap.app", category: "EventStorage")

// MARK: - SQLite Helpers
// SQLITE_TRANSIENT is a C macro that doesn't exist in Swift
// We use unsafeBitCast to create the equivalent behavior
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

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
    private static let localUserIdentifierDefaultsKey = "dosetap.local.user_identifier"
    
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
        
        storageLog.info("EventStorage initialized at: \(self.dbPath)")
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    // MARK: - Database Setup
    
    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            storageLog.error("Failed to open database: \(String(cString: sqlite3_errmsg(self.db)))")
        }
        
        // Enable foreign key enforcement (required for CASCADE to work)
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA foreign_keys = ON", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)

        // Improve crash resilience and concurrent read/write behavior.
        if sqlite3_prepare_v2(db, "PRAGMA journal_mode = WAL", -1, &stmt, nil) == SQLITE_OK {
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

        -- Normalized questionnaire submissions (pre-night + morning)
        -- Keeps question-id keyed answers and versioning for trend analysis.
        CREATE TABLE IF NOT EXISTS checkin_submissions (
            id TEXT PRIMARY KEY,
            source_record_id TEXT NOT NULL,
            session_id TEXT,
            session_date TEXT NOT NULL,
            checkin_type TEXT NOT NULL,
            questionnaire_version TEXT NOT NULL,
            user_id TEXT NOT NULL,
            submitted_at_utc TEXT NOT NULL,
            local_offset_minutes INTEGER NOT NULL,
            responses_json TEXT NOT NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(source_record_id, checkin_type)
        );

        -- CloudKit tombstones for outbound delete sync
        CREATE TABLE IF NOT EXISTS cloudkit_tombstones (
            key TEXT PRIMARY KEY,
            record_type TEXT NOT NULL,
            record_name TEXT NOT NULL,
            created_at TEXT NOT NULL
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
        CREATE INDEX IF NOT EXISTS idx_checkin_submissions_session_date ON checkin_submissions(session_date);
        CREATE INDEX IF NOT EXISTS idx_checkin_submissions_session_id ON checkin_submissions(session_id);
        CREATE INDEX IF NOT EXISTS idx_checkin_submissions_type_time ON checkin_submissions(checkin_type, submitted_at_utc);
        CREATE INDEX IF NOT EXISTS idx_pre_sleep_logs_session_id ON pre_sleep_logs(session_id);
        CREATE INDEX IF NOT EXISTS idx_sleep_sessions_date ON sleep_sessions(session_date);
        CREATE INDEX IF NOT EXISTS idx_cloudkit_tombstones_created ON cloudkit_tombstones(created_at);
        
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
                storageLog.error("Failed to create tables: \(String(cString: errMsg))")
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
        storageLog.info("EventStorage: Normalized sleep_events types and purged dose rows")
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
        storageLog.info("EventStorage: Migrated \(legacyIds.count) legacy session IDs to UUIDs")
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

    /// Produce a deterministic UUID for legacy session keys to keep migrations stable.
    private func deterministicSessionUUID(for legacyId: String) -> String {
        let digest = SHA256.hash(data: Data(legacyId.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // Version 5-style
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC4122 variant

        let hex = bytes.map { String(format: "%02x", $0) }
        return "\(hex[0])\(hex[1])\(hex[2])\(hex[3])-\(hex[4])\(hex[5])-\(hex[6])\(hex[7])-\(hex[8])\(hex[9])-\(hex[10])\(hex[11])\(hex[12])\(hex[13])\(hex[14])\(hex[15])"
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
        storageLog.info("EventStorage: Deduplicated legacy dose/sleep events")
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
            storageLog.debug("EventStorage: Backfilled \(rowsToUpdate.count) pre_sleep_logs with session_id")
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
            storageLog.debug("EventStorage: Backfilled \(rowsToUpdate.count) medication_events with session_id")
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
            storageLog.debug("EventStorage: Backfilled \(rowsToUpdate.count) dose_events with session_id")
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
            storageLog.debug("EventStorage: Backfilled \(rowsToUpdate.count) sleep_events with session_id")
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
                storageLog.debug("EventStorage: Backfilled current_session.session_id with \(fallback)")
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

    private func localUserIdentifier() -> String {
        if let existing = UserDefaults.standard.string(forKey: Self.localUserIdentifierDefaultsKey), !existing.isEmpty {
            return existing
        }
        let created = "local_\(UUID().uuidString.lowercased())"
        UserDefaults.standard.set(created, forKey: Self.localUserIdentifierDefaultsKey)
        return created
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

    private func resolvedSessionDate(sessionId: String?, fallbackDate: Date) -> String {
        guard let sessionId else { return sessionDateString(for: fallbackDate) }
        if isSessionDateString(sessionId) {
            return sessionId
        }
        if let mapped = findSessionDate(for: sessionId) {
            return mapped
        }
        return sessionDateString(for: fallbackDate)
    }

    private func jsonDictionary(from jsonString: String?) -> [String: Any] {
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

    private func jsonString(from dictionary: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]),
              let output = String(data: data, encoding: .utf8) else {
            return nil
        }
        return output
    }

    private func preSleepPainScore(_ pain: PreSleepLogAnswers.PainLevel) -> Int {
        switch pain {
        case .none: return 0
        case .mild: return 3
        case .moderate: return 6
        case .severe: return 8
        }
    }

    private func preSleepPainEntryDictionaries(_ entries: [PreSleepLogAnswers.PainEntry]) -> [[String: Any]] {
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
            storageLog.error("Failed to prepare medication event insert")
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
            storageLog.error("Failed to insert medication event: \(String(cString: sqlite3_errmsg(self.db)))")
        } else {
            storageLog.debug("Medication event inserted: \(entry.medicationId) \(entry.doseMg)\(entry.doseUnit)")
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
            storageLog.error("Failed to delete medication event")
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

/// Stored normalized questionnaire submission for pre-night and morning check-ins.
public struct StoredCheckInSubmission: Identifiable {
    public let id: String
    public let sourceRecordId: String
    public let sessionId: String?
    public let sessionDate: String
    public let checkInType: EventStorage.CheckInType
    public let questionnaireVersion: String
    public let userId: String
    public let submittedAtUTC: Date
    public let localOffsetMinutes: Int
    public let responsesJson: String

    public init(
        id: String,
        sourceRecordId: String,
        sessionId: String?,
        sessionDate: String,
        checkInType: EventStorage.CheckInType,
        questionnaireVersion: String,
        userId: String,
        submittedAtUTC: Date,
        localOffsetMinutes: Int,
        responsesJson: String
    ) {
        self.id = id
        self.sourceRecordId = sourceRecordId
        self.sessionId = sessionId
        self.sessionDate = sessionDate
        self.checkInType = checkInType
        self.questionnaireVersion = questionnaireVersion
        self.userId = userId
        self.submittedAtUTC = submittedAtUTC
        self.localOffsetMinutes = localOffsetMinutes
        self.responsesJson = responsesJson
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

/// Pending outbound CloudKit delete marker.
public struct CloudKitTombstone: Identifiable {
    public let key: String
    public let recordType: String
    public let recordName: String
    public let createdAt: Date

    public var id: String { key }

    public init(key: String, recordType: String, recordName: String, createdAt: Date) {
        self.key = key
        self.recordType = recordType
        self.recordName = recordName
        self.createdAt = createdAt
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

    public enum PainArea: String, Codable, CaseIterable {
        case headFace = "head_face"
        case neck = "neck"
        case upperBack = "upper_back"
        case midBack = "mid_back"
        case lowerBack = "lower_back"
        case shoulder = "shoulder"
        case armElbow = "arm_elbow"
        case wristHand = "wrist_hand"
        case chestRibs = "chest_ribs"
        case abdomen = "abdomen"
        case hipGlute = "hip_glute"
        case knee = "knee"
        case ankleFoot = "ankle_foot"
        case other = "other"

        public init(legacyLocation: PainLocation) {
            switch legacyLocation {
            case .head: self = .headFace
            case .neck: self = .neck
            case .back: self = .lowerBack
            case .shoulders: self = .shoulder
            case .legs: self = .ankleFoot
            case .joints: self = .knee
            case .stomach: self = .abdomen
            case .other: self = .other
            }
        }

        public var displayText: String {
            switch self {
            case .headFace: return "Head / Face"
            case .neck: return "Neck"
            case .upperBack: return "Upper Back"
            case .midBack: return "Mid Back"
            case .lowerBack: return "Lower Back"
            case .shoulder: return "Shoulder"
            case .armElbow: return "Arm / Elbow"
            case .wristHand: return "Wrist / Hand"
            case .chestRibs: return "Chest / Ribs"
            case .abdomen: return "Abdomen"
            case .hipGlute: return "Hip / Glute"
            case .knee: return "Knee"
            case .ankleFoot: return "Ankle / Foot"
            case .other: return "Other"
            }
        }
    }

    public enum PainSide: String, Codable, CaseIterable {
        case left = "left"
        case right = "right"
        case center = "center"
        case both = "both"
        case na = "na"

        public var displayText: String {
            switch self {
            case .left: return "Left"
            case .right: return "Right"
            case .center: return "Center"
            case .both: return "Both"
            case .na: return "N/A"
            }
        }
    }

    public enum PainSensation: String, Codable, CaseIterable {
        case aching = "aching"
        case sharp = "sharp"
        case shooting = "shooting"
        case stabbing = "stabbing"
        case burning = "burning"
        case throbbing = "throbbing"
        case cramping = "cramping"
        case tightness = "tightness"
        case radiating = "radiating"
        case pinsNeedles = "pins_needles"
        case numbness = "numbness"
        case other = "other"

        public var displayText: String {
            switch self {
            case .aching: return "Aching"
            case .sharp: return "Sharp"
            case .shooting: return "Shooting"
            case .stabbing: return "Stabbing"
            case .burning: return "Burning"
            case .throbbing: return "Throbbing"
            case .cramping: return "Cramping"
            case .tightness: return "Tightness"
            case .radiating: return "Radiating"
            case .pinsNeedles: return "Pins / Needles"
            case .numbness: return "Numbness"
            case .other: return "Other"
            }
        }
    }

    public enum PainPattern: String, Codable, CaseIterable {
        case constant = "constant"
        case intermittent = "intermittent"
        case unknown = "unknown"

        public var displayText: String {
            switch self {
            case .constant: return "Constant"
            case .intermittent: return "Comes and goes"
            case .unknown: return "Unknown"
            }
        }
    }

    public struct PainEntry: Codable, Hashable, Identifiable {
        public var area: PainArea
        public var side: PainSide
        public var intensity: Int
        public var sensations: [PainSensation]
        public var pattern: PainPattern?
        public var notes: String?

        public var entryKey: String {
            "\(area.rawValue)|\(side.rawValue)"
        }

        public var id: String { entryKey }

        public init(
            area: PainArea,
            side: PainSide,
            intensity: Int,
            sensations: [PainSensation],
            pattern: PainPattern? = nil,
            notes: String? = nil
        ) {
            self.area = area
            self.side = side
            self.intensity = max(0, min(10, intensity))
            self.sensations = Array(Set(sensations)).sorted { $0.rawValue < $1.rawValue }
            self.pattern = pattern
            self.notes = notes
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

    public enum ExerciseType: String, Codable, CaseIterable {
        case walking = "walking"
        case cardio = "cardio"
        case strength = "strength"
        case yogaMobility = "yoga_mobility"
        case sports = "sports"
        case labor = "labor"
        case other = "other"

        public var displayText: String {
            switch self {
            case .walking: return "Walking"
            case .cardio: return "Cardio"
            case .strength: return "Strength"
            case .yogaMobility: return "Yoga / Mobility"
            case .sports: return "Sports"
            case .labor: return "Physical Labor"
            case .other: return "Other"
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
        case none = "none"
        case eyeMask = "eye_mask"
        case earplugs = "earplugs"
        case whiteNoise = "white_noise"
        case fan = "fan"
        case blackoutCurtains = "blackout_curtains"
        case multiple = "multiple"
        
        public var displayText: String {
            switch self {
            case .none: return "None"
            case .eyeMask: return "Eye Mask"
            case .earplugs: return "Earplugs"
            case .whiteNoise: return "White Noise"
            case .fan: return "Fan"
            case .blackoutCurtains: return "Blackout Curtains"
            case .multiple: return "Multiple"
            }
        }
        
        public var icon: String {
            switch self {
            case .none: return "moon.zzz"
            case .eyeMask: return "eye"
            case .earplugs: return "ear"
            case .whiteNoise: return "waveform"
            case .fan: return "wind"
            case .blackoutCurtains: return "curtains.closed"
            case .multiple: return "square.grid.2x2"
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
    public var painEntries: [PainEntry]?
    public var painLocations: [PainLocation]?
    public var painType: PainType?
    public var stimulants: Stimulants?
    public var caffeineLastIntakeAt: Date?
    public var caffeineLastAmountMg: Int?
    public var caffeineDailyTotalMg: Int?
    public var alcohol: AlcoholLevel?
    public var alcoholLastDrinkAt: Date?
    public var alcoholLastAmountDrinks: Double?
    public var alcoholDailyTotalDrinks: Double?
    
    // Card 3: Activity + Naps
    public var exercise: ExerciseLevel?
    public var exerciseType: ExerciseType?
    public var exerciseLastAt: Date?
    public var exerciseDurationMinutes: Int?
    public var napToday: NapDuration?
    public var napCount: Int?
    public var napTotalMinutes: Int?
    public var napLastEndAt: Date?
    
    // Optional details
    public var lateMeal: LateMeal?
    public var screensInBed: ScreensInBed?
    public var roomTemp: RoomTemp?
    public var noiseLevel: NoiseLevel?
    public var sleepAids: SleepAid?
    
    // Legacy fields (for backwards compatibility)
    public var notes: String?
    
    public init(
        intendedSleepTime: IntendedSleepTime? = nil,
        stressLevel: Int? = nil,
        stressDriver: StressDriver? = nil,
        laterReason: LaterReason? = nil,
        bodyPain: PainLevel? = nil,
        painEntries: [PainEntry]? = nil,
        painLocations: [PainLocation]? = nil,
        painType: PainType? = nil,
        stimulants: Stimulants? = nil,
        caffeineLastIntakeAt: Date? = nil,
        caffeineLastAmountMg: Int? = nil,
        caffeineDailyTotalMg: Int? = nil,
        alcohol: AlcoholLevel? = nil,
        alcoholLastDrinkAt: Date? = nil,
        alcoholLastAmountDrinks: Double? = nil,
        alcoholDailyTotalDrinks: Double? = nil,
        exercise: ExerciseLevel? = nil,
        exerciseType: ExerciseType? = nil,
        exerciseLastAt: Date? = nil,
        exerciseDurationMinutes: Int? = nil,
        napToday: NapDuration? = nil,
        napCount: Int? = nil,
        napTotalMinutes: Int? = nil,
        napLastEndAt: Date? = nil,
        lateMeal: LateMeal? = nil,
        screensInBed: ScreensInBed? = nil,
        roomTemp: RoomTemp? = nil,
        noiseLevel: NoiseLevel? = nil,
        sleepAids: SleepAid? = nil,
        notes: String? = nil
    ) {
        self.intendedSleepTime = intendedSleepTime
        self.stressLevel = stressLevel
        self.stressDriver = stressDriver
        self.laterReason = laterReason
        self.bodyPain = bodyPain
        self.painEntries = painEntries
        self.painLocations = painLocations
        self.painType = painType
        self.stimulants = stimulants
        self.caffeineLastIntakeAt = caffeineLastIntakeAt
        self.caffeineLastAmountMg = caffeineLastAmountMg
        self.caffeineDailyTotalMg = caffeineDailyTotalMg
        self.alcohol = alcohol
        self.alcoholLastDrinkAt = alcoholLastDrinkAt
        self.alcoholLastAmountDrinks = alcoholLastAmountDrinks
        self.alcoholDailyTotalDrinks = alcoholDailyTotalDrinks
        self.exercise = exercise
        self.exerciseType = exerciseType
        self.exerciseLastAt = exerciseLastAt
        self.exerciseDurationMinutes = exerciseDurationMinutes
        self.napToday = napToday
        self.napCount = napCount
        self.napTotalMinutes = napTotalMinutes
        self.napLastEndAt = napLastEndAt
        self.lateMeal = lateMeal
        self.screensInBed = screensInBed
        self.roomTemp = roomTemp
        self.noiseLevel = noiseLevel
        self.sleepAids = sleepAids
        self.notes = notes
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
        let sql = """
        SELECT id, event_type, timestamp, session_date, metadata
        FROM dose_events
        WHERE \(sessionId != nil ? "(session_id = ? OR session_date = ?)" : "session_date = ?")
        ORDER BY timestamp ASC
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        
        if let sessionId = sessionId {
            sqlite3_bind_text(stmt, 1, sessionId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, sessionDate, -1, SQLITE_TRANSIENT)
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
        let now = nowProvider()
        var mapped = PreSleepLogAnswers(
            stressLevel: answers.stressLevel,
            stimulants: answers.caffeineLast6Hours == true
                ? .multiple
                : (answers.caffeineLast6Hours == false ? PreSleepLogAnswers.Stimulants.none : nil),
            caffeineLastIntakeAt: answers.caffeineLast6Hours == true ? now : nil,
            caffeineLastAmountMg: answers.caffeineLast6Hours == true ? 95 : nil,
            caffeineDailyTotalMg: answers.caffeineLast6Hours == true ? 95 : nil,
            alcohol: answers.alcoholLast6Hours == true
                ? .one
                : (answers.alcoholLast6Hours == false ? PreSleepLogAnswers.AlcoholLevel.none : nil),
            alcoholLastDrinkAt: answers.alcoholLast6Hours == true ? now : nil,
            alcoholLastAmountDrinks: answers.alcoholLast6Hours == true ? 1 : nil,
            alcoholDailyTotalDrinks: answers.alcoholLast6Hours == true ? 1 : nil,
            exercise: answers.exerciseLast4Hours == true
                ? .moderate
                : (answers.exerciseLast4Hours == false ? PreSleepLogAnswers.ExerciseLevel.none : nil),
            exerciseType: answers.exerciseLast4Hours == true ? .cardio : nil,
            exerciseLastAt: answers.exerciseLast4Hours == true ? now : nil,
            exerciseDurationMinutes: answers.exerciseLast4Hours == true ? 30 : nil,
            lateMeal: answers.heavyMealLast3Hours == true
                ? .heavyMeal
                : (answers.heavyMealLast3Hours == false ? PreSleepLogAnswers.LateMeal.none : nil),
            screensInBed: answers.screenTime30MinPrior == true
                ? .thirtyMin
                : (answers.screenTime30MinPrior == false ? PreSleepLogAnswers.ScreensInBed.none : nil),
            notes: answers.notes
        )

        if let goalHours = answers.sleepGoalHours, goalHours > 0 {
            mapped.notes = [mapped.notes, "Sleep goal: \(goalHours)h \(answers.sleepGoalMinutes ?? 0)m"]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " | ")
        }

        _ = try savePreSleepLogOrThrow(
            sessionId: sessionKey,
            answers: mapped,
            completionState: completionState,
            now: now,
            timeZone: timeZoneProvider(),
            existingLog: fetchMostRecentPreSleepLog(sessionId: sessionKey)
        )
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
