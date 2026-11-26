import XCTest
import DoseCore
@testable import DoseTap

@MainActor
final class WorkBlockRangeTests: XCTestCase {
    func testRefreshFiltersIncomingHistoryBeforeChartAndExport() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-30T20:00:00Z"))
        let window = DashboardReportingRange.month.window(asOf: date, timeZone: TimeZone(secondsFromGMT: 0)!)
        func night(_ key: String) -> DashboardNightAggregate {
            DashboardNightAggregate(sessionDate: key, dose1Time: date, dose2Time: nil, dose2Skipped: false, snoozeCount: 0, extraDoseCount: 0, events: [], morningCheckIn: nil, preSleepLog: nil, healthSummary: nil, whoopSummary: nil, duplicateClusterCount: 0, napSummary: .init(count: 0, totalMinutes: 0))
        }
        let inputs = [night("2026-09-29"), night("2026-05-31"), night("2026-10-01")]
        XCTAssertEqual(DashboardWorkBlockView.scopedNights(inputs, window: window).map(\.sessionDate), ["2026-09-29"])
        XCTAssertTrue(DashboardWorkBlockView.scopedNights(inputs, window: nil).isEmpty)
    }
}
