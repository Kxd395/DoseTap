import XCTest
import DoseCore
@testable import DoseTap

@MainActor
final class WorkCycleAdapterTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private func model() -> DashboardAnalyticsModel {
        let queries = DashboardProviderQueries(healthEnabled: { false }, whoopEnabled: { false },
            whoopConnected: { false }, prepareHealth: { .unavailable }, healthHistory: { _ in [] },
            whoopHistory: { _, _ in .init(summaries: [], sleepRecordCount: 0, recoveryRecordCount: 0, recoveryStatus: .completed) })
        let now = start.addingTimeInterval(50_000)
        let result = DashboardAnalyticsModel(now: { now }, sessionRepo: SessionRepository(storage: .inMemory()),
            timeZone: { .gmt }, providerAccess: DashboardProviderAccess(), providerQueries: queries)
        result.selectedRange = .all
        result.nights = [night("a"), night("b")]
        result.contextReadReady = true; result.doseReviewReadReady = true
        result.publishWorkInspectionContext(nil, nights: result.nights, asOf: now)
        return result
    }
    private func night(_ id: String) -> DashboardNightAggregate {
        var row = DashboardNightAggregate(sessionDate: "2026-09-21", dose1Time: start,
            dose2Time: start.addingTimeInterval(10800), dose2Skipped: false, snoozeCount: 0, extraDoseCount: 0,
            events: [], morningCheckIn: nil, preSleepLog: nil, healthSummary: nil, whoopSummary: nil,
            duplicateClusterCount: 0, napSummary: .init(count: 0, totalMinutes: 0))
        row.sessionID = id; row.stableID = "session:" + id
        row.doseEvents = [.init(id: id + "-d1", eventType: "dose1", timestamp: start, sessionDate: row.sessionDate, sessionId: id),
                          .init(id: id + "-d2", eventType: "dose2", timestamp: start.addingTimeInterval(10800), sessionDate: row.sessionDate, sessionId: id)]
        return row
    }
    func testReadinessFailureIsNotAnEmptySuccessfulComparison() {
        let value = model(); value.contextReadReady = false
        XCTAssertNil(value.workCycleComparison(metric: .doseInterval))
        XCTAssertNotNil(value.workCycleComparisonIssue(metric: .doseInterval))
        value.contextReadReady = true; value.invalidateWorkInspectionContext()
        XCTAssertNil(value.workCycleComparison(metric: .doseInterval))
    }
    func testValidEmptyFilterIsAnEmptyComparisonAndKeepsSelection() throws {
        let value = model(); value.inspection.workPhaseFilter = .entering
        value.inspection.selectedObservationID = "session:a"
        let comparison = try XCTUnwrap(value.workCycleComparison(metric: .doseInterval))
        XCTAssertTrue(comparison.observations.isEmpty)
        XCTAssertNil(value.workCycleComparisonIssue(metric: .doseInterval))
        XCTAssertEqual(value.inspection.selectedObservationID, "session:a")
    }
    func testAxisDomainRetainsSelectedRangeWhenSharedPhaseFilterHidesRows() throws {
        let value = model(); value.inspection.workPhaseFilter = .entering
        XCTAssertTrue(try XCTUnwrap(value.workCycleComparison(metric: .doseInterval)).observations.isEmpty)
        XCTAssertEqual(try XCTUnwrap(value.workCycleAxisObservations(metric: .doseInterval)).count, 2)
    }
    func testExactIdentitiesAndUnknownContextStaySeparate() throws {
        let value = model()
        let comparison = try XCTUnwrap(value.workCycleComparison(metric: .doseInterval))
        XCTAssertEqual(Set(comparison.observations.map(\.id)), ["session:a", "session:b"])
        XCTAssertEqual(comparison.selectedPeriod.count, 2)
        XCTAssertTrue(comparison.observations.allSatisfy { $0.value == 180 })
    }
    func testExactPeriodWithholdsBoundaryDoseIntervalButRetainsEvidence() throws {
        let value = model()
        let period = try PhysicianReportPeriod.resolve(.custom(start: start, endExclusive: start.addingTimeInterval(10800)),
            ledger: .init(), asOf: value.reportingAsOf, timeZone: .gmt)
        let comparison = try XCTUnwrap(value.workCycleComparison(metric: .doseInterval, period: period))
        XCTAssertTrue(comparison.observations.allSatisfy { $0.value == nil && $0.metricEvidence?.metric.value == 180 })
        XCTAssertTrue(comparison.observations.allSatisfy { $0.contributionReason == "metric_bounds_outside_selected_period" })
    }
    func testExactApplePeriodRequiresConsistentRecordedAsleepBounds() throws {
        let value = model(); value.inspection.includePartialMetrics = true
        var health = HealthKitService.SleepNightSummary(date: start, bedTime: nil, sleepOnset: start,
            firstWake: nil, finalWake: start.addingTimeInterval(3600), ttfwMinutes: nil,
            totalSleepMinutes: 60, wakeCount: 0, source: "Synthetic")
        health.recordedIntervals = [.init(start: start.addingTimeInterval(60), end: start.addingTimeInterval(3600), asleep: true)]
        value.nights[0].healthSummary = health
        let period = try PhysicianReportPeriod.resolve(.custom(start: start, endExclusive: start.addingTimeInterval(7200)),
            ledger: .init(), asOf: value.reportingAsOf, timeZone: .gmt)
        func contribution() throws -> Double? {
            try XCTUnwrap(value.workCycleComparison(metric: .mainSleep, period: period)).observations.first { $0.id == "session:a" }?.value
        }
        XCTAssertNil(try contribution(), "Named and recorded sleep bounds disagree")
        health.recordedIntervals = [.init(start: start, end: start.addingTimeInterval(3600), asleep: true)]
        value.nights[0].healthSummary = health
        XCTAssertEqual(try contribution(), 60)
        health.recordedIntervals = []; value.nights[0].healthSummary = health
        XCTAssertNil(try contribution(), "Missing recorded boundaries cannot produce an exact-period contribution")
    }
    func testAmbiguousDoseIdentityCannotSupplyInterval() throws {
        let value = model(); value.nights[0].identityNeedsReview = true
        let comparison = try XCTUnwrap(value.workCycleComparison(metric: .doseInterval))
        let row = try XCTUnwrap(comparison.observations.first { $0.id == "session:a" })
        XCTAssertNil(row.value); XCTAssertEqual(row.metricEvidence?.metric.state, .needsReview)
    }
}
