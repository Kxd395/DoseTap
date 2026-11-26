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

    func testMissingDiaryCollectionBlocksFullExportAndResetWithoutLosingRecords() throws {
        let storage = EventStorage.inMemory()
        let repo = SessionRepository(storage: storage, notificationScheduler: FakeNotificationScheduler(), clock: { self.now })
        let entry = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 5)
        try repo.saveDaytimeCheckIn(entry)
        // Schema initialization creates every diary collection; a missing one was removed outside this build.
        XCTAssertEqual(sqlite3_exec(storage.db, "DROP TABLE nap_diary", nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try repo.exportIndependentSourceRecords())
        XCTAssertFalse(storage.clearAllData())
        XCTAssertEqual(try repo.daytimeCheckIns().current, [entry])
    }
}
