import XCTest
import SQLite3
import DoseCore
@testable import DoseTap

@MainActor
final class ExportSourceSnapshotTests: XCTestCase {
    private func execute(_ sql: String, _ storage: EventStorage) {
        XCTAssertEqual(sqlite3_exec(storage.db, sql, nil, nil, nil), SQLITE_OK)
    }

    private func independentFixture() -> EventStorage {
        let storage = EventStorage.inMemory()
        for table in StudioIndependentSourceRecord.sourceTables {
            let key = StudioIndependentSourceRecord.primaryKeys[table]!
            execute("""
            DROP TABLE IF EXISTS \(table);
            CREATE TABLE \(table)(\(key) TEXT PRIMARY KEY, payload TEXT, missing TEXT, zero REAL, binary BLOB);
            INSERT INTO \(table) VALUES ('original', '{"revision":1,"score":0}', NULL, 0, X'0001');
            """, storage)
        }
        return storage
    }

    func testIndependentSnapshotPreservesAllSourcesWithoutNightRecords() throws {
        let storage = independentFixture()
        let rows = try storage.exportIndependentSourceRecords()
        XCTAssertEqual(rows.map(\.sourceTable), StudioIndependentSourceRecord.sourceTables)
        XCTAssertEqual(rows.count, StudioIndependentSourceRecord.sourceTables.count)
        let restored = try JSONDecoder().decode([StudioIndependentSourceRecord].self, from: JSONEncoder().encode(rows))
        XCTAssertEqual(restored.map(\.recordID), Array(repeating: "original", count: StudioIndependentSourceRecord.sourceTables.count))
        XCTAssertTrue(rows.allSatisfy { $0.columns["missing"]?.type == "null" && $0.columns["zero"]?.real == 0 })
        XCTAssertTrue(rows.allSatisfy { $0.columns["binary"]?.blobBase64 == "AAE=" })
        XCTAssertTrue(try storage.exportSourceSnapshot(sessionDate: "2026-09-30").records.isEmpty)
        XCTAssertEqual(rows, try storage.exportIndependentSourceRecords())
    }

    func testIndependentMissingTableOrInvalidUTF8FailsEntireRead() throws {
        let storage = independentFixture()
        execute("UPDATE daytime_events SET payload = CAST(X'FF' AS TEXT)", storage)
        XCTAssertThrowsError(try storage.exportIndependentSourceRecords())
        execute("UPDATE daytime_events SET payload = '{}'", storage)
        execute("DROP TABLE work_block_context", storage)
        XCTAssertThrowsError(try storage.exportIndependentSourceRecords())
    }

    func testIndependentSnapshotPreservesEmbeddedNullAndRejectsInvalidIdentity() throws {
        let storage = independentFixture()
        execute("UPDATE daytime_events SET payload = 'left' || char(0) || 'right'", storage)
        XCTAssertEqual(try storage.exportIndependentSourceRecords().first { $0.sourceTable == "daytime_events" }?.columns["payload"]?.text, "left\0right")
        execute("UPDATE daytime_events SET revision_id = NULL", storage)
        XCTAssertThrowsError(try storage.exportIndependentSourceRecords())
    }

    func testFullManualScopeIncludesIndependentRowsWhileScheduledSubsetExcludesThem() throws {
        let storage = independentFixture()
        // Use the same isolated source for both paths; no real providers are queried.
        let source = SessionRepository(storage: storage)
        let exporter = StudioBundleExporter()
        let full = try exporter.buildStudioInsightsBundleDataForTesting(using: source, sessionDates: [], includeIndependentRecords: true)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: full) as? [String: Any])
        XCTAssertEqual(root["schemaVersion"] as? Int, 6)
        XCTAssertEqual(root["archiveScope"] as? String, "manual_full_local_records")
        XCTAssertEqual(root["independentRecordsIncluded"] as? Bool, true)
        XCTAssertEqual((root["independentSourceRecords"] as? [Any])?.count, StudioIndependentSourceRecord.sourceTables.count)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("independent-scope-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // This is the production entry point used by scheduled archives.
        try exporter.writeLocalStudioExportBundle(using: source, to: folder)
        let subset = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("insights_bundle.json"))) as? [String: Any])
        XCTAssertEqual(subset["schemaVersion"] as? Int, 5)
        XCTAssertEqual(subset["archiveScope"] as? String, "local_subset")
        XCTAssertEqual(subset["independentRecordsIncluded"] as? Bool, false)
        XCTAssertNil(subset["independentSourceRecords"])
        XCTAssertTrue((subset["exportWarnings"] as? [String])?.contains(where: { $0.contains("full manual export") }) == true)
        execute("DROP TABLE nap_diary", storage)
        XCTAssertThrowsError(try exporter.buildStudioInsightsBundleDataForTesting(using: source, sessionDates: [], includeIndependentRecords: true))
        XCTAssertNoThrow(try exporter.writeLocalStudioExportBundle(using: source, to: folder))
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

    func testLinkedPreSleepIdentityIsCheckedAgainstOtherDates() throws {
        let storage = EventStorage.inMemory()
        execute("""
        INSERT INTO sleep_sessions(session_id,session_date,start_utc) VALUES('a','2030-04-06','2030-04-06T23:00:00Z');
        INSERT INTO pre_sleep_logs(id,session_id,created_at_utc,local_offset_minutes) VALUES('p','a','original',0);
        INSERT INTO checkin_submissions(id,source_record_id,session_id,session_date,checkin_type,
            questionnaire_version,user_id,submitted_at_utc,local_offset_minutes,responses_json)
        VALUES('submission','p',NULL,'2030-04-05','pre_night','v1','local','original',0,'{}');
        """, storage)
        let snapshot = try storage.exportSourceSnapshot(sessionDate: "2030-04-05")
        XCTAssertTrue(snapshot.identityResolution.isRawOnly)
        XCTAssertEqual(snapshot.identityResolution.reasons, ["session_identity_spans_dates"])
        XCTAssertEqual(snapshot.records.first { $0.sourceTable == "pre_sleep_logs" }?.columns["session_id"]?.text, "a")
    }
}
