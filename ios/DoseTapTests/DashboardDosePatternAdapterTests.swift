import XCTest
import SQLite3
import DoseCore
@testable import DoseTap

@MainActor
final class DashboardDosePatternAdapterTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_800_000)
    func seed(_ storage: EventStorage) {
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_sessions(session_id,session_date,start_utc) VALUES ('a','2026-09-29','2026-09-29T22:00:00Z')", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO dose_events(id,event_type,timestamp,session_date,session_id) VALUES ('d1','dose1','2026-09-29T22:00:00Z','2026-09-29','a')", nil, nil, nil), SQLITE_OK)
    }
    func model(_ storage: EventStorage) -> DashboardAnalyticsModel {
        let queries = DashboardProviderQueries(healthEnabled: { false }, whoopEnabled: { false }, whoopConnected: { false },
            prepareHealth: { .unavailable }, healthHistory: { _ in [] }, whoopHistory: { _, _ in
                .init(summaries: [], sleepRecordCount: 0, recoveryRecordCount: 0, recoveryStatus: .completed)
            })
        return DashboardAnalyticsModel(now: { self.now }, sessionRepo: SessionRepository(storage: storage, clock: { self.now }),
            providerAccess: DashboardProviderAccess(), providerQueries: queries)
    }
    func review(_ row: DashboardNightAggregate, count: Int = 1, plan: Int? = nil) throws -> DashboardDoseReview {
        .init(observationID: row.id, sourceFingerprint: try XCTUnwrap(row.reviewFingerprint), confirmedCount: count,
              historicalPlanCount: plan, secondNotTaken: nil, recordedAt: now, reason: "Reviewed history")
    }
    func testUnreviewedClosedSessionNeverConfirmsCountAndExplicitReviewDoes() async throws {
        let storage = EventStorage.inMemory(); seed(storage); let model = model(storage)
        await model.performRefresh(days: 30, includeProviders: false)
        var row = try XCTUnwrap(model.nights.first)
        row.sessionClosed = true
        XCTAssertEqual(row.dosePattern.pattern, .incomplete)
        XCTAssertFalse(row.dosePattern.countComplete)
        try model.saveDoseHistoryReview(review: review(row, plan: 1), observationID: row.id, expectedRevision: nil)
        await model.refreshAndWait()
        row = try XCTUnwrap(model.nights.first)
        XCTAssertEqual(row.dosePattern.pattern, .singlePlanned)
        XCTAssertEqual(row.dosePattern.interval.state, .notApplicable)
        XCTAssertNil(row.dosePattern.interval.value)
        XCTAssertEqual(storage.fetchDoseEvents(sessionKey: "2026-09-29").count, 1)
    }
    func testCanonicalCorrectionInvalidatesReviewAndStaleSave() async throws {
        let storage = EventStorage.inMemory(); seed(storage); let model = model(storage)
        await model.performRefresh(days: 30, includeProviders: false)
        let row = try XCTUnwrap(model.nights.first), review = try review(row)
        try model.saveDoseHistoryReview(review: review, observationID: row.id, expectedRevision: nil)
        await model.refreshAndWait()
        XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE dose_events SET timestamp='2026-09-29T23:00:00Z' WHERE id='d1'", nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try model.saveDoseHistoryReview(review: review, observationID: row.id, expectedRevision: review.revisionID))
        await model.performRefresh(days: 30, includeProviders: false)
        XCTAssertNil(model.nights.first?.doseReview)
        XCTAssertEqual(model.nights.first?.doseReviewLedger?.revisions.count, 1)
        XCTAssertEqual(model.nights.first?.dosePattern.pattern, .incomplete)
    }
    func testRevisionConflictAndCorruptLedgerFailClosed() async throws {
        let storage = EventStorage.inMemory(); seed(storage); let model = model(storage)
        await model.performRefresh(days: 30, includeProviders: false)
        let row = try XCTUnwrap(model.nights.first), first = try review(row)
        try model.saveDoseHistoryReview(review: first, observationID: row.id, expectedRevision: nil)
        await model.refreshAndWait()
        XCTAssertThrowsError(try model.saveDoseHistoryReview(review: review(row, count: 2), observationID: row.id, expectedRevision: nil))
        let ids = model.nights.map(\.id)
        XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE dashboard_dose_reviews SET payload='invalid'", nil, nil, nil), SQLITE_OK)
        await model.performRefresh(days: 30, includeProviders: false)
        XCTAssertEqual(model.nights.map(\.id), ids)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertThrowsError(try model.saveDoseHistoryReview(review: first, observationID: row.id, expectedRevision: first.revisionID))
    }
    func testCanonicalConflictsAndActiveStateRemainDistinct() async throws {
        let storage = EventStorage.inMemory(); seed(storage); let model = model(storage)
        await model.performRefresh(days: 30, includeProviders: false)
        var row = try XCTUnwrap(model.nights.first)
        row.sessionActive = true
        XCTAssertEqual(row.dosePattern.pattern, .inProgress)
        row.doseEvents.append(.init(id: "extra", eventType: "extra_dose", timestamp: now, sessionDate: row.sessionDate, metadata: nil, sessionId: "a"))
        XCTAssertEqual(row.dosePattern.pattern, .needsReview)
        row.doseEvents.removeLast(); row.identityNeedsReview = true
        XCTAssertEqual(row.dosePattern.pattern, .needsReview)
    }
    func testConfirmedUnknownTimeDoesNotInventInterval() async throws {
        let storage = EventStorage.inMemory(); seed(storage); let model = model(storage)
        await model.performRefresh(days: 30, includeProviders: false)
        let row = try XCTUnwrap(model.nights.first)
        try model.saveDoseHistoryReview(review: review(row, count: 2), observationID: row.id, expectedRevision: nil)
        await model.refreshAndWait()
        XCTAssertEqual(model.nights.first?.dosePattern.pattern, .twoReported)
        XCTAssertEqual(model.nights.first?.dosePattern.reportedCount, 2)
        XCTAssertEqual(model.nights.first?.dosePattern.interval.state, .unavailable)
        XCTAssertNil(model.nights.first?.dosePattern.interval.value)
    }
    func testProviderOnlyReviewRequiresCurrentSnapshotAndCreatesNoMedication() async throws {
        let storage = EventStorage.inMemory(); var failing = false
        let time = now.addingTimeInterval(-86400)
        let summary = HealthKitService.SleepNightSummary(date: time, bedTime: time, sleepOnset: time,
            firstWake: nil, finalWake: time.addingTimeInterval(3600), ttfwMinutes: nil,
            totalSleepMinutes: 60, wakeCount: 0, source: "Synthetic")
        let queries = DashboardProviderQueries(healthEnabled: { true }, whoopEnabled: { false }, whoopConnected: { false },
            prepareHealth: { .ready }, healthHistory: { _ in
                if failing { throw URLError(.timedOut) }; return [summary]
            }, whoopHistory: { _, _ in .init(summaries: [], sleepRecordCount: 0, recoveryRecordCount: 0, recoveryStatus: .completed) })
        let model = DashboardAnalyticsModel(now: { self.now }, sessionRepo: SessionRepository(storage: storage, clock: { self.now }),
            providerAccess: DashboardProviderAccess(), providerQueries: queries)
        await model.performRefresh(days: 30)
        let row = try XCTUnwrap(model.nights.first), first = try review(row, count: 0)
        XCTAssertNil(row.sessionID)
        try model.saveDoseHistoryReview(review: first, observationID: row.id, expectedRevision: nil)
        await model.refreshAndWait()
        XCTAssertEqual(model.nights.first?.dosePattern.pattern, .noneReported)
        XCTAssertTrue(try storage.dashboardLocalSessions().isEmpty)
        failing = true; await model.performRefresh(days: 30)
        XCTAssertThrowsError(try model.saveDoseHistoryReview(review: review(row), observationID: row.id, expectedRevision: first.revisionID))
    }

    func testExplicitReviewCannotEraseSkipOrConflictingDuplicateEvidence() async throws {
        let storage = EventStorage.inMemory(); seed(storage); let model = model(storage)
        await model.performRefresh(days: 30, includeProviders: false)
        var row = try XCTUnwrap(model.nights.first)
        row.doseEvents.append(.init(id: "skip", eventType: "dose2_skipped", timestamp: now, sessionDate: row.sessionDate, metadata: nil, sessionId: "a"))
        var ledger = DashboardDoseReviewLedger()
        try ledger.append(.init(observationID: row.id, sourceFingerprint: try XCTUnwrap(row.reviewFingerprint), confirmedCount: 1,
            historicalPlanCount: nil, secondNotTaken: false, recordedAt: now, reason: "Conflicting report"), expectedRevision: nil, now: now)
        row.doseReviewLedger = ledger
        XCTAssertEqual(row.dosePattern.pattern, .needsReview)
        row.doseEvents.removeLast(); row.doseReviewLedger = nil
        row.doseEvents.append(.init(id: "d1", eventType: "dose1", timestamp: row.doseEvents[0].timestamp,
            sessionDate: row.sessionDate, metadata: "changed", sessionId: "a"))
        XCTAssertEqual(row.dosePattern.pattern, .needsReview)
    }

    func testEmptyLocalDateCorrectionInvalidatesExistingZeroReview() async throws {
        let storage = EventStorage.inMemory(); seed(storage)
        XCTAssertEqual(sqlite3_exec(storage.db, "DELETE FROM dose_events", nil, nil, nil), SQLITE_OK)
        let model = model(storage); await model.performRefresh(days: 30, includeProviders: false)
        let row = try XCTUnwrap(model.nights.first), zero = try review(row, count: 0)
        try model.saveDoseHistoryReview(review: zero, observationID: row.id, expectedRevision: nil)
        await model.refreshAndWait()
        XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE sleep_sessions SET session_date='2026-09-28'", nil, nil, nil), SQLITE_OK)
        await model.performRefresh(days: 30, includeProviders: false)
        XCTAssertEqual(model.nights.first?.id, row.id)
        XCTAssertNil(model.nights.first?.doseReview)
        XCTAssertEqual(model.nights.first?.doseReviewLedger?.revisions.count, 1)
        let corrected = try XCTUnwrap(model.nights.first)
        XCTAssertThrowsError(try model.saveDoseHistoryReview(review: zero, observationID: row.id, expectedRevision: zero.revisionID))
        XCTAssertThrowsError(try storage.saveDashboardDoseReview(zero, sessionDate: corrected.sessionDate,
            expectedRevision: zero.revisionID, now: now, allowDateCorrection: true))
        let unexplained = DashboardDoseReview(observationID: corrected.id, sourceFingerprint: try XCTUnwrap(corrected.reviewFingerprint),
            confirmedCount: 0, historicalPlanCount: nil, secondNotTaken: nil, recordedAt: now, reason: "")
        XCTAssertThrowsError(try model.saveDoseHistoryReview(review: unexplained, observationID: corrected.id, expectedRevision: zero.revisionID))
        let next = try review(corrected, count: 0)
        XCTAssertThrowsError(try model.saveDoseHistoryReview(review: next, observationID: corrected.id, expectedRevision: nil))
        try model.saveDoseHistoryReview(review: next, observationID: corrected.id, expectedRevision: zero.revisionID)
        await model.refreshAndWait()
        XCTAssertEqual(model.nights.first?.doseReview, next)
        XCTAssertEqual(model.nights.first?.doseReviewLedger?.revisions, [zero, next])
    }
    func testWHOOPFetchAndDashboardPreserveScoredZeroAndSubminuteEvidence() throws {
        let model = model(EventStorage.inMemory())
        let cases: [(String?, Int?, Int?, Int?, Double?)] = [
            ("SCORED", 0, 0, 0, 0), ("SCORED", 1_000, 2_000, 3_000, 0.1),
            (nil, 60_000, 0, 0, nil), ("SCORED", 60_000, nil, 0, nil),
            ("SCORED", 60_000, -1, 0, nil)
        ]
        for (state, light, deep, rem, expected) in cases {
            var stages: [String: Any] = [:]
            stages["total_light_sleep_time_milli"] = light
            stages["total_slow_wave_sleep_time_milli"] = deep
            stages["total_rem_sleep_time_milli"] = rem
            var object: [String: Any] = ["id": "zero-or-raw", "start": "2026-09-29T22:00:00Z",
                "end": "2026-09-30T06:00:00Z", "score": ["stage_summary": stages]]
            object["score_state"] = state
            let raw = try WHOOPService.makeAPIDecoder().decode(WHOOPSleep.self,
                from: JSONSerialization.data(withJSONObject: object))
            guard let summary = WHOOPService.makeNightSummaries(sleeps: [raw], recoveries: []).first else {
                XCTFail("Reported stage fields must remain inspectable, including complete scored zero"); continue
            }
            let row = try XCTUnwrap(model.identityAggregates(local: [], health: [:], whoop: ["2026-09-29": summary]).first)
            if let expected { XCTAssertEqual(try XCTUnwrap(row.whoopSleepMinutes), expected, accuracy: 0.000001) }
            else { XCTAssertNil(row.whoopSleepMinutes) }
        }
    }

    func testWHOOPStageTotalExceedingOriginalEpisodeCannotSupplyNumericSleep() throws {
        let model = model(EventStorage.inMemory())
        let json = #"{"id":"inconsistent-night","start":"2026-09-29T22:00:00Z","end":"2026-09-30T06:00:00Z","score_state":"SCORED","score":{"stage_summary":{"total_light_sleep_time_milli":32400000,"total_slow_wave_sleep_time_milli":0,"total_rem_sleep_time_milli":0}}}"#
        let raw = try WHOOPService.makeAPIDecoder().decode(WHOOPSleep.self, from: Data(json.utf8))
        let summary = try XCTUnwrap(WHOOPService.makeNightSummaries(sleeps: [raw], recoveries: []).first)
        XCTAssertEqual(summary.totalSleepMinutes, 540) // Original aggregate remains inspectable.
        XCTAssertNotNil(summary.sleepEvidenceReviewReason)
        let row = try XCTUnwrap(model.identityAggregates(local: [], health: [:], whoop: ["2026-09-29": summary]).first)
        XCTAssertNil(row.whoopSleepMinutes)
    }

    func testSameProviderIDCorrectionsInvalidateCountReview() throws {
        let model = model(EventStorage.inMemory())
        func summary(_ date: Date, _ sleep: Int, inBed: Int = 440) -> WHOOPNightSummary {
            .init(date: date, sleepId: "same-episode", totalSleepMinutes: sleep, remMinutes: 90,
                deepMinutes: 70, lightMinutes: 260, awakeMinutes: 20, inBedMinutes: inBed, disturbanceCount: 2,
                sleepEfficiency: 95, sleepPerformance: nil, sleepConsistency: nil, respiratoryRate: nil,
                sleepNeedBaselineMinutes: nil, sleepNeedDebtMinutes: nil, sleepNeedStrainMinutes: nil,
                sleepNeedNapMinutes: nil, recoveryScore: 60, hrvMs: nil)
        }
        let row = try XCTUnwrap(model.identityAggregates(local: [], health: [:], whoop: ["2026-09-29": summary(now, 420)]).first)
        var ledger = DashboardDoseReviewLedger(); try ledger.append(review(row, count: 0), expectedRevision: nil, now: now)
        for changed in [summary(now.addingTimeInterval(3600), 420), summary(now, 430), summary(now, 420, inBed: 450)] {
            var corrected = try XCTUnwrap(model.identityAggregates(local: [], health: [:], whoop: ["2026-09-29": changed]).first)
            corrected.doseReviewLedger = ledger
            XCTAssertEqual(corrected.id, row.id)
            XCTAssertNotEqual(corrected.reviewFingerprint, row.reviewFingerprint)
            XCTAssertNil(corrected.doseReview)
        }
    }

}
