import Foundation
import CryptoKit
import SQLite3
import DoseCore

struct DaytimeMainWakeSource: Equatable, Identifiable {
    let id: String
    let revision: String
    let at: Date
    let recordedAt: Date
}

@MainActor
extension SessionRepository {
    /// Exact existing source identity only. Callers must not substitute a nearby source for a saved ID.
    func daytimeMainWakeSources(asOf: Date) throws -> [DaytimeMainWakeSource] {
        guard asOf.timeIntervalSince1970.isFinite else { throw DaytimeDiaryError.invalid }
        return try storage.withDaytimeEvidenceRead { try storage.daytimeMainWakeSources(asOf: asOf) }
    }
}

extension EventStorage {
    /// A scoped SQLite snapshot, including nested callers; never a cache or persisted certificate.
    func withDaytimeEvidenceRead<T>(_ read: () throws -> T) throws -> T {
        guard databaseInitializationFailure == nil, db != nil,
              sqlite3_exec(db, "SAVEPOINT daytime_evidence_read", nil, nil, nil) == SQLITE_OK else { throw DaytimeDiaryError.unreadable }
        var released = false
        defer { if !released { sqlite3_exec(db, "RELEASE daytime_evidence_read", nil, nil, nil) } }
        let result = try read()
        guard sqlite3_exec(db, "RELEASE daytime_evidence_read", nil, nil, nil) == SQLITE_OK else { throw DaytimeDiaryError.unreadable }
        released = true
        return result
    }
    private func daytimeSourceText(_ statement: OpaquePointer, _ column: Int32) throws -> String {
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT, let bytes = sqlite3_column_text(statement, column),
              let value = String(bytes: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(statement, column))), encoding: .utf8),
              !value.contains("\0") else { throw DaytimeDiaryError.unreadable }
        return value
    }
    /// Three batch statements replace per-night history/identity/outcome queries.
    func daytimeMainWakeSources(asOf: Date) throws -> [DaytimeMainWakeSource] {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let rows: [(day: String, id: String, record: NightOutcomeRecord)] = try readExportRows("SELECT session_date, source_record_id, session_id, questionnaire_version, responses_json FROM checkin_submissions WHERE checkin_type = 'night_outcome' ORDER BY session_date") { statement in
            let day = try daytimeSourceText(statement, 0), id = try daytimeSourceText(statement, 1)
            guard let date = formatter.date(from: day), formatter.string(from: date) == day,
                  !id.isEmpty, id.count <= 300, try daytimeSourceText(statement, 2) == id,
                  try daytimeSourceText(statement, 3) == "night_outcome.v1" else { throw DaytimeDiaryError.unreadable }
            let record = try decoder.decode(NightOutcomeRecord.self, from: Data(daytimeSourceText(statement, 4).utf8))
            return (day, id, record)
        }
        guard Set(rows.map(\.day)).count == rows.count, Set(rows.map(\.id)).count == rows.count else { throw DaytimeDiaryError.unreadable }
        let identities: [(day: String, id: String)] = try readExportRows("""
            SELECT DISTINCT session_date, session_id FROM (
                SELECT session_date, session_id FROM dose_events
                UNION ALL SELECT session_date, session_id FROM sleep_sessions
                UNION ALL SELECT session_date, session_id FROM current_session
            ) WHERE session_id IS NOT NULL AND session_date IN
                (SELECT session_date FROM checkin_submissions WHERE checkin_type = 'night_outcome')
            """) { (try daytimeSourceText($0, 0), try daytimeSourceText($0, 1)) }
        let byDay = Dictionary(grouping: identities, by: \.day)
        let doses: [(day: String, id: String?)] = try readExportRows("""
            SELECT id, event_type, timestamp, session_date, session_id FROM dose_events
            WHERE session_date IN (SELECT session_date FROM checkin_submissions WHERE checkin_type = 'night_outcome')
               OR session_id IN (SELECT source_record_id FROM checkin_submissions WHERE checkin_type = 'night_outcome')
            """) { statement in
            _ = try daytimeSourceText(statement, 0); _ = try daytimeSourceText(statement, 1)
            guard let at = AppFormatters.parseISO8601Flexible(try daytimeSourceText(statement, 2)),
                  at.timeIntervalSince1970.isFinite else { throw DaytimeDiaryError.unreadable }
            return (try daytimeSourceText(statement, 3), sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : try daytimeSourceText(statement, 4))
        }
        let dosesByDay = Dictionary(grouping: doses, by: \.day)
        let dosesByID = Dictionary(grouping: doses.compactMap { dose in dose.id.map { (day: dose.day, id: $0) } }, by: \.id)
        var values: [DaytimeMainWakeSource] = []
        for row in rows {
            let candidates = Set((byDay[row.day] ?? []).map(\.id).filter { $0 != row.day })
            guard candidates.count <= 1, (candidates.first ?? row.day) == row.id,
                  (dosesByID[row.id] ?? []).allSatisfy({ $0.day == row.day }),
                  row.id != row.day || !(dosesByDay[row.day] ?? []).isEmpty || !(byDay[row.day] ?? []).isEmpty else { throw DaytimeDiaryError.unreadable }
            let record = row.record
            let history = record.revisions.map { ($0.answers, $0.recordedAt) } + [(record.answers, record.recordedAt)]
            guard history.allSatisfy({ $0.1.timeIntervalSince1970.isFinite && $0.1 <= record.recordedAt
                && $0.0.validationError(now: $0.1) == nil && ($0.0.reviewedSleepWindow.map { $0.sessionID == row.id } ?? true) }),
                  zip(history, history.dropFirst()).allSatisfy({ $0.0.1 <= $0.1.1 }) else { throw DaytimeDiaryError.unreadable }
            guard let selected = history.last(where: { $0.1 <= asOf }), let wake = selected.0.finalWakeAt else { continue }
            guard wake <= asOf else { throw DaytimeDiaryError.unreadable }
            let semantic = "\(row.id.utf8.count):\(row.id)|\(wake.timeIntervalSince1970)"
            let revision = SHA256.hash(data: Data(semantic.utf8)).map { String(format: "%02x", $0) }.joined()
            values.append(.init(id: row.id, revision: revision, at: wake, recordedAt: selected.1))
        }
        return values.sorted { $0.at == $1.at ? $0.id < $1.id : $0.at < $1.at }
    }
}
