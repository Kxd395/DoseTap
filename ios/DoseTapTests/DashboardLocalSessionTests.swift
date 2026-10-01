import XCTest
import SQLite3
import DoseCore
@testable import DoseTap

@MainActor
final class DashboardLocalSessionTests: XCTestCase {
    func execute(_ sql: String, _ storage: EventStorage) {
        XCTAssertEqual(sqlite3_exec(storage.db, sql, nil, nil, nil), SQLITE_OK)
    }
    func testDashboardFullHistorySnapshotPerformance() throws {
        let storage = EventStorage.inMemory()
        for index in 0..<365 {
            execute("INSERT INTO dose_events(id,event_type,timestamp,session_date,session_id) VALUES('d\(index)','dose1','2026-09-29T22:00:00Z','2026-09-29','s\(index)')", storage)
        }
        measure {
            XCTAssertEqual(try? storage.dashboardContextSnapshot(capturedAt: Date(timeIntervalSince1970: 1_790_784_000)).sessions.count, 365)
        }
    }

    func testCapturedRowsAreImmutableAndDecodeMatchesSynchronousSnapshot() async throws {
        let storage = EventStorage.inMemory(), capturedAt = Date(timeIntervalSince1970: 1_790_784_000)
        execute("INSERT INTO dose_events(id,event_type,timestamp,session_date,session_id) VALUES('before','dose1','2026-09-29T22:00:00Z','2026-09-29','a')", storage)
        let expected = try storage.dashboardContextSnapshot(capturedAt: capturedAt)
        let copy = try storage.captureDashboardContext(capturedAt: capturedAt)
        XCTAssertEqual(sqlite3_get_autocommit(storage.db), 1, "No transaction may remain open while worker decoding suspends")
        execute("INSERT INTO dose_events(id,event_type,timestamp,session_date,session_id) VALUES('after','dose2','2026-09-30T02:00:00Z','2026-09-29','a')", storage)
        let actual = try await Task.detached { try copy.decode() }.value
        XCTAssertEqual(actual.sessions.map(\.fingerprint), expected.sessions.map(\.fingerprint))
        XCTAssertEqual(actual.sessions.flatMap(\.doses).map(\.id), ["before"])
        let fresh = try await SessionRepository(storage: storage).dashboardContextSnapshotAsync(capturedAt: capturedAt)
        XCTAssertEqual(Set(fresh.sessions.flatMap(\.doses).map(\.id)), ["before", "after"])
    }

    func testDashboardMainActorCapturePerformance() throws {
        let storage = EventStorage.inMemory()
        for index in 0..<365 {
            execute("INSERT INTO dose_events(id,event_type,timestamp,session_date,session_id) VALUES('d\(index)','dose1','2026-09-29T22:00:00Z','2026-09-29','s\(index)')", storage)
        }
        measure {
            XCTAssertNotNil(try? storage.captureDashboardContext(capturedAt: Date(timeIntervalSince1970: 1_790_784_000)))
        }
    }

    func testExactIdentityIncludesLegacyOrphansAndClosure() throws {
        let storage = EventStorage.inMemory()
        execute("""
        INSERT INTO sleep_sessions(session_id,session_date,start_utc,end_utc) VALUES('a','2026-09-29','2026-09-29T22:00:00Z','2026-09-30T08:00:00Z'),('b','2026-09-29','2026-09-30T02:00:00Z',NULL);
        INSERT INTO dose_events(id,event_type,timestamp,session_date,session_id) VALUES('d1','dose1','2026-09-29T22:00:00Z','2026-09-29','a'),('d2','dose2','2026-09-30T02:00:00Z','2026-09-29','b'),('legacy','dose2','2026-09-30T04:00:00Z','2026-09-29',NULL);
        INSERT INTO sleep_events(id,event_type,timestamp,session_date,session_id) VALUES('nap','nap_start','2026-09-30T05:00:00Z','2026-09-29','b');
        INSERT INTO pre_sleep_logs(id,created_at_utc,local_offset_minutes,answers_json) VALUES('orphan','2026-09-29T22:00:00Z',0,'{}');
        """, storage)
        let before = sqlite3_total_changes(storage.db)
        let rows = try storage.dashboardLocalSessions()
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows.first { $0.id == "session:a" }?.doses.map(\.id), ["d1"])
        XCTAssertEqual(rows.first { $0.id == "session:b" }?.doses.map(\.id), ["d2"])
        XCTAssertEqual(rows.first { $0.id == "session:a" }?.sessionClosed, true)
        XCTAssertEqual(rows.first { $0.id == "session:b" }?.sessionClosed, false)
        XCTAssertEqual(rows.first { $0.id == "legacy:2026-09-29" }?.needsReview, true)
        XCTAssertNotNil(rows.first { $0.id == "orphan:pre:orphan" }?.preSleep)
        XCTAssertEqual(sqlite3_total_changes(storage.db), before)
    }
    func testReadFailureAndOpenTransactionThrowInsteadOfReturningEmpty() {
        let storage = EventStorage.inMemory()
        execute("BEGIN", storage)
        XCTAssertThrowsError(try storage.dashboardLocalSessions())
        execute("ROLLBACK", storage)
        execute("DROP TABLE morning_checkins", storage)
        XCTAssertThrowsError(try storage.dashboardLocalSessions())
        XCTAssertEqual(sqlite3_get_autocommit(storage.db), 1)
    }
    func testMalformedEventTimestampFailsWholeSnapshot() {
        let storage = EventStorage.inMemory()
        execute("INSERT INTO dose_events(id,event_type,timestamp,session_date,session_id) VALUES('bad','dose1','invalid','2026-09-29','a')", storage)
        XCTAssertThrowsError(try storage.dashboardLocalSessions())
    }
    func testConflictingIdentityDatesStayUnresolved() throws {
        let storage = EventStorage.inMemory()
        execute("INSERT INTO dose_events(id,event_type,timestamp,session_date,session_id) VALUES('a','dose1','2026-09-29T22:00:00Z','2026-09-29','same'),('b','dose2','2026-09-30T02:00:00Z','2026-09-30','same')", storage)
        let rows = try storage.dashboardLocalSessions()
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.sessionID == nil && $0.needsReview })
    }
    func testActiveRequiresCurrentLifecycleNotJustAnUnclosedHistoricalRow() throws {
        let storage = EventStorage.inMemory()
        execute("""
        INSERT INTO sleep_sessions(session_id,session_date,start_utc) VALUES('old','2026-09-28','2026-09-28T22:00:00Z');
        INSERT INTO current_session(id,session_id,session_date,session_start_utc) VALUES(1,'live','2026-09-29','2026-09-29T22:00:00Z');
        """, storage)
        var rows = try storage.dashboardLocalSessions()
        XCTAssertEqual(rows.first { $0.sessionID == "old" }?.sessionActive, false)
        XCTAssertEqual(rows.first { $0.sessionID == "live" }?.sessionActive, true)
        execute("UPDATE current_session SET session_end_utc='2026-09-30T08:00:00Z',terminal_state='completed'", storage)
        rows = try storage.dashboardLocalSessions()
        XCTAssertEqual(rows.first { $0.sessionID == "live" }?.sessionActive, false)
        XCTAssertEqual(rows.first { $0.sessionID == "live" }?.sessionClosed, true)
    }
}
