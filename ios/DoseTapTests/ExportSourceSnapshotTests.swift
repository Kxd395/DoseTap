import XCTest
import SQLite3
@testable import DoseTap

@MainActor
final class ExportSourceSnapshotTests: XCTestCase {
    private func execute(_ sql: String, _ storage: EventStorage) {
        XCTAssertEqual(sqlite3_exec(storage.db, sql, nil, nil, nil), SQLITE_OK)
    }

    func testCheckedSourceSnapshotPreservesOriginalQuestionnairesAndDetectsConflicts() throws {
        let storage = EventStorage.inMemory()
        execute("""
        INSERT INTO dose_events(id,session_id,session_date,event_type,timestamp)
        VALUES('d1','a','2026-09-11','dose1','2026-09-11T23:00:00Z');
        INSERT INTO sleep_sessions(session_id,session_date,start_utc)
        VALUES('b','2026-09-11','2026-09-11T23:05:00Z');
        INSERT INTO pre_sleep_logs(id,session_id,created_at_utc,local_offset_minutes,answers_json)
        VALUES('p','b','capture-is-not-dose-time',-240,'{"future": [1, 2]}');
        INSERT INTO morning_checkins(id,session_id,session_date,timestamp,notes)
        VALUES('m1','a','2026-09-11','original-time',NULL),('m2','b','2026-09-11','another-time','');
        """, storage)
        let before = try storage.exportSourceSnapshot(sessionDate: "2026-09-11")
        XCTAssertTrue(before.identityResolution.isRawOnly)
        XCTAssertEqual(before.identityResolution.sessionIds, ["a", "b"])
        XCTAssertEqual(before.identityResolution.reasons, ["multiple_session_identities", "multiple_source_questionnaires"])
        let pre = try XCTUnwrap(before.records.first { $0.sourceTable == "pre_sleep_logs" })
        XCTAssertEqual(pre.columns["answers_json"]?.text, "{\"future\": [1, 2]}")
        XCTAssertEqual(pre.columns["local_offset_minutes"]?.integer, -240)
        XCTAssertEqual(pre.columns["created_at_utc"]?.text, "capture-is-not-dose-time")
        let mornings = before.records.filter { $0.sourceTable == "morning_checkins" }
        XCTAssertEqual(mornings.map { $0.columns["notes"]?.type }, ["null", "text"])
        XCTAssertEqual(mornings.last?.columns["notes"]?.text, "")
        XCTAssertEqual(before.records, try storage.exportSourceSnapshot(sessionDate: "2026-09-11").records)
    }

    func testCrossDateIdentityIsUnavailableButNullLegacyIdentityIsNotAssigned() throws {
        let storage = EventStorage.inMemory()
        execute("""
        INSERT INTO dose_events(id,session_id,session_date,event_type,timestamp)
        VALUES('d1',NULL,'2026-09-11','dose1','2026-09-11T23:00:00Z'),
              ('d2','shared','2026-09-12','dose1','2026-09-12T23:00:00Z'),
              ('d3','shared','2026-09-13','dose1','2026-09-13T23:00:00Z');
        """, storage)
        XCTAssertEqual(try storage.exportSourceSnapshot(sessionDate: "2026-09-11").identityResolution.status, "resolved")
        XCTAssertEqual(try storage.exportSourceSnapshot(sessionDate: "2026-09-12").identityResolution.reasons, ["session_identity_spans_dates"])
        XCTAssertNil(try storage.eventExportRecords(sessionDate: "2026-09-11").first?.sessionId)
    }

    func testActualReadFailureCannotBecomeAnExportableConflict() throws {
        let storage = EventStorage.inMemory()
        execute("DROP TABLE morning_checkins", storage)
        XCTAssertThrowsError(try storage.exportSourceSnapshot(sessionDate: "2026-09-11"))
    }
}
