//
//  DosingAmountSchema.swift
//  DoseTap
//
//  Created: January 19, 2026
//  Purpose: Schema definitions and migrations for dosing amount tracking
//

import Foundation
import SQLite3
import os.log

private let dosingSchemaLog = Logger(subsystem: "com.dosetap.app", category: "DosingAmountSchema")

// MARK: - Schema SQL Definitions

/// SQL statements for creating new dosing tables
enum DosingAmountSchema {
    
    /// Create the regimens table (the prescription/plan layer)
    static let createRegimensTable = """
    CREATE TABLE IF NOT EXISTS regimens (
        id TEXT PRIMARY KEY,
        medication_id TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        
        -- Effective date range
        start_at TEXT NOT NULL,
        end_at TEXT,
        
        -- Target dosing
        target_total_amount_value REAL NOT NULL,
        target_total_amount_unit TEXT NOT NULL DEFAULT 'mg',
        
        -- Split configuration
        split_mode TEXT NOT NULL DEFAULT 'equal',
        split_parts_count INTEGER NOT NULL DEFAULT 2,
        split_parts_ratio_json TEXT NOT NULL DEFAULT '[0.5, 0.5]',
        
        -- Optional context
        notes TEXT,
        prescribed_by TEXT
    );
    """
    
    /// Create the dose_bundles table (groups split parts)
    static let createDoseBundlesTable = """
    CREATE TABLE IF NOT EXISTS dose_bundles (
        id TEXT PRIMARY KEY,
        regimen_id TEXT,
        session_id TEXT NOT NULL,
        session_date TEXT NOT NULL,
        
        -- Snapshot of target at bundle creation
        target_total_amount_value REAL NOT NULL,
        target_total_amount_unit TEXT NOT NULL DEFAULT 'mg',
        target_split_ratio_json TEXT NOT NULL DEFAULT '[0.5, 0.5]',
        
        -- Timing
        bundle_started_at TEXT NOT NULL,
        bundle_completed_at TEXT,
        
        -- Label for UI
        bundle_label TEXT NOT NULL DEFAULT 'Bedtime',
        
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        notes TEXT,
        
        FOREIGN KEY (regimen_id) REFERENCES regimens(id)
    );
    """
    
    /// Create indexes for new tables
    static let createDosingIndexes = """
    CREATE INDEX IF NOT EXISTS idx_regimens_medication ON regimens(medication_id);
    CREATE INDEX IF NOT EXISTS idx_regimens_start ON regimens(start_at);
    CREATE INDEX IF NOT EXISTS idx_regimens_end ON regimens(end_at);
    CREATE INDEX IF NOT EXISTS idx_dose_bundles_session ON dose_bundles(session_id);
    CREATE INDEX IF NOT EXISTS idx_dose_bundles_session_date ON dose_bundles(session_date);
    CREATE INDEX IF NOT EXISTS idx_dose_bundles_regimen ON dose_bundles(regimen_id);
    CREATE INDEX IF NOT EXISTS idx_dose_events_bundle ON dose_events(bundle_id);
    """
    
    /// Migrations for dose_events table (new columns)
    static let doseEventsMigrations: [String] = [
        // Amount tracking (THE CRITICAL MISSING PIECE)
        "ALTER TABLE dose_events ADD COLUMN amount_value REAL",
        "ALTER TABLE dose_events ADD COLUMN amount_unit TEXT DEFAULT 'mg'",
        
        // Provenance tracking
        "ALTER TABLE dose_events ADD COLUMN source TEXT DEFAULT 'manual'",
        
        // Bundle relationship for split dose tracking
        "ALTER TABLE dose_events ADD COLUMN bundle_id TEXT",
        "ALTER TABLE dose_events ADD COLUMN part_index INTEGER",
        "ALTER TABLE dose_events ADD COLUMN parts_count INTEGER",
        
        // Medication link
        "ALTER TABLE dose_events ADD COLUMN medication_id TEXT",
        
        // Notes for manual annotations
        "ALTER TABLE dose_events ADD COLUMN notes TEXT"
    ]
    
    /// Migration to mark legacy dose_events as migrated
    static let markLegacyDoseEvents = """
    UPDATE dose_events 
    SET source = 'migrated' 
    WHERE source IS NULL OR source = 'manual'
    AND amount_value IS NULL;
    """
}

// MARK: - Migration Manager Extension

extension EventStorage {
    
    /// Run all dosing amount schema migrations.
    /// Safe to call multiple times - all operations are idempotent.
    func runDosingAmountMigrations() {
        dosingSchemaLog.info("Running dosing amount schema migrations")
        
        // 1. Create new tables
        createDosingTables()
        
        // 2. Add new columns to dose_events
        runDoseEventsMigrations()
        
        // 3. Mark legacy rows
        markLegacyDoseEventsAsMigrated()
        
        dosingSchemaLog.info("Dosing amount schema migrations complete")
    }
    
    private func createDosingTables() {
        let statements = [
            DosingAmountSchema.createRegimensTable,
            DosingAmountSchema.createDoseBundlesTable,
            DosingAmountSchema.createDosingIndexes
        ]
        
        for sql in statements {
            var errMsg: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
                // Ignore errors (table/index already exists)
                if let errMsg = errMsg {
                    // Only log if it's not an "already exists" error
                    let error = String(cString: errMsg)
                    if !error.contains("already exists") {
                        dosingSchemaLog.warning("Dosing schema warning: \(error, privacy: .public)")
                    }
                    sqlite3_free(errMsg)
                }
            }
        }
    }
    
    private func runDoseEventsMigrations() {
        for sql in DosingAmountSchema.doseEventsMigrations {
            var errMsg: UnsafeMutablePointer<CChar>?
            // Ignore errors (column already exists)
            sqlite3_exec(db, sql, nil, nil, &errMsg)
            if errMsg != nil {
                sqlite3_free(errMsg)
            }
        }
    }
    
    private func markLegacyDoseEventsAsMigrated() {
        var errMsg: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, DosingAmountSchema.markLegacyDoseEvents, nil, nil, &errMsg)
        if let errMsg = errMsg {
            sqlite3_free(errMsg)
        }
    }
}

// MARK: - Regimen Repository Methods

extension EventStorage {
    
    /// Insert a new regimen
    public func insertRegimen(_ regimen: Regimen) {
        let sql = """
        INSERT INTO regimens (
            id, medication_id, created_at, start_at, end_at,
            target_total_amount_value, target_total_amount_unit,
            split_mode, split_parts_count, split_parts_ratio_json,
            notes, prescribed_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        
        let ratioJson = (try? JSONEncoder().encode(regimen.splitPartsRatio))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[0.5, 0.5]"
        
        sqlite3_bind_text(stmt, 1, regimen.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, regimen.medicationId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, isoFormatter.string(from: regimen.createdAt), -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, isoFormatter.string(from: regimen.startAt), -1, SQLITE_TRANSIENT)
        if let endAt = regimen.endAt {
            sqlite3_bind_text(stmt, 5, isoFormatter.string(from: endAt), -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        sqlite3_bind_double(stmt, 6, regimen.targetTotalAmountValue)
        sqlite3_bind_text(stmt, 7, regimen.targetTotalAmountUnit.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 8, regimen.splitMode.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 9, Int32(regimen.splitPartsCount))
        sqlite3_bind_text(stmt, 10, ratioJson, -1, SQLITE_TRANSIENT)
        if let notes = regimen.notes {
            sqlite3_bind_text(stmt, 11, notes, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 11)
        }
        if let prescribedBy = regimen.prescribedBy {
            sqlite3_bind_text(stmt, 12, prescribedBy, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 12)
        }
        
        if sqlite3_step(stmt) != SQLITE_DONE {
            dosingSchemaLog.error("Failed to insert regimen: \(String(cString: sqlite3_errmsg(db)), privacy: .public)")
        }
    }
    
    /// Fetch the active regimen for a medication at a specific date
    public func fetchActiveRegimen(medicationId: String, at date: Date) -> Regimen? {
        let sql = """
        SELECT id, medication_id, created_at, start_at, end_at,
               target_total_amount_value, target_total_amount_unit,
               split_mode, split_parts_count, split_parts_ratio_json,
               notes, prescribed_by
        FROM regimens
        WHERE medication_id = ?
          AND start_at <= ?
          AND (end_at IS NULL OR end_at >= ?)
        ORDER BY start_at DESC
        LIMIT 1
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        
        let dateStr = isoFormatter.string(from: date)
        sqlite3_bind_text(stmt, 1, medicationId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, dateStr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, dateStr, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        
        return parseRegimenRow(stmt)
    }
    
    /// Fetch all regimens for a medication
    public func fetchAllRegimens(medicationId: String) -> [Regimen] {
        var regimens: [Regimen] = []
        
        let sql = """
        SELECT id, medication_id, created_at, start_at, end_at,
               target_total_amount_value, target_total_amount_unit,
               split_mode, split_parts_count, split_parts_ratio_json,
               notes, prescribed_by
        FROM regimens
        WHERE medication_id = ?
        ORDER BY start_at DESC
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, medicationId, -1, SQLITE_TRANSIENT)
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let regimen = parseRegimenRow(stmt) {
                regimens.append(regimen)
            }
        }
        
        return regimens
    }
    
    /// End a regimen (set end_at to now)
    public func endRegimen(id: String, at date: Date = Date()) {
        let sql = "UPDATE regimens SET end_at = ? WHERE id = ?"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, isoFormatter.string(from: date), -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, id, -1, SQLITE_TRANSIENT)
        
        sqlite3_step(stmt)
    }
    
    private func parseRegimenRow(_ stmt: OpaquePointer?) -> Regimen? {
        guard let idPtr = sqlite3_column_text(stmt, 0),
              let medIdPtr = sqlite3_column_text(stmt, 1),
              let createdPtr = sqlite3_column_text(stmt, 2),
              let startPtr = sqlite3_column_text(stmt, 3) else { return nil }
        
        let id = String(cString: idPtr)
        let medicationId = String(cString: medIdPtr)
        
        guard let createdAt = isoFormatter.date(from: String(cString: createdPtr)),
              let startAt = isoFormatter.date(from: String(cString: startPtr)) else { return nil }
        
        let endAt: Date? = sqlite3_column_text(stmt, 4)
            .flatMap { isoFormatter.date(from: String(cString: $0)) }
        
        let amountValue = sqlite3_column_double(stmt, 5)
        let amountUnit = sqlite3_column_text(stmt, 6)
            .flatMap { AmountUnit(rawValue: String(cString: $0)) } ?? .mg
        
        let splitMode = sqlite3_column_text(stmt, 7)
            .flatMap { SplitMode(rawValue: String(cString: $0)) } ?? .equal
        
        let partsCount = Int(sqlite3_column_int(stmt, 8))
        
        let ratioJson = sqlite3_column_text(stmt, 9).map { String(cString: $0) } ?? "[0.5, 0.5]"
        let partsRatio = (try? JSONDecoder().decode([Double].self, from: Data(ratioJson.utf8))) ?? [0.5, 0.5]
        
        let notes = sqlite3_column_text(stmt, 10).map { String(cString: $0) }
        let prescribedBy = sqlite3_column_text(stmt, 11).map { String(cString: $0) }
        
        return Regimen(
            id: id,
            medicationId: medicationId,
            createdAt: createdAt,
            startAt: startAt,
            endAt: endAt,
            targetTotalAmountValue: amountValue,
            targetTotalAmountUnit: amountUnit,
            splitMode: splitMode,
            splitPartsCount: partsCount,
            splitPartsRatio: partsRatio,
            notes: notes,
            prescribedBy: prescribedBy
        )
    }
}

// MARK: - Dose Bundle Repository Methods

extension EventStorage {
    
    /// Insert a new dose bundle
    public func insertDoseBundle(_ bundle: DoseBundle) {
        let sql = """
        INSERT INTO dose_bundles (
            id, regimen_id, session_id, session_date,
            target_total_amount_value, target_total_amount_unit, target_split_ratio_json,
            bundle_started_at, bundle_completed_at, bundle_label,
            created_at, notes
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        
        let ratioJson = (try? JSONEncoder().encode(bundle.targetSplitRatio))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[0.5, 0.5]"
        
        sqlite3_bind_text(stmt, 1, bundle.id, -1, SQLITE_TRANSIENT)
        if let regimenId = bundle.regimenId {
            sqlite3_bind_text(stmt, 2, regimenId, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        sqlite3_bind_text(stmt, 3, bundle.sessionId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, bundle.sessionDate, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 5, bundle.targetTotalAmountValue)
        sqlite3_bind_text(stmt, 6, bundle.targetTotalAmountUnit.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 7, ratioJson, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 8, isoFormatter.string(from: bundle.bundleStartedAt), -1, SQLITE_TRANSIENT)
        if let completedAt = bundle.bundleCompletedAt {
            sqlite3_bind_text(stmt, 9, isoFormatter.string(from: completedAt), -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 9)
        }
        sqlite3_bind_text(stmt, 10, bundle.bundleLabel, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 11, isoFormatter.string(from: bundle.createdAt), -1, SQLITE_TRANSIENT)
        if let notes = bundle.notes {
            sqlite3_bind_text(stmt, 12, notes, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 12)
        }
        
        if sqlite3_step(stmt) != SQLITE_DONE {
            dosingSchemaLog.error("Failed to insert dose bundle: \(String(cString: sqlite3_errmsg(db)), privacy: .public)")
        }
    }
    
    /// Fetch the current active bundle for a session
    public func fetchActiveBundle(sessionId: String) -> DoseBundle? {
        let sql = """
        SELECT id, regimen_id, session_id, session_date,
               target_total_amount_value, target_total_amount_unit, target_split_ratio_json,
               bundle_started_at, bundle_completed_at, bundle_label,
               created_at, notes
        FROM dose_bundles
        WHERE session_id = ? AND bundle_completed_at IS NULL
        ORDER BY bundle_started_at DESC
        LIMIT 1
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, sessionId, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        
        return parseBundleRow(stmt)
    }
    
    /// Mark a bundle as completed
    public func completeBundle(id: String, at date: Date = Date()) {
        let sql = "UPDATE dose_bundles SET bundle_completed_at = ? WHERE id = ?"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, isoFormatter.string(from: date), -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, id, -1, SQLITE_TRANSIENT)
        
        sqlite3_step(stmt)
    }
    
    private func parseBundleRow(_ stmt: OpaquePointer?) -> DoseBundle? {
        guard let idPtr = sqlite3_column_text(stmt, 0),
              let sessionIdPtr = sqlite3_column_text(stmt, 2),
              let sessionDatePtr = sqlite3_column_text(stmt, 3),
              let startedAtPtr = sqlite3_column_text(stmt, 7),
              let labelPtr = sqlite3_column_text(stmt, 9),
              let createdAtPtr = sqlite3_column_text(stmt, 10) else { return nil }
        
        let id = String(cString: idPtr)
        let regimenId = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
        let sessionId = String(cString: sessionIdPtr)
        let sessionDate = String(cString: sessionDatePtr)
        
        let amountValue = sqlite3_column_double(stmt, 4)
        let amountUnit = sqlite3_column_text(stmt, 5)
            .flatMap { AmountUnit(rawValue: String(cString: $0)) } ?? .mg
        
        let ratioJson = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? "[0.5, 0.5]"
        let splitRatio = (try? JSONDecoder().decode([Double].self, from: Data(ratioJson.utf8))) ?? [0.5, 0.5]
        
        guard let bundleStartedAt = isoFormatter.date(from: String(cString: startedAtPtr)),
              let createdAt = isoFormatter.date(from: String(cString: createdAtPtr)) else { return nil }
        
        let bundleCompletedAt: Date? = sqlite3_column_text(stmt, 8)
            .flatMap { isoFormatter.date(from: String(cString: $0)) }
        
        let bundleLabel = String(cString: labelPtr)
        let notes = sqlite3_column_text(stmt, 11).map { String(cString: $0) }
        
        return DoseBundle(
            id: id,
            regimenId: regimenId,
            sessionId: sessionId,
            sessionDate: sessionDate,
            targetTotalAmountValue: amountValue,
            targetTotalAmountUnit: amountUnit,
            targetSplitRatio: splitRatio,
            bundleStartedAt: bundleStartedAt,
            bundleCompletedAt: bundleCompletedAt,
            bundleLabel: bundleLabel,
            createdAt: createdAt,
            notes: notes
        )
    }
}

// MARK: - Dose Event With Amount Methods

extension EventStorage {
    
    /// Insert a dose event with amount
    public func insertDoseEventWithAmount(_ event: DoseEventWithAmount) {
        let sql = """
        INSERT INTO dose_events (
            id, event_type, timestamp, session_date, session_id,
            amount_value, amount_unit, source,
            bundle_id, part_index, parts_count,
            medication_id, notes, is_hazard, metadata
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            dosingSchemaLog.error("Failed to prepare dose event insert: \(String(cString: sqlite3_errmsg(db)), privacy: .public)")
            return
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, event.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, event.eventType, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, isoFormatter.string(from: event.occurredAt), -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, event.sessionDate, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, event.sessionId, -1, SQLITE_TRANSIENT)
        
        if let amount = event.amountValue {
            sqlite3_bind_double(stmt, 6, amount)
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        
        if let unit = event.amountUnit {
            sqlite3_bind_text(stmt, 7, unit.rawValue, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        
        sqlite3_bind_text(stmt, 8, event.source.rawValue, -1, SQLITE_TRANSIENT)
        
        if let bundleId = event.bundleId {
            sqlite3_bind_text(stmt, 9, bundleId, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 9)
        }
        
        if let partIndex = event.partIndex {
            sqlite3_bind_int(stmt, 10, Int32(partIndex))
        } else {
            sqlite3_bind_null(stmt, 10)
        }
        
        if let partsCount = event.partsCount {
            sqlite3_bind_int(stmt, 11, Int32(partsCount))
        } else {
            sqlite3_bind_null(stmt, 11)
        }
        
        if let medId = event.medicationId {
            sqlite3_bind_text(stmt, 12, medId, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 12)
        }
        
        if let notes = event.notes {
            sqlite3_bind_text(stmt, 13, notes, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 13)
        }
        
        sqlite3_bind_int(stmt, 14, event.isHazard ? 1 : 0)
        
        if sqlite3_step(stmt) != SQLITE_DONE {
            dosingSchemaLog.error("Failed to insert dose event: \(String(cString: sqlite3_errmsg(db)), privacy: .public)")
        }
    }
    
    /// Fetch dose events for a bundle
    public func fetchDoseEventsForBundle(bundleId: String) -> [DoseEventWithAmount] {
        var events: [DoseEventWithAmount] = []
        
        let sql = """
        SELECT id, event_type, timestamp, session_date, session_id,
               amount_value, amount_unit, source,
               bundle_id, part_index, parts_count,
               medication_id, notes, created_at, is_hazard
        FROM dose_events
        WHERE bundle_id = ?
        ORDER BY timestamp ASC
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, bundleId, -1, SQLITE_TRANSIENT)
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let event = parseDoseEventWithAmountRow(stmt) {
                events.append(event)
            }
        }
        
        return events
    }
    
    /// Fetch dose events with amounts for a session
    public func fetchDoseEventsWithAmount(sessionId: String) -> [DoseEventWithAmount] {
        var events: [DoseEventWithAmount] = []
        
        let sql = """
        SELECT id, event_type, timestamp, session_date, session_id,
               amount_value, amount_unit, source,
               bundle_id, part_index, parts_count,
               medication_id, notes, created_at, is_hazard
        FROM dose_events
        WHERE session_id = ?
        ORDER BY timestamp ASC
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, sessionId, -1, SQLITE_TRANSIENT)
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let event = parseDoseEventWithAmountRow(stmt) {
                events.append(event)
            }
        }
        
        return events
    }
    
    /// Count events with reliable amounts vs migrated
    public func countDoseEventsBySource() -> (withAmount: Int, migrated: Int) {
        var withAmount = 0
        var migrated = 0
        
        let sql = """
        SELECT 
            COUNT(CASE WHEN amount_value IS NOT NULL THEN 1 END) as with_amount,
            COUNT(CASE WHEN source = 'migrated' OR amount_value IS NULL THEN 1 END) as migrated
        FROM dose_events
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return (0, 0) }
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            withAmount = Int(sqlite3_column_int(stmt, 0))
            migrated = Int(sqlite3_column_int(stmt, 1))
        }
        
        return (withAmount, migrated)
    }
    
    private func parseDoseEventWithAmountRow(_ stmt: OpaquePointer?) -> DoseEventWithAmount? {
        guard let idPtr = sqlite3_column_text(stmt, 0),
              let typePtr = sqlite3_column_text(stmt, 1),
              let timestampPtr = sqlite3_column_text(stmt, 2),
              let sessionDatePtr = sqlite3_column_text(stmt, 3),
              let sessionIdPtr = sqlite3_column_text(stmt, 4) else { return nil }
        
        let id = String(cString: idPtr)
        let eventType = String(cString: typePtr)
        
        guard let occurredAt = isoFormatter.date(from: String(cString: timestampPtr)) else { return nil }
        
        let sessionDate = String(cString: sessionDatePtr)
        let sessionId = String(cString: sessionIdPtr)
        
        // Amount (nullable)
        let amountValue: Double? = sqlite3_column_type(stmt, 5) == SQLITE_NULL 
            ? nil : sqlite3_column_double(stmt, 5)
        let amountUnit: AmountUnit? = sqlite3_column_text(stmt, 6)
            .flatMap { AmountUnit(rawValue: String(cString: $0)) }
        
        // Source
        let source = sqlite3_column_text(stmt, 7)
            .flatMap { DoseEventSource(rawValue: String(cString: $0)) } ?? .manual
        
        // Bundle relationship
        let bundleId = sqlite3_column_text(stmt, 8).map { String(cString: $0) }
        let partIndex: Int? = sqlite3_column_type(stmt, 9) == SQLITE_NULL 
            ? nil : Int(sqlite3_column_int(stmt, 9))
        let partsCount: Int? = sqlite3_column_type(stmt, 10) == SQLITE_NULL 
            ? nil : Int(sqlite3_column_int(stmt, 10))
        
        // Metadata
        let medicationId = sqlite3_column_text(stmt, 11).map { String(cString: $0) }
        let notes = sqlite3_column_text(stmt, 12).map { String(cString: $0) }
        
        let createdAt = sqlite3_column_text(stmt, 13)
            .flatMap { isoFormatter.date(from: String(cString: $0)) } ?? Date()
        
        let isHazard = sqlite3_column_int(stmt, 14) != 0
        
        return DoseEventWithAmount(
            id: id,
            eventType: eventType,
            occurredAt: occurredAt,
            sessionId: sessionId,
            sessionDate: sessionDate,
            amountValue: amountValue,
            amountUnit: amountUnit,
            source: source,
            bundleId: bundleId,
            partIndex: partIndex,
            partsCount: partsCount,
            medicationId: medicationId,
            notes: notes,
            createdAt: createdAt,
            isHazard: isHazard
        )
    }
}

// MARK: - Bundle Status Calculation

extension EventStorage {
    
    /// Get the current status of a dose bundle including logged events
    public func getBundleStatus(bundleId: String) -> DoseBundleStatus? {
        guard let bundle = fetchBundleById(bundleId) else { return nil }
        let events = fetchDoseEventsForBundle(bundleId: bundleId)
        return DoseBundleStatus(bundle: bundle, loggedEvents: events)
    }
    
    private func fetchBundleById(_ id: String) -> DoseBundle? {
        let sql = """
        SELECT id, regimen_id, session_id, session_date,
               target_total_amount_value, target_total_amount_unit, target_split_ratio_json,
               bundle_started_at, bundle_completed_at, bundle_label,
               created_at, notes
        FROM dose_bundles
        WHERE id = ?
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        
        return parseBundleRow(stmt)
    }
    
    /// Create a bundle from the active regimen for a session
    public func createBundleFromActiveRegimen(
        medicationId: String,
        sessionId: String,
        sessionDate: String,
        bundleLabel: String = "Bedtime"
    ) -> DoseBundle? {
        // Find active regimen
        let regimen = fetchActiveRegimen(medicationId: medicationId, at: Date())
        
        let bundle = DoseBundle(
            regimenId: regimen?.id,
            sessionId: sessionId,
            sessionDate: sessionDate,
            targetTotalAmountValue: regimen?.targetTotalAmountValue ?? 0,
            targetTotalAmountUnit: regimen?.targetTotalAmountUnit ?? .mg,
            targetSplitRatio: regimen?.splitPartsRatio ?? [0.5, 0.5],
            bundleLabel: bundleLabel
        )
        
        insertDoseBundle(bundle)
        return bundle
    }
}
