import XCTest
import DoseCore
@testable import DoseTap

final class WorkCycleCategoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private func answer(_ id: String, category: String, state: DashboardMetricState = .available) -> ContextOutcomeObservation {
        .init(id: id, sessionID: id, treatmentDate: "2026-09-21", occurredAt: now,
            context: nil, compatibilityStratum: "documented:one", source: "reviewed_answer_v1",
            unit: "original category", value: nil, category: category, state: state, reason: "source_answer",
            relationship: "Following waking-day answer")
    }
    func testCategoriesRemainCountsWithoutNumericalMidpoints() {
        let rows = [answer("a", category: "Rested"), answer("b", category: "Rested"), answer("c", category: "Not rested")]
        let report = WorkCycleCategoryReport(sourceRows: rows, workRows: [], asOf: now,
            timeZoneID: "UTC", filters: "exact selection", metric: "Feeling rested", basis: .confirmed)
        XCTAssertEqual(report.comparison.eligibleCount, 3)
        XCTAssertEqual(report.comparison.groups.first?.categoryCounts, ["Rested": 2, "Not rested": 1])
        XCTAssertTrue(report.comparison.observations.allSatisfy { $0.value == nil })
        XCTAssertEqual(report.knownBlockCount, 0); XCTAssertEqual(report.unknownWorkCount, 3)
    }
    func testLegacyUnconfirmedCategoryIsRawEvidenceOnly() {
        let report = WorkCycleCategoryReport(sourceRows: [answer("a", category: "3 / 5", state: .needsReview)],
            workRows: [], asOf: now, timeZoneID: "UTC", filters: "exact selection", metric: "Sleep quality", basis: .planned)
        XCTAssertEqual(report.sourceRows.first?.category, "3 / 5")
        XCTAssertEqual(report.comparison.eligibleCount, 0)
        XCTAssertEqual(report.comparison.groups.first?.categoryCounts, [:])
    }
    func testConflictingIdentityRemainsExcludedAndCSVKeepsSelectionMetadata() throws {
        let report = WorkCycleCategoryReport(sourceRows: [answer("a", category: "Rested"), answer("a", category: "Not rested")],
            workRows: [], asOf: now, timeZoneID: "UTC", filters: "exact selection", metric: "Feeling rested", basis: .confirmed)
        XCTAssertEqual(report.comparison.eligibleCount, 0)
        let csv = try XCTUnwrap(report.csv)
        let rows = try ReportCSV.rows(csv)
        XCTAssertEqual(rows.count, 3)
        let eligible = try XCTUnwrap(rows[0].firstIndex(of: "group_eligible")), excluded = try XCTUnwrap(rows[0].firstIndex(of: "group_excluded"))
        XCTAssertTrue(rows.dropFirst().allSatisfy { $0[eligible] == "0" && $0[excluded] == "2" })
        XCTAssertTrue(csv.contains("exact selection")); XCTAssertTrue(csv.contains("confirmed"))
        XCTAssertTrue(rows.allSatisfy { $0.count == rows[0].count })
    }

    func testAmbiguousWorkRowsCannotAssignCategoryToFirstPhaseOrBlock() {
        let work = [WorkCycleObservation(sleepID: "a", sleepDate: "2026-09-21", phase: .entering, position: "Before", blockID: "one", value: 1),
                    WorkCycleObservation(sleepID: "a", sleepDate: "2026-09-21", phase: .off, position: "Off", blockID: "two", value: 1)]
        let report = WorkCycleCategoryReport(sourceRows: [answer("a", category: "Rested")], workRows: work,
            asOf: now, timeZoneID: "UTC", filters: "all", metric: "Rested", basis: .confirmed)
        XCTAssertNil(report.comparison.observations.first?.context)
        XCTAssertEqual(report.knownBlockCount, 0); XCTAssertEqual(report.unknownWorkCount, 1)
    }
    func testCrossGroupConflictingAnswersKeepTheirOwnDenominators() throws {
        let first = answer("a", category: "Rested")
        let second = ContextOutcomeObservation(id: "a", sessionID: "a", treatmentDate: "2026-09-21", occurredAt: now,
            context: nil, compatibilityStratum: "other", source: first.source, unit: first.unit, value: nil, category: "Not rested",
            state: .available, reason: "source", relationship: first.relationship)
        let report = WorkCycleCategoryReport(sourceRows: [first, second, answer("b", category: "Rested")], workRows: [],
            asOf: now, timeZoneID: "UTC", filters: "all", metric: "Rested", basis: .confirmed)
        let rows = try ReportCSV.rows(XCTUnwrap(report.csv)), header = rows[0]
        let eligible = try XCTUnwrap(header.firstIndex(of: "group_eligible")), excluded = try XCTUnwrap(header.firstIndex(of: "group_excluded"))
        XCTAssertEqual(Set(rows.dropFirst().map { [$0[eligible], $0[excluded]] }), Set([["1", "1"], ["0", "1"]]))
    }

}
