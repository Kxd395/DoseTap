import XCTest
@testable import DoseCore

final class DashboardDaytimeWindowTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/New_York")!
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    func testPresetsUseCivilDaysAcrossSpringDSTAndBeforeSixPM() throws {
        let now = date("2026-03-10T12:00:00-04:00")
        for (range, days) in [(DashboardReportingRange.week, 7), (.twoWeeks, 14), (.fourWeeks, 28), (.month, 30), (.quarter, 90)] {
            let window = try range.daytimeWindow(asOf: now, timeZone: zone)
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            XCTAssertEqual(window.start, calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)))
            XCTAssertEqual(window.calendarDayCount, days)
            XCTAssertEqual(window.endExclusive, now)
            XCTAssertEqual(window.asOf, now); XCTAssertEqual(window.timeZone, zone)
            XCTAssertFalse(window.contains(now))
        }
        let week = try DashboardReportingRange.week.daytimeWindow(asOf: now, timeZone: zone)
        XCTAssertEqual(week.start, date("2026-03-04T00:00:00-05:00"))
        XCTAssertEqual(now.timeIntervalSince(try XCTUnwrap(week.start)), 155 * 3600)
        let late = try DashboardReportingRange.week.daytimeWindow(asOf: date("2026-03-10T20:00:00-04:00"), timeZone: zone)
        XCTAssertEqual(late.start, week.start)
    }

    func testCalendarMonthsAreNotFixedDayDurations() throws {
        let now = date("2026-09-30T12:00:00-04:00")
        XCTAssertEqual(try DashboardReportingRange.sixMonths.daytimeWindow(asOf: now, timeZone: zone).start,
                       date("2026-03-30T00:00:00-04:00"))
        XCTAssertEqual(try DashboardReportingRange.year.daytimeWindow(asOf: now, timeZone: zone).start,
                       date("2025-09-30T00:00:00-04:00"))
    }

    func testCustomExactBoundsExcludeMidnightWithoutLosingFullDay() throws {
        let start = date("2026-11-01T00:00:00-04:00"), end = date("2026-11-02T00:00:00-05:00")
        let asOf = date("2026-11-03T12:00:00-05:00")
        let period = try PhysicianReportPeriod.resolve(.custom(start: start, endExclusive: end), ledger: .init(), asOf: asOf, timeZone: zone)
        let window = try DashboardReportingRange.custom.daytimeWindow(asOf: asOf, timeZone: zone, reviewedPeriod: period)
        XCTAssertEqual(window.start, start); XCTAssertEqual(window.endExclusive, end)
        XCTAssertEqual(window.calendarDayCount, 1)
        XCTAssertEqual(end.timeIntervalSince(start), 25 * 3600)
        XCTAssertTrue(window.contains(start)); XCTAssertFalse(window.contains(end))
        XCTAssertFalse(window.isEmpty)
    }

    func testCompletedVisitKeepsExactAfternoonStartAndExcludesAppointments() throws {
        let asOf = date("2026-09-30T12:00:00-04:00"), occurred = date("2026-09-29T15:12:00-04:00")
        var ledger = PhysicianVisitLedger()
        ledger.appointments = [.init(id: UUID(), scheduledAt: asOf.addingTimeInterval(86400), status: .planned)]
        XCTAssertThrowsError(try PhysicianReportPeriod.resolve(.sinceCompletedVisit, ledger: ledger, asOf: asOf, timeZone: zone))
        let visit = try PhysicianVisit(occurredAt: occurred, recordedAt: occurred, now: asOf)
        try ledger.append(visit, now: asOf)
        let period = try PhysicianReportPeriod.resolve(.sinceCompletedVisit, ledger: ledger, asOf: asOf, timeZone: zone)
        let window = try DashboardReportingRange.sinceCompletedVisit.daytimeWindow(asOf: asOf, timeZone: zone, reviewedPeriod: period)
        XCTAssertEqual(window.start, occurred); XCTAssertEqual(window.calendarDayCount, 2)
        XCTAssertFalse(window.contains(occurred.addingTimeInterval(-1)))
        XCTAssertThrowsError(try DashboardReportingRange.custom.daytimeWindow(asOf: asOf, timeZone: zone, reviewedPeriod: period))
    }

    func testAllTimeHasNoInventedStartAndPreservesActualEvidenceInstant() throws {
        let asOf = date("2026-09-30T12:00:00-04:00")
        let unknown = try DashboardReportingRange.all.daytimeWindow(asOf: asOf, timeZone: zone)
        XCTAssertNil(unknown.start); XCTAssertEqual(unknown.calendarDayCount, 0)
        XCTAssertTrue(unknown.isEmpty); XCTAssertFalse(unknown.contains(asOf.addingTimeInterval(-1)))
        let earliest = date("2026-09-28T15:12:00-04:00")
        let known = try DashboardReportingRange.all.daytimeWindow(asOf: asOf, timeZone: zone, earliestEvidenceAt: earliest)
        XCTAssertEqual(known.start, earliest); XCTAssertEqual(known.calendarDayCount, 3)
        XCTAssertTrue(known.contains(earliest))
        XCTAssertTrue(try DashboardReportingRange.all.daytimeWindow(asOf: asOf, timeZone: zone, earliestEvidenceAt: asOf).isEmpty)
        XCTAssertThrowsError(try DashboardReportingRange.all.daytimeWindow(asOf: asOf, timeZone: zone, earliestEvidenceAt: asOf.addingTimeInterval(1)))
    }

    func testInvalidCaptureAndUnsupportedDatesHaveNoFallbackWindow() throws {
        let asOf = date("2026-09-30T12:00:00-04:00")
        let period = try PhysicianReportPeriod.resolve(.custom(start: asOf.addingTimeInterval(-3600), endExclusive: asOf), ledger: .init(), asOf: asOf, timeZone: zone)
        XCTAssertThrowsError(try DashboardReportingRange.custom.daytimeWindow(asOf: asOf, timeZone: zone))
        XCTAssertThrowsError(try DashboardReportingRange.custom.daytimeWindow(asOf: asOf.addingTimeInterval(1), timeZone: zone, reviewedPeriod: period))
        XCTAssertThrowsError(try DashboardReportingRange.custom.daytimeWindow(asOf: asOf, timeZone: .gmt, reviewedPeriod: period))
        XCTAssertThrowsError(try DashboardReportingRange.sinceCompletedVisit.daytimeWindow(asOf: asOf, timeZone: zone, reviewedPeriod: period))
        XCTAssertThrowsError(try DashboardReportingRange.week.daytimeWindow(asOf: Date(timeIntervalSince1970: .infinity), timeZone: zone))
        XCTAssertThrowsError(try DashboardReportingRange.year.daytimeWindow(asOf: date("0001-01-02T12:00:00Z"), timeZone: .gmt))
    }
}
