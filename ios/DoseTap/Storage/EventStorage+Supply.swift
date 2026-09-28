import Foundation
import SQLite3
import DoseCore

enum SupplyStorageError: LocalizedError {
    case unavailable, invalid
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Supply information could not be saved or loaded. Please retry."
        case .invalid: return "This supply record is invalid or uses an unsupported version."
        }
    }
}

struct SupplyUsageSummary: Equatable {
    let recordedNights: Int
    let recordedDoses: Int
    let excludedRows: Int
}

extension EventStorage {
    /// A single SELECT supplies one read snapshot. Counts are date groups, not
    /// bottle allocations; identity/duplicate checks include rows outside the range.
    func supplyUsage(since: Date, through: Date) throws -> SupplyUsageSummary {
        guard since.timeIntervalSince1970.isFinite, through.timeIntervalSince1970.isFinite,
              since <= through else { throw SupplyStorageError.invalid }
        let full = ISO8601DateFormatter(), fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let civil = DateFormatter()
        civil.locale = Locale(identifier: "en_US_POSIX"); civil.timeZone = TimeZone(secondsFromGMT: 0)
        civil.dateFormat = "yyyy-MM-dd"; civil.isLenient = false
        let rows = try readExportRows("""
        WITH identities AS (
            SELECT session_id, session_date FROM dose_events
            UNION SELECT session_id, session_date FROM sleep_sessions
            UNION SELECT session_id, session_date FROM current_session
        ), identity_counts AS (
            SELECT session_date, COUNT(DISTINCT session_id) AS n FROM identities
            WHERE session_id IS NOT NULL AND session_id != session_date GROUP BY session_date
        )
        SELECT e.id, e.event_type, e.timestamp, e.session_date, e.session_id, COALESCE(i.n, 0)
        FROM dose_events e LEFT JOIN identity_counts i ON i.session_date = e.session_date
        """) { stmt in
            func text(_ column: Int32, allowEmpty: Bool = false) throws -> String {
                guard sqlite3_column_type(stmt, column) == SQLITE_TEXT, let pointer = sqlite3_column_text(stmt, column),
                      let value = String(bytes: UnsafeBufferPointer(start: pointer, count: Int(sqlite3_column_bytes(stmt, column))), encoding: .utf8),
                      allowEmpty || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SupplyStorageError.invalid }
                return value
            }
            _ = try text(0)
            let type = try text(1), rawTime = try text(2), day = try text(3)
            guard let time = fractional.date(from: rawTime) ?? full.date(from: rawTime), time.timeIntervalSince1970.isFinite,
                  day.count == 10, let date = civil.date(from: day), civil.string(from: date) == day else { throw SupplyStorageError.invalid }
            let session: String?
            if sqlite3_column_type(stmt, 4) == SQLITE_NULL { session = nil }
            else { let raw = try text(4, allowEmpty: true); session = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : raw }
            guard sqlite3_column_type(stmt, 5) == SQLITE_INTEGER else { throw SupplyStorageError.invalid }
            return (type: CanonicalDoseEventType(canonicalizing: type), time: time, day: day, session: session,
                    conflictingIdentity: sqlite3_column_int64(stmt, 5) != 1)
        }
        var nights = 0, doses = 0, excluded = 0
        for (day, group) in Dictionary(grouping: rows, by: { $0.day }) {
            let candidates = group.filter { $0.type?.countsAsTakenDose == true && since <= $0.time && $0.time <= through }
            guard !candidates.isEmpty else { continue }
            let identities = Set(group.compactMap { $0.session })
            let ambiguous = group.contains { $0.conflictingIdentity || $0.session == nil || $0.session == day }
                || identities.count != 1 || group.filter { $0.type == .dose1 }.count > 1 || group.filter { $0.type == .dose2 }.count > 1
            if ambiguous { excluded += candidates.count }
            else { nights += 1; doses += candidates.count }
        }
        return SupplyUsageSummary(recordedNights: nights, recordedDoses: doses, excludedRows: excluded)
    }

    func loadSupply() throws -> SupplyBackup {
        guard databaseInitializationFailure == nil, db != nil else { throw SupplyStorageError.unavailable }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM supply_state WHERE id = 1", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw SupplyStorageError.unavailable }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return SupplyBackup() }
        guard result == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { throw SupplyStorageError.unavailable }
        let value = try JSONDecoder().decode(SupplyBackup.self, from: Data(String(cString: text).utf8))
        guard value.isValid else { throw SupplyStorageError.invalid }
        return value
    }

    /// One SQLite statement commits reminder and bottle records atomically.
    func saveSupply(_ value: SupplyBackup) throws {
        guard value.isValid else { throw SupplyStorageError.invalid }
        guard databaseInitializationFailure == nil, db != nil else { throw SupplyStorageError.unavailable }
        let payload = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO supply_state (id, payload) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw SupplyStorageError.unavailable }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_text(statement, 1, payload, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_DONE else { throw SupplyStorageError.unavailable }
    }
}

extension SessionRepository {
    func supplyUsage(since: Date, through: Date) throws -> SupplyUsageSummary {
        try storage.supplyUsage(since: since, through: through)
    }
    func loadSupply() throws -> SupplyBackup { try storage.loadSupply() }
    func saveSupply(_ value: SupplyBackup) throws {
        try storage.saveSupply(value)
        supplyGeneration &+= 1
        sessionDidChange.send()
    }
}
