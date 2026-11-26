import Foundation
import SQLite3
import DoseCore

@MainActor
extension EventStorage {
    private func physicianRecords<T: Decodable>(_ kind: String, as: T.Type) throws -> [T] {
        try readExportRows("SELECT id, payload FROM physician_review_records WHERE kind = ? ORDER BY rowid", binding: kind) { stmt in
            let payload = try StoredExportColumn(statement: stmt, index: 1)
            guard payload.type == "text", let text = payload.text else { throw ExportReadError.unreadable }
            let value = try JSONDecoder().decode(T.self, from: Data(text.utf8))
            if let snapshot = value as? PhysicianReportSnapshot { try snapshot.validate() }
            let storedID = try StoredExportColumn(statement: stmt, index: 0).text
            let expectedID = (value as? PhysicianVisit)?.revisionID ?? (value as? PhysicianReportSnapshot)?.id
            guard storedID == expectedID?.uuidString else { throw ExportReadError.unreadable }
            return value
        }
    }
    func physicianVisits(now: Date) throws -> PhysicianVisitLedger {
        var ledger = PhysicianVisitLedger()
        for value in try physicianRecords("visit", as: PhysicianVisit.self) { try ledger.append(value, now: now) }
        return ledger
    }
    func physicianReports() throws -> [PhysicianReportSnapshot] {
        try physicianRecords("report", as: PhysicianReportSnapshot.self).reversed()
    }
    func savePhysicianVisit(_ value: PhysicianVisit, now: Date) throws -> Bool {
        try value.validate(now: now)
        return try appendPhysicianRecord(value, id: value.revisionID, kind: "visit") {
            var ledger = try self.physicianVisits(now: now)
            if let prior = ledger.revisions.first(where: { $0.revisionID == value.revisionID }) {
                guard prior == value else { throw PhysicianReviewError.invalidRevision }
            } else { try ledger.append(value, now: now) }
        }
    }
    func savePhysicianReport(_ value: PhysicianReportSnapshot, now: Date) throws -> Bool {
        try value.validate()
        guard value.generatedAt <= now, value.period.endExclusive <= value.generatedAt,
              value.period.start < value.period.endExclusive, value.version == PhysicianReportSnapshot.formatVersion else {
            throw PhysicianReviewError.invalidPeriod
        }
        return try appendPhysicianRecord(value, id: value.id, kind: "report") {}
    }
    private func appendPhysicianRecord<T: Encodable>(_ value: T, id: UUID, kind: String,
                                                    validate: () throws -> Void) throws -> Bool {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard let payload = String(data: data, encoding: .utf8), databaseInitializationFailure == nil, let db,
              injectedMedicationFailure(at: .begin) == nil,
              sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { throw ExportReadError.unreadable }
        var committed = false
        defer { if !committed { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) } }
        try validate()
        let existing = try readExportRows("SELECT payload FROM physician_review_records WHERE id = ?", binding: id.uuidString) {
            try StoredExportColumn(statement: $0, index: 0).text
        }
        if let prior = existing.first {
            guard prior == payload else { throw PhysicianReviewError.invalidRevision }
        } else {
            guard injectedMedicationFailure(at: .insert) == nil else { throw ExportReadError.unreadable }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "INSERT INTO physician_review_records (id, kind, payload) VALUES (?, ?, ?)", -1, &stmt, nil) == SQLITE_OK,
                  let stmt else { throw ExportReadError.unreadable }
            for (index, text) in [id.uuidString, kind, payload].enumerated() {
                guard sqlite3_bind_text(stmt, Int32(index + 1), text, -1, SQLITE_TRANSIENT) == SQLITE_OK else { throw ExportReadError.unreadable }
            }
            guard sqlite3_step(stmt) == SQLITE_DONE, sqlite3_changes(db) == 1 else { throw ExportReadError.unreadable }
        }
        guard injectedMedicationFailure(at: .commit) == nil,
              sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else { throw ExportReadError.unreadable }
        committed = true
        storageLog.info("Physician review record commit verified")
        return existing.isEmpty
    }
}

@MainActor
extension SessionRepository {
    func physicianVisits() throws -> PhysicianVisitLedger { try storage.physicianVisits(now: clock()) }
    func physicianReports() throws -> [PhysicianReportSnapshot] { try storage.physicianReports() }
    func savePhysicianVisit(_ value: PhysicianVisit) throws {
        if try storage.savePhysicianVisit(value, now: clock()) { sessionDidChange.send() }
    }
    func savePhysicianReport(_ value: PhysicianReportSnapshot) throws {
        if try storage.savePhysicianReport(value, now: clock()) { sessionDidChange.send() }
    }
}
