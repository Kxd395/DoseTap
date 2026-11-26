import XCTest
@testable import DoseCore

final class WorkCycleComparisonTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private func row(_ id: String, date: String = "2026-09-22", phase: WorkPhase = .after,
                     position: String = "First post-block main sleep", stratum: String? = "regimen-a",
                     state: DashboardMetricState = .available, value: Double? = 300) -> WorkCycleObservation {
        let observation = WorkCycleObservation(sleepID: id, sleepDate: date, phase: phase, position: position,
            blockID: "block-a", value: nil, stratumID: stratum, stratumLabel: stratum)
        let evidence = WorkCycleMetricEvidence(metricID: "main-sleep", source: "apple-health", definitionVersion: "v1",
            metric: .init(value: value, state: state, reason: "fixture", unit: "minutes"),
            start: start, end: start.addingTimeInterval(3600))
        return observation.applying(evidence, includePartial: false)
    }
    func testMonthAndSelectedWindowKeepPositionRegimenAndSourceSeparate() {
        var otherSource = row("whoop")
        otherSource = otherSource.applying(.init(metricID: "main-sleep", source: "whoop", definitionVersion: "v1",
            metric: .init(value: 301, state: .available, reason: "fixture", unit: "minutes"), start: start, end: start.addingTimeInterval(3600)), includePartial: false)
        let rows = [row("a"), row("b", date: "2026-08-22"), row("c", phase: .off, position: "Later off-block"),
                    row("d", stratum: "regimen-b"), otherSource]
        let result = WorkCycleComparison(observations: rows)
        XCTAssertEqual(result.selectedPeriod.count, 4)
        XCTAssertEqual(result.monthly.count, 5)
        XCTAssertEqual(result.selectedPeriod.first { $0.observationIDs.contains("a") }?.summary.availableCount, 2)
        XCTAssertEqual(result.selectedPeriod.first { $0.observationIDs.contains("a") }?.summary.distinctBlockCount, 1)
    }
    func testUnknownContextIsNeverPooled() {
        let result = WorkCycleComparison(observations: [row("a", stratum: nil), row("b", stratum: nil)])
        XCTAssertEqual(result.selectedPeriod.count, 2)
    }
    func testPartialAndNotApplicableHaveIndependentDenominators() throws {
        let partial = row("partial", state: .partial, value: 120)
        let unavailable = row("missing", state: .unavailable, value: nil)
        let notApplicable = row("none", state: .notApplicable, value: nil)
        let group = try XCTUnwrap(WorkCycleComparison(observations: [row("full"), partial, unavailable, notApplicable]).selectedPeriod.first)
        XCTAssertEqual(group.summary.availableCount, 1)
        XCTAssertEqual(group.partialCount, 1); XCTAssertEqual(group.partialIncludedCount, 0)
        XCTAssertEqual(group.notApplicableCount, 1); XCTAssertEqual(group.eligibleCount, 3)
        XCTAssertEqual(group.summary.missingCount, 2)
        let included = partial.applying(try XCTUnwrap(partial.metricEvidence), includePartial: true)
        let includedGroup = try XCTUnwrap(WorkCycleComparison(observations: [included]).selectedPeriod.first)
        XCTAssertEqual(includedGroup.partialIncludedCount, 1); XCTAssertEqual(includedGroup.summary.availableCount, 1)
    }
    func testExactPeriodRejectsMissingOrBoundaryEndpointsWithoutErasingRawEvidence() throws {
        let period = try PhysicianReportPeriod.resolve(.custom(start: start, endExclusive: start.addingTimeInterval(3600)), ledger: .init(), asOf: start.addingTimeInterval(7200), timeZone: TimeZone(secondsFromGMT: 0)!)
        let source = row("boundary")
        let excluded = source.applying(try XCTUnwrap(source.metricEvidence), includePartial: true, period: period)
        XCTAssertNil(excluded.value); XCTAssertEqual(excluded.metricEvidence?.metric.value, 300)
        XCTAssertEqual(excluded.contributionReason, "metric_bounds_outside_selected_period")
        var evidence = try XCTUnwrap(source.metricEvidence); evidence.end = nil
        let missing = source.applying(evidence, includePartial: true, period: period)
        XCTAssertNil(missing.value); XCTAssertEqual(missing.contributionReason, "metric_bounds_unavailable")
    }
    func testDuplicateStableIDsCannotInflateSummary() {
        let source = row("same")
        let result = WorkCycleComparison(observations: [source, source])
        XCTAssertEqual(result.selectedPeriod.first?.summary.availableCount, 1)
        XCTAssertEqual(result.duplicateIDs, ["same"])
    }
    func testConflictingDuplicateIDIsRetainedButExcluded() {
        let result = WorkCycleComparison(observations: [row("same"), row("same", value: 400)])
        XCTAssertEqual(result.conflictingIDs, ["same"])
        XCTAssertEqual(result.selectedPeriod.first?.summary.availableCount, 0)
    }
    func testMeasuredZeroRemainsEligibleAndNegativeDurationIsExcluded() {
        XCTAssertEqual(row("zero", value: 0).value, 0)
        let negative = row("negative", value: -1)
        XCTAssertNil(negative.value); XCTAssertEqual(negative.contributionReason, "invalid_duration_value")
    }
    func testCSVKeepsPartialRawValueSeparateFromExcludedContribution() throws {
        let partial = row("partial", state: .partial, value: 120)
        let parsed = try ReportCSV.rows(WorkCycleSummary.csv([partial], metric: "Main sleep", basis: .planned,
            range: "6 months", revision: UUID(), asOf: start))
        func field(_ name: String) throws -> String { parsed[1][try XCTUnwrap(parsed[0].firstIndex(of: name))] }
        XCTAssertEqual(try field("value_minutes"), "")
        XCTAssertEqual(try field("value_state"), "partial")
        XCTAssertEqual(try field("raw_metric_value"), "120.0")
        XCTAssertEqual(try field("contribution_reason"), "partial_excluded")
        XCTAssertEqual(try field("metric_source"), "apple-health")
    }
    func testMalformedProvidedBoundsCannotContributeWithoutPeriodFilter() throws {
        let source = row("bad")
        var evidence = try XCTUnwrap(source.metricEvidence); evidence.end = .distantPast
        XCTAssertNil(source.applying(evidence, includePartial: false).value)
        evidence.end = Date(timeIntervalSince1970: .infinity)
        XCTAssertNil(source.applying(evidence, includePartial: false).value)
    }
    func testInvalidDateCannotEnterMonthlyGroup() {
        let result = WorkCycleComparison(observations: [row("invalid", date: "2026-02-30")])
        XCTAssertTrue(result.monthly.isEmpty); XCTAssertEqual(result.unplacedIDs, ["invalid"])
    }
}
