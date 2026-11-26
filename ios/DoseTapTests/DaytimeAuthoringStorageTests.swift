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

    func testCorrectionThatChangesContextIsRejected() throws {
        let storage = EventStorage.inMemory()
        let repo = SessionRepository(storage: storage, notificationScheduler: FakeNotificationScheduler(), clock: { self.now })
        let original = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 3)
        try repo.saveDaytimeCheckIn(original)
        let altered = try DaytimeCheckIn(id: original.id, predecessorID: original.revisionID, createdAt: original.createdAt,
            assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 4, status: .answered,
            origin: original.origin, activity: original.activity, setting: original.setting, coping: original.coping,
            copingActions: Set(original.copingActions), note: "Changed note", correctionReason: "Reviewed",
            promptID: original.promptID, eventReview: original.eventReview, samplingProtocolID: original.samplingProtocolID,
            samplingProtocolLabel: original.samplingProtocolLabel, sourceLinks: original.sourceLinks)
        XCTAssertThrowsError(try repo.saveDaytimeCheckIn(altered))
        XCTAssertEqual(try repo.daytimeCheckIns().current, [original])
        let correction = try original.corrected(response: 4, status: .answered, reason: "Reviewed", recordedAt: now)
        try repo.saveDaytimeCheckIn(correction)
        XCTAssertEqual(try repo.daytimeCheckIns().current, [correction])
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
