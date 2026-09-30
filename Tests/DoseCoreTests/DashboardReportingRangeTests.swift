import XCTest
@testable import DoseCore

final class DashboardReportingRangeTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/New_York")!
    private func window(_ range: DashboardReportingRange, _ instant: String,
                        zone: TimeZone? = nil) throws -> DashboardReportingWindow {
        try XCTUnwrap(range.window(asOf: try XCTUnwrap(ISO8601DateFormatter().date(from: instant)),
                                   timeZone: zone ?? self.zone))
    }

    func testCalendarMonthsDifferFromFixed180Dates() throws {
        for (instant, first, last, prior) in [
            ("2026-09-30T22:00:00-04:00", "2026-04-01", "2026-09-30", "2025-10-01"),
            ("2026-09-26T22:00:00-04:00", "2026-03-27", "2026-09-26", "2025-09-27"),
            ("2027-02-28T22:00:00-05:00", "2026-09-01", "2027-02-28", "2026-03-01"),
            ("2026-03-30T22:00:00-04:00", "2025-09-30", "2026-03-30", "2025-03-30")
        ] {
            let value = try window(.sixMonths, instant)
            XCTAssertEqual(value.firstTreatmentDate, first)
            XCTAssertEqual(value.lastTreatmentDate, last)
            XCTAssertEqual(value.priorFirstTreatmentDate, prior)
            XCTAssertTrue(value.contains(first)); XCTAssertFalse(value.contains(first, prior: true))
            XCTAssertTrue(value.contains(prior, prior: true)); XCTAssertFalse(value.contains(prior))
        }
    }

    func testLeapYearAndProviderTruncationAreExplicit() throws {
        let value = try window(.year, "2024-02-29T22:00:00-05:00")
        XCTAssertEqual(value.firstTreatmentDate, "2023-03-01")
        XCTAssertEqual(value.priorFirstTreatmentDate, "2022-03-01")
        XCTAssertTrue(value.contains("2024-02-29"))
        XCTAssertFalse(value.contains("2024-03-01"))
        XCTAssertEqual(value.healthQueryDays, 730)
        XCTAssertTrue(value.healthQueryTruncatesPriorPeriod)
        XCTAssertEqual(value.healthFirstTreatmentDate, "2022-03-02")
        let halfYear = try window(.sixMonths, "2026-09-26T22:00:00-04:00")
        XCTAssertEqual(halfYear.healthQueryDays, 367)
        XCTAssertFalse(halfYear.healthQueryTruncatesPriorPeriod)
    }

    func testFixedDaysStayCivilAcrossBothDSTTransitions() throws {
        for instant in ["2026-03-10T22:00:00-04:00", "2026-11-03T22:00:00-05:00"] {
            for (range, count) in [(DashboardReportingRange.week, 7), (.twoWeeks, 14), (.month, 30), (.quarter, 90)] {
                let value = try window(range, instant)
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
                XCTAssertEqual(calendar.dateComponents([.day], from: try XCTUnwrap(value.start), to: value.endExclusive).day, count)
                XCTAssertEqual(calendar.dateComponents([.day], from: try XCTUnwrap(value.priorStart), to: try XCTUnwrap(value.start)).day, count)
                XCTAssertEqual(calendar.component(.hour, from: value.endExclusive), 0)
                XCTAssertEqual(value.healthQueryDays, count * 2 + 2)
            }
        }
    }

    func testRolloverAndExplicitTimezoneDetermineAnchor() throws {
        let before = try window(.sixMonths, "2026-10-01T17:59:59-04:00")
        let after = try window(.sixMonths, "2026-10-01T18:00:00-04:00")
        XCTAssertEqual(before.lastTreatmentDate, "2026-09-30")
        XCTAssertEqual(before.firstTreatmentDate, "2026-04-01")
        XCTAssertEqual(after.firstTreatmentDate, "2026-04-02")
        let instant = "2026-10-01T00:30:00Z"
        XCTAssertEqual(try window(.week, instant).lastTreatmentDate, "2026-09-30")
        XCTAssertEqual(try window(.week, instant, zone: TimeZone(identifier: "Pacific/Honolulu")!).lastTreatmentDate, "2026-09-29")
    }

    func testMalformedAndFutureDatesNeverEnterEvenAllTime() throws {
        let value = try window(.all, "2026-09-30T22:00:00-04:00")
        XCTAssertNil(value.firstTreatmentDate); XCTAssertNil(value.priorFirstTreatmentDate)
        XCTAssertEqual(value.healthQueryDays, 730)
        XCTAssertFalse(value.healthQueryTruncatesPriorPeriod)
        for key in ["invalid", "2026-9-01", "2026-02-29", "2026-04-31", "0000-01-01", "2026-10-01", "2026-09-30extra"] {
            XCTAssertFalse(value.contains(key), key)
        }
        XCTAssertTrue(value.contains("2020-02-29"))
        XCTAssertFalse(value.contains("2020-02-29", prior: true))
        XCTAssertNil(DashboardReportingRange.year.window(asOf: Date(timeIntervalSince1970: .nan), timeZone: zone))
    }
    func testEraBoundaryCannotBecomeMisleadingPositiveDateKeys() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        for year in [1, 2] {
            let date = try XCTUnwrap(calendar.date(from: DateComponents(era: 1, year: year, month: 1, day: 1, hour: 22)))
            XCTAssertNil(DashboardReportingRange.year.window(asOf: date, timeZone: .gmt))
        }
        let bce = try XCTUnwrap(calendar.date(from: DateComponents(era: 0, year: 1, month: 6, day: 1, hour: 22)))
        XCTAssertNil(DashboardReportingRange.all.window(asOf: bce, timeZone: .gmt))
    }

    func testReportDoseAndQuestionnaireMembershipUsesSameWindow() throws {
        let captured = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-30T22:00:00Z"))
        let keys = ["2026-03-31", "2026-04-01", "2026-09-30", "2026-10-01"]
        func text(_ value: String) -> [String: String] { ["type": "text", "text": value] }
        let rows: [[String: Any]] = keys.map { key in
            ["sourceTable": "morning_checkins", "columns": ["id": text(key), "session_id": text(key), "session_date": text(key)]]
        }
        let snapshot = CloudDashboardSnapshot(sourceID: "range-fixture", sequence: 1, capturedAt: captured,
            sections: try DashboardDataset.allCases.map { dataset in
                let values = dataset == .morning ? rows : []
                return DashboardSnapshotSection(dataset: dataset,
                    rows: try JSONSerialization.data(withJSONObject: values), rowCount: values.count)
            })
        let answers = try DashboardQuestionnaireProjection(snapshot: snapshot, now: captured)
        let doseRows = (keys + ["invalid", "2026-02-29", "2026-04-01"]).map {
            DashboardReportDoseDay(treatmentDate: $0, intervalMinutes: nil, state: .missing, dose1At: nil, dose2At: nil)
        }
        XCTAssertEqual(answers.selected(range: .sixMonths, timeZone: .gmt).map(\.treatmentDate).sorted(), ["2026-04-01", "2026-09-30"])
        XCTAssertEqual(DashboardReportStatistics.selected(doseRows, range: .sixMonths,
            capturedAt: captured, timeZone: .gmt).map(\.treatmentDate), ["2026-04-01", "2026-09-30", "2026-04-01"])
    }

}
