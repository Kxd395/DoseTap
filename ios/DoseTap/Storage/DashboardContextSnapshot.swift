import Foundation
import SQLite3
import DoseCore

private struct DashboardContentJoinKey: Hashable {
    let kind: String
    let sourceID: String
    let sessionID: String
    let sessionDate: String
}

struct DashboardContextLocalSnapshot {
    let sessions: [DashboardLocalSession]
    let associations: [DashboardProviderAssociation]
    let timeline: DashboardContextTimeline
}

@MainActor
extension SessionRepository {
    func dashboardContextSnapshot(capturedAt: Date) throws -> DashboardContextLocalSnapshot {
        try storage.dashboardContextSnapshot(capturedAt: capturedAt)
    }
}

@MainActor
extension EventStorage {
    /// Context and exact local identity share a single snapshot; failures never mean an empty history.
    func dashboardContextSnapshot(capturedAt: Date) throws -> DashboardContextLocalSnapshot {
        guard databaseInitializationFailure == nil, let db, sqlite3_get_autocommit(db) != 0,
              sqlite3_exec(db, "BEGIN DEFERRED", nil, nil, nil) == SQLITE_OK else { throw ExportReadError.unreadable }
        var committed = false
        defer { if !committed { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) } }
        var sessions = try dashboardLocalSessions(inTransaction: true)
        let sources = try dashboardRows("checkin_submissions").map { row -> (row: StoredExportSourceRecord, content: DashboardContentObservation) in
            guard let id = row.columns["id"]?.text, !id.isEmpty, let kind = row.columns["checkin_type"]?.text, !kind.isEmpty,
                  let rawTime = row.columns["submitted_at_utc"]?.text, let time = AppFormatters.parseISO8601Flexible(rawTime) else {
                throw ExportReadError.unreadable
            }
            let rawVersion = row.columns["questionnaire_version"]?.text
            let version = rawVersion.flatMap { $0.isEmpty ? nil : $0 }
            return (row, try .init(sourceRecordID: "checkin_submissions:" + id, instrumentID: "dosetap." + kind,
                contentVersion: version, language: nil, observedAt: time))
        }
        var allContent = Dictionary(uniqueKeysWithValues: sources.map { ($0.content.sourceRecordID, $0.content) })
        var links: [DashboardContentJoinKey: [DashboardContentObservation]] = [:]
        for source in sources {
            let c = source.row.columns
            if let kind = c["checkin_type"]?.text, let sourceID = c["source_record_id"]?.text,
               let sessionID = c["session_id"]?.text, let date = c["session_date"]?.text {
                links[.init(kind: kind, sourceID: sourceID, sessionID: sessionID, sessionDate: date), default: []].append(source.content)
            }
        }
        for index in sessions.indices {
            let session = sessions[index]
            func observation(table: String, kind: String, id: String, time: Date) throws -> DashboardContentObservation {
                if let identity = session.sessionID {
                    let matching = links[.init(kind: kind, sourceID: id, sessionID: identity, sessionDate: session.sessionDate)] ?? []
                    if matching.count == 1 { return matching[0] }
                }
                return try .init(sourceRecordID: table + ":" + id, instrumentID: "dosetap." + kind,
                    contentVersion: nil, language: nil, observedAt: time)
            }
            var values: [DashboardContentObservation] = []
            if let morning = session.morning {
                values.append(try observation(table: "morning_checkins", kind: "morning", id: morning.id, time: morning.timestamp))
            }
            if let pre = session.preSleep {
                guard let time = AppFormatters.parseISO8601Flexible(pre.createdAtUtc) else { throw ExportReadError.unreadable }
                values.append(try observation(table: "pre_sleep_logs", kind: "pre_night", id: pre.id, time: time))
            }
            if let identity = session.sessionID {
                values += links[.init(kind: "night_outcome", sourceID: identity, sessionID: identity,
                    sessionDate: session.sessionDate)] ?? []
            }
            sessions[index].contentObservations = values
            for value in values { allContent[value.sourceRecordID] = value }
        }
        let timeline = try DashboardContextTimeline(presets: medicationPresetExportSnapshot(),
            content: Array(allContent.values), capturedAt: capturedAt)
        let associations = try dashboardAssociations()
        guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else { throw ExportReadError.unreadable }
        committed = true
        return .init(sessions: sessions, associations: associations, timeline: timeline)
    }
}
