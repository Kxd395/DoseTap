import Foundation
import SQLite3
import DoseCore

/// SQLite values are tagged so NULL, empty text, numbers and blobs stay distinct.
struct StoredExportColumn: Encodable, Equatable, Sendable {
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

struct StoredExportSourceRecord: Encodable, Equatable, Sendable {
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
    /// Read archive rows without changing their stored identity or payload.
    func exportIndependentSourceRecords(in requestedTable: String? = nil) throws -> [StoredExportSourceRecord] {
        if let requestedTable, !StudioIndependentSourceRecord.sourceTables.contains(requestedTable) {
            throw ExportReadError.unreadable
        }
        guard databaseInitializationFailure == nil, db != nil else { throw ExportReadError.unreadable }
        return try withSQLiteTransaction {
            let tables = try independentRecordTables(checkUnknownTables: requestedTable == nil)
            return try (requestedTable.map { [$0] } ?? tables).filter(tables.contains).flatMap { table in
                try readIndependentRecords(table: table)
            }
        }
    }

    func nativeDaytimeTables() throws -> Set<String> {
        let receipts = try readExportRows("""
            SELECT id FROM schema_migrations
            WHERE id IN ('native_daytime_checkins_v1', 'native_daytime_prompts_v1')
            """) { row in
            guard let receipt = sqlite3_column_text(row, 0) else { throw ExportReadError.unreadable }
            return String(cString: receipt)
        }
        var owned = Set<String>()
        if receipts.contains("native_daytime_checkins_v1") { owned.insert("daytime_checkins") }
        if receipts.contains("native_daytime_prompts_v1") { owned.insert("daytime_prompt_state") }
        return owned
    }

    /// Must run inside the caller's SQLite transaction.
    func independentRecordTables(checkUnknownTables: Bool = false) throws -> [String] {
        let tables = StudioIndependentSourceRecord.sourceTables
        let objects = try readExportRows("""
            SELECT name, type FROM main.sqlite_schema WHERE name NOT GLOB 'sqlite_*'
            """) { row in
            guard let name = sqlite3_column_text(row, 0), let type = sqlite3_column_text(row, 1) else {
                throw ExportReadError.unreadable
            }
            return (String(cString: name), String(cString: type))
        }
        if checkUnknownTables {
            let existing = Set(objects.filter { $0.1 == "table" }.map { $0.0 })
            guard existing.isSubset(of: Self.nativeStorageTables.union(tables)) else {
                throw ExportReadError.incompatibleSchema
            }
        }
        let independent = objects.filter { tables.contains($0.0.lowercased()) }
        guard independent.allSatisfy({ $0.1 == "table" }) else { throw ExportReadError.unreadable }
        let names = Set(independent.map { $0.0 })
        let native = try nativeDaytimeTables()
        if !native.isEmpty {
            guard names == native else { throw ExportReadError.unreadable }
        } else {
            guard names.isEmpty || names == Set(tables) else { throw ExportReadError.unreadable }
        }
        return tables.filter(names.contains)
    }

    func readIndependentRecords(table: String) throws -> [StoredExportSourceRecord] {
        guard let key = StudioIndependentSourceRecord.primaryKeys[table],
              let required = Self.independentRecordColumns[table] else { throw ExportReadError.unreadable }
        let columns = try readExportRows("SELECT name, pk FROM pragma_table_info(?1, 'main')", binding: table) { row in
            guard let name = sqlite3_column_text(row, 0) else { throw ExportReadError.unreadable }
            return (String(cString: name), sqlite3_column_int(row, 1))
        }
        guard columns.filter({ $0.1 > 0 }).map({ $0.0 }) == [key],
              required.isSubset(of: Set(columns.map { $0.0 })) else { throw ExportReadError.unreadable }
        let rows = try readExportSourceRows(table: table,
            sql: "SELECT * FROM main.\(table) ORDER BY rowid", sessionDate: nil)
        for row in rows {
            guard let id = row.columns[key], id.integer != nil || id.text?.isEmpty == false else {
                throw ExportReadError.unreadable
            }
        }
        return rows
    }

    /// Required non-key columns from the build-108 storage schema. Additional original columns are archived as well.
    private static let independentRecordColumns: [String: Set<String>] = [
        "daytime_checkins": ["observation_id", "payload"],
        "daytime_events": ["event_id", "payload"],
        "daytime_prompt_state": ["payload"],
        "nap_diary": ["payload"],
        "physician_review_records": ["kind", "payload"],
        "work_block_context": ["payload"],
        "dashboard_dose_reviews": ["session_date", "payload"],
        "dashboard_provider_associations": [
            "provider", "session_id", "session_date", "session_fingerprint", "episode_fingerprint", "revision", "recorded_at"
        ]
    ]

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
        let associatedDates = try allIds.flatMap { id in
            try readExportSourceRows(table: "identity_evidence",
                sql: "SELECT DISTINCT session_date FROM (\(Self.exportIdentitiesSQL)) WHERE session_id = ?1", sessionDate: id)
        }
        if associatedDates.contains(where: { $0.columns["session_date"]?.text != sessionDate }) {
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

    private func readExportSourceRows(table: String, sql: String, sessionDate: String?) throws -> [StoredExportSourceRecord] {
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
