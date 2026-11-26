import XCTest
import DoseCore
@testable import DoseTap

final class WorkCycleNapDayTests: XCTestCase {
    private let asOf = Date(timeIntervalSince1970: 1_790_100_000)
    func testOnlyExplicitNoneCreatesZeroAndPartialBoundaryDaysRemainUnassessed() throws {
        let lower = try XCTUnwrap(NapPeriodEligibility.dayBounds(day: "2026-09-21", timeZoneID: "UTC"))
        var doc = NapDiaryDocument()
        doc.reviews = [.init(day: "2026-09-21", timeZoneID: "UTC", status: .none, recordedAt: asOf)]
        let period = try PhysicianReportPeriod.resolve(.custom(start: lower.0, endExclusive: lower.1), ledger: .init(), asOf: asOf, timeZone: .gmt)
        let window = try DashboardReportingRange.custom.daytimeWindow(asOf: asOf, timeZone: .gmt, reviewedPeriod: period)
        let report = WorkCycleNapDayReport(document: doc, merged: [], window: window)
        XCTAssertEqual(report.assessedDayCount, 1); XCTAssertEqual(report.rows.first?.recordCount, 0)
        XCTAssertEqual(report.rows.first?.phase, .unknown)
        let partialPeriod = try PhysicianReportPeriod.resolve(.custom(start: lower.0.addingTimeInterval(3600), endExclusive: lower.1), ledger: .init(), asOf: asOf, timeZone: .gmt)
        let partial = WorkCycleNapDayReport(document: doc, merged: [], window: try DashboardReportingRange.custom.daytimeWindow(asOf: asOf, timeZone: .gmt, reviewedPeriod: partialPeriod))
        XCTAssertEqual(partial.assessedDayCount, 0); XCTAssertNil(partial.rows.first?.recordCount)
        doc.reviews[0] = .init(day: "2026-09-21", timeZoneID: "UTC", status: .complete, recordedAt: asOf)
        XCTAssertNil(WorkCycleNapDayReport(document: doc, merged: [], window: window).rows.first?.recordCount)
    }
    func testChangedEvidenceDoesNotRetainReviewedZero() throws {
        let window = try DashboardReportingRange.week.daytimeWindow(asOf: asOf, timeZone: .gmt)
        var doc = NapDiaryDocument()
        doc.reviews = [.init(day: "2026-09-21", timeZoneID: "UTC", status: .none, recordedAt: asOf)]
        let episode = NapEpisode(day: "2026-09-21", timeZoneID: "UTC", recordedAt: asOf)
        let report = WorkCycleNapDayReport(document: doc, merged: [episode], window: window)
        XCTAssertEqual(report.assessedDayCount, 0); XCTAssertNil(report.rows.first?.recordCount)
        XCTAssertEqual(report.rows.first?.intentCounts[.unknown], 1)
    }
}
