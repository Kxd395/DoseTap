import XCTest
@testable import DoseCore

final class DashboardReviewedPeriodTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/New_York")!
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    func testFourWeeksUseCivilTreatmentDatesAcrossDST() throws {
        let asOf = date("2026-03-15T20:00:00-04:00")
        let window = try XCTUnwrap(DashboardReportingRange.fourWeeks.window(asOf: asOf, timeZone: zone))
        XCTAssertEqual(window.firstTreatmentDate, "2026-02-16")
        XCTAssertEqual(window.lastTreatmentDate, "2026-03-15")
        XCTAssertEqual(window.healthQueryDays, 58)
        XCTAssertEqual(window.healthQueryEnd, asOf)
    }

    func testCustomPreservesCutoffAndLabelsWholeBoundaryNights() throws {
        let asOf = date("2026-09-30T20:00:00-04:00")
        let start = date("2026-03-07T20:00:00-05:00"), end = date("2026-03-10T07:00:00-04:00")
        let period = try PhysicianReportPeriod.resolve(.custom(start: start, endExclusive: end),
            ledger: .init(), asOf: asOf, timeZone: zone)
        let window = try XCTUnwrap(DashboardReportingRange.custom.window(asOf: asOf, timeZone: zone, reviewedPeriod: period))
        XCTAssertEqual(window.firstTreatmentDate, "2026-03-07")
        XCTAssertEqual(window.lastTreatmentDate, "2026-03-09")
        XCTAssertEqual(window.healthQueryEnd, end)
        XCTAssertEqual(window.reviewedPeriod, period)
        XCTAssertNil(window.priorStart)
        XCTAssertFalse(window.contains("2026-03-07", prior: true))
        XCTAssertTrue(window.contains("2026-03-09"))
        XCTAssertFalse(window.contains("2026-03-10"))
    }

    func testSinceVisitUsesCompletedLedgerRatherThanFutureBooking() throws {
        let asOf = date("2026-09-30T20:00:00-04:00")
        let visit = try PhysicianVisit(occurredAt: date("2026-06-01T10:00:00-04:00"), recordedAt: asOf, now: asOf)
        var ledger = PhysicianVisitLedger(); try ledger.append(visit, now: asOf)
        ledger.appointments = [.init(id: UUID(), scheduledAt: date("2026-10-05T10:00:00-04:00"), status: .planned)]
        let period = try PhysicianReportPeriod.resolve(.sinceCompletedVisit, ledger: ledger, asOf: asOf, timeZone: zone)
        let window = try XCTUnwrap(DashboardReportingRange.sinceCompletedVisit.window(asOf: asOf, timeZone: zone, reviewedPeriod: period))
        XCTAssertEqual(window.reviewedPeriod?.completedVisitID, visit.id)
        XCTAssertEqual(window.firstTreatmentDate, "2026-05-31")
        XCTAssertEqual(window.lastTreatmentDate, "2026-09-30")
    }

    func testReviewedPeriodsRejectUnresolvedChangedTimezoneOrCutoff() throws {
        let asOf = date("2026-09-30T20:00:00-04:00")
        let period = try PhysicianReportPeriod.resolve(.custom(start: asOf.addingTimeInterval(-86400), endExclusive: asOf),
            ledger: .init(), asOf: asOf, timeZone: zone)
        XCTAssertNil(DashboardReportingRange.custom.window(asOf: asOf, timeZone: zone))
        XCTAssertNil(DashboardReportingRange.custom.window(asOf: asOf, timeZone: .gmt, reviewedPeriod: period))
        XCTAssertNil(DashboardReportingRange.custom.window(asOf: asOf.addingTimeInterval(1), timeZone: zone, reviewedPeriod: period))
        XCTAssertNil(DashboardReportingRange.sinceCompletedVisit.window(asOf: asOf, timeZone: zone, reviewedPeriod: period))
        XCTAssertFalse(DashboardReportingRange.presetCases.contains(.custom))
        XCTAssertFalse(DashboardReportingRange.presetCases.contains(.sinceCompletedVisit))
        XCTAssertTrue(DashboardReportingRange.presetCases.contains(.fourWeeks))
    }

    func testLongReviewedPeriodKeepsLocalBoundsWhileDisclosingProviderLimit() throws {
        let asOf = date("2026-09-30T20:00:00-04:00")
        let period = try PhysicianReportPeriod.resolve(.custom(start: date("2020-01-01T18:00:00-05:00"), endExclusive: asOf),
            ledger: .init(), asOf: asOf, timeZone: zone)
        let window = try XCTUnwrap(DashboardReportingRange.custom.window(asOf: asOf, timeZone: zone, reviewedPeriod: period))
        XCTAssertEqual(window.firstTreatmentDate, "2020-01-01")
        XCTAssertEqual(window.healthQueryDays, 730)
        XCTAssertTrue(window.healthQueryTruncatesSelectedPeriod)
        XCTAssertFalse(window.healthQueryTruncatesPriorPeriod)
    }
}
