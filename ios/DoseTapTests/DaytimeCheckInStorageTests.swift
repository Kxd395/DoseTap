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

extension DaytimeCheckInStorageTests {
    func testLinkedEventReviewCountsOneIndependentEvent() throws {
        let repository = repo(EventStorage(dbPath: ":memory:"))
        let event = try DaytimeEvent(kind: .unplannedSleep, occurredAt: now.addingTimeInterval(-600), recordedAt: now, timeZoneIdentifier: "UTC")
        try repository.saveDaytimeEvent(event); try repository.saveDaytimeEvent(event)
        let review = try DaytimeEventReview(from: now.addingTimeInterval(-3600), to: now, status: .eventsReported, eventIDs: [event.id])
        for _ in 0..<2 {
            let observation = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: nil, status: .incomplete, eventReview: review)
            try repository.saveDaytimeCheckIn(observation)
        }
        XCTAssertEqual(try repository.daytimeEvents().current.count, 1)
        XCTAssertEqual(try repository.daytimeCheckIns().current.count, 2)
        XCTAssertTrue(try repository.sessionDatesForExport().isEmpty)
    }
    func testUnknownEventReferenceRejectedWithoutSaving() throws {
        let repository = repo(EventStorage(dbPath: ":memory:"))
        let review = try DaytimeEventReview(from: now, to: now, status: .eventsReported, eventIDs: [UUID()])
        let observation = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 4, eventReview: review)
        XCTAssertThrowsError(try repository.saveDaytimeCheckIn(observation))
        XCTAssertTrue(try repository.daytimeCheckIns().current.isEmpty)
    }
    func testEventFailureAndCorrectionHistory() throws {
        let storage = EventStorage(dbPath: ":memory:"), repository = repo(storage)
        let event = try DaytimeEvent(kind: .struggling, occurredAt: now, recordedAt: now, timeZoneIdentifier: "UTC")
        storage.medicationFaultInjector = { $0 == .commit ? MedicationStorageInjectedFailure(code: .diskFull, sqliteCode: 13, detail: "Synthetic") : nil }
        XCTAssertThrowsError(try repository.saveDaytimeEvent(event))
        XCTAssertTrue(try repository.daytimeEvents().current.isEmpty)
        storage.medicationFaultInjector = nil
        try repository.saveDaytimeEvent(event)
        let corrected = try event.corrected(kind: .unclear, note: "Unsure", reason: "Correction", recordedAt: now)
        try repository.saveDaytimeEvent(corrected)
        XCTAssertEqual(try repository.daytimeEvents().revisions.count, 2)
        XCTAssertEqual(try repository.daytimeEvents().current, [corrected])
        storage.clearAllData(); XCTAssertTrue(try repository.daytimeEvents().revisions.isEmpty)
    }
}

extension DaytimeCheckInStorageTests {
    func testNearbySnapshotIncludesIndependentRevisions() throws {
        let storage = EventStorage(dbPath: ":memory:"), repository = repo(storage), a = try value()
        try repository.saveDaytimeCheckIn(a)
        try repository.saveDaytimeEvent(DaytimeEvent(kind: .unclear, occurredAt: now, recordedAt: now, timeZoneIdentifier: "UTC"))
        let snapshot = try storage.dashboardSnapshot(sourceID: "synthetic", sequence: 1, capturedAt: now)
        let section = try XCTUnwrap(snapshot.sections.first { $0.dataset == .daytimeDiary })
        XCTAssertEqual(section.rowCount, 2)
        let text = String(data: try XCTUnwrap(section.rows), encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("daytime_checkins")); XCTAssertTrue(text.contains("daytime_events"))
    }
}
