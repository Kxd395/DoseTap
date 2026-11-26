import Foundation
import SQLite3
import DoseCore

struct DashboardLocalSession {
    let id: String
    let sessionID: String?
    let sessionDate: String
    var sessionClosed = false
    var sessionActive = false
    var doses: [DoseCore.StoredDoseEvent] = []
    var events: [StoredSleepEvent] = []
    var morning: StoredMorningCheckIn?
    var preSleep: StoredPreSleepLog?
    var outcome: NightOutcomeDiary?
    var outcomeReadFailed = false
    var needsReview = false
    var fingerprint = ""
    var contentObservations: [DashboardContentObservation] = []
}

@MainActor
extension SessionRepository {
    func dashboardLocalSessions() throws -> [DashboardLocalSession] {
        try storage.dashboardLocalSessions()
    }
}

@MainActor
extension EventStorage {
    /// Read every contributing table in one snapshot. No date-based fallback,
    /// legacy synchronization, limits, writes, or swallowed SQL failures.
    func dashboardLocalSessions(inTransaction: Bool = false) throws -> [DashboardLocalSession] {
        guard databaseInitializationFailure == nil, let db,
              (inTransaction ? sqlite3_get_autocommit(db) == 0 : (sqlite3_get_autocommit(db) != 0 && sqlite3_exec(db, "BEGIN DEFERRED", nil, nil, nil) == SQLITE_OK)) else { throw ExportReadError.unreadable }
        var committed = false
        defer { if !committed && !inTransaction { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) } }
        let records = try ["sleep_sessions", "current_session", "dose_events", "sleep_events",
                           "morning_checkins", "checkin_submissions", "pre_sleep_logs"].flatMap { try dashboardRows($0) }
        let result = try DashboardLocalSessionDecoder(timeZone: timeZoneProvider()).decode(records)
        guard inTransaction || sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else { throw ExportReadError.unreadable }
        committed = true
        return result
    }
}

/// Per-read formatters and value-only input; safe to use on a background worker.
struct DashboardLocalSessionDecoder {
    let timeZone: TimeZone
    private let plain: ISO8601DateFormatter
    private let fractional: ISO8601DateFormatter
    init(timeZone: TimeZone) {
        self.timeZone = timeZone
        plain = ISO8601DateFormatter()
        fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }
    func parse(_ text: String) -> Date? { fractional.date(from: text) ?? plain.date(from: text) }
    func decode(_ records: [StoredExportSourceRecord]) throws -> [DashboardLocalSession] {
        var dates: [String: Set<String>] = [:]
        for row in records where row.sourceTable != "pre_sleep_logs" {
            guard let day = row.columns["session_date"]?.text else { continue }
            if let identity = row.columns["session_id"]?.text, !identity.isEmpty, identity != day {
                dates[identity, default: []].insert(day)
            }
        }
        var groups: [String: DashboardLocalSession] = [:]
        var evidence: [String: [String]] = [:]
        var questionnaireCounts: [String: Int] = [:]
        for row in records {
            try Task.checkCancellation()
            let c = row.columns
            func text(_ key: String) -> String? { c[key]?.text }
            func required(_ key: String) throws -> String {
                guard let value = text(key), !value.isEmpty else { throw ExportReadError.unreadable }; return value
            }
            func timestamp(_ key: String) throws -> Date {
                guard let value = parse(try required(key)),
                      value.timeIntervalSince1970.isFinite else { throw ExportReadError.unreadable }; return value
            }
            // The singleton's unstarted placeholder is not an observation.
            if row.sourceTable == "current_session", text("session_id") == nil { continue }
            if row.sourceTable == "checkin_submissions", text("checkin_type") != "night_outcome" { continue }
            let identity = text("session_id").flatMap { $0.isEmpty ? nil : $0 }
            let day: String
            if row.sourceTable == "pre_sleep_logs" {
                if let identity, dates[identity]?.count == 1, let known = dates[identity]?.first { day = known }
                else if let identity, identity.count == 10, identity.dropFirst(4).first == "-" { day = identity }
                else { day = sessionKey(for: try timestamp("created_at_utc"), timeZone: timeZone, rolloverHour: 18) }
            } else { day = try required("session_date") }
            let resolved = identity.flatMap { $0 != day && dates[$0]?.count == 1 ? $0 : nil }
            let key: String
            if let resolved { key = "session:\(resolved)" }
            else if let identity, identity != day { key = "unresolved:\(identity):\(day)" }
            else if row.sourceTable == "pre_sleep_logs", identity == nil { key = "orphan:pre:\(try required("id"))" }
            else { key = "legacy:\(day)" }
            var group = groups[key] ?? DashboardLocalSession(id: key, sessionID: resolved, sessionDate: day)
            group.needsReview = group.needsReview || resolved == nil
            switch row.sourceTable {
            case "sleep_sessions", "current_session":
                if row.sourceTable == "current_session", resolved != nil,
                   text("session_end_utc") == nil, text("terminal_state") == nil,
                   let start = text("session_start_utc") ?? text("dose1_time") {
                    guard parse(start) != nil else { throw ExportReadError.unreadable }
                    group.sessionActive = true
                }
                if let ending = text("end_utc") ?? text("session_end_utc") {
                    guard parse(ending) != nil else { throw ExportReadError.unreadable }
                    group.sessionClosed = true
                }
            case "dose_events":
                group.doses.append(.init(id: try required("id"), eventType: try required("event_type"),
                    timestamp: try timestamp("timestamp"), sessionDate: day, metadata: text("metadata"), sessionId: identity))
            case "sleep_events":
                group.events.append(.init(id: try required("id"), eventType: try required("event_type"),
                    timestamp: try timestamp("timestamp"), sessionDate: day, colorHex: text("color_hex"), notes: text("notes")))
            case "pre_sleep_logs":
                let raw = try required("answers_json")
                let answers = try? JSONDecoder().decode(PreSleepLogAnswers.self, from: Data(raw.utf8))
                group.needsReview = group.needsReview || answers == nil
                let log = StoredPreSleepLog(id: try required("id"), sessionId: identity,
                    createdAtUtc: try required("created_at_utc"), localOffsetMinutes: Int(c["local_offset_minutes"]?.integer ?? 0),
                    completionState: try required("completion_state"), answers: answers)
                _ = try timestamp("created_at_utc")
                if group.preSleep == nil || log.createdAtUtc > group.preSleep!.createdAtUtc { group.preSleep = log }
                questionnaireCounts[key + ":pre", default: 0] += 1
            case "morning_checkins":
                let value = try dashboardMorning(row)
                if group.morning == nil || value.timestamp > group.morning!.timestamp { group.morning = value }
                questionnaireCounts[key + ":morning", default: 0] += 1
            case "checkin_submissions":
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                let record = text("responses_json").flatMap { try? decoder.decode(NightOutcomeRecord.self, from: Data($0.utf8)) }
                if text("questionnaire_version") == "night_outcome.v1", let record,
                   record.answers.validationError(now: record.recordedAt) == nil,
                   record.answers.reviewedSleepWindow.map({ $0.sessionID == resolved }) ?? true,
                   text("source_record_id") == identity, resolved != nil {
                    group.outcome = record.answers
                } else { group.outcomeReadFailed = true }
                questionnaireCounts[key + ":outcome", default: 0] += 1
            default: break
            }
            evidence[key, default: []].append(dashboardFingerprint([row.sourceTable] + c.keys.sorted().flatMap { name in
                let value = c[name]!
                return [name, value.type, value.text ?? "", value.integer.map(String.init) ?? "",
                        value.real.map { String($0) } ?? "", value.blobBase64 ?? ""]
            }))
            groups[key] = group
        }
        for key in groups.keys {
            if groups[key]?.sessionClosed == true {
                if groups[key]?.sessionActive == true { groups[key]?.needsReview = true }
                groups[key]?.sessionActive = false
            }
            groups[key]?.fingerprint = dashboardFingerprint(evidence[key, default: []].sorted())
            if questionnaireCounts[key + ":outcome", default: 0] > 1 {
                groups[key]?.outcome = nil; groups[key]?.outcomeReadFailed = true
            }
            if [":pre", ":morning", ":outcome"].contains(where: { questionnaireCounts[key + $0, default: 0] > 1 }) {
                groups[key]?.needsReview = true
            }
        }
        return groups.values.sorted { $0.id < $1.id }
    }

    private func dashboardMorning(_ row: StoredExportSourceRecord) throws -> StoredMorningCheckIn {
        let c = row.columns
        func s(_ key: String) -> String? { c[key]?.text }
        func n(_ key: String) -> Int { Int(c[key]?.integer ?? 0) }
        func b(_ key: String) -> Bool { n(key) != 0 }
        guard let id = s("id"), let session = s("session_id"), let day = s("session_date"),
              let raw = s("timestamp"), let timestamp = parse(raw) else { throw ExportReadError.unreadable }
        return StoredMorningCheckIn(id: id, sessionId: session, timestamp: timestamp, sessionDate: day,
            sleepQuality: c["sleep_quality"]?.real ?? Double(n("sleep_quality")), feelRested: s("feel_rested") ?? "moderate",
            grogginess: s("grogginess") ?? "mild", sleepInertiaDuration: s("sleep_inertia_duration") ?? "fiveToFifteen",
            dreamRecall: s("dream_recall") ?? "none", hasPhysicalSymptoms: b("has_physical_symptoms"),
            physicalSymptomsJson: s("physical_symptoms_json"), hasRespiratorySymptoms: b("has_respiratory_symptoms"),
            respiratorySymptomsJson: s("respiratory_symptoms_json"), mentalClarity: n("mental_clarity"), mood: s("mood") ?? "neutral",
            anxietyLevel: s("anxiety_level") ?? "none", stressLevel: c["stress_level"]?.integer.map(Int.init),
            stressContextJson: s("stress_context_json"), readinessForDay: n("readiness_for_day"), hadSleepParalysis: b("had_sleep_paralysis"),
            hadHallucinations: b("had_hallucinations"), hadAutomaticBehavior: b("had_automatic_behavior"), fellOutOfBed: b("fell_out_of_bed"),
            hadConfusionOnWaking: b("had_confusion_on_waking"), usedSleepTherapy: b("used_sleep_therapy"),
            sleepTherapyJson: s("sleep_therapy_json"), hasSleepEnvironment: b("has_sleep_environment"),
            sleepEnvironmentJson: s("sleep_environment_json"), timingContextJson: s("timing_context_json"), notes: s("notes"))
    }
}
