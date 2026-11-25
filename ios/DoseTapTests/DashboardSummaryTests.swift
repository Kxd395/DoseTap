import XCTest
@testable import DoseTap

final class DashboardSummaryTests: XCTestCase {
    private func night(_ date: String, _ interval: Double?, sleep: Double? = nil, single: Bool = false) -> DashboardSummaryNight {
        DashboardSummaryNight(date: date, interval: interval,
                              inWindow: interval.map { (150...240).contains($0) }, sleep: sleep, single: single)
    }
    private func tile(_ tiles: [DashboardSummaryTile], _ kind: DashboardSummaryTile.Kind) throws -> DashboardSummaryTile {
        try XCTUnwrap(tiles.first { $0.kind == kind })
    }

    func testMedianHandlesOddEvenEmptyAndNonFinite() {
        XCTAssertEqual(DashboardSummary.median([3, 1, 2]), 2)
        XCTAssertEqual(DashboardSummary.median([4, 1, 3, 2]), 2.5)
        XCTAssertNil(DashboardSummary.median([]))
        XCTAssertEqual(DashboardSummary.median([.nan, 5]), 5)
    }

    func testTilesUseMediansAndCountMissingAsMissing() throws {
        let current = [night("2026-11-01", 160, sleep: 420), night("2026-11-02", 180, sleep: nil),
                       night("2026-11-03", 260, sleep: 480), night("2026-11-04", nil, sleep: 400, single: true)]
        let tiles = DashboardSummary.tiles(current: current, prior: [])
        XCTAssertEqual(tiles.map(\.kind), [.spacing, .inWindow, .sleep, .nights])
        let spacing = try tile(tiles, .spacing)
        XCTAssertEqual(spacing.value, "180 min"); XCTAssertEqual(spacing.detail, "3 dose pairs")
        XCTAssertEqual(spacing.spark, [160, 180, 260]); XCTAssertNil(spacing.change)
        let window = try tile(tiles, .inWindow)
        XCTAssertEqual(window.value, "67%"); XCTAssertEqual(window.detail, "2 of 3 pairs")
        let sleep = try tile(tiles, .sleep)
        XCTAssertEqual(sleep.value, "7 h 00 m"); XCTAssertEqual(sleep.detail, "3 nights with sleep")
        let nights = try tile(tiles, .nights)
        XCTAssertEqual(nights.value, "4"); XCTAssertEqual(nights.detail, "1 single-dose night")
    }

    func testChangeComparesWithPriorPeriodOnlyWhenBothExist() throws {
        let current = [night("2026-11-10", 170, sleep: 450), night("2026-11-11", 190, sleep: 470)]
        let prior = [night("2026-10-10", 150, sleep: 470), night("2026-10-11", 250, sleep: 490), night("2026-10-12", 140)]
        let tiles = DashboardSummary.tiles(current: current, prior: prior)
        XCTAssertEqual(try tile(tiles, .spacing).change, "+30 min vs previous period")
        XCTAssertEqual(try tile(tiles, .inWindow).change, "+67 pts vs previous period")
        XCTAssertEqual(try tile(tiles, .sleep).change, "−20 min vs previous period")
        XCTAssertEqual(try tile(tiles, .nights).change, "−1 nights vs previous period")
        let unchanged = DashboardSummary.tiles(current: current, prior: current)
        XCTAssertEqual(try tile(unchanged, .spacing).change, "No change vs previous period")
    }

    func testEmptyPeriodShowsPlainEmptyValues() throws {
        let tiles = DashboardSummary.tiles(current: [], prior: [])
        XCTAssertEqual(try tile(tiles, .spacing).value, "No pairs")
        XCTAssertEqual(try tile(tiles, .inWindow).value, "—")
        XCTAssertNil(try tile(tiles, .inWindow).share)
        XCTAssertEqual(try tile(tiles, .sleep).value, "No sleep")
        XCTAssertEqual(try tile(tiles, .nights).value, "0")
    }

    func testRollingMedianIsTrailingAndNeedsThreeValues() {
        let result = DashboardSummary.rollingMedian([100, 200, 300, 400, 500], window: 3)
        XCTAssertNil(result[0]); XCTAssertNil(result[1])
        XCTAssertEqual(result[2], 200); XCTAssertEqual(result[3], 300); XCTAssertEqual(result[4], 400)
        XCTAssertEqual(DashboardSummary.rollingMedian(Array(repeating: 180, count: 20)).last ?? nil, 180)
    }
}
