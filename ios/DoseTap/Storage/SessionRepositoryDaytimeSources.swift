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
        var values: [DaytimeMainWakeSource] = []
        let rows: [(day: String, id: String, payload: String)] = try storage.readExportRows("SELECT session_date, source_record_id, session_id, questionnaire_version, responses_json FROM checkin_submissions WHERE checkin_type = 'night_outcome' ORDER BY session_date") { statement in
            func text(_ column: Int32) throws -> String {
                guard sqlite3_column_type(statement, column) == SQLITE_TEXT, let bytes = sqlite3_column_text(statement, column),
                      let value = String(bytes: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(statement, column))), encoding: .utf8),
                      !value.contains("\0") else { throw DaytimeDiaryError.unreadable }
                return value
            }
            let day = try text(0), id = try text(1)
            guard day.count == 10, !id.isEmpty, id.count <= 300,
                  try text(2) == id, try text(3) == "night_outcome.v1" else { throw DaytimeDiaryError.unreadable }
            return (day, id, try text(4))
        }
        for row in rows {
            let snapshot = try nightOutcomeSnapshot(sessionDate: row.day)
            guard snapshot.history.sessionId == row.id, snapshot.rawJSON == row.payload else { throw DaytimeDiaryError.unreadable }
            guard let record = snapshot.record else { continue }
            let history = record.revisions.map { ($0.answers, $0.recordedAt) } + [(record.answers, record.recordedAt)]
            guard history.allSatisfy({ $0.1.timeIntervalSince1970.isFinite && $0.1 <= record.recordedAt && $0.0.validationError(now: $0.1) == nil }),
                  zip(history, history.dropFirst()).allSatisfy({ $0.0.1 <= $0.1.1 }) else { throw DaytimeDiaryError.unreadable }
            guard let selected = history.last(where: { $0.1 <= asOf }), let wake = selected.0.finalWakeAt else { continue }
            let id = snapshot.history.sessionId
            guard !id.isEmpty, id.count <= 300, !id.contains("\0"), wake <= asOf else { throw DaytimeDiaryError.unreadable }
            let semantic = "\(id.utf8.count):\(id)|\(wake.timeIntervalSince1970)"
            let revision = SHA256.hash(data: Data(semantic.utf8)).map { String(format: "%02x", $0) }.joined()
            values.append(.init(id: id, revision: revision, at: wake, recordedAt: selected.1))
        }
        guard Set(values.map(\.id)).count == values.count else { throw DaytimeDiaryError.unreadable }
        return values.sorted { $0.at == $1.at ? $0.id < $1.id : $0.at < $1.at }
    }
}
