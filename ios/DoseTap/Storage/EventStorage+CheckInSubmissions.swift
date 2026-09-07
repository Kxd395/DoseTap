import Foundation
import SQLite3
import DoseCore
import os.log

// MARK: - Normalized Check-In Submission Storage

struct NightOutcomeRecord: Codable {
    struct Revision: Codable {
        let answers: NightOutcomeDiary
        let recordedAt: Date
        let reason: String
    }
    let answers: NightOutcomeDiary
    let recordedAt: Date
    let revisions: [Revision]
}

struct NightOutcomeSnapshot {
    let history: HistoryRecordSnapshot
    let rawJSON: String?
    let record: NightOutcomeRecord?
}

extension EventStorage {
    /// Unlike the reporting query, editing must throw on missing/partial reads,
    /// unknown versions, malformed answers, and conflicting stable identities.
    func nightOutcomeSnapshot(sessionDate: String) throws -> NightOutcomeSnapshot {
        let history = try historySnapshot(sessionDate: sessionDate)
        let sql = "SELECT source_record_id, session_id, session_date, questionnaire_version, responses_json FROM checkin_submissions WHERE checkin_type = 'night_outcome' AND (session_date = ?1 OR source_record_id = ?2)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw MedicationStorageInjectedFailure(code: .statement, detail: "Night outcomes could not be read.")
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, sessionDate, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, history.sessionId, -1, SQLITE_TRANSIENT)
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return .init(history: history, rawJSON: nil, record: nil) }
        func text(_ column: Int32) -> String? { sqlite3_column_text(statement, column).map { String(cString: $0) } }
        guard status == SQLITE_ROW, text(0) == history.sessionId, text(1) == history.sessionId,
              text(2) == sessionDate, text(3) == "night_outcome.v1", let raw = text(4),
              sqlite3_step(statement) == SQLITE_DONE else {
            throw MedicationStorageInjectedFailure(code: .precondition, detail: "Conflicting night outcomes need review. No answer was selected or changed.")
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(NightOutcomeRecord.self, from: Data(raw.utf8))
        guard record.answers.validationError(now: record.recordedAt) == nil else {
            throw MedicationStorageInjectedFailure(code: .precondition, detail: "Stored night outcomes need review.")
        }
        return .init(history: history, rawJSON: raw, record: record)
    }

    func saveNightOutcome(_ answers: NightOutcomeDiary, review: NightOutcomeSnapshot,
                          reason: String, recordedAt: Date) -> MedicationMutationResult {
        performMedicationTransaction(operation: .reconcileDoseState, sessionId: review.history.sessionId,
            sessionDate: review.history.sessionDate, timestamp: recordedAt) {
            let current = try nightOutcomeSnapshot(sessionDate: review.history.sessionDate)
            guard !current.history.isNew, current.history.sessionId == review.history.sessionId,
                  current.history.events == review.history.events, current.rawJSON == review.rawJSON else {
                throw MedicationStorageInjectedFailure(code: .precondition, detail: "This night's records changed. Reopen the diary and review before saving.")
            }
            if let error = answers.validationError(now: recordedAt) {
                throw MedicationStorageInjectedFailure(code: .precondition, detail: error)
            }
            let dose2 = current.history.events.first { $0.eventType == "dose2" }?.timestamp
            let dose1 = current.history.events.first { $0.eventType == "dose1" }?.timestamp
            guard answers.wakeMethod == .unknown || dose2 != nil,
                  answers.sleepiness == nil || answers.finalWakeAt != nil,
                  answers.finalWakeAt.map({ $0 >= (dose2 ?? dose1 ?? $0) }) ?? true else {
                throw MedicationStorageInjectedFailure(code: .precondition, detail: "Record Dose 2 before its wake method. For next-day sleepiness, record final awakening after the dose.")
            }
            let explanation = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard explanation.count <= 500,
                  !(current.record.map { answers.changesAnsweredFields(of: $0.answers) } ?? false) || !explanation.isEmpty else {
                throw MedicationStorageInjectedFailure(code: .precondition, detail: "Enter a reason when correcting an existing answer (up to 500 characters).")
            }
            var revisions = current.record?.revisions ?? []
            if let previous = current.record {
                revisions.append(.init(answers: previous.answers, recordedAt: previous.recordedAt, reason: explanation))
            }
            let record = NightOutcomeRecord(answers: answers, recordedAt: recordedAt, revisions: revisions)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(record)
            guard let responses = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw MedicationStorageInjectedFailure(code: .statement, detail: "Night outcomes could not be encoded.")
            }
            try upsertCheckInSubmissionOrThrow(sourceRecordId: current.history.sessionId, sessionId: current.history.sessionId,
                sessionDate: current.history.sessionDate, checkInType: .nightOutcome,
                questionnaireVersion: "night_outcome.v1", submittedAt: recordedAt, responsesByQuestionID: responses)
        }
    }
}

extension EventStorage {

    enum SQLiteTransactionError: Error, LocalizedError {
        case beginFailed(String)
        case commitFailed(String)

        var errorDescription: String? {
            switch self {
            case .beginFailed(let message): return "Failed to begin SQLite transaction: \(message)"
            case .commitFailed(let message): return "Failed to commit SQLite transaction: \(message)"
            }
        }
    }

    enum CheckInSubmissionStoreError: Error, LocalizedError {
        case encodeFailed(String)
        case prepareFailed(String)
        case stepFailed(String)
        case deletePrepareFailed(String)
        case deleteStepFailed(String)

        var errorDescription: String? {
            switch self {
            case .encodeFailed(let sourceRecordId): return "Failed to encode check-in responses for \(sourceRecordId)"
            case .prepareFailed(let message): return "Failed to prepare check-in submission upsert: \(message)"
            case .stepFailed(let message): return "Failed to upsert check-in submission: \(message)"
            case .deletePrepareFailed(let message): return "Failed to prepare check-in submission delete: \(message)"
            case .deleteStepFailed(let message): return "Failed to delete check-in submission: \(message)"
            }
        }
    }

    func withSQLiteTransaction<T>(_ operation: () throws -> T) throws -> T {
        guard sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil) == SQLITE_OK else {
            throw SQLiteTransactionError.beginFailed(String(cString: sqlite3_errmsg(db)))
        }

        do {
            let result = try operation()
            guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else {
                let message = String(cString: sqlite3_errmsg(db))
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                throw SQLiteTransactionError.commitFailed(message)
            }
            return result
        } catch {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }

    func upsertCheckInSubmission(
        sourceRecordId: String,
        sessionId: String?,
        sessionDate: String,
        checkInType: CheckInType,
        questionnaireVersion: String,
        submittedAt: Date,
        responsesByQuestionID: [String: Any]
    ) {
        do {
            try upsertCheckInSubmissionOrThrow(
                sourceRecordId: sourceRecordId,
                sessionId: sessionId,
                sessionDate: sessionDate,
                checkInType: checkInType,
                questionnaireVersion: questionnaireVersion,
                submittedAt: submittedAt,
                responsesByQuestionID: responsesByQuestionID
            )
        } catch {
            storageLog.error("\(error.localizedDescription)")
        }
    }

    func upsertCheckInSubmissionOrThrow(
        sourceRecordId: String,
        sessionId: String?,
        sessionDate: String,
        checkInType: CheckInType,
        questionnaireVersion: String,
        submittedAt: Date,
        responsesByQuestionID: [String: Any]
    ) throws {
        guard let responsesJson = jsonString(from: responsesByQuestionID) else {
            throw CheckInSubmissionStoreError.encodeFailed(sourceRecordId)
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
            throw CheckInSubmissionStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
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
            throw CheckInSubmissionStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
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

    func deleteCheckInSubmissionOrThrow(sourceRecordId: String, checkInType: CheckInType) throws {
        let sql = "DELETE FROM checkin_submissions WHERE source_record_id = ? AND checkin_type = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw CheckInSubmissionStoreError.deletePrepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, sourceRecordId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, checkInType.rawValue, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw CheckInSubmissionStoreError.deleteStepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }
}
