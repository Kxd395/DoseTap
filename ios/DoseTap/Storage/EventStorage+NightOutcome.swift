import Foundation
import SQLite3
import DoseCore

extension SessionRepository {
    func collectedNightSummary(for key: String, intervals: [RecordedSleepInterval] = [],
                               providerFinalWake: Date? = nil,
                               windowAssessment: ReviewedWindowAssessment? = nil) throws -> CollectedNightSummary {
        let dose = fetchDoseLog(forSession: key)
        let food = fetchPreSleepLog(forSessionDate: key)?.answers?.lastFood
        let record = try nightOutcomeSnapshot(sessionDate: key).record
        var result = CollectedNightSummary()
        result.lastFoodFinishedAt = food?.finishedAt
        result.lastFoodKind = food?.kind?.rawValue
        result.lastFoodHighFat = food?.highFat
        result.lastFoodNotes = food?.notes
        result.lastFoodToDose1Minutes = CollectedNightSummary.minutes(from: food?.finishedAt, to: dose?.dose1Time)
        result.lastFoodToDose2Minutes = CollectedNightSummary.minutes(from: food?.finishedAt, to: dose?.dose2Time)
        result.dose2WakeMethod = record?.answers.wakeMethod.rawValue
        result.backupAlarmSet = record?.answers.backupAlarmSet
        result.followingDayType = record?.answers.dayType.rawValue
        result.finalWakeAt = record?.answers.finalWakeAt
        result.sleepiness0To10 = record?.answers.sleepiness
        result.sleepinessAssessedAt = record?.answers.assessedAt
        result.outcomeRecordedAt = record?.recordedAt
        result.reviewedSleepWindow = record?.answers.reviewedSleepWindow
        result.reviewedWindowAssessment = windowAssessment ?? reviewedWindowAssessment(sessionDate: key)
        result.estimateSleep(dose2: dose?.dose2Time, finalWake: result.finalWakeAt ?? providerFinalWake, intervals: intervals)
        return result
    }
}

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
    /// A read snapshot, never a persisted certificate or a medication transaction.
    func reviewedWindowAssessment(sessionDate: String, now: Date) -> ReviewedWindowAssessment {
        reviewedWindowAssessments(sessionDates: [sessionDate], now: now)[sessionDate] ?? .unavailable(now: now)
    }

    /// Batch-scoped evidence only: shared rows are decoded once, with no cache across exports.
    func reviewedWindowAssessments(sessionDates: [String], now: Date) -> [String: ReviewedWindowAssessment] {
        reviewedWindowRead(sessionDates: sessionDates, now: now).assessments
    }

    func reviewedNightSleepInput(sessionDate: String, now: Date) -> ReviewedNightSleepInput? {
        reviewedWindowRead(sessionDates: [sessionDate], now: now).inputs[sessionDate]
    }

    private func reviewedWindowRead(sessionDates: [String], now: Date)
        -> (assessments: [String: ReviewedWindowAssessment], inputs: [String: ReviewedNightSleepInput]) {
        let keys = Set(sessionDates).sorted()
        guard !keys.isEmpty else { return ([:], [:]) }
        let unavailable = Dictionary(uniqueKeysWithValues: keys.map { ($0, ReviewedWindowAssessment.unavailable(now: now)) })
        guard sqlite3_exec(db, "SAVEPOINT reviewed_window_read", nil, nil, nil) == SQLITE_OK else {
            return (unavailable, [:])
        }
        var released = false
        defer { if !released { sqlite3_exec(db, "RELEASE reviewed_window_read", nil, nil, nil) } }
        var results = unavailable
        var inputs: [String: ReviewedNightSleepInput] = [:]
        do {
            var snapshots: [String: NightOutcomeSnapshot] = [:]
            for key in keys {
                do { snapshots[key] = try nightOutcomeSnapshot(sessionDate: key) }
                catch { continue } // This key retains unavailable; other readable nights still get assessed.
            }
            for (key, snapshot) in snapshots where snapshot.record?.answers.reviewedSleepWindow == nil {
                results[key] = .calculate(window: nil, sessionID: snapshot.history.sessionId,
                    doses: [], otherWindows: [], naps: [], now: now)
            }
            var windows: [ReviewedSleepWindow] = [], naps: [ReviewedWindowAssessment.NapMarker] = []
            if snapshots.values.contains(where: { $0.record?.answers.reviewedSleepWindow != nil }) {
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                try readWindowEvidenceRows("SELECT source_record_id, session_id, questionnaire_version, responses_json FROM checkin_submissions WHERE checkin_type = 'night_outcome'") { row in
                    guard let identity = row(0), row(1) == identity, row(2) == "night_outcome.v1", let raw = row(3) else {
                        throw MedicationStorageInjectedFailure(code: .precondition, detail: "Night-window evidence needs review.")
                    }
                    let record = try decoder.decode(NightOutcomeRecord.self, from: Data(raw.utf8))
                    guard record.answers.validationError(now: record.recordedAt) == nil else {
                        throw MedicationStorageInjectedFailure(code: .precondition, detail: "Night-window evidence needs review.")
                    }
                    if let window = record.answers.reviewedSleepWindow {
                        guard window.sessionID == identity else {
                            throw MedicationStorageInjectedFailure(code: .precondition, detail: "Night-window identity needs review.")
                        }
                        windows.append(window)
                    }
                }
                try readWindowEvidenceRows("SELECT id, event_type, timestamp, session_id, session_date FROM sleep_events") { row in
                    guard let type = row(1) else { return }
                    let canonical = EventType(type)
                    guard canonical == .napStart || canonical == .napEnd else { return }
                    guard let id = row(0), let raw = row(2), let timestamp = AppFormatters.parseISO8601Flexible(raw),
                          let key = row(4), !key.isEmpty else {
                        throw MedicationStorageInjectedFailure(code: .precondition, detail: "Nap evidence needs review.")
                    }
                    let identity = row(3)
                    let group = identity.flatMap { !$0.isEmpty && $0 != key ? "id:\($0)" : nil } ?? "date:\(key)"
                    naps.append(.init(id: id, group: group, timestamp: timestamp, isStart: canonical == .napStart))
                }
            }
            for (key, snapshot) in snapshots {
                // Normalize only this read projection, using the same aliases as medication history.
                let doses = snapshot.history.events.map { event in
                    DoseCore.StoredDoseEvent(id: event.id,
                        eventType: CanonicalDoseEventType(canonicalizing: event.eventType)?.rawValue ?? event.eventType,
                        timestamp: event.timestamp, sessionDate: event.sessionDate,
                        metadata: event.metadata, sessionId: event.sessionId)
                }
                results[key] = ReviewedWindowAssessment.calculate(window: snapshot.record?.answers.reviewedSleepWindow,
                    sessionID: snapshot.history.sessionId, doses: doses, otherWindows: windows, naps: naps, now: now)
                inputs[key] = .init(sessionID: snapshot.history.sessionId, window: snapshot.record?.answers.reviewedSleepWindow,
                    outcomeJSON: snapshot.rawJSON, doses: doses, otherWindows: windows, naps: naps)
            }
            guard sqlite3_exec(db, "RELEASE reviewed_window_read", nil, nil, nil) == SQLITE_OK else { return (unavailable, [:]) }
            released = true
            return (results, inputs)
        } catch { return (results, [:]) } // Incomplete shared reads cannot supply a provider-query snapshot.
    }

    private func readWindowEvidenceRows(_ sql: String, consume: ((Int32) -> String?) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw MedicationStorageInjectedFailure(code: .statement, detail: "Window evidence could not be read.")
        }
        defer { sqlite3_finalize(statement) }
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            try consume { column in sqlite3_column_text(statement, column).map { String(cString: $0) } }
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else {
            throw MedicationStorageInjectedFailure(code: .statement, detail: "Window evidence was only partly read.")
        }
    }

    /// Called only inside a confirmed Dose 2 transaction, after its ledger insert.
    /// A failed answer write rolls back the dose too; selecting a checkbox never writes.
    func recordDose2WakeInCurrentTransaction(_ method: Dose2WakeKind?, sessionId: String,
                                             sessionDate: String, recordedAt: Date) throws {
        guard let method, method != .unknown else { return }
        let current = try nightOutcomeSnapshot(sessionDate: sessionDate)
        guard current.history.sessionId == sessionId,
              current.history.events.contains(where: { $0.eventType == "dose2" }) else {
            throw MedicationStorageInjectedFailure(code: .precondition, detail: "The Dose 2 wake answer needs the confirmed dose record.")
        }
        var answers = current.record?.answers ?? NightOutcomeDiary()
        answers.wakeMethod = method
        if let error = answers.validationError(now: recordedAt) {
            throw MedicationStorageInjectedFailure(code: .precondition, detail: error)
        }
        var revisions = current.record?.revisions ?? []
        if let previous = current.record, previous.answers != answers {
            revisions.append(.init(answers: previous.answers, recordedAt: previous.recordedAt,
                reason: "Wake method selected with explicit Dose 2 confirmation"))
        }
        let record = NightOutcomeRecord(answers: answers, recordedAt: recordedAt, revisions: revisions)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        guard let responses = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MedicationStorageInjectedFailure(code: .statement, detail: "The wake answer could not be encoded.")
        }
        try upsertCheckInSubmissionOrThrow(sourceRecordId: sessionId, sessionId: sessionId,
            sessionDate: sessionDate, checkInType: .nightOutcome, questionnaireVersion: "night_outcome.v1",
            submittedAt: recordedAt, responsesByQuestionID: responses)
    }

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
        guard record.answers.validationError(now: record.recordedAt) == nil,
              record.answers.reviewedSleepWindow.map({ $0.sessionID == history.sessionId }) ?? true else {
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
            guard answers.reviewedSleepWindow.map({ $0.sessionID == current.history.sessionId }) ?? true else {
                throw MedicationStorageInjectedFailure(code: .precondition, detail: "This window belongs to another night. Reload before saving.")
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
