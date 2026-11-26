import XCTest
import SQLite3
import DoseCore
@testable import DoseTap

@MainActor
final class DashboardSharedSleepProducerTests: XCTestCase {
    let start = ISO8601DateFormatter().date(from: "2026-09-29T22:00:00Z")!
    var now: Date { start.addingTimeInterval(12 * 3600) }
    var packet: DashboardSleepEvidence {
        .init(queryStart: start.addingTimeInterval(-3600), queryEnd: now, completedAt: now,
              timeZoneID: "UTC", samples: [.init(sampleID: "sample", start: start, end: start.addingTimeInterval(3600),
                rawCategory: 1, stage: .asleep, origin: .init(sourceName: "Test Watch", bundleIdentifier: nil))])
    }
    func store() -> EventStorage {
        let storage = EventStorage.inMemory()
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO dose_events(id,event_type,timestamp,session_date,session_id) VALUES('d1','dose1','2026-09-29T21:00:00Z','2026-09-29','a')", nil, nil, nil), SQLITE_OK)
        return storage
    }
    func read(_ storage: EventStorage, evidence: DashboardSleepEvidence? = nil) throws -> [DashboardSharedSleepEpisode] {
        XCTAssertEqual(sqlite3_exec(storage.db, "BEGIN DEFERRED", nil, nil, nil), SQLITE_OK)
        defer { sqlite3_exec(storage.db, "ROLLBACK", nil, nil, nil) }
        return try storage.dashboardSharedSleepEpisodes(evidence: evidence ?? packet, capturedAt: now)
    }
    func associate(_ storage: EventStorage) throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let summary = try XCTUnwrap(HealthKitService.dashboardSleepSummaries(segments: [.init(start: start,
            end: start.addingTimeInterval(3600), stage: .asleep, source: "Test Watch")], days: 2, through: now, calendar: calendar).first)
        let session = try XCTUnwrap(storage.dashboardLocalSessions().first)
        try storage.saveDashboardAssociation(.init(episodeID: summary.id, provider: "apple-health", sessionID: "a",
            sessionDate: "2026-09-29", sessionFingerprint: session.fingerprint,
            episodeFingerprint: summary.associationFingerprint, revision: UUID().uuidString), expectedRevision: nil, now: now)
    }
    func testSnapshotOptInCarriesExactReviewedEpisodeAndOptOutOmitsIt() throws {
        let storage = store(); try associate(storage)
        let repository = SessionRepository(storage: storage, clock: { self.now })
        let local = try repository.dashboardSnapshot(sourceID: "test", sequence: 1)
        XCTAssertNil(local.sleepEpisodes)
        XCTAssertNotNil(local.sections.first { $0.dataset == .appleHealth }?.unavailableReason)
        let shared = try repository.dashboardSnapshot(sourceID: "test", sequence: 2, sleepEvidence: packet)
        XCTAssertEqual(shared.sleepEpisodes?.first?.sessionID, "a")
        XCTAssertEqual(shared.sleepEpisodes?.first?.completedAt, packet.completedAt)
        XCTAssertNotNil(shared.sections.first { $0.dataset == .whoop }?.unavailableReason)
        var cache = CloudDashboardCache(accountScope: "test", sourceID: "test")
        XCTAssertTrue(try cache.accept(shared, accountScope: "test", now: now))
        let receiver = try DashboardCompanionProjection(snapshot: shared, now: now)
        let night = try XCTUnwrap(receiver.nights.first { $0.id == "session:a" })
        XCTAssertEqual(receiver.episode(for: night)?.episodeID, shared.sleepEpisodes?.first?.episodeID)
        XCTAssertEqual(receiver.sleepMetric(for: night, definition: .mainProviderEpisode).metric.value, 60)
        let encoded = String(decoding: try JSONEncoder().encode(shared), as: UTF8.self)
        XCTAssertFalse(encoded.contains("sessionFingerprint")); XCTAssertFalse(encoded.contains("episodeFingerprint"))
        XCTAssertEqual(sqlite3_get_autocommit(storage.db), 1)
        XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE dose_events SET timestamp='2026-09-29T20:00:00Z' WHERE id='d1'", nil, nil, nil), SQLITE_OK)
        let stale = try repository.dashboardSnapshot(sourceID: "test", sequence: 3, sleepEvidence: packet)
        XCTAssertNil(stale.sleepEpisodes?.first?.sessionID)
        XCTAssertEqual(stale.sleepEpisodes?.count, 1)
    }
    func testRequiresSnapshotTransactionAndNeverDateMatches() throws {
        let storage = store()
        XCTAssertThrowsError(try storage.dashboardSharedSleepEpisodes(evidence: packet, capturedAt: now))
        let rows = try read(storage)
        XCTAssertEqual(rows.count, 1); XCTAssertNil(rows.first?.sessionID)
        XCTAssertEqual(rows.first?.completedAt, packet.completedAt)
    }
    func testReviewedMatchThenLocalCorrectionInvalidates() throws {
        let storage = store(); try associate(storage)
        let bound = try XCTUnwrap(read(storage).first)
        XCTAssertEqual(bound.sessionID, "a"); XCTAssertNotNil(bound.associationRevision)
        XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE dose_events SET timestamp='2026-09-29T20:00:00Z' WHERE id='d1'", nil, nil, nil), SQLITE_OK)
        XCTAssertNil(try read(storage).first?.sessionID)
    }
    func testProviderCorrectionInvalidatesWithoutDroppingRawEpisode() throws {
        let storage = store(); try associate(storage)
        var corrected = packet
        corrected.samples = [.init(sampleID: "sample", start: start, end: start.addingTimeInterval(1800),
            rawCategory: 1, stage: .asleep, origin: .init(sourceName: "Test Watch", bundleIdentifier: nil))]
        let rows = try read(storage, evidence: corrected)
        XCTAssertEqual(rows.count, 1); XCTAssertNil(rows.first?.sessionID)
        XCTAssertEqual(rows.first?.totalSleepMinutes, 30)
    }
    func testMalformedLocalIdentityDoesNotLoseOptedInProviderEvidence() throws {
        let storage = store()
        XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE dose_events SET timestamp='broken' WHERE id='d1'", nil, nil, nil), SQLITE_OK)
        let rows = try read(storage)
        XCTAssertEqual(rows.count, 1); XCTAssertNil(rows.first?.sessionID)
    }
    func testEmptyPacketAndInvalidReceipt() throws {
        let storage = store(); var empty = packet; empty.samples = []
        XCTAssertTrue(try read(storage, evidence: empty).isEmpty)
        var invalid = packet; invalid.completedAt = now.addingTimeInterval(1)
        XCTAssertThrowsError(try read(storage, evidence: invalid))
    }
    func testProviderOnlyReviewRequiresExactCurrentPrivateContext() throws {
        let storage = store()
        let episode = try XCTUnwrap(read(storage).first)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let summary = try XCTUnwrap(HealthKitService.dashboardSleepSummaries(segments: [.init(start: start,
            end: start.addingTimeInterval(3600), stage: .asleep, source: "Test Watch")], days: 2, through: now, calendar: calendar).first)
        let fingerprint = try XCTUnwrap(DashboardDoseReview.observationFingerprint(observationID: episode.episodeID,
            sessionDate: episode.treatmentDate, events: [], providerFingerprint: summary.associationFingerprint))
        let review = DashboardDoseReview(observationID: episode.episodeID, sourceFingerprint: fingerprint,
            confirmedCount: 1, historicalPlanCount: 1, secondNotTaken: nil, recordedAt: now, reason: "Private review note")
        try storage.saveDashboardDoseReview(review, sessionDate: episode.treatmentDate, expectedRevision: nil, now: now)
        let rows = try read(storage)
        XCTAssertEqual(rows.first?.review?.confirmedCount, 1)
        let json = String(decoding: try JSONEncoder().encode(rows), as: UTF8.self)
        XCTAssertFalse(json.contains("Private review note")); XCTAssertFalse(json.contains(fingerprint))
        try associate(storage)
        XCTAssertNil(try read(storage).first?.review)
    }
}
