import Foundation
import SQLite3
import DoseCore
import os.log

enum NapDiaryStorageError: LocalizedError {
    case unreadable, invalid, stale
    var errorDescription: String? {
        switch self {
        case .unreadable: return "Nap review could not be read or saved. Retry after reopening."
        case .invalid: return "Review the nap times, estimate and correction reason. Existing history cannot be replaced."
        case .stale: return "Nap review changed. Reopen it before saving."
        }
    }
}
@MainActor
extension EventStorage {
    func napDiary() throws -> NapDiaryDocument? {
        guard databaseInitializationFailure == nil, db != nil else { throw NapDiaryStorageError.unreadable }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM nap_diary WHERE id = 1", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw NapDiaryStorageError.unreadable }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW, sqlite3_column_type(statement, 0) == SQLITE_TEXT, let bytes = sqlite3_column_text(statement, 0) else { throw NapDiaryStorageError.unreadable }
        let document = try JSONDecoder().decode(NapDiaryDocument.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0))))
        guard document.isValid else { throw NapDiaryStorageError.invalid }; return document
    }
    func saveNapDiary(_ value: NapDiaryDocument, expectedRevision: UUID?) throws {
        guard value.isValid else { throw NapDiaryStorageError.invalid }
        guard databaseInitializationFailure == nil, let db, sqlite3_get_autocommit(db) != 0,
              sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { throw NapDiaryStorageError.unreadable }
        var committed = false
        defer { if !committed { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) } }
        let previous = try napDiary()
        guard previous?.revision == expectedRevision else { throw NapDiaryStorageError.stale }
        if let previous {
            guard previous.revision != value.revision, value.episodes.starts(with: previous.episodes), value.reviews.starts(with: previous.reviews) else { throw NapDiaryStorageError.invalid }
        }
        let payload = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO nap_diary(id,payload) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw NapDiaryStorageError.unreadable }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_text(statement, 1, payload, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_DONE, sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else { throw NapDiaryStorageError.unreadable }
        committed = true
    }
}
@MainActor
extension SessionRepository {
    func napDiary() throws -> NapDiaryDocument? {
        do { return try storage.napDiary() }
        catch { storageLog.error("Nap review read failed; no empty replacement published"); throw error }
    }
    func saveNapDiary(_ value: NapDiaryDocument, expectedRevision: UUID?) throws {
        do { try storage.saveNapDiary(value, expectedRevision: expectedRevision) }
        catch { storageLog.error("Nap review save failed; existing history retained"); throw error }
        sessionDidChange.send()
    }
    private func napTimerMarkers(inTransaction: Bool = false) throws -> [NapTimerMarker] {
        try storage.dashboardLocalSessions(inTransaction: inTransaction).flatMap { session in
            session.events.compactMap { event -> NapTimerMarker? in
                let kind = normalizeStoredEventType(event.eventType)
                guard ["nap_start", "nap_end"].contains(kind) else { return nil }
                return .init(id: event.id, sessionID: session.sessionID, date: event.timestamp, isStart: kind == "nap_start")
            }
        }
    }
    func napTimerEpisodes(asOf: Date, timeZoneID: String) throws -> [NapEpisode] {
        NapEpisode.timers(try napTimerMarkers(), zone: timeZoneID, asOf: asOf)
    }
    /// Reconstruct each reviewed timer in its recorded zone; travel does not change its source identity.
    func napDiarySources(document: NapDiaryDocument?, asOf: Date, defaultTimeZoneID: String, inTransaction: Bool = false) throws -> [NapEpisode] {
        guard asOf.timeIntervalSince1970.isFinite, TimeZone(identifier: defaultTimeZoneID) != nil, document?.isValid != false else { throw NapDiaryStorageError.invalid }
        let storedZones = Dictionary(uniqueKeysWithValues: (document?.current ?? []).map { ($0.id, $0.timeZoneID) })
        let markers = try napTimerMarkers(inTransaction: inTransaction)
        return Set(storedZones.values).union([defaultTimeZoneID]).sorted().flatMap { sourceZone in
            NapEpisode.timers(markers, zone: sourceZone, asOf: asOf).filter {
                (storedZones[$0.id] ?? defaultTimeZoneID) == sourceZone
            }
        }
    }
    func reviewedNapEpisodes(asOf: Date, defaultTimeZoneID: String, inTransaction: Bool = false) throws -> [NapEpisode] {
        let document = try napDiary() ?? NapDiaryDocument()
        return document.merging(try napDiarySources(document: document, asOf: asOf, defaultTimeZoneID: defaultTimeZoneID, inTransaction: inTransaction))
    }

}
