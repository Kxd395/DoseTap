import XCTest
import DoseCore
@testable import DoseTap
final class NapPeriodEligibilityTests: XCTestCase {
    func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    func testPartialBoundaryDateRetainsRecordButExcludesUnplacedEstimate() throws {
        let asOf = date("2026-09-30T12:00:00Z")
        let window = try DashboardReportingRange.week.daytimeWindow(asOf: asOf, timeZone: TimeZone(secondsFromGMT: 0)!)
        var nap = NapEpisode(id: "synthetic", day: "2026-09-30", timeZoneID: "UTC", estimatedSleepMinutes: 30, recordedAt: asOf)
        XCTAssertTrue(NapPeriodEligibility.isVisible(nap, in: window))
        XCTAssertNotNil(NapPeriodEligibility.exclusion(nap, in: window))
        nap.day = "2026-09-29"
        XCTAssertNil(NapPeriodEligibility.exclusion(nap, in: window))
        nap.day = "2026-09-30"; nap.start = asOf.addingTimeInterval(-1800)
        XCTAssertNil(NapPeriodEligibility.exclusion(nap, in: window))
        nap.start = asOf
        XCTAssertNotNil(NapPeriodEligibility.exclusion(nap, in: window))
    }
    func testRecordedTimezoneAndDSTDayBoundsArePreserved() throws {
        let asOf = date("2026-11-02T06:00:00Z")
        let window = try DashboardReportingRange.week.daytimeWindow(asOf: asOf, timeZone: TimeZone(secondsFromGMT: 0)!)
        let nap = NapEpisode(id: "synthetic", day: "2026-11-01", timeZoneID: "America/New_York", estimatedSleepMinutes: 30, recordedAt: asOf)
        let bounds = try XCTUnwrap(NapPeriodEligibility.dayBounds(nap))
        XCTAssertEqual(bounds.1.timeIntervalSince(bounds.0), 25 * 3600); XCTAssertNotEqual(NapPeriodEligibility.stamp(bounds.0, zone: "UTC"), NapPeriodEligibility.stamp(bounds.0, zone: "America/New_York"))
        XCTAssertNil(NapPeriodEligibility.exclusion(nap, in: window))
        let edgeWindow = try DashboardReportingRange.week.daytimeWindow(asOf: date("2026-09-07T12:00:00Z"), timeZone: TimeZone(secondsFromGMT: 0)!)
        let edge = NapEpisode(id: "edge", day: "2026-08-31", timeZoneID: "America/Los_Angeles", estimatedSleepMinutes: 30, recordedAt: asOf)
        XCTAssertTrue(NapPeriodEligibility.isVisible(edge, in: edgeWindow)); XCTAssertNotNil(NapPeriodEligibility.exclusion(edge, in: edgeWindow))
    }
}
