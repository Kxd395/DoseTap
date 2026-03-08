import Foundation
import SQLite3
import DoseCore
import CryptoKit

@MainActor
extension EventStorage {
    // MARK: - Database Setup
    
    func openDatabase() {
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
    
    func createTables() {
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
            stress_level INTEGER,
            stress_context_json TEXT,
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
            "ALTER TABLE morning_checkins ADD COLUMN stress_level INTEGER",
            "ALTER TABLE morning_checkins ADD COLUMN stress_context_json TEXT",
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
        AppFormatters.parseISO8601Flexible(string)
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
    
}
