import XCTest
@testable import DoseTapStudio

final class StudioDoseTimingSummaryTests: XCTestCase {
    func testMissingAndInvalidPairsAreUnavailableNotZero() {
        let summary = StudioDoseTimingSummary(intervalSeconds: [nil, -1, .nan, .infinity])
        XCTAssertEqual(summary.pairCount, 0)
        XCTAssertNil(summary.inWindowPercent)
        XCTAssertNil(summary.averageMinutes)
        XCTAssertNil(DoseTapAnalytics.empty.adherenceRate30d)
        XCTAssertNil(DoseTapAnalytics.empty.averageWindow30d)
        XCTAssertEqual(DoseTapAnalytics.empty.adherenceStatusText, "No recorded pairs in the last 30 days")
        XCTAssertEqual(DoseTapAnalytics.empty.windowStatusText, "No recorded pairs in the last 30 days")
    }

    func testOnlyValidPairsContributeAndEndpointsUseSeconds() {
        let summary = StudioDoseTimingSummary(intervalSeconds: [nil, -1, 8999.999, 9000, 14400, 14400.001])
        XCTAssertEqual(summary.pairCount, 4)
        XCTAssertEqual(summary.inWindowPercent, 50)
        XCTAssertEqual(summary.averageMinutes!, 195, accuracy: 0.000001)
    }

    func testNonpositivePairsRequireReview() {
        let summary = StudioDoseTimingSummary(intervalSeconds: [nil, 0, -60, 10800])
        XCTAssertEqual(summary.pairCount, 1)
        XCTAssertEqual(summary.inWindowPercent, 100)
        XCTAssertEqual(summary.averageMinutes, 180)
    }
}
