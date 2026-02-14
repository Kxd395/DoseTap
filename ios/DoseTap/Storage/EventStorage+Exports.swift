import Foundation
import SQLite3

@MainActor
extension EventStorage {
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
