import XCTest
import DoseCore
@testable import DoseTap

@MainActor
final class ContextMorningOutcomesTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func night(pre: DoseTap.PreSleepLogAnswers? = nil, morning: DoseTap.StoredMorningCheckIn? = nil) -> DashboardNightAggregate {
        var n = DashboardNightAggregate(sessionDate: "2026-09-30", dose1Time: nil, dose2Time: nil,
            dose2Skipped: false, snoozeCount: 0, extraDoseCount: 0, events: [], morningCheckIn: morning,
            preSleepLog: pre.map { .init(id: "p", sessionId: "s", createdAtUtc: "2026-09-30T01:00:00Z", localOffsetMinutes: 0, completionState: "complete", answers: $0) },
            healthSummary: nil, whoopSummary: nil, duplicateClusterCount: 0, napSummary: .init(count: 0, totalMinutes: 0))
        n.sessionID = "s"; n.stableID = "session:s"; return n
    }
    func observation(_ n: DashboardNightAggregate, metric: ContextMorningMetric = .grogginess,
                     context: ContextMorningGrouping = .dayDemand) -> ContextOutcomeObservation {
        ContextMorningProjection.observation(n, metric: metric, grouping: context, source: .appleHealth,
            freshness: .current, work: nil, asOf: now)
    }
    func testReportedDayDemandDoesNotInferFromSchedule() {
        XCTAssertNil(observation(night()).context)
        var n = night(); var diary = NightOutcomeDiary(); diary.dayType = .dayOff; n.outcome = diary
        XCTAssertEqual(observation(n).context, "Reported day off")
    }
    func testCaffeineVolumeAndUnverifiedLegacyMassAreNotMassContext() {
        var a = DoseTap.PreSleepLogAnswers(); var caffeine = CaffeineAmounts(); caffeine.lastVolumeUSFlOz = 12
        a.caffeineAmounts = caffeine; a.caffeineLastAmountMg = 200
        XCTAssertNil(observation(night(pre: a), context: .caffeineMass).context)
        caffeine.lastCaffeineMg = 80; caffeine.source = .labelReported; a.caffeineAmounts = caffeine
        XCTAssertEqual(observation(night(pre: a), context: .caffeineMass).context, "80 mg · label_reported")
        caffeine.source = .estimated; a.caffeineAmounts = caffeine
        XCTAssertNil(observation(night(pre: a), context: .caffeineMass).context)
    }
    func testMorningCategoryAndUnknownAssessmentTimePreserved() {
        let m = DoseTap.StoredMorningCheckIn(id: "m", sessionId: "s", timestamp: now, sessionDate: "2026-09-30", grogginess: "moderate", sleepInertiaDuration: "fiveToFifteen")
        let row = observation(night(morning: m), metric: .sleepInertia)
        XCTAssertEqual(row.category, "fiveToFifteen"); XCTAssertNil(row.value); XCTAssertNil(row.occurredAt)
        XCTAssertTrue(row.reason.contains("saved"))
        XCTAssertEqual(row.state, .needsReview)
        let report = ContextOutcomeComparison(observations: [row], asOf: now, timeZoneID: "UTC", filterDescription: "all", metric: "Inertia", includePartial: true)
        XCTAssertEqual(report.eligibleCount, 0)
    }
    func testMislinkedMorningAnswerIsExcluded() {
        let m = DoseTap.StoredMorningCheckIn(id: "m", sessionId: "other", timestamp: now, sessionDate: "2026-09-30")
        XCTAssertEqual(observation(night(morning: m)).state, .unavailable)
    }
    func testFinalWakeMethodIsNotDose2WakeMethod() {
        var n = night(); var d = NightOutcomeDiary(); d.wakeMethod = .alarm; n.outcome = d
        XCTAssertNil(observation(n, context: .finalWakeMethod).context)
    }
    func testUnresolvedIdentityPreservesRowButExcludesValue() {
        var n = night(); n.identityNeedsReview = true
        XCTAssertEqual(observation(n, metric: .mainSleep).state, .needsReview)
    }
}
