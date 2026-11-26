import Combine
import DoseCore
import SQLite3
import XCTest
@testable import DoseTap

@MainActor
final class ImportedSessionDeletionTests: XCTestCase {
    private let old = "2000-06-10"
    private let recent = "2099-06-11"

    private func execute(_ sql: String, in storage: EventStorage) throws {
        let code = sqlite3_exec(storage.db, sql, nil, nil, nil)
        guard code == SQLITE_OK else {
            throw NSError(domain: "ImportedSessionDeletionTests", code: Int(code),
                          userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(storage.db))])
        }
    }

    private func ids(in table: String, storage: EventStorage) throws -> [String] {
        try storage.readExportRows("SELECT id FROM \(table) ORDER BY id") { row in
            String(cString: try XCTUnwrap(sqlite3_column_text(row, 0)))
        }
    }

    private func fixture() throws -> EventStorage {
        let storage = EventStorage.inMemory()
        // The schema creates these collections; replace them with minimal dated shapes.
        try execute("""
            DROP TABLE dashboard_dose_reviews; DROP TABLE dashboard_provider_associations; DROP TABLE daytime_events;
            CREATE TABLE dashboard_dose_reviews (observation_id TEXT PRIMARY KEY, session_date TEXT, payload TEXT);
            CREATE TABLE dashboard_provider_associations (episode_id TEXT PRIMARY KEY, session_date TEXT, session_id TEXT);
            CREATE TABLE daytime_events (id TEXT PRIMARY KEY, payload TEXT);
            INSERT INTO daytime_events VALUES ('independent', '{"day":"\(old)"}');
            """, in: storage)
        for day in [old, recent] {
            try execute("""
                INSERT INTO dose_events (id, event_type, timestamp, session_date) VALUES ('\(day)', 'dose1', '\(day)T23:00:00Z', '\(day)');
                INSERT INTO dashboard_dose_reviews VALUES ('\(day)', '\(day)', '{}');
                INSERT INTO dashboard_provider_associations VALUES ('\(day)', '\(day)', 'session-\(day)');
                """, in: storage)
        }
        return storage
    }

    private func dates(in table: String, storage: EventStorage) throws -> [String] {
        try storage.readExportRows("SELECT session_date FROM \(table) ORDER BY session_date") { row in
            String(cString: try XCTUnwrap(sqlite3_column_text(row, 0)))
        }
    }

    private func checkRows(_ days: [String], in storage: EventStorage, file: StaticString = #filePath, line: UInt = #line) throws {
        for table in ["dashboard_dose_reviews", "dashboard_provider_associations", "dose_events"] {
            XCTAssertEqual(try dates(in: table, storage: storage), days, table, file: file, line: line)
        }
        XCTAssertEqual(try ids(in: "daytime_events", storage: storage), ["independent"], file: file, line: line)
    }

    func testDayDeletionAndRetentionIncludeOnlyExplicitlyDatedImportedRows() throws {
        let perDay = try fixture()
        XCTAssertTrue(perDay.deleteSession(sessionDate: old))
        try checkRows([recent], in: perDay)
        let retention = try fixture()
        XCTAssertTrue(retention.clearOldData(olderThanDays: 30))
        try checkRows([recent], in: retention)
    }

    func testRetentionKeepsTheCutoffDayAndRefusesANegativeAge() throws {
        let storage = try fixture()
        let asOf = try XCTUnwrap(ISO8601DateFormatter().date(from: "2000-07-10T22:00:00Z"))
        storage.nowProvider = { asOf }
        storage.timeZoneProvider = { TimeZone(secondsFromGMT: 0)! }
        XCTAssertFalse(storage.clearOldData(olderThanDays: -1))
        XCTAssertTrue(storage.clearOldData(olderThanDays: 30))
        try checkRows([old, recent], in: storage)
        XCTAssertTrue(storage.clearOldData(olderThanDays: 29))
        try checkRows([recent], in: storage)
    }

    func testFailedImportedDeleteRollsBackRetentionAndNightDeletion() throws {
        let storage = try fixture()
        try execute("""
            CREATE TRIGGER reject_link BEFORE DELETE ON dashboard_provider_associations
            BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END;
            """, in: storage)
        XCTAssertFalse(storage.clearOldData(olderThanDays: 30))
        try checkRows([old, recent], in: storage)
        XCTAssertFalse(storage.deleteSession(sessionDate: old))
        try checkRows([old, recent], in: storage)
        XCTAssertTrue(storage.fetchCloudKitTombstones().isEmpty)
        try execute("DROP TRIGGER reject_link", in: storage)
        XCTAssertTrue(storage.deleteSession(sessionDate: old))
        try checkRows([recent], in: storage)
    }

    func testEmptyImportedTablesAndUnexpectedSchema() throws {
        let storage = EventStorage.inMemory()
        XCTAssertTrue(storage.clearOldData(olderThanDays: 30))
        XCTAssertTrue(storage.deleteSession(sessionDate: old, recordCloudKitDeletion: false))
        try execute("""
            DROP TABLE dashboard_dose_reviews;
            CREATE VIEW dashboard_dose_reviews AS SELECT session_date FROM dose_events;
            """, in: storage)
        XCTAssertFalse(storage.clearOldData(olderThanDays: 30))
        XCTAssertFalse(storage.deleteSession(sessionDate: old))
        XCTAssertTrue(storage.fetchCloudKitTombstones().isEmpty)
    }

    func testDeletingNewCalendarDayKeepsPriorActiveNightAndAlarms() throws {
        let storage = EventStorage.inMemory()
        let scheduler = FakeNotificationScheduler()
        var now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-21T17:55:00Z"))
        let dose = now
        let repository = SessionRepository(storage: storage, notificationScheduler: scheduler,
            clock: { now }, timeZoneProvider: { TimeZone(secondsFromGMT: 0)! })
        XCTAssertTrue(repository.setDose1Time(dose).isCommitted)
        let originalDate = try XCTUnwrap(repository.activeSessionDate)
        let originalID = try XCTUnwrap(repository.activeSessionId)
        now = now.addingTimeInterval(10 * 60)
        let newCalendarDay = storage.currentSessionDate()
        XCTAssertNotEqual(originalDate, newCalendarDay)
        try execute("""
            INSERT INTO sleep_events (id, event_type, timestamp, session_date)
            VALUES ('new-day', 'wake', '2026-09-21T18:04:00Z', '\(newCalendarDay)');
            """, in: storage)

        scheduler.reset()
        XCTAssertTrue(repository.deleteSession(sessionDate: newCalendarDay))
        XCTAssertTrue(repository.deleteSessionFromSync(sessionDate: newCalendarDay))
        XCTAssertEqual(try ids(in: "sleep_events", storage: storage), [])
        XCTAssertEqual(repository.activeSessionId, originalID)
        XCTAssertEqual(repository.activeSessionDate, originalDate)
        XCTAssertEqual(repository.dose1Time, dose)
        XCTAssertEqual(storage.loadCurrentSessionState().dose1Time, dose)
        XCTAssertTrue(scheduler.cancelledIdentifiers.isEmpty)
    }

    func testInboundActiveSessionDeleteClearsDoseAndOnlySessionAlarmsOnce() throws {
        let storage = EventStorage.inMemory()
        let scheduler = FakeNotificationScheduler()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-21T23:00:00Z"))
        let repository = SessionRepository(storage: storage, notificationScheduler: scheduler,
            clock: { now }, timeZoneProvider: { TimeZone(secondsFromGMT: 0)! })
        XCTAssertTrue(repository.setDose1Time(now).isCommitted)
        let date = try XCTUnwrap(repository.activeSessionDate)
        scheduler.reset()
        XCTAssertTrue(repository.deleteSessionFromSync(sessionDate: date))
        XCTAssertNil(repository.activeSessionId)
        XCTAssertNil(repository.activeSessionDate)
        XCTAssertNil(repository.dose1Time)
        XCTAssertNil(storage.loadCurrentSessionState().dose1Time)
        XCTAssertTrue(storage.fetchCloudKitTombstones().isEmpty)
        XCTAssertEqual(scheduler.cancelledIdentifiers, SessionRepository.sessionNotificationIdentifiers)
        XCTAssertEqual(Set(scheduler.cancelledIdentifiers), Set(AlarmService.wakeNotificationIdentifiers + AlarmService.reminderNotificationIdentifiers))

        scheduler.reset()
        XCTAssertTrue(repository.deleteSessionFromSync(sessionDate: date))
        XCTAssertTrue(scheduler.cancelledIdentifiers.isEmpty)
        XCTAssertTrue(storage.fetchCloudKitTombstones().isEmpty)
    }

    func testRetentionClearsCachedDoseAndAlarmsOnlyAfterDeletingTheCurrentRow() throws {
        let storage = EventStorage.inMemory()
        let scheduler = FakeNotificationScheduler()
        var now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-21T23:00:00Z"))
        let dose = now
        let repository = SessionRepository(storage: storage, notificationScheduler: scheduler,
            clock: { now }, timeZoneProvider: { TimeZone(secondsFromGMT: 0)! })
        XCTAssertTrue(repository.setDose1Time(dose).isCommitted)
        let active = try XCTUnwrap(repository.activeSessionId)
        scheduler.reset()
        XCTAssertTrue(repository.clearOldData(olderThanDays: 30))
        XCTAssertEqual(repository.activeSessionId, active)
        XCTAssertTrue(scheduler.cancelledIdentifiers.isEmpty)

        now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-05T23:00:00Z"))
        sqlite3_commit_hook(storage.db, { _ in 1 }, nil)
        XCTAssertFalse(repository.clearOldData(olderThanDays: 30))
        sqlite3_commit_hook(storage.db, nil, nil)
        XCTAssertEqual(repository.activeSessionId, active)
        XCTAssertEqual(storage.loadCurrentSessionState().dose1Time, dose)
        XCTAssertTrue(scheduler.cancelledIdentifiers.isEmpty)

        XCTAssertTrue(repository.clearOldData(olderThanDays: 30))
        XCTAssertNil(repository.activeSessionId)
        XCTAssertNil(repository.dose1Time)
        XCTAssertNil(storage.loadCurrentSessionState().dose1Time)
        XCTAssertEqual(scheduler.cancelledIdentifiers, SessionRepository.sessionNotificationIdentifiers)
        scheduler.reset()
        XCTAssertTrue(repository.clearOldData(olderThanDays: 30))
        XCTAssertTrue(scheduler.cancelledIdentifiers.isEmpty)
    }

    func testFailedDeleteRetainsActiveMedicationAndReminders() throws {
        let storage = EventStorage.inMemory()
        let scheduler = FakeNotificationScheduler()
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let repository = SessionRepository(storage: storage, notificationScheduler: scheduler,
            clock: { now }, timeZoneProvider: { TimeZone(secondsFromGMT: 0)! })
        XCTAssertTrue(repository.setDose1Time(now).isCommitted)
        let date = try XCTUnwrap(repository.activeSessionDate)
        try execute("""
            DROP TABLE dashboard_provider_associations;
            CREATE TABLE dashboard_provider_associations (session_date TEXT);
            INSERT INTO dashboard_provider_associations VALUES ('\(date)');
            CREATE TRIGGER reject_link BEFORE DELETE ON dashboard_provider_associations
            BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END;
            """, in: storage)
        scheduler.reset()
        var changes = 0
        let subscription = repository.sessionDidChange.sink { changes += 1 }
        defer { subscription.cancel() }
        XCTAssertFalse(repository.deleteSession(sessionDate: date))
        XCTAssertFalse(repository.deleteSessionFromSync(sessionDate: date))
        repository.clearTonight()
        XCTAssertEqual(repository.dose1Time, now)
        XCTAssertEqual(repository.activeSessionDate, date)
        XCTAssertTrue(scheduler.cancelledIdentifiers.isEmpty)
        XCTAssertEqual(changes, 0)
    }
}
