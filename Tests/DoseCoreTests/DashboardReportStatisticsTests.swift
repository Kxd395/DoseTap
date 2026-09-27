import XCTest
@testable import DoseCore

final class DashboardReportStatisticsTests: XCTestCase {
    private func day(_ date: String, _ value: Double?, _ state: DashboardDoseDayState = .paired) -> DashboardReportDoseDay {
        DashboardReportDoseDay(treatmentDate: date, intervalMinutes: value, state: state, dose1At: nil, dose2At: nil)
    }
    func testMissingSkippedAndConflictsNeverBecomeZero() {
        let stats = DashboardReportStatistics(days: [day("2026-09-01", 120), day("2026-09-02", 180),
            day("2026-09-03", nil, .missing), day("2026-09-04", nil, .skipped), day("2026-09-05", nil, .conflict)])
        XCTAssertEqual(stats.days.count, 5); XCTAssertEqual(stats.values.count, 2)
        XCTAssertEqual(stats.mean, 150); XCTAssertEqual(stats.median, 150)
        XCTAssertEqual(stats.count(.skipped), 1); XCTAssertEqual(stats.count(.missing), 1)
        XCTAssertEqual(stats.count(.conflict), 1)
    }
    func testQuantilesMonthlyDenominatorsAndHistogramBoundaries() {
        let stats = DashboardReportStatistics(days: [day("2026-08-01", 120), day("2026-08-02", 180),
            day("2026-09-01", 240), day("2026-09-02", 300)])
        XCTAssertEqual(stats.median, 210); XCTAssertEqual(stats.lowerQuartile, 165); XCTAssertEqual(stats.upperQuartile, 255)
        XCTAssertEqual(stats.months.map(\.count), [2, 2]); XCTAssertEqual(stats.months.map(\.median), [150, 270])
        XCTAssertEqual(stats.distribution.map(\.count), [0, 0, 1, 1, 1, 1, 0])
        let bounds = DashboardReportStatistics(days: [day("2026-09-01", 59.9), day("2026-09-02", 60), day("2026-09-03", 360), day("2026-09-04", 9999)])
        XCTAssertEqual(bounds.distribution.map(\.count), [1, 1, 0, 0, 0, 0, 2])
    }
    func testEmptyAndSingleObservationAreNotInventedZeros() {
        let empty = DashboardReportStatistics(days: [day("2026-09-01", nil, .missing)])
        XCTAssertNil(empty.mean); XCTAssertNil(empty.median); XCTAssertTrue(empty.months.isEmpty)
        let single = DashboardReportStatistics(days: [day("2026-09-01", 195)])
        XCTAssertEqual(single.lowerQuartile, 195); XCTAssertEqual(single.upperQuartile, 195)
    }
    func testInclusiveRangeUsesCapturedTreatmentNightAcrossRolloverAndDST() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let iso = ISO8601DateFormatter()
        let values = (6...9).map { day("2026-03-0\($0)", 180) }
        let before = try XCTUnwrap(iso.date(from: "2026-03-08T17:59:00-04:00"))
        let after = try XCTUnwrap(iso.date(from: "2026-03-08T18:00:00-04:00"))
        XCTAssertEqual(DashboardReportStatistics.selected(values, count: 2, capturedAt: before, timeZone: zone).map(\.treatmentDate), ["2026-03-06", "2026-03-07"])
        XCTAssertEqual(DashboardReportStatistics.selected(values, count: 2, capturedAt: after, timeZone: zone).map(\.treatmentDate), ["2026-03-07", "2026-03-08"])
        XCTAssertEqual(DashboardReportStatistics.selected(values, count: 0, capturedAt: before, timeZone: zone).map(\.treatmentDate), ["2026-03-06", "2026-03-07"])
        XCTAssertEqual(DashboardReportStatistics.selected(values, count: 0, capturedAt: after, timeZone: zone).map(\.treatmentDate), ["2026-03-06", "2026-03-07", "2026-03-08"])
    }
}
