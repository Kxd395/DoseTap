import Foundation
import SQLite3
import DoseCore
import os.log

// MARK: - Normalized Check-In Submission Storage

extension EventStorage {

    func upsertCheckInSubmission(
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

    @discardableResult
    public func recordSymptomEvent(
        _ event: StoredSymptomEvent,
        idempotencyKey: String
    ) throws -> StoredSymptomEvent {
        if let existing = fetchSymptomEvent(forIdempotencyKey: idempotencyKey) {
            return existing
        }

        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        do {
            try insertSymptomCommand(
                idempotencyKey: idempotencyKey,
                event: event,
                status: "pending",
                createdEventId: nil,
                errorCode: nil
            )
            try insertSymptomEvent(event)
            for location in event.locations {
                try insertSymptomLocation(location, eventId: event.id)
                for point in location.points {
                    try insertBodyMapPoint(point, locationId: location.id)
                }
            }
            try rebuildSymptomSummary(sessionDate: event.sessionDate)
            try updateSymptomCommandComplete(idempotencyKey: idempotencyKey, eventId: event.id)
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
            return event
        } catch {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            try? markSymptomCommandFailed(idempotencyKey: idempotencyKey, event: event, error: error)
            throw error
        }
    }

    @discardableResult
    public func replaceSymptomEvents(
        source: SymptomEventSource,
        sourceRecordId: String,
        sessionDate: String,
        events: [StoredSymptomEvent]
    ) throws -> [StoredSymptomEvent] {
        guard events.allSatisfy({
            $0.source == source
                && $0.sourceRecordId == sourceRecordId
                && $0.sessionDate == sessionDate
        }) else {
            throw SymptomStorageError.sourceRecordMismatch
        }

        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        do {
            try deleteSymptomCommands(source: source, sourceRecordId: sourceRecordId)
            try deleteSymptomEvents(source: source, sourceRecordId: sourceRecordId)

            for event in events {
                let idempotencyKey = symptomIdempotencyKey(for: event)
                try insertSymptomCommand(
                    idempotencyKey: idempotencyKey,
                    event: event,
                    status: "pending",
                    createdEventId: nil,
                    errorCode: nil
                )
                try insertSymptomEvent(event)
                for location in event.locations {
                    try insertSymptomLocation(location, eventId: event.id)
                    for point in location.points {
                        try insertBodyMapPoint(point, locationId: location.id)
                    }
                }
                try updateSymptomCommandComplete(idempotencyKey: idempotencyKey, eventId: event.id)
            }

            try rebuildSymptomSummary(sessionDate: sessionDate)
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
            return events
        } catch {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }

    public func clearSymptomEvents(
        source: SymptomEventSource,
        sourceRecordId: String
    ) throws {
        let affectedSessionDates = fetchSymptomSessionDates(source: source, sourceRecordId: sourceRecordId)

        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        do {
            try deleteSymptomCommands(source: source, sourceRecordId: sourceRecordId)
            try deleteSymptomEvents(source: source, sourceRecordId: sourceRecordId)
            for sessionDate in affectedSessionDates {
                try rebuildSymptomSummary(sessionDate: sessionDate)
            }
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
        } catch {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }

    public func fetchSymptomEvents(sessionDate: String) -> [StoredSymptomEvent] {
        fetchSymptomEvents(whereClause: "session_date = ?", bindValue: sessionDate)
    }

    public func fetchSymptomEvents(sessionId: String) -> [StoredSymptomEvent] {
        fetchSymptomEvents(whereClause: "session_id = ?", bindValue: sessionId)
    }

    public func fetchSymptomSummary(sessionDate: String) -> StoredSymptomSummary? {
        let sql = """
            SELECT session_date, session_id, symptom_count, highest_severity,
                   sleep_disruption_count, still_present_count, summary_hash, rebuilt_at
            FROM symptom_summaries
            WHERE session_date = ?
            LIMIT 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let sessionDatePtr = sqlite3_column_text(stmt, 0),
              let hashPtr = sqlite3_column_text(stmt, 6),
              let rebuiltPtr = sqlite3_column_text(stmt, 7) else { return nil }

        return StoredSymptomSummary(
            sessionDate: String(cString: sessionDatePtr),
            sessionId: sqlite3_column_text(stmt, 1).map { String(cString: $0) },
            symptomCount: Int(sqlite3_column_int(stmt, 2)),
            highestSeverity: sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 3)),
            sleepDisruptionCount: Int(sqlite3_column_int(stmt, 4)),
            stillPresentCount: Int(sqlite3_column_int(stmt, 5)),
            summaryHash: String(cString: hashPtr),
            rebuiltAt: isoFormatter.date(from: String(cString: rebuiltPtr)) ?? Date(timeIntervalSince1970: 0)
        )
    }

    func symptomEvents(
        fromPainEntries entries: [PreSleepLogAnswers.PainEntry],
        source: SymptomEventSource,
        sourceRecordId: String,
        sessionId: String?,
        sessionDate: String,
        phase: SymptomCheckInPhase,
        noticedAt: Date,
        sleepDisruption: Bool,
        stillPresent: Bool
    ) throws -> [StoredSymptomEvent] {
        try entries.sorted { $0.entryKey < $1.entryKey }.enumerated().map { index, entry in
            let entryKey = entry.entryKey
            let eventId = stableSymptomEventId(
                source: source,
                sourceRecordId: sourceRecordId,
                sourceEntryKey: entryKey
            )
            let location = StoredSymptomLocation(
                id: "\(eventId):location:0",
                bodySide: symptomBodySide(from: entry.side),
                bodyRegionId: entry.area.rawValue,
                anatomyLayer: symptomAnatomyLayer(from: entry.sensations),
                precision: .region,
                confidence: .approximate
            )

            return try StoredSymptomEvent(
                id: eventId,
                sessionId: sessionId,
                sessionDate: sessionDate,
                phase: phase,
                source: source,
                sourceRecordId: sourceRecordId,
                sourceEntryKey: entryKey,
                kind: symptomKind(from: entry.sensations),
                noticedAt: noticedAt.addingTimeInterval(TimeInterval(index)),
                severity0to10: entry.intensity,
                sleepDisruption: sleepDisruption,
                stillPresent: stillPresent,
                functionalImpact: entry.pattern?.rawValue,
                note: normalizedSymptomNote(entry.notes),
                schemaVersion: 1,
                appVersion: currentAppVersionString(),
                createdAt: nowProvider(),
                locations: [location]
            )
        }
    }

    func painEntries(fromPhysicalSymptomsJson json: String?) -> [PreSleepLogAnswers.PainEntry] {
        let physical = jsonDictionary(from: json)
        if let entries = physical["painEntries"] as? [[String: Any]] {
            let parsed = entries.compactMap(parsePainEntry)
            if !parsed.isEmpty {
                return parsed.sorted { $0.entryKey < $1.entryKey }
            }
        }
        return legacyPainEntries(from: physical).sorted { $0.entryKey < $1.entryKey }
    }

    private func fetchSymptomEvent(forIdempotencyKey idempotencyKey: String) -> StoredSymptomEvent? {
        let sql = """
            SELECT created_event_id
            FROM symptom_command_log
            WHERE idempotency_key = ? AND status = 'complete' AND created_event_id IS NOT NULL
            LIMIT 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, idempotencyKey, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let idPtr = sqlite3_column_text(stmt, 0) else { return nil }
        return fetchSymptomEvent(id: String(cString: idPtr))
    }

    private func fetchSymptomEvent(id: String) -> StoredSymptomEvent? {
        fetchSymptomEvents(whereClause: "id = ?", bindValue: id).first
    }

    private func fetchSymptomSessionDates(source: SymptomEventSource, sourceRecordId: String) -> [String] {
        let sql = """
            SELECT DISTINCT session_date
            FROM symptom_events
            WHERE source = ? AND source_record_id = ?
            ORDER BY session_date ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, source.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, sourceRecordId, -1, SQLITE_TRANSIENT)

        var rows: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let datePtr = sqlite3_column_text(stmt, 0) else { continue }
            rows.append(String(cString: datePtr))
        }
        return rows
    }

    private func fetchSymptomEvents(whereClause: String, bindValue: String) -> [StoredSymptomEvent] {
        let sql = """
            SELECT id, session_id, session_date, phase, source, source_record_id, source_entry_key, kind, noticed_at,
                   severity_0_10, sleep_disruption, still_present, functional_impact,
                   note, schema_version, app_version, created_at
            FROM symptom_events
            WHERE \(whereClause)
            ORDER BY noticed_at ASC, created_at ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, bindValue, -1, SQLITE_TRANSIENT)
        var rows: [StoredSymptomEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let event = decodeSymptomEventRow(stmt) else { continue }
            rows.append(event)
        }
        return rows
    }

    private func decodeSymptomEventRow(_ stmt: OpaquePointer?) -> StoredSymptomEvent? {
        guard
            let idPtr = sqlite3_column_text(stmt, 0),
            let sessionDatePtr = sqlite3_column_text(stmt, 2),
            let phasePtr = sqlite3_column_text(stmt, 3),
            let sourcePtr = sqlite3_column_text(stmt, 4),
            let kindPtr = sqlite3_column_text(stmt, 7),
            let noticedPtr = sqlite3_column_text(stmt, 8),
            let appVersionPtr = sqlite3_column_text(stmt, 15),
            let createdPtr = sqlite3_column_text(stmt, 16),
            let phase = SymptomCheckInPhase(rawValue: String(cString: phasePtr)),
            let source = SymptomEventSource(rawValue: String(cString: sourcePtr)),
            let kind = SymptomKind(rawValue: String(cString: kindPtr))
        else { return nil }

        let eventId = String(cString: idPtr)
        return try? StoredSymptomEvent(
            id: eventId,
            sessionId: sqlite3_column_text(stmt, 1).map { String(cString: $0) },
            sessionDate: String(cString: sessionDatePtr),
            phase: phase,
            source: source,
            sourceRecordId: sqlite3_column_text(stmt, 5).map { String(cString: $0) },
            sourceEntryKey: sqlite3_column_text(stmt, 6).map { String(cString: $0) },
            kind: kind,
            noticedAt: isoFormatter.date(from: String(cString: noticedPtr)) ?? Date(timeIntervalSince1970: 0),
            severity0to10: sqlite3_column_type(stmt, 9) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 9)),
            sleepDisruption: sqlite3_column_int(stmt, 10) != 0,
            stillPresent: sqlite3_column_int(stmt, 11) != 0,
            functionalImpact: sqlite3_column_text(stmt, 12).map { String(cString: $0) },
            note: sqlite3_column_text(stmt, 13).map { String(cString: $0) },
            schemaVersion: Int(sqlite3_column_int(stmt, 14)),
            appVersion: String(cString: appVersionPtr),
            createdAt: isoFormatter.date(from: String(cString: createdPtr)) ?? Date(timeIntervalSince1970: 0),
            locations: fetchSymptomLocations(eventId: eventId)
        )
    }

    private func fetchSymptomLocations(eventId: String) -> [StoredSymptomLocation] {
        let sql = """
            SELECT id, body_side, body_region_id, anatomy_layer, precision, confidence
            FROM symptom_locations
            WHERE event_id = ?
            ORDER BY rowid ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, eventId, -1, SQLITE_TRANSIENT)
        var rows: [StoredSymptomLocation] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard
                let idPtr = sqlite3_column_text(stmt, 0),
                let sidePtr = sqlite3_column_text(stmt, 1),
                let regionPtr = sqlite3_column_text(stmt, 2),
                let layerPtr = sqlite3_column_text(stmt, 3),
                let precisionPtr = sqlite3_column_text(stmt, 4),
                let confidencePtr = sqlite3_column_text(stmt, 5),
                let side = SymptomBodySide(rawValue: String(cString: sidePtr)),
                let layer = SymptomAnatomyLayer(rawValue: String(cString: layerPtr)),
                let precision = SymptomLocationPrecision(rawValue: String(cString: precisionPtr)),
                let confidence = SymptomLocationConfidence(rawValue: String(cString: confidencePtr))
            else { continue }

            let locationId = String(cString: idPtr)
            rows.append(
                StoredSymptomLocation(
                    id: locationId,
                    bodySide: side,
                    bodyRegionId: String(cString: regionPtr),
                    anatomyLayer: layer,
                    precision: precision,
                    confidence: confidence,
                    points: fetchBodyMapPoints(locationId: locationId)
                )
            )
        }
        return rows
    }

    private func fetchBodyMapPoints(locationId: String) -> [StoredBodyMapPoint] {
        let sql = """
            SELECT id, map_id, normalized_x, normalized_y, zoom_level, body_view
            FROM body_map_points
            WHERE location_id = ?
            ORDER BY rowid ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, locationId, -1, SQLITE_TRANSIENT)
        var rows: [StoredBodyMapPoint] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard
                let idPtr = sqlite3_column_text(stmt, 0),
                let mapPtr = sqlite3_column_text(stmt, 1),
                let viewPtr = sqlite3_column_text(stmt, 5),
                let view = SymptomBodyView(rawValue: String(cString: viewPtr))
            else { continue }

            if let point = try? StoredBodyMapPoint(
                id: String(cString: idPtr),
                mapId: String(cString: mapPtr),
                normalizedX: sqlite3_column_double(stmt, 2),
                normalizedY: sqlite3_column_double(stmt, 3),
                zoomLevel: sqlite3_column_double(stmt, 4),
                bodyView: view
            ) {
                rows.append(point)
            }
        }
        return rows
    }

    private func insertSymptomCommand(
        idempotencyKey: String,
        event: StoredSymptomEvent,
        status: String,
        createdEventId: String?,
        errorCode: String?
    ) throws {
        let sql = """
            INSERT INTO symptom_command_log (
                idempotency_key, command_type, source, source_record_id, source_entry_key, session_id, session_date, status,
                created_event_id, error_code, created_at, completed_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SymptomStorageError.commandAlreadyProcessed
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, idempotencyKey, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, "record_symptom_event", -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, event.source.rawValue, -1, SQLITE_TRANSIENT)
        bindNullableText(event.sourceRecordId, to: stmt, at: 4)
        bindNullableText(event.sourceEntryKey, to: stmt, at: 5)
        bindNullableText(event.sessionId, to: stmt, at: 6)
        sqlite3_bind_text(stmt, 7, event.sessionDate, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 8, status, -1, SQLITE_TRANSIENT)
        bindNullableText(createdEventId, to: stmt, at: 9)
        bindNullableText(errorCode, to: stmt, at: 10)
        sqlite3_bind_text(stmt, 11, isoFormatter.string(from: nowProvider()), -1, SQLITE_TRANSIENT)
        bindNullableText(status == "complete" ? isoFormatter.string(from: nowProvider()) : nil, to: stmt, at: 12)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SymptomStorageError.commandAlreadyProcessed
        }
    }

    private func insertSymptomEvent(_ event: StoredSymptomEvent) throws {
        let sql = """
            INSERT INTO symptom_events (
                id, session_id, session_date, phase, source, source_record_id, source_entry_key, kind, noticed_at,
                severity_0_10, sleep_disruption, still_present, functional_impact,
                note, schema_version, app_version, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SymptomStorageError.eventNotFound
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, event.id, -1, SQLITE_TRANSIENT)
        bindNullableText(event.sessionId, to: stmt, at: 2)
        sqlite3_bind_text(stmt, 3, event.sessionDate, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, event.phase.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, event.source.rawValue, -1, SQLITE_TRANSIENT)
        bindNullableText(event.sourceRecordId, to: stmt, at: 6)
        bindNullableText(event.sourceEntryKey, to: stmt, at: 7)
        sqlite3_bind_text(stmt, 8, event.kind.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 9, isoFormatter.string(from: event.noticedAt), -1, SQLITE_TRANSIENT)
        if let severity = event.severity0to10 {
            sqlite3_bind_int(stmt, 10, Int32(severity))
        } else {
            sqlite3_bind_null(stmt, 10)
        }
        sqlite3_bind_int(stmt, 11, event.sleepDisruption ? 1 : 0)
        sqlite3_bind_int(stmt, 12, event.stillPresent ? 1 : 0)
        bindNullableText(event.functionalImpact, to: stmt, at: 13)
        bindNullableText(event.note, to: stmt, at: 14)
        sqlite3_bind_int(stmt, 15, Int32(event.schemaVersion))
        sqlite3_bind_text(stmt, 16, event.appVersion, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 17, isoFormatter.string(from: event.createdAt), -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SymptomStorageError.eventNotFound
        }
    }

    private func insertSymptomLocation(_ location: StoredSymptomLocation, eventId: String) throws {
        let sql = """
            INSERT INTO symptom_locations (
                id, event_id, body_side, body_region_id, anatomy_layer, precision, confidence
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SymptomStorageError.missingLocation
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, location.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, eventId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, location.bodySide.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, location.bodyRegionId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, location.anatomyLayer.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 6, location.precision.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 7, location.confidence.rawValue, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SymptomStorageError.missingLocation
        }
    }

    private func insertBodyMapPoint(_ point: StoredBodyMapPoint, locationId: String) throws {
        let sql = """
            INSERT INTO body_map_points (
                id, location_id, map_id, normalized_x, normalized_y, zoom_level, body_view
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SymptomStorageError.invalidNormalizedPoint
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, point.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, locationId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, point.mapId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 4, point.normalizedX)
        sqlite3_bind_double(stmt, 5, point.normalizedY)
        sqlite3_bind_double(stmt, 6, point.zoomLevel)
        sqlite3_bind_text(stmt, 7, point.bodyView.rawValue, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SymptomStorageError.invalidNormalizedPoint
        }
    }

    private func deleteSymptomCommands(source: SymptomEventSource, sourceRecordId: String) throws {
        let sql = "DELETE FROM symptom_command_log WHERE source = ? AND source_record_id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SymptomStorageError.commandAlreadyProcessed
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, source.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, sourceRecordId, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SymptomStorageError.commandAlreadyProcessed
        }
    }

    private func deleteSymptomEvents(source: SymptomEventSource, sourceRecordId: String) throws {
        let sql = "DELETE FROM symptom_events WHERE source = ? AND source_record_id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SymptomStorageError.eventNotFound
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, source.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, sourceRecordId, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SymptomStorageError.eventNotFound
        }
    }

    private func updateSymptomCommandComplete(idempotencyKey: String, eventId: String) throws {
        let sql = """
            UPDATE symptom_command_log
            SET status = 'complete', created_event_id = ?, completed_at = ?
            WHERE idempotency_key = ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SymptomStorageError.commandAlreadyProcessed
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, eventId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, isoFormatter.string(from: nowProvider()), -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, idempotencyKey, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SymptomStorageError.commandAlreadyProcessed
        }
    }

    private func markSymptomCommandFailed(
        idempotencyKey: String,
        event: StoredSymptomEvent,
        error: Error
    ) throws {
        if fetchSymptomEvent(forIdempotencyKey: idempotencyKey) != nil { return }
        try? insertSymptomCommand(
            idempotencyKey: idempotencyKey,
            event: event,
            status: "failed",
            createdEventId: nil,
            errorCode: String(describing: error)
        )
    }

    private func rebuildSymptomSummary(sessionDate: String) throws {
        let events = fetchSymptomEvents(sessionDate: sessionDate)
        guard !events.isEmpty else {
            try deleteSymptomSummary(sessionDate: sessionDate)
            return
        }
        let highestSeverity = events.compactMap(\.severity0to10).max()
        let sleepDisruptionCount = events.filter(\.sleepDisruption).count
        let stillPresentCount = events.filter(\.stillPresent).count
        let hashInput = [
            sessionDate,
            String(events.count),
            String(highestSeverity ?? -1),
            String(sleepDisruptionCount),
            String(stillPresentCount)
        ].joined(separator: "|")

        let sql = """
            INSERT OR REPLACE INTO symptom_summaries (
                session_date, session_id, symptom_count, highest_severity,
                sleep_disruption_count, still_present_count, summary_hash, rebuilt_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SymptomStorageError.eventNotFound
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
        bindNullableText(events.first?.sessionId, to: stmt, at: 2)
        sqlite3_bind_int(stmt, 3, Int32(events.count))
        if let highestSeverity {
            sqlite3_bind_int(stmt, 4, Int32(highestSeverity))
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_bind_int(stmt, 5, Int32(sleepDisruptionCount))
        sqlite3_bind_int(stmt, 6, Int32(stillPresentCount))
        sqlite3_bind_text(stmt, 7, hashInput, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 8, isoFormatter.string(from: nowProvider()), -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SymptomStorageError.eventNotFound
        }
    }

    private func deleteSymptomSummary(sessionDate: String) throws {
        let sql = "DELETE FROM symptom_summaries WHERE session_date = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SymptomStorageError.eventNotFound
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SymptomStorageError.eventNotFound
        }
    }

    private func symptomIdempotencyKey(for event: StoredSymptomEvent) -> String {
        [
            "derived_symptom_event",
            event.source.rawValue,
            event.sourceRecordId ?? "",
            event.sourceEntryKey ?? event.id
        ].joined(separator: ":")
    }

    private func stableSymptomEventId(
        source: SymptomEventSource,
        sourceRecordId: String,
        sourceEntryKey: String
    ) -> String {
        "symptom:\(source.rawValue):\(sourceRecordId):\(sourceEntryKey)"
    }

    private func currentAppVersionString() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (version, build) {
        case let (version?, build?):
            return "\(version) (\(build))"
        case let (version?, nil):
            return version
        case let (nil, build?):
            return build
        default:
            return "unknown"
        }
    }

    private func symptomKind(from sensations: [PreSleepLogAnswers.PainSensation]) -> SymptomKind {
        if sensations.contains(.numbness) { return .numbness }
        if sensations.contains(.pinsNeedles) { return .pinsNeedles }
        if sensations.contains(.burning) { return .burning }
        if sensations.contains(.shooting) || sensations.contains(.radiating) { return .electric }
        if sensations.contains(.throbbing) { return .throbbing }
        if sensations.contains(.cramping) { return .spasm }
        if sensations.contains(.tightness) { return .tightness }
        return .pain
    }

    private func symptomAnatomyLayer(from sensations: [PreSleepLogAnswers.PainSensation]) -> SymptomAnatomyLayer {
        if sensations.contains(.numbness)
            || sensations.contains(.pinsNeedles)
            || sensations.contains(.shooting)
            || sensations.contains(.radiating) {
            return .nerveLike
        }
        if sensations.contains(.cramping) || sensations.contains(.tightness) {
            return .muscle
        }
        return .unsure
    }

    private func symptomBodySide(from side: PreSleepLogAnswers.PainSide) -> SymptomBodySide {
        switch side {
        case .left: return .left
        case .right: return .right
        case .center: return .center
        case .both: return .both
        case .na: return .unknown
        }
    }

    private func normalizedSymptomNote(_ note: String?) -> String? {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == true ? nil : trimmed
    }

    private func parsePainEntry(from item: [String: Any]) -> PreSleepLogAnswers.PainEntry? {
        guard
            let areaValue = item["area"] as? String,
            let area = PreSleepLogAnswers.PainArea(rawValue: areaValue)
        else {
            return nil
        }

        let sideValue = item["side"] as? String ?? PreSleepLogAnswers.PainSide.na.rawValue
        let side = PreSleepLogAnswers.PainSide(rawValue: sideValue) ?? .na
        let intensity = intValue(from: item["intensity"]) ?? 0
        let sensations = (item["sensations"] as? [String] ?? [])
            .compactMap(PreSleepLogAnswers.PainSensation.init(rawValue:))
        let pattern = (item["pattern"] as? String).flatMap(PreSleepLogAnswers.PainPattern.init(rawValue:))
        let notes = item["notes"] as? String

        return PreSleepLogAnswers.PainEntry(
            area: area,
            side: side,
            intensity: intensity,
            sensations: sensations.isEmpty ? [.aching] : sensations,
            pattern: pattern,
            notes: notes
        )
    }

    private func legacyPainEntries(from physical: [String: Any]) -> [PreSleepLogAnswers.PainEntry] {
        guard let locations = physical["painLocations"] as? [String], !locations.isEmpty else {
            return []
        }

        let intensity = max(1, intValue(from: physical["painSeverity"]) ?? 1)
        let sensation = painSensation(fromLegacyPainType: physical["painType"] as? String)

        return locations.compactMap { location in
            guard let area = painArea(fromLegacyLocation: location) else { return nil }
            return PreSleepLogAnswers.PainEntry(
                area: area,
                side: .na,
                intensity: intensity,
                sensations: [sensation]
            )
        }
    }

    private func painArea(fromLegacyLocation value: String) -> PreSleepLogAnswers.PainArea? {
        if let exact = PreSleepLogAnswers.PainArea(rawValue: value) {
            return exact
        }

        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "head": return .headFace
        case "neck": return .neck
        case "shoulders": return .shoulder
        case "upper back": return .upperBack
        case "lower back": return .lowerBack
        case "hips": return .hipGlute
        case "legs", "feet": return .ankleFoot
        case "knees": return .knee
        case "hands": return .wristHand
        case "arms": return .armElbow
        case "chest": return .chestRibs
        case "abdomen": return .abdomen
        default: return .other
        }
    }

    private func painSensation(fromLegacyPainType value: String?) -> PreSleepLogAnswers.PainSensation {
        switch value {
        case "sharp": return .sharp
        case "burning": return .burning
        case "throbbing": return .throbbing
        case "cramping", "stiff": return .tightness
        default: return .aching
        }
    }

    private func intValue(from value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let double as Double:
            return Int(double)
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private func bindNullableText(_ value: String?, to stmt: OpaquePointer?, at index: Int32) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }
}
