import Foundation
import SQLite3
import CryptoKit

struct DashboardProviderAssociation {
    let episodeID: String
    let provider: String
    let sessionID: String
    let sessionDate: String
    let sessionFingerprint: String
    let episodeFingerprint: String
    let revision: String
}

func dashboardFingerprint(_ fields: [String]) -> String {
    var hash = SHA256()
    for field in fields { hash.update(data: Data("\(field.utf8.count):\(field)".utf8)) }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}

@MainActor
extension SessionRepository {
    func dashboardIdentitySnapshot() throws -> (sessions: [DashboardLocalSession], associations: [DashboardProviderAssociation]) {
        try storage.dashboardIdentitySnapshot()
    }
    func saveDashboardAssociation(_ association: DashboardProviderAssociation, expectedRevision: String?) throws {
        try storage.saveDashboardAssociation(association, expectedRevision: expectedRevision, now: clock())
    }
    func removeDashboardAssociation(_ association: DashboardProviderAssociation) throws {
        try storage.executeMedicationStatement("DELETE FROM dashboard_provider_associations WHERE episode_id = ? AND revision = ?", at: .delete, requireChanges: true) { statement in
            sqlite3_bind_text(statement, 1, association.episodeID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, association.revision, -1, SQLITE_TRANSIENT)
        }
    }
}

@MainActor
extension EventStorage {
    func dashboardIdentitySnapshot() throws -> (sessions: [DashboardLocalSession], associations: [DashboardProviderAssociation]) {
        guard let db, sqlite3_get_autocommit(db) != 0,
              sqlite3_exec(db, "BEGIN DEFERRED", nil, nil, nil) == SQLITE_OK else { throw ExportReadError.unreadable }
        var committed = false
        defer { if !committed { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) } }
        let result = (try dashboardLocalSessions(inTransaction: true), try dashboardAssociations())
        guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else { throw ExportReadError.unreadable }
        committed = true
        return result
    }
    func dashboardAssociations() throws -> [DashboardProviderAssociation] {
        try readExportRows("SELECT episode_id,provider,session_id,session_fingerprint,episode_fingerprint,revision,session_date FROM dashboard_provider_associations") { statement in
            var fields: [String] = []
            for index: Int32 in 0..<7 {
                guard let value = sqlite3_column_text(statement, index) else { throw ExportReadError.unreadable }
                fields.append(String(cString: value))
            }
            return DashboardProviderAssociation(episodeID: fields[0], provider: fields[1], sessionID: fields[2], sessionDate: fields[6],
                sessionFingerprint: fields[3], episodeFingerprint: fields[4], revision: fields[5])
        }
    }
    func saveDashboardAssociation(_ value: DashboardProviderAssociation, expectedRevision: String?, now: Date) throws {
        let textFields = [value.episodeID, value.provider, value.sessionID, value.sessionDate,
                          value.sessionFingerprint, value.episodeFingerprint, value.revision]
        guard textFields.allSatisfy({ !$0.isEmpty && !$0.contains("\0") }),
              [value.sessionFingerprint, value.episodeFingerprint].allSatisfy({ $0.count == 64 && Set("0123456789abcdef").isSuperset(of: $0) }),
              ["apple-health", "whoop"].contains(value.provider), value.episodeID.hasPrefix(value.provider + ":"),
              value.episodeID.utf8.count <= 4096, !value.sessionID.isEmpty,
              value.sessionFingerprint.count == 64, value.episodeFingerprint.count == 64,
              UUID(uuidString: value.revision) != nil, now.timeIntervalSince1970.isFinite,
              let db, sqlite3_get_autocommit(db) != 0,
              sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { throw ExportReadError.unreadable }
        var committed = false
        defer { if !committed { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) } }
        guard let session = try dashboardLocalSessions(inTransaction: true).first(where: { $0.sessionID == value.sessionID }),
              !session.needsReview, session.sessionDate == value.sessionDate, session.fingerprint == value.sessionFingerprint,
              try dashboardAssociations().first(where: { $0.episodeID == value.episodeID })?.revision == expectedRevision else {
            throw ExportReadError.unreadable
        }
        try executeMedicationStatement("""
        INSERT INTO dashboard_provider_associations(episode_id,provider,session_id,session_fingerprint,episode_fingerprint,revision,recorded_at,session_date)
        VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(episode_id) DO UPDATE SET session_id=excluded.session_id,
        session_fingerprint=excluded.session_fingerprint,episode_fingerprint=excluded.episode_fingerprint,
        revision=excluded.revision,recorded_at=excluded.recorded_at,session_date=excluded.session_date
        """, at: .update, requireChanges: true) { statement in
            for (index, field) in [value.episodeID, value.provider, value.sessionID, value.sessionFingerprint,
                                   value.episodeFingerprint, value.revision, isoFormatter.string(from: now), value.sessionDate].enumerated() {
                sqlite3_bind_text(statement, Int32(index + 1), field, -1, SQLITE_TRANSIENT)
            }
        }
        guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else { throw ExportReadError.unreadable }
        committed = true
    }
}
