import XCTest
@testable import DoseCore

final class ContextOutcomeComparisonTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func row(_ id: String, value: Double? = 20, context: String? = "Work", stratum: String? = "v1",
             category: String? = nil, state: DashboardMetricState = .available, time: Date? = nil) -> ContextOutcomeObservation {
        .init(id: id, sessionID: id, treatmentDate: "2026-09-30", occurredAt: time,
              context: context, compatibilityStratum: stratum, source: "Diary", unit: category == nil ? "minutes" : "category",
              value: value, category: category, state: state, reason: "recorded", relationship: "Following waking day")
    }
    func report(_ rows: [ContextOutcomeObservation], partial: Bool = false) -> ContextOutcomeComparison {
        .init(observations: rows, asOf: now, timeZoneID: "America/New_York", filterDescription: "Selected sessions",
              metric: "Duration", includePartial: partial)
    }
    func testMedianAndSpreadAreComputedWithinCompatibleGroups() {
        let r = report([row("a", value: 10), row("b", value: 30), row("c", value: 50, stratum: "v2")])
        XCTAssertEqual(r.groups.count, 2)
        let group = r.groups.first { $0.observations.count == 2 }!
        XCTAssertEqual(group.summary.median, 20)
        XCTAssertEqual(group.summary.lowerQuartile, 15)
        XCTAssertEqual(group.summary.upperQuartile, 25)
    }
    func testUnknownContextsRemainVisibleAndUnknownCompatibilityDoesNotPool() {
        let r = report([row("a", context: nil, stratum: nil), row("b", context: nil, stratum: nil)])
        XCTAssertEqual(r.unknownContextCount, 2)
        XCTAssertEqual(r.groups.count, 2)
    }
    func testMissingIsNotZeroAndZeroIsUsable() {
        let r = report([row("a", value: nil, state: .unavailable), row("b", value: 0)])
        XCTAssertEqual(r.eligibleCount, 1)
        XCTAssertEqual(r.excludedCount, 1)
        XCTAssertEqual(r.groups.first?.summary.median, 0)
    }
    func testPartialEvidenceRequiresExplicitInclusion() {
        let rows = [row("a", value: 5, state: .partial)]
        XCTAssertEqual(report(rows).eligibleCount, 0)
        XCTAssertEqual(report(rows, partial: true).eligibleCount, 1)
    }
    func testCategoriesRemainCategories() {
        let r = report([row("a", value: nil, category: "Moderate"), row("b", value: nil, category: "Moderate")])
        XCTAssertEqual(r.groups.first?.categoryCounts["Moderate"], 2)
        XCTAssertNil(r.groups.first?.summary.median)
    }
    func testIdenticalDuplicatesCollapseAndConflictIsRetainedForReview() {
        let a = row("a")
        XCTAssertEqual(report([a, a]).observations.count, 1)
        let r = report([a, row("a", value: 30)])
        XCTAssertEqual(r.eligibleCount, 0)
        XCTAssertEqual(r.conflictingIDs, ["a"])
        XCTAssertEqual(r.observations.count, 2)
    }
    func testInvalidAndFutureEvidenceExcludedButMissingTimeNotInvented() {
        let r = report([row("a", value: .nan), row("b", value: -1), row("c", time: now.addingTimeInterval(1)), row("d")])
        XCTAssertEqual(r.eligibleCount, 1)
        XCTAssertNil(r.eligible.first?.occurredAt)
    }
    func testContradictoryCategoryAndNumberExcluded() {
        XCTAssertEqual(report([row("a", value: 3, category: "Moderate")]).eligibleCount, 0)
    }
    func testDSTObservationTimesRemainAbsoluteAndUnchanged() {
        let first = Date(timeIntervalSince1970: 1_762_061_400)
        let second = first.addingTimeInterval(3600)
        let r = report([row("a", time: first), row("b", time: second)])
        XCTAssertEqual(r.eligible[1].occurredAt!.timeIntervalSince(r.eligible[0].occurredAt!), 3600)
    }
    func testEmptyExportRetainsReportContract() {
        let csv = report([]).csv
        XCTAssertTrue(csv.contains("context-outcomes-v1"))
        XCTAssertTrue(csv.contains("Selected sessions"))
    }
    func testCSVNeutralizesSpreadsheetFormulaText() {
        let r = report([row("a", context: "=1+1")])
        XCTAssertTrue(r.csv.contains("'=1+1"))
    }
    func testExportPreservesContextQuotesMissingnessAndVersion() {
        let r = report([row("a", value: nil, context: "Work, \"night\"", state: .unavailable)])
        let csv = r.csv
        XCTAssertTrue(csv.contains("context-outcomes-v1"))
        XCTAssertTrue(csv.contains("America/New_York"))
        XCTAssertTrue(csv.contains("unavailable"))
        XCTAssertTrue(csv.contains("Following waking day"))
        XCTAssertTrue(csv.contains("\"Work, \"\"night\"\"\""))
    }
}
