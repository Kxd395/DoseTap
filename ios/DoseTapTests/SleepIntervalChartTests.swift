import XCTest
@testable import DoseTap

final class SleepIntervalChartTests: XCTestCase {
    func point(interval: Double?, sleep: Double?, single: Bool = false) -> SleepIntervalChartPoint? {
        .init(id: "exact-id", date: "2026-09-29", interval: interval, sleep: sleep,
              single: single, work: .unknown, source: "Apple Health")
    }
    func testSingleHasZeroCategoryButNoInventedInterval() throws {
        let p = try XCTUnwrap(point(interval: nil, sleep: 415, single: true))
        XCTAssertEqual(p.x, 0); XCTAssertNil(p.interval); XCTAssertEqual(p.sleep, 415)
        XCTAssertTrue(p.label.contains("Single dose")); XCTAssertTrue(p.label.contains("415"))
    }
    func testUnknownCountMissingAndInvalidValuesRemainUnplotted() {
        XCTAssertNil(point(interval: nil, sleep: 415))
        XCTAssertNil(point(interval: 180, sleep: nil))
        XCTAssertNil(point(interval: .infinity, sleep: 415))
        XCTAssertNil(point(interval: 180, sleep: .nan))
        XCTAssertNil(point(interval: -1, sleep: 415))
        XCTAssertNil(point(interval: 180, sleep: -1))
        XCTAssertNotNil(point(interval: 180, sleep: 0))
    }
    func testMeasuredIntervalKeepsExactFractionalValue() throws {
        let p = try XCTUnwrap(point(interval: 166.468767, sleep: 415.25))
        XCTAssertEqual(p.interval, 166.468767); XCTAssertEqual(p.x, 166.468767)
        XCTAssertEqual(p.sleep, 415.25); XCTAssertEqual(p.id, "exact-id")
    }
    func testQuarterAndIntermediateGridLinesArePresentAndBounded() {
        let ticks = SleepIntervalChartScale.ticks(in: 0...100, step: 12.5)
        for x in [12.5, 25, 50, 75, 87.5] { XCTAssertTrue(ticks.contains(x)) }
        XCTAssertLessThanOrEqual(SleepIntervalChartScale.ticks(in: 0...1e9, step: 12.5).count, 121)
    }
    func testExtremeDomainRemainsFinite() {
        let domain = SleepIntervalChartScale.domain(maximum: .greatestFiniteMagnitude, focus: .infinity, zoom: .nan, minimumSpan: 50)
        XCTAssertTrue(domain.lowerBound.isFinite); XCTAssertTrue(domain.upperBound.isFinite)
    }
    func testZoomRetainsSelectedFocusAndZeroHasPlotPadding() {
        let full = SleepIntervalChartScale.domain(maximum: 300, focus: nil, zoom: 1, minimumSpan: 50)
        XCTAssertLessThan(full.lowerBound, 0)
        let zoom = SleepIntervalChartScale.domain(maximum: 300, focus: 0, zoom: 4, minimumSpan: 50)
        XCTAssertTrue(zoom.contains(0)); XCTAssertLessThan(zoom.upperBound-zoom.lowerBound, full.upperBound-full.lowerBound)
        let edge = SleepIntervalChartScale.domain(maximum: 300, focus: 300, zoom: 8, minimumSpan: 50)
        XCTAssertTrue(edge.contains(300)); XCTAssertLessThanOrEqual(edge.upperBound, full.upperBound)
    }
}
