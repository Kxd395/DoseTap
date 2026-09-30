import XCTest
@testable import DoseCore

final class PhysicianReportTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func observation(_ id: String, value: Double? = nil, state: PhysicianMetricState = .available,
                     version: String = "v1", serious: Bool = false) -> PhysicianReportObservation {
        .init(id: id, observedAt: now.addingTimeInterval(-3600), metricID: "sleep", value: value,
              state: state, unit: "minutes", source: "Apple Health", definitionVersion: version,
              detail: "=SUM(A1:A2), synthetic\nreport", recordIDs: [id], requiresReview: serious)
    }
    func snapshot(_ values: [PhysicianReportObservation]) throws -> PhysicianReportSnapshot {
        let period = try PhysicianReportPeriod.resolve(.days28, ledger: .init(), asOf: now, timeZone: TimeZone(secondsFromGMT: 0)!)
        return try .init(period: period, observations: values, notes: [], questions: ["Discuss changes"], appVersion: "test", generatedAt: now)
    }
    func testMissingnessVersionsAndAssessedDaysRemainDistinct() throws {
        let report = try snapshot([observation("a", value: 120), observation("b", value: 180),
            observation("c", state: .unavailable), observation("d", state: .notApplicable),
            observation("e", value: 300, version: "v2")])
        XCTAssertEqual(report.summaries.count, 2)
        let first = try XCTUnwrap(report.summaries.first { $0.definitionVersion == "v1" })
        XCTAssertEqual(first.availableCount, 2); XCTAssertEqual(first.eligibleCount, 3)
        XCTAssertEqual(first.assessedDays, 1); XCTAssertEqual(first.median, 150)
        XCTAssertEqual(first.unavailableCount, 1); XCTAssertEqual(first.notApplicableCount, 1)
        XCTAssertEqual(report.monthlySummaries.count, 2)
    }
    func testSeriousAndUnknownReportsStayInAppendixAndCSVIsReversible() throws {
        let report = try snapshot([observation("serious", state: .needsReview, serious: true)])
        XCTAssertEqual(report.observations.count, 1)
        XCTAssertEqual(report.summaries.first?.availableCount, 0)
        let csv = report.detailCSV
        XCTAssertTrue(csv.contains("'\u{200B}=SUM"))
        let rows = try ReportCSV.rows(csv)
        XCTAssertTrue(rows[1].contains("=SUM(A1:A2), synthetic\nreport"))
        XCTAssertEqual(try JSONDecoder().decode(PhysicianReportSnapshot.self, from: report.jsonData()), report)
    }
    func testRejectsDuplicateAndNonfiniteObservations() throws {
        let value = observation("same", value: 1)
        XCTAssertThrowsError(try snapshot([value, value]))
        XCTAssertThrowsError(try snapshot([observation("infinite", value: .infinity)]))
        XCTAssertThrowsError(try snapshot([observation("missing", value: nil)]))
    }
    func testSnapshotDoesNotChangeWhenInputIsCorrected() throws {
        var values = [observation("old", value: 100)]
        let original = try snapshot(values)
        values = [observation("new", value: 200)]
        XCTAssertEqual(original.summaries.first?.median, 100)
        XCTAssertNotEqual(try snapshot(values).id, original.id)
    }
}
