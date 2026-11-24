import XCTest
import SwiftUI
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
    func testPanPreservesSpanAndClampsAtFullBounds() {
        XCTAssertEqual(SleepIntervalChartScale.panCenter(range: 100...200, bounds: 0...300, translation: 50, length: 100), 100)
        XCTAssertEqual(SleepIntervalChartScale.panCenter(range: 100...200, bounds: 0...300, translation: -50, length: 100), 200)
        XCTAssertEqual(SleepIntervalChartScale.panCenter(range: 100...200, bounds: 0...300, translation: 1000, length: 100), 50)
        XCTAssertEqual(SleepIntervalChartScale.panCenter(range: 100...200, bounds: 0...300, translation: -1000, length: 100), 250)
        XCTAssertEqual(SleepIntervalChartScale.panCenter(range: 100...200, bounds: 0...300, translation: 50, length: 100, inverted: true), 200)
    }
    func testPanRejectsInvalidGeometryAndTranslation() {
        for size in [0.0, -1, .infinity, .nan] {
            XCTAssertEqual(SleepIntervalChartScale.panCenter(range: 100...200, bounds: 0...300, translation: 50, length: size), 150)
        }
        XCTAssertEqual(SleepIntervalChartScale.panCenter(range: 100...200, bounds: 0...300, translation: .nan, length: 100), 150)
    }
    func testNearbyUniqueRecordsRemainIndividuallyInspectable() {
        let records = [DosePatternPresentation.PlotPoint(id: "night-a", point: .init(x: 100, y: 100)),
                       DosePatternPresentation.PlotPoint(id: "night-b", point: .init(x: 100, y: 100)),
                       DosePatternPresentation.PlotPoint(id: "night-c", point: .init(x: 180, y: 100))]
        XCTAssertEqual(DosePatternPresentation.candidates(at: .init(x: 100, y: 100), points: records), ["night-a", "night-b"])
    }
    func testFittedRangesStartNearDataAndKeepReference() {
        let f = SleepIntervalChartScale.fitted(intervals: [172, 195, 260], sleeps: [372, 455, 512], hasSingle: false)
        XCTAssertTrue(f.x.contains(150) && f.x.contains(240) && f.x.contains(260))
        XCTAssertGreaterThan(f.x.lowerBound, 100, "No empty run from zero to the first night")
        XCTAssertNil(f.singleColumnX); XCTAssertNil(f.dividerX)
        XCTAssertTrue(f.y.contains(372) && f.y.contains(512))
        XCTAssertGreaterThan(f.y.lowerBound, 300, "Sleep axis no longer starts at zero")
    }
    func testSingleDoseGetsSeparateColumnLeftOfSpacing() throws {
        let f = SleepIntervalChartScale.fitted(intervals: [180], sleeps: [420, 526], hasSingle: true)
        let column = try XCTUnwrap(f.singleColumnX), divider = try XCTUnwrap(f.dividerX)
        XCTAssertLessThan(column, divider); XCTAssertLessThan(divider, f.spacingStart)
        XCTAssertTrue(f.x.contains(column))
        let single = try XCTUnwrap(point(interval: nil, sleep: 526, single: true))
        XCTAssertEqual(SleepIntervalChartScale.plotX(single, fitted: f), column)
        XCTAssertEqual(single.x, 0, "Point model keeps no invented interval")
    }
    func testFittedRangesIgnoreInvalidValuesAndStayFinite() {
        let f = SleepIntervalChartScale.fitted(intervals: [.nan, .infinity, -4], sleeps: [], hasSingle: false)
        XCTAssertTrue(f.x.lowerBound.isFinite && f.x.upperBound.isFinite && f.y.lowerBound.isFinite)
        XCTAssertTrue(f.x.contains(150) && f.x.contains(240))
    }
    func testFittedZoomStaysInsideFittedRange() {
        let f = SleepIntervalChartScale.fitted(intervals: [160, 230], sleeps: [400, 470], hasSingle: true)
        let full = SleepIntervalChartScale.domain(maximum: f.x.upperBound, focus: nil, zoom: 1, minimumSpan: 50, minimum: f.x.lowerBound)
        XCTAssertEqual(full, f.x)
        let zoomed = SleepIntervalChartScale.domain(maximum: f.x.upperBound, focus: f.singleColumnX, zoom: 4, minimumSpan: 50, minimum: f.x.lowerBound)
        XCTAssertGreaterThanOrEqual(zoomed.lowerBound, f.x.lowerBound); XCTAssertTrue(zoomed.contains(f.singleColumnX!))
    }
    func testReadoutUsesDurationsNotRecordIDs() throws {
        XCTAssertEqual(SleepIntervalChartScale.duration(166.4), "2 h 46 m")
        XCTAssertEqual(SleepIntervalChartScale.duration(45), "45 m")
        XCTAssertEqual(SleepIntervalChartScale.hourLabel(420), "7 h")
        let p = try XCTUnwrap(point(interval: 180, sleep: 420))
        XCTAssertFalse(SleepIntervalReadout.context(p).contains(p.id))
        XCTAssertEqual(SleepIntervalReadout.context(p), "Work not reviewed")
    }
    func testNightPaletteKeepsSeriesDistinctByBrightness() {
        let night = DashboardPalette(isNight: true)
        func red(_ c: Color) -> CGFloat { var r: CGFloat = 0; UIColor(c).getRed(&r, green: nil, blue: nil, alpha: nil); return r }
        let inside = red(SleepIntervalChartMarker.spacingColor(interval: 180, palette: night))
        let outside = red(SleepIntervalChartMarker.spacingColor(interval: 100, palette: night))
        XCTAssertGreaterThan(inside - outside, 0.3, "Night Mode keeps mainly the red channel, so series must differ in brightness")
        XCTAssertNotEqual(night.chart(.blue), night.chart(.blue, warmth: 0.3))
    }

}
