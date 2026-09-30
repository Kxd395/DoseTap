import XCTest
import SQLite3
import DoseCore
@testable import DoseTap

@MainActor
final class DaytimeCheckInStorageTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000.123)
    func value() throws -> DaytimeCheckIn {
        try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 0)
    }
    func repo(_ storage: EventStorage) -> SessionRepository {
        SessionRepository(storage: storage, clock: { self.now.addingTimeInterval(100) }, timeZoneProvider: { TimeZone(secondsFromGMT: 0)! })
    }
    func testIndependentRepeatedObservationAndRestart() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let repository = repo(EventStorage(dbPath: path)), a = try value(), b = try value()
        try repository.saveDaytimeCheckIn(a); try repository.saveDaytimeCheckIn(b)
        XCTAssertNil(repository.dose1Time)
        XCTAssertTrue(try repository.sessionDatesForExport().isEmpty)
        XCTAssertEqual(try repo(EventStorage(dbPath: path)).daytimeCheckIns().current.count, 2)
        XCTAssertTrue(try repository.daytimeCheckIns().current.contains(a))
    }
    func testFailedCommitRollbackAndRetryKeepExactIdentity() throws {
        let storage = EventStorage(dbPath: ":memory:"), repository = repo(storage), a = try value()
        storage.medicationFaultInjector = { $0 == .commit ? MedicationStorageInjectedFailure(code: .diskFull, sqliteCode: 13, detail: "Synthetic") : nil }
        XCTAssertThrowsError(try repository.saveDaytimeCheckIn(a))
        XCTAssertTrue(try repository.daytimeCheckIns().current.isEmpty)
        storage.medicationFaultInjector = nil
        try repository.saveDaytimeCheckIn(a); try repository.saveDaytimeCheckIn(a)
        XCTAssertEqual(try repository.daytimeCheckIns().revisions, [a])
    }
    func testCorrectionRejectsStaleAndChangedIDAndClearRemovesAll() throws {
        let storage = EventStorage(dbPath: ":memory:"), repository = repo(storage), a = try value()
        try repository.saveDaytimeCheckIn(a)
        let next = try a.corrected(response: 4, status: .answered, reason: "Correction", recordedAt: now.addingTimeInterval(30))
        try repository.saveDaytimeCheckIn(next)
        XCTAssertThrowsError(try repository.saveDaytimeCheckIn(a.corrected(response: 6, status: .answered, reason: "Stale", recordedAt: now.addingTimeInterval(40))))
        let changed = try DaytimeCheckIn(id: a.id, revisionID: a.revisionID, assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 2)
        XCTAssertThrowsError(try repository.saveDaytimeCheckIn(changed))
        XCTAssertEqual(try repository.daytimeCheckIns().current, [next])
        storage.clearAllData()
        XCTAssertTrue(try repository.daytimeCheckIns().revisions.isEmpty)
    }
    func testCorruptPayloadFailsClosed() throws {
        let storage = EventStorage(dbPath: ":memory:"), repository = repo(storage)
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO daytime_checkins VALUES ('bad', 'bad', '{}')", nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try repository.daytimeCheckIns())
        XCTAssertThrowsError(try repository.saveDaytimeCheckIn(value()))
    }
}
