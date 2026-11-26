import XCTest
import DoseCore
@testable import DoseTap

@MainActor
final class WHOOPSleepReviewProjectionTests: XCTestCase {
    private func row(milliseconds: Int, scored: Bool = true) throws -> DashboardNightAggregate {
        var object: [String: Any] = ["id": "review-projection-night", "start": "2026-09-29T22:00:00Z",
            "end": "2026-09-30T06:00:00Z", "score": ["stage_summary": [
                "total_light_sleep_time_milli": milliseconds, "total_slow_wave_sleep_time_milli": 0,
                "total_rem_sleep_time_milli": 0]]]
        if scored { object["score_state"] = "SCORED" }
        let raw = try WHOOPService.makeAPIDecoder().decode(WHOOPSleep.self,
            from: JSONSerialization.data(withJSONObject: object))
        let model = DashboardAnalyticsModel(sessionRepo: SessionRepository(storage: EventStorage.inMemory()))
        return try XCTUnwrap(model.identityAggregates(local: [], health: [:], whoop: ["2026-09-29": raw.toNightSummary()]).first)
    }
    func testInconsistentRawWHOOPSleepRequiresReviewAndNeverEntersSummary() throws {
        let night = try row(milliseconds: 32_400_000)
        let reason = try XCTUnwrap(night.whoopSummary?.sleepEvidenceReviewReason)
        XCTAssertEqual(night.whoopSummary?.totalSleepMinutes, 540)
        for freshness in [DashboardSleepMetricProjection.Freshness.current, .stale, .unavailable] {
            let projection = DosePatternPresentation.sleepProjection(night, source: .whoop, outcome: .mainSleep, freshness: freshness)
            XCTAssertEqual(projection.metric.state, .needsReview); XCTAssertEqual(projection.metric.reason, reason)
            XCTAssertEqual(projection.freshness, freshness); XCTAssertEqual(projection.source, .whoop)
            XCTAssertNil(projection.metric.value); XCTAssertNil(projection.summaryValue(includePartial: true))
        }
        XCTAssertEqual(night.whoopSummary?.totalSleepMinutes, 540)
        let apple = DosePatternPresentation.sleepProjection(night, source: .appleHealth, outcome: .mainSleep)
        XCTAssertEqual(apple.metric.state, .unavailable); XCTAssertNil(apple.metric.value)
    }
    func testExplicitScoredZeroAndLegacyMissingScoreRemainDifferent() throws {
        let zero = try row(milliseconds: 0)
        let observed = DosePatternPresentation.sleepProjection(zero, source: .whoop, outcome: .mainSleep)
        XCTAssertEqual(observed.metric.state, .available); XCTAssertEqual(observed.metric.value, 0)
        let legacy = try row(milliseconds: 25_200_000, scored: false)
        XCTAssertEqual(legacy.whoopSummary?.totalSleepMinutes, 420)
        XCTAssertNil(legacy.whoopSummary?.sleepEvidenceReviewReason)
        let unavailable = DosePatternPresentation.sleepProjection(legacy, source: .whoop, outcome: .mainSleep)
        XCTAssertEqual(unavailable.metric.state, .unavailable); XCTAssertNil(unavailable.metric.value)
    }
    func testMainSleepReviewDoesNotOverridePostDoseApplicability() throws {
        let provider = try row(milliseconds: 32_400_000)
        let first = Date(timeIntervalSince1970: 1_790_720_000), second = first.addingTimeInterval(180 * 60)
        func local(secondTaken: Bool) -> DashboardNightAggregate {
            var night = DashboardNightAggregate(sessionDate: provider.sessionDate, dose1Time: first,
                dose2Time: secondTaken ? second : nil, dose2Skipped: false, snoozeCount: 0, extraDoseCount: 0,
                events: [], morningCheckIn: nil, preSleepLog: nil, healthSummary: nil, whoopSummary: provider.whoopSummary,
                duplicateClusterCount: 0, napSummary: .init(count: 0, totalMinutes: 0))
            night.sessionID = "local-dose-session"; night.stableID = "session:local-dose-session"
            night.doseEvents = [.init(id: "first", eventType: "dose1", timestamp: first, sessionDate: night.sessionDate, sessionId: night.sessionID)]
            if secondTaken { night.doseEvents.append(.init(id: "second", eventType: "dose2", timestamp: second, sessionDate: night.sessionDate, sessionId: night.sessionID)) }
            return night
        }
        var night = local(secondTaken: true)
        let unsupported = DosePatternPresentation.sleepProjection(night, source: .whoop, outcome: .postDose2)
        XCTAssertEqual(unsupported.metric.state, .unavailable)
        XCTAssertEqual(unsupported.metric.reason, "whoop_post_dose_intervals_unavailable")
        XCTAssertNil(unsupported.metric.value)
        night = local(secondTaken: false)
        let fingerprint = try XCTUnwrap(night.reviewFingerprint)
        var ledger = DashboardDoseReviewLedger()
        try ledger.append(.init(observationID: night.id, sourceFingerprint: fingerprint, confirmedCount: 1,
            historicalPlanCount: 1, secondNotTaken: nil, recordedAt: first, reason: "Complete reported single-dose count"),
            expectedRevision: nil, now: second)
        night.doseReviewLedger = ledger
        let notApplicable = DosePatternPresentation.sleepProjection(night, source: .whoop, outcome: .postDose2)
        XCTAssertEqual(notApplicable.metric.state, .notApplicable)
        XCTAssertEqual(notApplicable.metric.reason, "no_second_administration")
    }
}
