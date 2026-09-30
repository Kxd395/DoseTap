import XCTest
import SQLite3
import DoseCore
@testable import DoseTap

@MainActor
final class DashboardContextAdapterTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_784_000)
    func fixture() -> EventStorage {
        let storage = EventStorage.inMemory()
        XCTAssertEqual(sqlite3_exec(storage.db, """
        INSERT INTO dose_events(id,event_type,timestamp,session_date,session_id) VALUES
        ('a1','dose1','2026-09-29T22:00:00Z','2026-09-29','a'),('a2','dose2','2026-09-30T02:00:00Z','2026-09-29','a'),
        ('b1','dose1','2026-09-29T23:00:00Z','2026-09-29','b');
        INSERT INTO morning_checkins(id,session_id,timestamp,session_date) VALUES
        ('ma','a','2026-09-30T10:00:00Z','2026-09-29'),('mb','b','2026-09-30T11:00:00Z','2026-09-29');
        INSERT INTO checkin_submissions(id,source_record_id,session_id,session_date,checkin_type,questionnaire_version,user_id,submitted_at_utc,local_offset_minutes,responses_json)
        VALUES('morning:ma','ma','a','2026-09-29','morning','morning.v2','synthetic','2026-09-30T10:00:00Z',0,'{}');
        """, nil, nil, nil), SQLITE_OK)
        return storage
    }
    func preset() throws -> MedicationPresetRevision {
        try MedicationPresetRevision(presetID: UUID(), revisionID: UUID(), supersedesRevisionID: nil,
            labelName: "Synthetic label", ingredient: "Synthetic ingredient", releaseProfile: .immediateRelease,
            components: [.init(id: UUID(), form: .tablet, strengthMilligrams: 5, unitCount: 1)], instructions: "Entered label",
            schedule: .scheduled, effectiveFrom: now.addingTimeInterval(-172800), effectiveUntil: nil,
            recordedAt: now.addingTimeInterval(-172800))
    }
    func testExactQuestionnaireVersionAndUnknownLegacyRemainSeparate() throws {
        let storage = fixture()
        let snapshot = try SessionRepository(storage: storage).dashboardContextSnapshot(capturedAt: now)
        let a = try XCTUnwrap(snapshot.sessions.first { $0.sessionID == "a" })
        let b = try XCTUnwrap(snapshot.sessions.first { $0.sessionID == "b" })
        XCTAssertEqual(a.contentObservations.map(\.contentVersion), ["morning.v2"])
        XCTAssertEqual(b.contentObservations.count, 1)
        XCTAssertNil(b.contentObservations.first?.contentVersion)
        XCTAssertEqual(snapshot.timeline.annotations.filter { $0.kind == .questionnaireContent }.count, 2)
        XCTAssertTrue(snapshot.timeline.annotations.allSatisfy { $0.effectiveAt == nil })
        XCTAssertEqual(sqlite3_get_autocommit(storage.db), 1)
    }
    func testMislinkedSameDateVersionIsPreservedButNeverAttachedToAnotherSession() throws {
        let storage = fixture()
        XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE checkin_submissions SET session_id='b' WHERE id='morning:ma'", nil, nil, nil), SQLITE_OK)
        let snapshot = try SessionRepository(storage: storage).dashboardContextSnapshot(capturedAt: now)
        XCTAssertTrue(snapshot.sessions.flatMap(\.contentObservations).allSatisfy { $0.contentVersion == nil })
        XCTAssertEqual(snapshot.timeline.annotations.filter { $0.kind == .questionnaireContent }.count, 3)
        XCTAssertTrue(snapshot.timeline.annotations.contains { $0.sourceRecordIDs == ["checkin_submissions:morning:ma"] })
    }
    func testContextReadFailureCannotBecomeEmptySuccess() throws {
        let storage = fixture()
        XCTAssertEqual(sqlite3_exec(storage.db, "DROP TABLE medication_preset_revisions", nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try SessionRepository(storage: storage).dashboardContextSnapshot(capturedAt: now))
        XCTAssertEqual(sqlite3_get_autocommit(storage.db), 1)
    }
    func testLateMorningSubmissionCannotSupplyNightWindowEnd() throws {
        let storage = fixture(), repo = SessionRepository(storage: storage)
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO checkin_submissions(id,source_record_id,session_id,session_date,checkin_type,questionnaire_version,user_id,submitted_at_utc,local_offset_minutes,responses_json) VALUES('morning:mb','mb','b','2026-09-29','morning','morning.v2','synthetic','2026-09-30T11:00:00Z',0,'{}')", nil, nil, nil), SQLITE_OK)
        let p = try preset()
        try repo.saveMedicationPresetRevision(p)
        let snapshot = try repo.dashboardContextSnapshot(capturedAt: now)
        let model = DashboardAnalyticsModel(sessionRepo: repo)
        let rows = model.identityAggregates(local: snapshot.sessions, health: [:], whoop: [:], contextTimeline: snapshot.timeline)
        XCTAssertEqual(rows.first { $0.sessionID == "a" }?.contextStratum.status, .documentedReference)
        XCTAssertEqual(rows.first { $0.sessionID == "a" }?.contextStratum(for: .whoop).status, .unknown)
        XCTAssertEqual(rows.first { $0.sessionID == "b" }?.contextStratum.status, .unknown)
        XCTAssertNotEqual(rows.first { $0.sessionID == "a" }?.contextStratum.id, rows.first { $0.sessionID == "b" }?.contextStratum.id)
    }
    func testFailedRefreshAndProviderInvalidationDisableContextPublication() async throws {
        let storage = fixture(), access = DashboardProviderAccess()
        let actualRepo = SessionRepository(storage: storage)
        try actualRepo.saveMedicationPresetRevision(preset())
        let model = DashboardAnalyticsModel(now: { self.now }, sessionRepo: actualRepo,
            providerAccess: access)
        await model.performRefresh(days: 30, includeProviders: false)
        XCTAssertTrue(model.contextReadReady)
        XCTAssertNotNil(model.contextTimeline)
        XCTAssertEqual(model.nights.first { $0.sessionID == "a" }?.contextStratum.status, .documentedReference)
        access.invalidate(.health)
        XCTAssertFalse(model.contextReadReady)
        XCTAssertTrue(model.nights.allSatisfy { $0.contextStratum.status == .unknown && $0.contextAnnotations.isEmpty })
        await model.performRefresh(days: 30, includeProviders: false)
        XCTAssertTrue(model.contextReadReady)
        XCTAssertEqual(sqlite3_exec(storage.db, "DROP TABLE medication_preset_revisions", nil, nil, nil), SQLITE_OK)
        await model.performRefresh(days: 30, includeProviders: false)
        XCTAssertFalse(model.contextReadReady)
        XCTAssertNil(model.contextTimeline)
        XCTAssertTrue(model.nights.allSatisfy { $0.contextStratum.status == .unknown && $0.contextAnnotations.isEmpty })
        XCTAssertNotNil(model.errorMessage)
    }

}
