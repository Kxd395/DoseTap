import XCTest
import SQLite3
import DoseCore
@testable import DoseTap

private final class DashboardConcurrentWriter {
    let db: OpaquePointer
    var result: Int32?
    init(db: OpaquePointer) { self.db = db }
    func writeOnce() {
        guard result == nil else { return }
        result = sqlite3_exec(db, """
        BEGIN IMMEDIATE;
        INSERT INTO sleep_events(id,event_type,timestamp,session_date) VALUES('concurrent','nap_start','original','2000-01-01');
        INSERT INTO inventory_snapshots(id,as_of_utc,medication_name) VALUES('concurrent','original','synthetic');
        COMMIT;
        """, nil, nil, nil)
    }
}

@MainActor
final class DashboardSnapshotStorageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private func execute(_ sql: String, _ storage: EventStorage) {
        XCTAssertEqual(sqlite3_exec(storage.db, sql, nil, nil, nil), SQLITE_OK)
    }
    private func rows(_ dataset: DashboardDataset, _ snapshot: CloudDashboardSnapshot) throws -> [[String: Any]] {
        let section = try XCTUnwrap(snapshot.sections.first { $0.dataset == dataset })
        return try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(section.rows)) as? [[String: Any]])
    }
    private func columns(_ row: [String: Any]) throws -> [String: [String: Any]] {
        try XCTUnwrap(row["columns"] as? [String: [String: Any]])
    }
    func testEmptyCompleteLocalSectionsAndExplicitMissingCapabilities() throws {
        let storage = EventStorage.inMemory()
        let repository = SessionRepository(storage: storage, clock: { self.now })
        let snapshot = try repository.dashboardSnapshot(sourceID: "synthetic-install", sequence: 1)
        XCTAssertEqual(snapshot.capturedAt, now)
        XCTAssertEqual(Set(snapshot.sections.map(\.dataset)), Set(DashboardDataset.allCases))
        XCTAssertEqual(snapshot.sections.first { $0.dataset == .amendments }?.notCollectedBySource, true)
        for section in snapshot.sections where section.dataset.isProvider {
            XCTAssertNotNil(section.unavailableReason); XCTAssertNil(section.rows)
        }
        for section in snapshot.sections where !section.dataset.isProvider && section.dataset != .amendments {
            XCTAssertEqual(section.rowCount, 0)
        }
        var cache = CloudDashboardCache(accountScope: "test-only", sourceID: snapshot.sourceID)
        XCTAssertTrue(try cache.accept(snapshot, accountScope: "test-only", now: now))
    }
    func testAllDatesOrphanSourcesAndRawQuestionnaireReferencesAreRetained() throws {
        let storage = EventStorage.inMemory()
        execute("""
        INSERT INTO sleep_sessions(session_id,session_date,start_utc) VALUES('old','1999-01-01','original');
        INSERT INTO current_session(id,session_date,session_id) VALUES(1,'2099-12-31','new');
        INSERT INTO dose_events(id,event_type,timestamp,session_date,session_id) VALUES('dose','dose1','original','1999-01-01','old');
        INSERT INTO sleep_events(id,event_type,timestamp,session_date,session_id) VALUES('quick','nap_start','original','2099-12-31',NULL);
        INSERT INTO medication_events(id,session_date,medication_id,dose_mg,taken_at_utc) VALUES('independent','1900-01-01','custom',10,'original');
        INSERT INTO pre_sleep_logs(id,created_at_utc,local_offset_minutes,answers_json) VALUES('orphan','original',-240,'{"future":true}');
        INSERT INTO morning_checkins(id,session_id,session_date,timestamp,timing_context_json) VALUES('morning','old','1999-01-01','original','{"daytimeSleepiness":4}');
        INSERT INTO checkin_submissions(id,source_record_id,session_date,checkin_type,questionnaire_version,user_id,submitted_at_utc,local_offset_minutes,responses_json)
        VALUES('outcome','old','1999-01-01','night_outcome','night_outcome.v1','local','original',0,'{"future":[],"answers":{"sleepiness":3}}');
        INSERT INTO inventory_snapshots(id,as_of_utc,medication_name) VALUES('inventory','original','custom');
        """, storage)
        let before = sqlite3_total_changes(storage.db)
        let snapshot = try storage.dashboardSnapshot(sourceID: "test", sequence: 1, capturedAt: now)
        XCTAssertEqual(try rows(.sessions, snapshot).count, 2)
        for dataset: DashboardDataset in [.doseEvents, .quickLogs, .medicationEntries, .preSleep, .morning, .normalizedAnswers, .inventory] {
            XCTAssertEqual(try rows(dataset, snapshot).count, 1)
        }
        let daytime = try rows(.daytimeDiary, snapshot)
        XCTAssertEqual(daytime.count, 2) // Morning source plus night-outcome source; never two measured observations.
        let reviewed = try rows(.reviewedSleepWindows, snapshot)
        XCTAssertEqual(reviewed.count, 1)
        XCTAssertEqual(try columns(reviewed[0])["responses_json"]?["text"] as? String,
                       "{\"future\":[],\"answers\":{\"sleepiness\":3}}")
        XCTAssertEqual(try columns(rows(.medicationEntries, snapshot)[0])["session_id"]?["type"] as? String, "null")
        XCTAssertEqual(sqlite3_total_changes(storage.db), before)
        XCTAssertEqual(sqlite3_get_autocommit(storage.db), 1)
    }
    func testExactSQLiteTypesAndUnknownColumnsSurviveWithoutGenericNumberConversion() throws {
        let storage = EventStorage.inMemory()
        execute("""
        ALTER TABLE sleep_events ADD COLUMN future_integer;
        ALTER TABLE sleep_events ADD COLUMN future_real;
        ALTER TABLE sleep_events ADD COLUMN future_blob;
        INSERT INTO sleep_events(id,event_type,timestamp,session_date,notes,future_integer,future_real,future_blob)
        VALUES('typed','unknown','original','2000-01-01','',9223372036854775807,1.25,X'00FF');
        """, storage)
        let snapshot = try storage.dashboardSnapshot(sourceID: "test", sequence: 1, capturedAt: now)
        let values = try columns(rows(.quickLogs, snapshot)[0])
        XCTAssertEqual(values["future_integer"]?["type"] as? String, "integer")
        XCTAssertEqual((values["future_integer"]?["integer"] as? NSNumber)?.int64Value, Int64.max)
        XCTAssertEqual(values["future_real"]?["real"] as? Double, 1.25)
        XCTAssertEqual(values["future_blob"]?["blobBase64"] as? String, "AP8=")
        XCTAssertEqual(values["notes"]?["text"] as? String, "")
        XCTAssertEqual(values["session_id"]?["type"] as? String, "null")
    }
    func testNoNightPresetPayloadRemainsByteExactAndUnknownTimeAbsent() throws {
        let storage = EventStorage.inMemory()
        let component = try MedicationPresetComponent(id: UUID(), form: .tablet,
            strengthMilligrams: Decimal(string: "1.12345678901234567890123456789")!, unitCount: 1)
        let preset = try MedicationPresetRevision(presetID: UUID(), revisionID: UUID(), supersedesRevisionID: nil,
            labelName: "Synthetic", ingredient: "Synthetic", releaseProfile: .unknown, components: [component],
            instructions: "Synthetic", schedule: .asNeeded, effectiveFrom: now, effectiveUntil: nil, recordedAt: now)
        let actual = try ConfirmedMedicationAdministration(id: UUID(), preset: preset, actualComponents: [component],
            occurredAt: nil, precision: .unknown, timeZoneIdentifier: nil, utcOffsetSeconds: nil, confirmedAt: now, recordedAt: now)
        _ = try storage.saveMedicationPresetRevision(preset)
        _ = try storage.saveConfirmedMedicationAdministration(actual)
        let snapshot = try storage.dashboardSnapshot(sourceID: "test", sequence: 1, capturedAt: now)
        XCTAssertTrue(try rows(.sessions, snapshot).isEmpty)
        let fields = try columns(rows(.administrations, snapshot)[0])
        XCTAssertEqual(fields["payload"]?["text"] as? String, try MedicationPresetExportSnapshot.encode(actual))
        XCTAssertEqual(fields["occurred_at_utc"]?["type"] as? String, "null")
        XCTAssertEqual(try rows(.presetVersions, snapshot).count, 1)
    }
    func testMissingTableMalformedTextAndNestedTransactionFailWithoutMutation() throws {
        let storage = EventStorage.inMemory()
        execute("BEGIN IMMEDIATE", storage)
        XCTAssertThrowsError(try storage.dashboardSnapshot(sourceID: "test", sequence: 1, capturedAt: now))
        XCTAssertEqual(sqlite3_get_autocommit(storage.db), 0)
        execute("ROLLBACK", storage)
        execute("INSERT INTO sleep_events(id,event_type,timestamp,session_date,notes) VALUES('bad','x','t','d',CAST(X'FF' AS TEXT))", storage)
        XCTAssertThrowsError(try storage.dashboardSnapshot(sourceID: "test", sequence: 1, capturedAt: now))
        XCTAssertEqual(sqlite3_get_autocommit(storage.db), 1)
        execute("DELETE FROM sleep_events; DROP TABLE inventory_snapshots", storage)
        XCTAssertThrowsError(try storage.dashboardSnapshot(sourceID: "test", sequence: 1, capturedAt: now))
        XCTAssertEqual(sqlite3_get_autocommit(storage.db), 1)
    }
    func testConcurrentCommitCannotTearAcrossDatasets() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("snapshot.sqlite").path
        let storage = EventStorage(dbPath: path)
        execute("PRAGMA journal_mode=WAL", storage)
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &connection), SQLITE_OK)
        let writer = try XCTUnwrap(connection)
        defer { sqlite3_close(writer) }
        let probe = DashboardConcurrentWriter(db: writer)
        sqlite3_trace_v2(storage.db, UInt32(SQLITE_TRACE_STMT), { _, context, statement, _ in
            guard let context, let statement,
                  let sql = sqlite3_sql(OpaquePointer(statement)),
                  String(cString: sql).contains("FROM dose_events") else { return 0 }
            Unmanaged<DashboardConcurrentWriter>.fromOpaque(context).takeUnretainedValue().writeOnce()
            return 0
        }, Unmanaged.passUnretained(probe).toOpaque())
        defer { sqlite3_trace_v2(storage.db, 0, nil, nil) }
        let first = try storage.dashboardSnapshot(sourceID: "test", sequence: 1, capturedAt: now)
        XCTAssertEqual(probe.result, SQLITE_OK)
        XCTAssertTrue(try rows(.quickLogs, first).isEmpty)
        XCTAssertTrue(try rows(.inventory, first).isEmpty)
        let next = try storage.dashboardSnapshot(sourceID: "test", sequence: 2, capturedAt: now)
        XCTAssertEqual(try rows(.quickLogs, next).count, 1)
        XCTAssertEqual(try rows(.inventory, next).count, 1)
    }
    func testSymptomAuditCacheWorkScheduleAndSupplyRemainDistinctSourceEvidence() throws {
        let storage = EventStorage.inMemory()
        execute("""
        INSERT INTO symptom_events(id,session_date,phase,source,kind,noticed_at,app_version,created_at)
        VALUES('event','1999-01-01','day','synthetic','pain','original','synthetic','original');
        INSERT INTO symptom_locations(id,event_id,body_side,body_region_id,anatomy_layer,precision,confidence)
        VALUES('location','event','left','arm','surface','region','reported');
        INSERT INTO body_map_points(id,location_id,map_id,normalized_x,normalized_y,body_view)
        VALUES('point','location','original-map',0.125,0.875,'front');
        INSERT INTO symptom_command_log(idempotency_key,command_type,source,status,created_event_id,created_at)
        VALUES('command','create','synthetic','complete','event','original');
        INSERT INTO symptom_summaries(session_date,symptom_count,sleep_disruption_count,still_present_count,summary_hash,rebuilt_at)
        VALUES('1999-01-01',99,0,0,'original-cache-hash','original');
        INSERT INTO work_wake_schedule(id,payload,updated_at) VALUES(1,'{"future":true}','original');
        INSERT INTO supply_state(id,payload) VALUES(1,'{"exact":"0.12345678901234567890123456789"}');
        """, storage)
        let before = sqlite3_total_changes(storage.db)
        let snapshot = try storage.dashboardSnapshot(sourceID: "test", sequence: 1, capturedAt: now)
        let evidence = try rows(.symptoms, snapshot)
        XCTAssertEqual(Set(evidence.compactMap { $0["sourceTable"] as? String }),
            Set(["symptom_events", "symptom_locations", "body_map_points", "symptom_command_log", "symptom_summaries"]))
        let cached = try XCTUnwrap(evidence.first { $0["sourceTable"] as? String == "symptom_summaries" })
        XCTAssertEqual((try columns(cached)["symptom_count"]?["integer"] as? NSNumber)?.intValue, 99)
        let point = try XCTUnwrap(evidence.first { $0["sourceTable"] as? String == "body_map_points" })
        XCTAssertEqual(try columns(point)["location_id"]?["text"] as? String, "location")
        XCTAssertEqual(try columns(point)["normalized_x"]?["real"] as? Double, 0.125)
        XCTAssertEqual(try columns(rows(.workSchedule, snapshot)[0])["payload"]?["text"] as? String, "{\"future\":true}")
        let supply = try rows(.inventory, snapshot)
        XCTAssertEqual(supply.count, 1)
        XCTAssertEqual(supply[0]["sourceTable"] as? String, "supply_state")
        XCTAssertEqual(try columns(supply[0])["payload"]?["text"] as? String,
            "{\"exact\":\"0.12345678901234567890123456789\"}")
        XCTAssertEqual(sqlite3_total_changes(storage.db), before)
    }
}
