import XCTest
@testable import DoseCore

final class TimeIntervalMathCharacterizationTests: XCTestCase {
    func testMinutesBetweenUsesAbsoluteForwardTimestampsAcrossMidnight() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval((3 * 60 + 58) * 60)

        XCTAssertEqual(TimeIntervalMath.minutesBetween(start: start, end: end), 238)
    }

    func testMinutesBetweenTruncatesPartialPositiveMinutes() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(90.9)

        XCTAssertEqual(TimeIntervalMath.minutesBetween(start: start, end: end), 1)
    }

    func testMinutesBetweenPreservesNonRolloverNegativeValue() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(-60)

        XCTAssertEqual(TimeIntervalMath.minutesBetween(start: start, end: end), -1)
    }

    func testReversedAbsoluteInstantsNeverBecomeNextDayIntervals() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(TimeIntervalMath.minutesBetween(start: start, end: start.addingTimeInterval(-72000)), -1200)
        XCTAssertLessThan(TimeIntervalMath.minutesBetween(start: start, end: start.addingTimeInterval(-1)), 0)
    }

    func testFormatMinutesCharacterizesPositiveZeroAndNegativeOutput() {
        XCTAssertEqual(TimeIntervalMath.formatMinutes(0), "0m")
        XCTAssertEqual(TimeIntervalMath.formatMinutes(59), "59m")
        XCTAssertEqual(TimeIntervalMath.formatMinutes(60), "1h 0m")
        XCTAssertEqual(TimeIntervalMath.formatMinutes(125), "2h 5m")
        XCTAssertEqual(TimeIntervalMath.formatMinutes(-61), "-1h 1m")
    }
}
