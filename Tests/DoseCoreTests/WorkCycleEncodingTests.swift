import XCTest
@testable import DoseCore

final class WorkCycleEncodingTests: XCTestCase {
    func testGroupingHasOneMeaningAndBoundaryReferenceIsInclusive() {
        let row = WorkCycleObservation(sleepID: "a", sleepDate: "2026-09-29", phase: .between, position: "Between 1 and 2", blockID: "b", value: 300, intervalMinutes: 150)
        XCTAssertEqual(row.groupLabel(.none), "All observations")
        XCTAssertEqual(row.groupLabel(.workPhase), "Between shifts")
        XCTAssertEqual(row.groupSymbol(.workPhase), "square")
        XCTAssertEqual(row.groupSymbol(.spacingReference), "circle")
        XCTAssertEqual(row.groupLabel(.spacingReference), "Within reference")
        var upper = row; upper.intervalMinutes = 240
        XCTAssertEqual(upper.groupLabel(.spacingReference), "Within reference")
        upper.intervalMinutes = 241
        XCTAssertEqual(upper.groupLabel(.spacingReference), "Longer than reference")
        upper.intervalMinutes = 149
        XCTAssertEqual(upper.groupLabel(.spacingReference), "Shorter than reference")
        upper.intervalMinutes = nil
        XCTAssertEqual(upper.groupLabel(.spacingReference), "Interval unavailable")
    }
    func testEmptyComparisonStillExportsSnapshotDefinition() {
        let csv = WorkCycleSummary.csv([], metric: "Apple main sleep", basis: .confirmed, range: "28 days", revision: UUID(), asOf: Date(timeIntervalSince1970: 100), grouping: .workPhase)
        XCTAssertTrue(csv.contains("comparison_metadata")); XCTAssertTrue(csv.contains("28 days"))
        XCTAssertTrue(csv.contains("Built-in spacing reference; not a prescription."))
    }
    func testExportPreservesSelectedGroupingAndIndependentInterval() {
        let row = WorkCycleObservation(sleepID: "a", sleepDate: "2026-09-29", phase: .off, position: "Later off", blockID: "b", value: nil, intervalMinutes: 201)
        let csv = WorkCycleSummary.csv([row], metric: "Apple main sleep", basis: .planned, range: "28 days", revision: UUID(), asOf: Date(timeIntervalSince1970: 100), grouping: .workPhase, phaseFilter: "off", positionFilter: "All", matrixEncoding: "Value intensity")
        XCTAssertTrue(csv.contains("interval_minutes"))
        XCTAssertTrue(csv.contains("workPhase"))
        XCTAssertTrue(csv.contains("Value intensity"))
        XCTAssertTrue(csv.contains("201.0"))
        XCTAssertTrue(csv.contains("Built-in spacing reference; not a prescription."))
    }
}
