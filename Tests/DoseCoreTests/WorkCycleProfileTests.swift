import XCTest
@testable import DoseCore

final class WorkCycleProfileTests: XCTestCase {
    func testPerMetricMissingnessQuartilesAndDistinctBlocks() {
        let rows = [1.0, 2, 3, 4].enumerated().map { WorkCycleObservation(sleepID: "\($0.offset)", sleepDate: "2026-09-22", phase: .between, position: "Between 1 and 2", blockID: "block", value: $0.element) }
            + [WorkCycleObservation(sleepID: "missing", sleepDate: "2026-09-23", phase: .between, position: "Between 1 and 2", blockID: nil, value: nil)]
        let summary = WorkCycleSummary(observations: rows)
        XCTAssertEqual(summary.availableCount, 4); XCTAssertEqual(summary.missingCount, 1)
        XCTAssertEqual(summary.distinctBlockCount, 1); XCTAssertEqual(summary.unresolvedBlockCount, 1)
        XCTAssertEqual(summary.median, 2.5); XCTAssertEqual(summary.lowerQuartile, 1.75); XCTAssertEqual(summary.upperQuartile, 3.25)
    }
    func testZeroIsObservedAndInvalidValuesExcluded() {
        let rows = [0.0, Double.nan, -.infinity, -1].enumerated().map { WorkCycleObservation(sleepID: "\($0.offset)", sleepDate: "2026-09-22", phase: .unknown, position: "Unknown", blockID: nil, value: $0.element) }
        let summary = WorkCycleSummary(observations: rows)
        XCTAssertEqual(summary.availableCount, 1); XCTAssertEqual(summary.median, 0)
        XCTAssertNil(summary.lowerQuartile); XCTAssertEqual(summary.missingCount, 3)
    }
    func testCSVPreservesUnknownAndEscapesUntrustedText() throws {
        let row = WorkCycleObservation(sleepID: "=FORMULA()", sleepDate: "2026-09-22", phase: .unknown, position: "Unknown", blockID: nil, value: nil)
        let csv = WorkCycleSummary.csv([row], metric: "Apple Health main sleep minutes", basis: .planned, range: "6 calendar months", revision: UUID(), asOf: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(csv.contains("'\u{200B}=FORMULA()"))
        let parsed = try ReportCSV.rows(csv)
        XCTAssertEqual(parsed[1][0], "=FORMULA()")
        XCTAssertEqual(parsed[1][6], "unavailable")
        XCTAssertTrue(csv.contains("Built-in spacing reference; not a prescription."))
    }
}
