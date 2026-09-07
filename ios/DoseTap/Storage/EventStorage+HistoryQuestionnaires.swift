import Foundation
import SQLite3
import DoseCore

enum HistoryQuestionnaireKind: String, Identifiable {
    case preSleep, morning
    var id: String { rawValue }
    var title: String { self == .preSleep ? "Pre-Sleep Questionnaire" : "Morning Questionnaire" }
    var checkInType: EventStorage.CheckInType { self == .preSleep ? .preNight : .morning }
}

struct HistoryQuestionnaireSnapshot {
    let history: HistoryRecordSnapshot
    let kind: HistoryQuestionnaireKind
    let originalRows: [[String: String]]
    let originalSubmissions: [[String: String]]
    var existingID: String? { originalRows.first?["id"] }
}

extension EventStorage {
    /// Capture every stored field, not just fields understood by today's form.
    /// Fixed SQL is selected internally; dates and identities are bound values.
    func historyQuestionnaireSnapshot(sessionDate: String, kind: HistoryQuestionnaireKind) throws -> HistoryQuestionnaireSnapshot {
        let history = try historySnapshot(sessionDate: sessionDate)
        let table = kind == .preSleep ? "pre_sleep_logs" : "morning_checkins"
        let dateFilter = kind == .preSleep
            ? "id IN (SELECT source_record_id FROM checkin_submissions WHERE session_date = ?2 AND checkin_type = ?3)"
            : "session_date = ?2"
        let rows = try questionnaireRows("SELECT * FROM \(table) WHERE session_id IN (?1, ?2) OR \(dateFilter) ORDER BY id", history: history, kind: kind)
        let submissions = try questionnaireRows("SELECT * FROM checkin_submissions WHERE session_date = ?2 AND checkin_type = ?3 ORDER BY id", history: history, kind: kind)
        guard rows.count <= 1, submissions.count <= 1,
              rows.allSatisfy({ $0["session_id"] == history.sessionId || $0["session_id"] == sessionDate }),
              rows.allSatisfy({ $0["session_date"] == nil || $0["session_date"] == sessionDate }),
              submissions.allSatisfy({ $0["source_record_id"] == rows.first?["id"] && ($0["session_id"] == history.sessionId || $0["session_id"] == sessionDate) }) else {
            throw MedicationStorageInjectedFailure(code: .precondition, detail: "Conflicting questionnaire records need review. Nothing was selected or changed.")
        }
        return HistoryQuestionnaireSnapshot(history: history, kind: kind, originalRows: rows, originalSubmissions: submissions)
    }

    private func questionnaireRows(_ sql: String, history: HistoryRecordSnapshot, kind: HistoryQuestionnaireKind) throws -> [[String: String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw MedicationStorageInjectedFailure(code: .statement, detail: "Questionnaire history could not be read.")
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, history.sessionId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, history.sessionDate, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, kind.checkInType.rawValue, -1, SQLITE_TRANSIENT)
        var rows: [[String: String]] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            var row: [String: String] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                if let value = sqlite3_column_text(statement, index) {
                    row[String(cString: sqlite3_column_name(statement, index))] = String(cString: value)
                }
            }
            rows.append(row); status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw MedicationStorageInjectedFailure(code: .statement, detail: "Questionnaire history was only partially read.") }
        return rows
    }

    private func saveHistoryQuestionnaire(review: HistoryQuestionnaireSnapshot, occurredAt: Date, recordedAt: Date,
        reason: String, confirmed: Bool, write: (_ provenance: [String: Any]) throws -> Void) -> MedicationMutationResult {
        let history = review.history
        return performMedicationTransaction(operation: .reconcileDoseState, sessionId: history.sessionId,
            sessionDate: history.sessionDate, timestamp: occurredAt) {
            let current = try historyQuestionnaireSnapshot(sessionDate: history.sessionDate, kind: review.kind)
            let explanation = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard confirmed, !explanation.isEmpty, explanation.count <= 500,
                  occurredAt.timeIntervalSince1970.isFinite, recordedAt.timeIntervalSince1970.isFinite,
                  occurredAt <= recordedAt, sessionDateString(for: occurredAt) == history.sessionDate,
                  current.originalRows == review.originalRows, current.originalSubmissions == review.originalSubmissions,
                  current.history.events == history.events,
                  current.history.sessionId == history.sessionId || (current.history.isNew && history.isNew) else {
                throw MedicationStorageInjectedFailure(code: .precondition, detail: "Confirm the past time and reason for this treatment night. If its records changed, reopen the questionnaire.")
            }
            if current.history.isNew {
                try executeMedicationStatement("INSERT INTO sleep_sessions (session_id, session_date, start_utc, end_utc, terminal_state) VALUES (?, ?, ?, ?, 'history_manual')", at: .insert) { s in
                    sqlite3_bind_text(s, 1, history.sessionId, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(s, 2, history.sessionDate, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(s, 3, isoFormatter.string(from: occurredAt), -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(s, 4, isoFormatter.string(from: recordedAt), -1, SQLITE_TRANSIENT)
                }
            }
            try write(["entry_mode": "retrospective", "recorded_at_utc": isoFormatter.string(from: recordedAt),
                       "occurred_at_utc": isoFormatter.string(from: occurredAt), "reason": explanation,
                       "previous_records": review.originalRows, "previous_submissions": review.originalSubmissions])
        }
    }

    func saveHistoryPreSleep(answers: PreSleepLogAnswers, review: HistoryQuestionnaireSnapshot,
        occurredAt: Date, recordedAt: Date, reason: String, confirmed: Bool) -> MedicationMutationResult {
        saveHistoryQuestionnaire(review: review, occurredAt: occurredAt, recordedAt: recordedAt, reason: reason, confirmed: confirmed) { provenance in
            guard review.kind == .preSleep else { throw MedicationStorageInjectedFailure(code: .precondition, detail: "Reopen the pre-sleep questionnaire.") }
            let normalized = normalizedPreSleepAnswers(answers)
            let json = String(decoding: try JSONEncoder().encode(normalized), as: UTF8.self)
            let id = review.existingID ?? UUID().uuidString
            try upsertPreSleepLogRowOrThrow(id: id, sessionId: review.history.sessionId,
                createdAtUtc: isoFormatter.string(from: occurredAt), localOffsetMinutes: timeZoneProvider().secondsFromGMT(for: occurredAt) / 60,
                completionState: "complete", answersJson: json, replacing: review.existingID != nil)
            var responses = preSleepResponsesByQuestionID(normalized)
            responses["history.provenance"] = provenance
            try upsertCheckInSubmissionOrThrow(sourceRecordId: id, sessionId: review.history.sessionId, sessionDate: review.history.sessionDate,
                checkInType: .preNight, questionnaireVersion: CheckInQuestionnaireVersion.preNight, submittedAt: recordedAt, responsesByQuestionID: responses)
            try replacePreSleepSymptomEventsInCurrentTransaction(sourceRecordId: id, sessionId: review.history.sessionId,
                sessionDate: review.history.sessionDate, answers: normalized, completionState: "complete", submittedAt: occurredAt)
        }
    }

    func saveHistoryMorning(_ checkIn: StoredMorningCheckIn, review: HistoryQuestionnaireSnapshot,
        occurredAt: Date, recordedAt: Date, reason: String, confirmed: Bool) -> MedicationMutationResult {
        saveHistoryQuestionnaire(review: review, occurredAt: occurredAt, recordedAt: recordedAt, reason: reason, confirmed: confirmed) { provenance in
            guard review.kind == .morning, checkIn.sessionId == review.history.sessionId,
                  checkIn.sessionDate == review.history.sessionDate, checkIn.timestamp == occurredAt,
                  review.existingID == nil || review.existingID == checkIn.id else {
                throw MedicationStorageInjectedFailure(code: .precondition, detail: "Reopen the morning questionnaire for the selected night.")
            }
            try saveMorningCheckInRowOrThrow(checkIn, sessionDate: review.history.sessionDate, replacing: review.existingID != nil)
            var responses = morningResponsesByQuestionID(checkIn)
            responses["history.provenance"] = provenance
            try upsertCheckInSubmissionOrThrow(sourceRecordId: checkIn.id, sessionId: review.history.sessionId, sessionDate: review.history.sessionDate,
                checkInType: .morning, questionnaireVersion: CheckInQuestionnaireVersion.morning, submittedAt: recordedAt, responsesByQuestionID: responses)
            try replaceMorningCheckInSymptomEventsInCurrentTransaction(checkIn, sessionDate: review.history.sessionDate)
        }
    }
}
