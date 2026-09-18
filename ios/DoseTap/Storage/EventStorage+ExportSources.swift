import Foundation
import SQLite3

/// SQLite values are tagged so NULL, empty text, numbers and blobs stay distinct.
struct StoredExportColumn: Encodable, Equatable {
    let type: String
    var text: String? = nil
    var integer: Int64? = nil
    var real: Double? = nil
    var blobBase64: String? = nil

    init(statement: OpaquePointer, index: Int32) throws {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_NULL: type = "null"
        case SQLITE_INTEGER: type = "integer"; integer = sqlite3_column_int64(statement, index)
        case SQLITE_FLOAT:
            type = "real"; real = sqlite3_column_double(statement, index)
            guard real?.isFinite == true else { throw ExportReadError.unreadable }
        case SQLITE_TEXT:
            type = "text"
            guard let pointer = sqlite3_column_text(statement, index),
                  let value = String(bytes: UnsafeBufferPointer(start: pointer,
                    count: Int(sqlite3_column_bytes(statement, index))), encoding: .utf8) else {
                throw ExportReadError.unreadable
            }
            text = value
        case SQLITE_BLOB:
            type = "blob"
            let count = Int(sqlite3_column_bytes(statement, index))
            if count == 0 { blobBase64 = "" }
            else {
                guard let pointer = sqlite3_column_blob(statement, index) else { throw ExportReadError.unreadable }
                blobBase64 = Data(bytes: pointer, count: count).base64EncodedString()
            }
        default: throw ExportReadError.unreadable
        }
    }
}

struct StoredExportSourceRecord: Encodable, Equatable {
    let sourceTable: String
    let columns: [String: StoredExportColumn]
}

struct ExportIdentityResolution: Encodable {
    let version = 1
    let status: String
    let sessionIds: [String]
    let reasons: [String]
    var isRawOnly: Bool { status == "raw_only" }
}

struct ExportSourceSnapshot {
    let identityResolution: ExportIdentityResolution
    let records: [StoredExportSourceRecord]
}

@MainActor
extension EventStorage {
    /// Date grouping is for archival discovery, never authority to join two identities.
    private static let exportIdentitiesSQL = ["dose_events", "sleep_events", "sleep_sessions",
        "current_session", "morning_checkins", "checkin_submissions", "medication_events"]
        .map { "SELECT session_id, session_date FROM \($0)" }.joined(separator: " UNION ALL ")

    func exportSourceSnapshot(sessionDate: String) throws -> ExportSourceSnapshot {
        let evidence = try readExportSourceRows(table: "identity_evidence", sql: """
        WITH identities AS (\(Self.exportIdentitiesSQL))
        SELECT DISTINCT session_id, session_date FROM identities
        WHERE session_date = ?1 OR session_id IN
            (SELECT session_id FROM identities WHERE session_date = ?1)
        ORDER BY session_id, session_date
        """, sessionDate: sessionDate)
        let ids = try Set(evidence.compactMap { row -> String? in
            guard row.columns["session_date"]?.type == "text",
                  let value = row.columns["session_id"], ["null", "text"].contains(value.type) else {
                throw ExportReadError.unreadable
            }
            guard let id = value.text, id != sessionDate else { return nil }
            return id
        }).sorted()
        var records: [StoredExportSourceRecord] = []
        for table in ["sleep_sessions", "current_session", "morning_checkins", "checkin_submissions"] {
            records += try readExportSourceRows(table: table,
                sql: "SELECT * FROM \(table) WHERE session_date = ?1 ORDER BY rowid", sessionDate: sessionDate)
        }
        records += try readExportSourceRows(table: "pre_sleep_logs", sql: """
        SELECT * FROM pre_sleep_logs WHERE session_id = ?1
        OR session_id IN (SELECT session_id FROM (\(Self.exportIdentitiesSQL)) WHERE session_date = ?1)
        OR id IN (SELECT source_record_id FROM checkin_submissions
                  WHERE session_date = ?1 AND checkin_type = 'pre_night')
        ORDER BY rowid
        """, sessionDate: sessionDate)
        var reasons: [String] = []
        let allIds = Set(ids + records.compactMap { $0.columns["session_id"]?.text }.filter { $0 != sessionDate })
        if allIds.count > 1 { reasons.append("multiple_session_identities") }
        if evidence.contains(where: { $0.columns["session_date"]?.text != sessionDate }) {
            reasons.append("session_identity_spans_dates")
        }
        let duplicatedSource = ["pre_sleep_logs", "morning_checkins"].contains { table in
            records.filter { $0.sourceTable == table }.count > 1
        }
        let submissions = records.filter { $0.sourceTable == "checkin_submissions" }
        let duplicateSubmission = Dictionary(grouping: submissions, by: { $0.columns["checkin_type"]?.text ?? "" })
            .values.contains { $0.count > 1 }
        if duplicatedSource || duplicateSubmission { reasons.append("multiple_source_questionnaires") }
        return ExportSourceSnapshot(identityResolution: ExportIdentityResolution(
            status: reasons.isEmpty ? "resolved" : "raw_only", sessionIds: allIds.sorted(), reasons: reasons), records: records)
    }

    private func readExportSourceRows(table: String, sql: String, sessionDate: String) throws -> [StoredExportSourceRecord] {
        try readExportRows(sql, binding: sessionDate) { stmt in
            var columns: [String: StoredExportColumn] = [:]
            for index in 0..<sqlite3_column_count(stmt) {
                guard let name = sqlite3_column_name(stmt, index) else { throw ExportReadError.unreadable }
                columns[String(cString: name)] = try StoredExportColumn(statement: stmt, index: index)
            }
            return StoredExportSourceRecord(sourceTable: table, columns: columns)
        }
    }
}
