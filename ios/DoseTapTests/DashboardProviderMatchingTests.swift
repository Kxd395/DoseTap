import XCTest
import SQLite3
import DoseCore
@testable import DoseTap

@MainActor
final class DashboardProviderMatchingTests: XCTestCase {
    private func store() -> EventStorage {
        let value = EventStorage.inMemory()
        XCTAssertEqual(sqlite3_exec(value.db, "INSERT INTO dose_events(id,event_type,timestamp,session_date,session_id) VALUES('d1','dose1','2026-09-29T22:00:00Z','2026-09-29','a'),('d2','dose2','2026-09-30T02:00:00Z','2026-09-29','b')", nil, nil, nil), SQLITE_OK)
        return value
    }
    private var summary: HealthKitService.SleepNightSummary {
        let time = Date(timeIntervalSince1970: 1_790_721_600)
        return .init(date: time, bedTime: time, sleepOnset: time, firstWake: nil,
            finalWake: time.addingTimeInterval(3600), ttfwMinutes: nil, totalSleepMinutes: 60, wakeCount: 0, source: "Test")
    }
    private func match(_ storage: EventStorage, sessionID: String = "a", episode: String? = nil) throws -> DashboardProviderAssociation {
        let session = try XCTUnwrap(storage.dashboardLocalSessions().first { $0.sessionID == sessionID })
        return .init(episodeID: episode ?? summary.id, provider: "apple-health", sessionID: sessionID,
            sessionDate: session.sessionDate, sessionFingerprint: session.fingerprint,
            episodeFingerprint: summary.associationFingerprint, revision: UUID().uuidString)
    }
    func testExplicitMatchAttachesOnlyNamedSessionAndEditsInvalidate() throws {
        let storage = store(), model = DashboardAnalyticsModel(sessionRepo: SessionRepository(storage: store()))
        let value = try match(storage)
        try storage.saveDashboardAssociation(value, expectedRevision: nil, now: Date())
        let snapshot = try storage.dashboardIdentitySnapshot()
        let rows = model.identityAggregates(local: snapshot.sessions, health: ["2026-09-29": summary], whoop: [:], associations: snapshot.associations)
        XCTAssertEqual(rows.count, 2)
        XCTAssertNotNil(rows.first { $0.sessionID == "a" }?.healthSummary)
        XCTAssertNil(rows.first { $0.sessionID == "b" }?.healthSummary)
        XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE dose_events SET timestamp='2026-09-29T23:00:00Z' WHERE id='d1'", nil, nil, nil), SQLITE_OK)
        let edited = try storage.dashboardIdentitySnapshot()
        let next = model.identityAggregates(local: edited.sessions, health: ["2026-09-29": summary], whoop: [:], associations: edited.associations)
        XCTAssertEqual(next.count, 3)
        XCTAssertTrue(next.filter { $0.sessionID != nil }.allSatisfy { $0.healthSummary == nil })
        XCTAssertThrowsError(try storage.saveDashboardAssociation(value, expectedRevision: value.revision, now: Date()))
    }
    func testRevisionConflictAndSecondEpisodeCannotOverwrite() throws {
        let storage = store(), value = try match(storage)
        try storage.saveDashboardAssociation(value, expectedRevision: nil, now: Date())
        XCTAssertThrowsError(try storage.saveDashboardAssociation(value, expectedRevision: nil, now: Date()))
        XCTAssertThrowsError(try storage.saveDashboardAssociation(match(storage, episode: "apple-health:other"), expectedRevision: nil, now: Date()))
        XCTAssertEqual(try storage.dashboardAssociations().count, 1)
        XCTAssertEqual(sqlite3_get_autocommit(storage.db), 1)
    }
    func testUnlinkAndClearLeaveMedicationUntouched() throws {
        let storage = store()
        let value = try match(storage)
        try storage.saveDashboardAssociation(value, expectedRevision: nil, now: Date())
        let actualRepo = SessionRepository(storage: storage)
        try actualRepo.removeDashboardAssociation(value)
        XCTAssertTrue(try storage.dashboardAssociations().isEmpty)
        XCTAssertEqual(try storage.dashboardLocalSessions().flatMap(\.doses).count, 2)
        try storage.saveDashboardAssociation(value, expectedRevision: nil, now: Date())
        storage.clearAllData()
        XCTAssertTrue(try storage.dashboardAssociations().isEmpty)
    }
    func testProviderCorrectionRetainsSeparateSleep() throws {
        let storage = store(), model = DashboardAnalyticsModel(sessionRepo: SessionRepository(storage: store()))
        let value = try match(storage); var corrected = summary
        corrected.recordedIntervals = [.init(start: summary.date, end: summary.date.addingTimeInterval(1800), asleep: true)]
        let rows = model.identityAggregates(local: try storage.dashboardLocalSessions(), health: ["2026-09-29": corrected], whoop: [:], associations: [value])
        XCTAssertEqual(rows.count, 3)
        XCTAssertNotNil(rows.first { $0.sessionID == nil }?.healthSummary)
    }
    func testExplicitReassignmentRequiresCurrentRevisionAndPreservesSingleOwner() throws {
        let storage = store(), first = try match(storage)
        try storage.saveDashboardAssociation(first, expectedRevision: nil, now: Date())
        let next = try match(storage, sessionID: "b")
        try storage.saveDashboardAssociation(next, expectedRevision: first.revision, now: Date())
        let saved = try storage.dashboardAssociations()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.sessionID, "b")
        XCTAssertEqual(saved.first?.revision, next.revision)
        XCTAssertThrowsError(try storage.saveDashboardAssociation(first, expectedRevision: first.revision, now: Date()))
    }
    func testDateDeletionRemovesAssociation() throws {
        let storage = store(), value = try match(storage)
        try storage.saveDashboardAssociation(value, expectedRevision: nil, now: Date())
        storage.deleteSession(sessionDate: "2026-09-29")
        XCTAssertTrue(try storage.dashboardAssociations().isEmpty)
    }
    func testModelRequiresFreshProviderAndUnchangedPublishedLocalEvidence() async throws {
        let storage = store(), access = DashboardProviderAccess()
        let asOf = try XCTUnwrap(AppFormatters.parseISO8601Flexible("2026-09-30T12:00:00Z"))
        let evening = try XCTUnwrap(AppFormatters.parseISO8601Flexible("2026-09-29T18:00:00Z"))
        let health = HealthKitService.SleepNightSummary(date: evening, bedTime: evening, sleepOnset: evening,
            firstWake: nil, finalWake: evening.addingTimeInterval(3600), ttfwMinutes: nil,
            totalSleepMinutes: 60, wakeCount: 0, source: "Test")
        var enabled = true
        let queries = DashboardProviderQueries(healthEnabled: { enabled }, whoopEnabled: { false }, whoopConnected: { false },
            prepareHealth: { .ready }, healthHistory: { _ in [health] },
            whoopHistory: { _, _ in .init(summaries: [], sleepRecordCount: 0, recoveryRecordCount: 0, recoveryStatus: .completed) })
        let model = DashboardAnalyticsModel(now: { asOf }, sessionRepo: SessionRepository(storage: storage),
            timeZone: { TimeZone(secondsFromGMT: 0)! }, providerAccess: access, providerQueries: queries)
        await model.performRefresh(days: 30)
        let source = try XCTUnwrap(model.nights.first { $0.healthSummary != nil })
        enabled = false
        XCTAssertThrowsError(try model.saveProviderAssociation(providerRowID: source.id, sessionID: "a"))
        enabled = true; model.isLoading = true
        XCTAssertThrowsError(try model.saveProviderAssociation(providerRowID: source.id, sessionID: "a"))
        model.isLoading = false
        try model.saveProviderAssociation(providerRowID: source.id, sessionID: "a")
        await model.refreshAndWait()
        XCTAssertNotNil(model.nights.first { $0.sessionID == "a" }?.healthSummary)
        XCTAssertEqual(try storage.dashboardAssociations().count, 1)
    }
    func testSingleDateCandidateIsNotAnAutomaticAssociation() throws {
        let storage = store(), model = DashboardAnalyticsModel(sessionRepo: SessionRepository(storage: store()))
        let local = try storage.dashboardLocalSessions().filter { $0.sessionID == "a" }
        let rows = model.identityAggregates(local: local, health: ["2026-09-29": summary], whoop: [:])
        XCTAssertEqual(rows.count, 2)
        XCTAssertNil(rows.first { $0.sessionID == "a" }?.healthSummary)
    }
}
