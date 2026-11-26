import XCTest
@testable import DoseCore

/// Activate as a test target source for the authorized RED checkpoint; no implementation yet.
final class WorkCycleEligibilityDraftTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private func observation() -> WorkCycleObservation {
        .init(sleepID: "session:exact", sleepDate: "2026-09-22", phase: .after,
              position: "First post-block main sleep", blockID: "block:one", value: nil,
              detail: "PRIVATE OVERRIDE NOTE", isOverride: true, stratumID: "regimen:one")
    }
    private func evidence(end: Date?, boundaryIssue: String? = nil) -> WorkCycleMetricEvidence {
        .init(metricID: "main_sleep", source: "apple_health", definitionVersion: "primary_episode_boundary_v2",
              metric: .init(value: 60, state: .available, reason: "recorded_total", unit: "minutes"),
              start: start, end: end, boundaryIssue: boundaryIssue)
    }
    func testFutureEndpointIsWithheldWithoutAnExactPeriodAndRawValueSurvives() {
        let asOf = start.addingTimeInterval(1800)
        let row = observation().applying(evidence(end: start.addingTimeInterval(3600)), includePartial: false, asOf: asOf)
        XCTAssertNil(row.value)
        XCTAssertEqual(row.metricEvidence?.metric.value, 60)
        XCTAssertEqual(row.metricEvidence?.metric.state, .available)
        XCTAssertEqual(row.contributionReason, "metric_bounds_after_capture")
        XCTAssertEqual(row.contributionState, .needsReview)
    }
    func testEndpointAtCaptureIsAllowedButNonfiniteCaptureIsRejected() {
        let end = start.addingTimeInterval(3600)
        XCTAssertEqual(observation().applying(evidence(end: end), includePartial: false, asOf: end).value, 60)
        let invalid = observation().applying(evidence(end: end), includePartial: false,
            asOf: Date(timeIntervalSince1970: .infinity))
        XCTAssertNil(invalid.value); XCTAssertEqual(invalid.contributionReason, "invalid_capture_time")
    }
    func testExplicitInvalidBoundaryIsDifferentFromMissingChronologicalBoundary() {
        let asOf = start.addingTimeInterval(7200)
        let missing = observation().applying(evidence(end: nil), includePartial: false, asOf: asOf)
        XCTAssertEqual(missing.value, 60, "An original endpoint can be unavailable while the reported chronological total remains available")
        let invalid = observation().applying(evidence(end: nil, boundaryIssue: "inconsistent_recorded_sleep_bounds"),
            includePartial: false, asOf: asOf)
        XCTAssertNil(invalid.value)
        XCTAssertEqual(invalid.contributionReason, "inconsistent_recorded_sleep_bounds")
        XCTAssertEqual(invalid.contributionState, .needsReview)
        XCTAssertEqual(WorkCycleComparison(observations: [invalid]).selectedPeriod.first?.needsReviewCount, 1)
        XCTAssertEqual(invalid.metricEvidence?.metric.value, 60)
    }
    func testExactPeriodStillRequiresBothEndpointsAndExcludesEndBoundary() throws {
        let end = start.addingTimeInterval(3600), asOf = start.addingTimeInterval(7200)
        let period = try PhysicianReportPeriod.resolve(.custom(start: start, endExclusive: end),
            ledger: .init(), asOf: asOf, timeZone: .gmt)
        let missing = observation().applying(evidence(end: nil), includePartial: true, period: period, asOf: asOf)
        XCTAssertNil(missing.value); XCTAssertEqual(missing.contributionReason, "metric_bounds_unavailable")
        let boundary = observation().applying(evidence(end: end), includePartial: true, period: period, asOf: asOf)
        XCTAssertNil(boundary.value); XCTAssertEqual(boundary.contributionReason, "metric_bounds_outside_selected_period")
    }
    private var exportContext: WorkCycleExportContext {
        .init(selectedSource: "apple_health", selectedDefinition: "main_sleep:primary_episode_boundary_v2",
              timeZoneIdentifier: "America/New_York", periodStart: start, periodEndExclusive: start.addingTimeInterval(7200),
              dosePatternFilter: "confirmed_single", contextStratumFilter: "regimen:one", includePartialMetrics: true,
              selectedObservationID: "session:exact", visualization: "Summaries", monthlySummaries: true)
    }
    private func export(_ rows: [WorkCycleObservation]) throws -> [[String]] {
        try ReportCSV.rows(WorkCycleSummary.csv(rows, metric: "Main sleep", basis: .confirmed, range: "6 calendar months",
            revision: nil, asOf: start.addingTimeInterval(7200), grouping: .workPhase,
            phaseFilter: "after", positionFilter: "First post-block main sleep", matrixEncoding: "Value intensity",
            exportContext: exportContext))
    }
    private func field(_ table: [[String]], _ name: String, row: Int = 1) throws -> String {
        table[row][try XCTUnwrap(table[0].firstIndex(of: name))]
    }
    func testEmptyExportRetainsExactViewPolicyAndExplicitlyMissingContextRevision() throws {
        let table = try export([])
        XCTAssertEqual(try field(table, "row_type"), "comparison_metadata")
        XCTAssertEqual(try field(table, "context_revision"), "")
        XCTAssertEqual(try field(table, "context_revision_state"), "unavailable")
        XCTAssertEqual(try field(table, "selected_source"), "apple_health")
        XCTAssertEqual(try field(table, "selected_definition"), "main_sleep:primary_episode_boundary_v2")
        XCTAssertEqual(try field(table, "selected_timezone"), "America/New_York")
        XCTAssertEqual(try field(table, "selected_period_start_utc"), ISO8601DateFormatter().string(from: start))
        XCTAssertEqual(try field(table, "selected_period_end_exclusive_utc"), ISO8601DateFormatter().string(from: start.addingTimeInterval(7200)))
        XCTAssertEqual(try field(table, "dose_pattern_filter"), "confirmed_single")
        XCTAssertEqual(try field(table, "context_stratum_filter"), "regimen:one")
        XCTAssertEqual(try field(table, "include_partial_metrics"), "true")
        XCTAssertEqual(try field(table, "selected_observation_id"), "session:exact")
        XCTAssertEqual(try field(table, "visualization"), "Summaries")
        XCTAssertEqual(try field(table, "summary_period"), "calendar_month")
        XCTAssertEqual(try field(table, "eligible_observations"), "0")
    }
    func testPopulatedExportPreservesRawEvidenceAndNeverIncludesOverrideFreeText() throws {
        let row = observation().applying(evidence(end: start.addingTimeInterval(3600)), includePartial: false,
            asOf: start.addingTimeInterval(1800))
        let table = try export([row])
        XCTAssertEqual(try field(table, "sleep_id"), "session:exact")
        XCTAssertEqual(try field(table, "is_override"), "true")
        XCTAssertEqual(try field(table, "override_reason"), "")
        XCTAssertEqual(try field(table, "detail"), "")
        XCTAssertEqual(try field(table, "raw_metric_value"), "60.0")
        XCTAssertEqual(try field(table, "value_minutes"), "")
        XCTAssertEqual(try field(table, "contribution_reason"), "metric_bounds_after_capture")
        XCTAssertEqual(try field(table, "selected_source"), "apple_health")
        XCTAssertFalse(table.joined().contains("PRIVATE OVERRIDE NOTE"))
    }
}
