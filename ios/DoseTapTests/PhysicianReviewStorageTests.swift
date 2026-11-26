import XCTest
import SQLite3
import DoseCore
@testable import DoseTap

@MainActor
final class PhysicianReviewStorageTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func repository(_ storage: EventStorage) -> SessionRepository {
        SessionRepository(storage: storage, clock: { self.now }, timeZoneProvider: { TimeZone(secondsFromGMT: 0)! })
    }
    func testCompletedVisitAndSnapshotSurviveRestartWithoutNightSession() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let repo = repository(EventStorage(dbPath: path))
        let visit = try PhysicianVisit(occurredAt: now.addingTimeInterval(-86400), recordedAt: now, now: now)
        try repo.savePhysicianVisit(visit); try repo.savePhysicianVisit(visit)
        let period = try PhysicianReportPeriod.resolve(.sinceCompletedVisit, ledger: repo.physicianVisits(), asOf: now, timeZone: TimeZone(secondsFromGMT: 0)!)
        let snapshot = try PhysicianReportSnapshot(period: period, observations: [], notes: [], questions: ["Question"], appVersion: "test", generatedAt: now)
        try repo.savePhysicianReport(snapshot); try repo.savePhysicianReport(snapshot)
        let restarted = repository(EventStorage(dbPath: path))
        XCTAssertEqual(try restarted.physicianVisits().revisions, [visit])
        XCTAssertEqual(try restarted.physicianReports(), [snapshot])
        XCTAssertNil(restarted.activeSessionId)
        XCTAssertTrue(try restarted.sessionDatesForExport().isEmpty)
    }
    func testFailedCommitPublishesNothingAndRetryIsIdempotent() throws {
        let storage = EventStorage(dbPath: ":memory:"), repo = repository(storage)
        let visit = try PhysicianVisit(occurredAt: now, recordedAt: now, now: now)
        for point: MedicationStorageFaultPoint in [.begin, .insert, .commit] {
            storage.medicationFaultInjector = { $0 == point ? MedicationStorageInjectedFailure(code: .diskFull, detail: "Synthetic") : nil }
            XCTAssertThrowsError(try repo.savePhysicianVisit(visit))
            storage.medicationFaultInjector = nil
            XCTAssertTrue(try repo.physicianVisits().revisions.isEmpty)
        }
        try repo.savePhysicianVisit(visit); try repo.savePhysicianVisit(visit)
        XCTAssertEqual(try repo.physicianVisits().revisions.count, 1)
    }
    func testStaleCorrectionCannotBranchHistory() throws {
        let repo = repository(EventStorage(dbPath: ":memory:"))
        let first = try PhysicianVisit(occurredAt: now.addingTimeInterval(-1), recordedAt: now, now: now)
        try repo.savePhysicianVisit(first)
        let correction = try PhysicianVisit(id: first.id, predecessorID: first.revisionID, occurredAt: now.addingTimeInterval(-2), recordedAt: now, now: now)
        try repo.savePhysicianVisit(correction)
        let stale = try PhysicianVisit(id: first.id, predecessorID: first.revisionID, occurredAt: now.addingTimeInterval(-3), recordedAt: now, now: now)
        XCTAssertThrowsError(try repo.savePhysicianVisit(stale))
        XCTAssertEqual(try repo.physicianVisits().current, [correction])
    }
    func testCorruptPayloadFailsClosedAndClearRemovesRecords() throws {
        let storage = EventStorage(dbPath: ":memory:"), repo = repository(storage)
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO physician_review_records VALUES ('invalid','visit','{}')", nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try repo.physicianVisits())
        storage.clearAllData()
        XCTAssertTrue(try repo.physicianVisits().revisions.isEmpty)
    }
}
