import XCTest
@testable import DoseCore

final class DashboardSleepMetricProjectionTests: XCTestCase {
    func testProviderEvidenceReviewRetainsReasonAndFreshnessWithoutNumericSummary() throws {
        for freshness in [DashboardSleepMetricProjection.Freshness.current, .stale, .unavailable] {
            for total in [nil, 0, 540] as [Double?] {
                let reason = "WHOOP scored sleep exceeds the original episode interval."
                let projection = DashboardSleepMetricProjection.providerEpisode(totalMinutes: total,
                    source: .whoop, freshness: freshness, evidenceReviewReason: reason)
                XCTAssertEqual(projection.metric.state, .needsReview)
                XCTAssertEqual(projection.metric.reason, reason)
                XCTAssertEqual(projection.source, .whoop); XCTAssertEqual(projection.freshness, freshness)
                XCTAssertEqual(projection.definition, .mainProviderEpisode)
                XCTAssertNil(projection.metric.value); XCTAssertNil(projection.summaryValue(includePartial: true))
                let data = try JSONEncoder().encode(projection)
                XCTAssertEqual(try JSONDecoder().decode(DashboardSleepMetricProjection.self, from: data), projection)
            }
        }
        XCTAssertEqual(DashboardSleepMetricProjection.providerEpisode(totalMinutes: 0, source: .whoop,
            freshness: .current).summaryValue(), 0)
        XCTAssertEqual(DashboardSleepMetricProjection.providerEpisode(totalMinutes: nil, source: .whoop,
            freshness: .current).metric.state, .unavailable)
    }
    let start = Date(timeIntervalSince1970: 1_790_720_000)
    func pattern(second: Bool = true) -> DashboardDosePattern {
        var rows: [DashboardDosePattern.Administration] = [.init(id: "d1", sessionID: "s", slot: 1, occurredAt: start)]
        if second { rows.append(.init(id: "d2", sessionID: "s", slot: 2, occurredAt: start.addingTimeInterval(180 * 60))) }
        return .derive(sessionID: "s", administrations: rows, confirmedCount: second ? 2 : 1,
                       historicalPlanCount: second ? 2 : 1, secondNotTaken: false, sessionOpen: false)
    }
    func estimate(awake: Bool = false, gap: Bool = false) -> PostDoseSleepEstimate? {
        let dose2 = start.addingTimeInterval(180 * 60)
        return .calculate(dose2: dose2, finalWake: dose2.addingTimeInterval(60 * 60),
            intervals: [.init(start: dose2, end: dose2.addingTimeInterval((gap ? 30 : 60) * 60), asleep: !awake)])
    }
    func testPartialMeasurementHasExplicitCoverageAndInclusionPolicy() throws {
        let result = DashboardSleepMetricProjection.afterDose2(pattern: pattern(), estimate: estimate(gap: true), source: .appleHealth,
            freshness: .current, boundaryBasis: .reportedFinalAwakening)
        XCTAssertEqual(result.boundaryBasis, .reportedFinalAwakening)
        XCTAssertEqual(result.metric.state, .partial); XCTAssertEqual(result.metric.value, 30)
        XCTAssertEqual(result.coveredMinutes, 30); XCTAssertEqual(result.intervalMinutes, 60)
        XCTAssertEqual(result.unmeasuredMinutes, 30); XCTAssertNil(result.summaryValue())
        XCTAssertEqual(result.summaryValue(includePartial: true), 30)
        let encoded = try JSONEncoder().encode(result)
        XCTAssertEqual(try JSONDecoder().decode(DashboardSleepMetricProjection.self, from: encoded), result)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: encoded) as? [String: Any])?["unmeasuredMinutes"] as? Double, 30)
    }
    func testObservedAllAwakeIsZeroAndNoDoseIsNotApplicable() {
        let awake = DashboardSleepMetricProjection.afterDose2(pattern: pattern(), estimate: estimate(awake: true), source: .appleHealth,
            freshness: .current, boundaryBasis: .providerLastObservedSleepEnd)
        XCTAssertEqual(awake.metric.state, .available); XCTAssertEqual(awake.summaryValue(), 0)
        let absent = DashboardSleepMetricProjection.afterDose2(pattern: pattern(second: false), estimate: nil, source: .appleHealth, freshness: .current)
        XCTAssertEqual(absent.metric.state, .notApplicable); XCTAssertNil(absent.metric.value)
    }
    func testFreshnessAndSourceDoNotSubstituteObservations() {
        let stale = DashboardSleepMetricProjection.providerEpisode(totalMinutes: 0, source: .appleHealth, freshness: .stale)
        XCTAssertEqual(stale.metric.state, .partial); XCTAssertEqual(stale.metric.value, 0); XCTAssertNil(stale.summaryValue())
        let missing = DashboardSleepMetricProjection.providerEpisode(totalMinutes: 500, source: .appleHealth, freshness: .unavailable)
        XCTAssertEqual(missing.metric.state, .unavailable); XCTAssertNil(missing.metric.value)
        let wrong = DashboardSleepMetricProjection.afterDose2(pattern: pattern(), estimate: estimate(), source: .whoop, freshness: .current)
        XCTAssertEqual(wrong.metric.state, .unavailable); XCTAssertNil(wrong.metric.value)
    }
    func testInvalidProviderTotalsAndUnresolvedDoseTimeRemainDistinct() {
        for invalid in [-1.0, .infinity, .nan] {
            let value = DashboardSleepMetricProjection.providerEpisode(totalMinutes: invalid, source: .appleHealth, freshness: .current)
            XCTAssertEqual(value.metric.state, .needsReview); XCTAssertNil(value.summaryValue(includePartial: true))
        }
        let incomplete = DashboardDosePattern.derive(sessionID: "s", administrations: [
            .init(id: "d1", sessionID: "s", slot: 1, occurredAt: start),
            .init(id: "d2", sessionID: "s", slot: 2, occurredAt: nil)
        ], confirmedCount: 2, historicalPlanCount: 2, secondNotTaken: false, sessionOpen: false)
        let unresolved = DashboardSleepMetricProjection.afterDose2(pattern: incomplete, estimate: estimate(), source: .appleHealth, freshness: .current)
        XCTAssertEqual(unresolved.metric.state, .unavailable); XCTAssertNil(unresolved.metric.value)
        XCTAssertEqual(DashboardSleepMetricProjection.providerEpisode(totalMinutes: 400, source: .appleHealth, freshness: .current).summaryValue(), 400)
    }
    func testNonpositiveExplicitEndpointNeedsReview() {
        let result = DashboardSleepMetricProjection.afterDose2(pattern: pattern(), estimate: nil, source: .appleHealth,
            freshness: .current, boundaryBasis: .reportedFinalAwakening, dose2At: start, endpointAt: start)
        XCTAssertEqual(result.metric.state, .needsReview); XCTAssertNil(result.metric.value)
    }
    func testUnnamedOrMainEpisodeBoundaryCannotAuthorizePostDoseSummary() {
        for basis in [DashboardSleepMetricProjection.BoundaryBasis.unresolved, .providerMainEpisode] {
            let result = DashboardSleepMetricProjection.afterDose2(pattern: pattern(), estimate: estimate(),
                source: .appleHealth, freshness: .current, boundaryBasis: basis)
            XCTAssertEqual(result.metric.state, .needsReview)
            XCTAssertNil(result.summaryValue(includePartial: true))
            XCTAssertEqual(result.coveredMinutes, 60)
        }
    }
    func testReviewedAndPlannedWindowBasesRequireExplicitCoverageAndRemainDistinct() throws {
        let dose2 = start.addingTimeInterval(180 * 60), end = dose2.addingTimeInterval(60 * 60)
        let coverage = try XCTUnwrap(SleepIntervalCoverage.calculate(start: dose2, end: end,
            intervals: [.init(start: dose2, end: end, asleep: true)]))
        for basis in [DashboardSleepMetricProjection.BoundaryBasis.reviewedWindowEnd, .appSessionEnd, .requiredWakeTarget] {
            let bound = DashboardSleepMetricProjection.afterDose2(pattern: pattern(), coverage: coverage,
                source: .appleHealth, freshness: .current, boundaryBasis: basis)
            XCTAssertEqual(bound.metric.state, .available); XCTAssertEqual(bound.summaryValue(), 60)
            XCTAssertEqual(bound.boundaryBasis, basis); XCTAssertEqual(bound.derivationVersion, "dashboard-sleep-metric.v2")
            XCTAssertEqual(try JSONDecoder().decode(DashboardSleepMetricProjection.self, from: JSONEncoder().encode(bound)), bound)
            let unbound = DashboardSleepMetricProjection.afterDose2(pattern: pattern(), estimate: estimate(),
                source: .appleHealth, freshness: .current, boundaryBasis: basis)
            XCTAssertEqual(unbound.metric.state, .needsReview); XCTAssertNil(unbound.summaryValue(includePartial: true))
        }
    }
    func testDecodedLegacyUnnamedWindowCannotEnterSummary() throws {
        let named = DashboardSleepMetricProjection.afterDose2(pattern: pattern(), estimate: estimate(),
            source: .appleHealth, freshness: .current, boundaryBasis: .reportedFinalAwakening)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(named)) as? [String: Any])
        for basis in ["unresolved", "providerMainEpisode"] {
            object["boundaryBasis"] = basis; object["derivationVersion"] = "dashboard-sleep-metric.v1"
            let decoded = try JSONDecoder().decode(DashboardSleepMetricProjection.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertNil(decoded.summaryValue(includePartial: true))
        }
    }
}
