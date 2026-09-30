import XCTest
import SQLite3
import DoseCore
@testable import DoseTap

@MainActor
final class PreSleepWorkSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_794_800)
    private func makeStorage() throws -> EventStorage {
        let storage = EventStorage.inMemory()
        var context = WorkContextDocument()
        context.rosters = [.init(effectiveFrom: "2026-09-01", effectiveTo: "2026-12-31",
            timeZoneIdentifier: "UTC", weekdays: [3, 4, 5], plannedShiftMinutes: 780,
            recordedAt: now.addingTimeInterval(-3600))]
        try storage.saveWorkContext(context, expectedRevision: nil)
        return storage
    }
    func testNewExplicitCompleteSaveCapturesPlanWithNoInventedSessionID() throws {
        let storage = try makeStorage()
        let repository = SessionRepository(storage: storage, clock: { self.now })
        let saved = try repository.savePreSleepLog(answers: .init())
        let snapshot = try XCTUnwrap(storage.loadWorkContext()?.planSnapshots?.first)
        XCTAssertEqual(snapshot.preSleepLogID, saved.id)
        XCTAssertEqual(snapshot.capturedAt, now)
        XCTAssertNil(snapshot.sessionID)
        XCTAssertEqual(snapshot.rosterCount, 1)
    }
    func testSkippedAndPreviouslySavedDraftNeverBackfillProspectiveSnapshot() throws {
        let storage = try makeStorage()
        let skipped = try storage.savePreSleepLogOrThrow(sessionId: "skip", answers: .init(),
            completionState: "skipped", now: now, prospectiveCaptureEligible: true)
        XCTAssertTrue(try storage.loadWorkContext()?.planSnapshots?.isEmpty ?? true)
        _ = try storage.savePreSleepLogOrThrow(sessionId: "skip", answers: .init(),
            now: now.addingTimeInterval(60), existingLog: skipped, prospectiveCaptureEligible: true)
        XCTAssertTrue(try storage.loadWorkContext()?.planSnapshots?.isEmpty ?? true)
        _ = try storage.savePreSleepLogOrThrow(sessionId: "imported", answers: .init(), now: now)
        XCTAssertTrue(try storage.loadWorkContext()?.planSnapshots?.isEmpty ?? true)
    }
    func testRetryAndHistoricalEditPreserveOriginalPlanCapture() throws {
        let storage = try makeStorage()
        let original = try storage.savePreSleepLogOrThrow(sessionId: "session", answers: .init(),
            now: now, prospectiveCaptureEligible: true, prospectiveCaptureSessionID: "session")
        let snapshot = try XCTUnwrap(storage.loadWorkContext()?.planSnapshots?.first)
        _ = try storage.savePreSleepLogOrThrow(sessionId: "session", answers: .init(),
            now: now.addingTimeInterval(60), prospectiveCaptureEligible: true,
            prospectiveCaptureSessionID: "session")
        _ = try storage.savePreSleepLogOrThrow(sessionId: "session", answers: .init(),
            now: now.addingTimeInterval(120), existingLog: original, prospectiveCaptureEligible: true,
            prospectiveCaptureSessionID: "session")
        XCTAssertEqual(try storage.loadWorkContext()?.planSnapshots, [snapshot])
    }
    func testCaptureFailureRollsBackQuestionnaireAndPreSleepRecordTogether() throws {
        let storage = try makeStorage(), before = try storage.loadWorkContext()
        XCTAssertEqual(sqlite3_exec(storage.db,
            "CREATE TRIGGER synthetic_work_capture_failure BEFORE UPDATE ON work_block_context BEGIN SELECT RAISE(ABORT, 'synthetic capture failure'); END;",
            nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try storage.savePreSleepLogOrThrow(sessionId: "failed", answers: .init(),
            now: now, prospectiveCaptureEligible: true))
        XCTAssertEqual(storage.fetchPreSleepLogCount(sessionId: "failed"), 0)
        XCTAssertEqual(try storage.loadWorkContext(), before)
    }
}
