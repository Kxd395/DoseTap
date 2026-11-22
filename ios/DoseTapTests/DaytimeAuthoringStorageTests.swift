import DoseCore
import SQLite3
import XCTest
@testable import DoseTap

@MainActor
final class DaytimeAuthoringStorageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_100)

    func testCommitFailureRollsBackCollectionAndAllowsExactRetry() throws {
        var fail = true
        let storage = EventStorage(dbPath: ":memory:", medicationFaultInjector: { point in
            point == .commit && fail ? .init(code: .io, sqliteCode: SQLITE_IOERR, detail: "Synthetic failure") : nil
        })
        let repository = SessionRepository(storage: storage, notificationScheduler: FakeNotificationScheduler(), clock: { self.now })
        let entry = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 0)
        XCTAssertThrowsError(try repository.saveDaytimeCheckIn(entry))
        XCTAssertTrue(try repository.daytimeCheckIns().current.isEmpty)
        XCTAssertTrue(try repository.exportIndependentSourceRecords().isEmpty)
        fail = false

        try repository.saveDaytimeCheckIn(entry)
        try repository.saveDaytimeCheckIn(entry)
        let correction = try entry.corrected(response: nil, status: .unsure, reason: "Reviewed", recordedAt: now)
        try repository.saveDaytimeCheckIn(correction)
        XCTAssertEqual(try repository.daytimeCheckIns().current, [correction])
        let rows = try repository.exportIndependentSourceRecords()
        XCTAssertEqual(rows.compactMap { $0.columns["payload"]?.text }, try [entry.encoded(), correction.encoded()])
        XCTAssertTrue(try repository.exportIndependentSourceRecords(in: "daytime_events").isEmpty)
        XCTAssertTrue(try storage.exportSourceSnapshot(sessionDate: "2026-09-21").records.isEmpty)
        XCTAssertTrue(storage.clearAllData())
        XCTAssertTrue(try repository.daytimeCheckIns().revisions.isEmpty)
    }

    func testReminderSaveIsAtomicAndRejectsStaleChangesAfterReopen() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var fail = true
        let storage = EventStorage(dbPath: url.path, medicationFaultInjector: { point in
            point == .commit && fail ? .init(code: .io, sqliteCode: SQLITE_IOERR, detail: "test") : nil
        })
        let repo = SessionRepository(storage: storage, notificationScheduler: FakeNotificationScheduler())
        let initial = try repo.daytimePrompts()
        var configured = initial
        try configured.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true, at: now)
        XCTAssertThrowsError(try repo.saveDaytimePrompts(configured, replacing: initial))
        XCTAssertTrue(try storage.independentRecordTables().isEmpty)
        fail = false
        try repo.saveDaytimePrompts(configured, replacing: initial)
        try repo.saveDaytimePrompts(configured, replacing: initial)

        let reopened = SessionRepository(storage: EventStorage(dbPath: url.path), notificationScheduler: FakeNotificationScheduler())
        XCTAssertEqual(try reopened.daytimePrompts(), configured)
        var competing = initial
        try competing.configure(hour: 15, minute: 0, timeZone: "UTC", enabled: true, at: now)
        XCTAssertThrowsError(try reopened.saveDaytimePrompts(competing, replacing: initial))
        let entry = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 0)
        _ = try storage.saveDaytimeCheckIn(entry)
        XCTAssertEqual(Set(try storage.exportIndependentSourceRecords().map(\.sourceTable)), ["daytime_checkins", "daytime_prompt_state"])
        XCTAssertTrue(storage.clearAllData())
        XCTAssertEqual(try reopened.daytimePrompts(), initial)
        XCTAssertTrue(try reopened.daytimeCheckIns().current.isEmpty)
    }

    func testUnreadableReminderCannotBeOverwrittenAfterCheckInFirst() throws {
        let storage = EventStorage.inMemory()
        let repo = SessionRepository(storage: storage, notificationScheduler: FakeNotificationScheduler())
        let entry = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 0)
        _ = try storage.saveDaytimeCheckIn(entry)
        let initial = try repo.daytimePrompts()
        var changed = initial
        try changed.configure(hour: 9, minute: 30, timeZone: "UTC", enabled: true, at: now)
        try repo.saveDaytimePrompts(changed, replacing: initial)
        for payload in ["{}", "not JSON"] {
            XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE daytime_prompt_state SET payload = '\(payload)'", nil, nil, nil), SQLITE_OK)
            XCTAssertThrowsError(try repo.daytimePrompts())
            XCTAssertThrowsError(try repo.saveDaytimePrompts(changed, replacing: initial))
            XCTAssertEqual(try storage.exportIndependentSourceRecords(in: "daytime_prompt_state").first?.columns["payload"]?.text, payload)
        }
        XCTAssertEqual(try repo.daytimeCheckIns().current, [entry])
    }

    func testUnmarkedPartialPhoneSchemaStaysRejected() throws {
        let storage = EventStorage.inMemory()
        XCTAssertEqual(sqlite3_exec(storage.db, """
            CREATE TABLE daytime_checkins (
                revision_id TEXT PRIMARY KEY, observation_id TEXT NOT NULL, payload TEXT NOT NULL
            )
            """, nil, nil, nil), SQLITE_OK)
        let repo = SessionRepository(storage: storage, notificationScheduler: FakeNotificationScheduler(), clock: { self.now })
        let entry = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 5)
        XCTAssertThrowsError(try repo.saveDaytimeCheckIn(entry))
        XCTAssertThrowsError(try repo.exportIndependentSourceRecords())
        XCTAssertFalse(storage.clearAllData())
    }
}
