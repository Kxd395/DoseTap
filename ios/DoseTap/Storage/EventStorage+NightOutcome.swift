import Foundation
import SQLite3
import DoseCore

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
