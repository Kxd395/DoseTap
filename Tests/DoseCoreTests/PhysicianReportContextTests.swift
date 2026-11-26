import XCTest
@testable import DoseCore

final class PhysicianReportContextTests: XCTestCase {
    func testContextIsImmutableValidatedAndPortable() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let period = try PhysicianReportPeriod.resolve(.days28, ledger: .init(), asOf: now, timeZone: TimeZone(secondsFromGMT: 0)!)
        let context = try PhysicianReportContext(id: "daytime", title: "Daytime review coverage", lines: ["4 events; 12 dates with reviewed intervals; 2 dates without reviewed intervals."], source: "Synthetic diary", definitionVersion: "analysis.v1", recordIDs: ["event-1"])
        let snapshot = try PhysicianReportSnapshot(period: period, observations: [], notes: [], questions: [], appVersion: "test", generatedAt: now, contexts: [context])
        try snapshot.validate()
        XCTAssertEqual(snapshot.contexts, [context])
        XCTAssertTrue(snapshot.reviewText.contains(context.lines[0]))
        XCTAssertEqual(try JSONDecoder().decode(PhysicianReportSnapshot.self, from: snapshot.jsonData()), snapshot)
        XCTAssertThrowsError(try PhysicianReportSnapshot(period: period, observations: [], notes: [], questions: [], appVersion: "test", generatedAt: now, contexts: [context, context]))
        XCTAssertThrowsError(try PhysicianReportContext(id: "", title: "", lines: [], source: "", definitionVersion: "", recordIDs: []))
    }
    func testDetailOnlyRecordsStayOutOfMetricsAndKeepSeriousAppendix() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let period = try PhysicianReportPeriod.resolve(.days28, ledger: .init(), asOf: now, timeZone: TimeZone(secondsFromGMT: 0)!)
        let rows = [false, true].map { serious in
            PhysicianReportObservation(id: String(serious), observedAt: now.addingTimeInterval(-1), metricID: "Event record", value: 1,
                state: .available, unit: "record", source: "Synthetic", definitionVersion: "v1", detail: serious ? "Serious event retained" : "Routine raw event",
                recordIDs: [], requiresReview: serious, detailOnly: true)
        }
        let snapshot = try PhysicianReportSnapshot(period: period, observations: rows, notes: [], questions: [], appVersion: "test", generatedAt: now)
        XCTAssertTrue(snapshot.summaries.isEmpty); XCTAssertTrue(snapshot.monthlySummaries.isEmpty)
        XCTAssertEqual(snapshot.observations.count, 2)
        XCTAssertTrue(snapshot.reviewText.contains("Serious event retained"))
        XCTAssertFalse(snapshot.reviewText.contains("Routine raw event"))
        XCTAssertTrue(snapshot.detailCSV.contains("Routine raw event")); XCTAssertTrue(snapshot.detailCSV.contains("detail_only"))
        try snapshot.validate()
    }

    func testEmptyCalendarMonthRemainsVisibleWithoutZeroMetric() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let period = try PhysicianReportPeriod.resolve(.days28, ledger: .init(), asOf: now, timeZone: TimeZone(identifier: "America/New_York")!)
        let row = PhysicianReportObservation(id: "january", observedAt: now.addingTimeInterval(-1), metricID: "sleep", value: 120,
            state: .available, unit: "minutes", source: "Synthetic", definitionVersion: "v1", detail: "", recordIDs: [])
        let report = try PhysicianReportSnapshot(period: period, observations: [row], notes: [], questions: [], appVersion: "test", generatedAt: now)
        let december = try XCTUnwrap(report.monthlyCoverage.first { $0.month == "2026-12" })
        XCTAssertEqual(december.calendarDayCount, 13); XCTAssertEqual(december.observationDays, 0); XCTAssertEqual(december.observationCount, 0)
        XCTAssertEqual(report.monthlyCoverage.count, 2)
        XCTAssertEqual(report.monthlySummaries.map(\.month), ["2027-01"])
        XCTAssertTrue(report.reviewText.contains("2026-12")); XCTAssertTrue(report.reviewText.contains("No observations recorded"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: report.jsonData()) as? [String: Any])
        XCTAssertEqual((json["monthlyCoverage"] as? [[String: Any]])?.count, 2)
        let csv = try ReportCSV.rows(report.summaryCSV), header = try XCTUnwrap(csv.first)
        let kind = try XCTUnwrap(header.firstIndex(of: "row_type")), month = try XCTUnwrap(header.firstIndex(of: "month"))
        let median = try XCTUnwrap(header.firstIndex(of: "median")), eligible = try XCTUnwrap(header.firstIndex(of: "eligible_observations"))
        let decemberCSV = try XCTUnwrap(csv.dropFirst().first { $0[kind] == "calendar_coverage" && $0[month] == "2026-12" })
        XCTAssertEqual(decemberCSV[median], ""); XCTAssertEqual(decemberCSV[eligible], "")
    }

    func testCoverageExcludesMidnightNextMonthAndUnplacedRows() throws {
        let iso = ISO8601DateFormatter(), zone = TimeZone(identifier: "America/New_York")!
        let start = try XCTUnwrap(iso.date(from: "2026-03-07T17:00:00Z")), end = try XCTUnwrap(iso.date(from: "2026-04-01T04:00:00Z"))
        let period = try PhysicianReportPeriod.resolve(.custom(start: start, endExclusive: end), ledger: .init(), asOf: end, timeZone: zone)
        let row = PhysicianReportObservation(id: "unplaced", observedAt: nil, metricID: "source", value: nil,
            state: .unavailable, unit: "record", source: "Synthetic", definitionVersion: "v1", detail: "", recordIDs: [])
        let report = try PhysicianReportSnapshot(period: period, observations: [row], notes: [], questions: [], appVersion: "test", generatedAt: end)
        XCTAssertEqual(report.monthlyCoverage.map(\.month), ["2026-03"])
        XCTAssertEqual(report.monthlyCoverage.first?.calendarDayCount, 25)
        XCTAssertEqual(report.monthlyCoverage.first?.observationCount, 0)
        XCTAssertEqual(report.observations.count, 1)
    }

    func testPartialPolicyIsFrozenWithSeparateContributionCount() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let period = try PhysicianReportPeriod.resolve(.days28, ledger: .init(), asOf: now, timeZone: TimeZone(secondsFromGMT: 0)!)
        let rows = [(PhysicianMetricState.available, 120.0), (.partial, 60.0)].enumerated().map { index, pair in
            PhysicianReportObservation(id: String(index), observedAt: now.addingTimeInterval(-1), metricID: "sleep", value: pair.1,
                state: pair.0, unit: "minutes", source: "Synthetic", definitionVersion: "v1", detail: "", recordIDs: [])
        }
        let ordinary = try PhysicianReportSnapshot(period: period, observations: rows, notes: [], questions: [], appVersion: "test", generatedAt: now)
        let selected = try PhysicianReportSnapshot(period: period, observations: rows, notes: [], questions: [], appVersion: "test", generatedAt: now, includePartialMetrics: true)
        XCTAssertEqual(ordinary.summaries.first?.median, 120)
        XCTAssertEqual(ordinary.summaries.first?.numericContributionCount, 1)
        XCTAssertEqual(selected.summaries.first?.median, 90)
        XCTAssertEqual(selected.summaries.first?.availableCount, 1)
        XCTAssertEqual(selected.summaries.first?.partialCount, 1)
        XCTAssertEqual(selected.summaries.first?.includedPartialCount, 1)
        XCTAssertEqual(selected.summaries.first?.numericContributionCount, 2)
        XCTAssertTrue(selected.reviewText.contains("Partial values included by explicit selection"))
        XCTAssertTrue(selected.summaryCSV.contains("included_partial_observations"))
        XCTAssertEqual(try JSONDecoder().decode(PhysicianReportSnapshot.self, from: selected.jsonData()), selected)
        try selected.validate()
    }

    func testPartialWithoutValueOrOccurrenceNeverContributes() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let period = try PhysicianReportPeriod.resolve(.days28, ledger: .init(), asOf: now, timeZone: TimeZone(secondsFromGMT: 0)!)
        let rows = [
            PhysicianReportObservation(id: "no-value", observedAt: now.addingTimeInterval(-1), metricID: "sleep", value: nil,
                state: .partial, unit: "minutes", source: "Synthetic", definitionVersion: "v1", detail: "", recordIDs: []),
            PhysicianReportObservation(id: "unplaced", observedAt: nil, metricID: "sleep", value: 100,
                state: .partial, unit: "minutes", source: "Synthetic", definitionVersion: "v1", detail: "", recordIDs: [])]
        let report = try PhysicianReportSnapshot(period: period, observations: rows, notes: [], questions: [], appVersion: "test", generatedAt: now, includePartialMetrics: true)
        XCTAssertNil(report.summaries.first?.median)
        XCTAssertEqual(report.summaries.first?.numericContributionCount, 0)
        XCTAssertEqual(report.summaries.first?.eligibleCount, 1)
        XCTAssertEqual(report.summaries.first?.unplacedCount, 1)
    }

    func testReadableComparisonLabelsRemainSeparateAndPortable() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let period = try PhysicianReportPeriod.resolve(.days28, ledger: .init(), asOf: now, timeZone: TimeZone(secondsFromGMT: 0)!)
        let rows = ["Scheduled morning", "User initiated evening"].enumerated().map { index, label in
            PhysicianReportObservation(id: String(index), observedAt: now.addingTimeInterval(-1), metricID: "rating", value: Double(index),
                state: .available, unit: "custom 0–10", source: "Synthetic", definitionVersion: "v1", detail: "", recordIDs: [], comparisonLabel: label)
        }
        let report = try PhysicianReportSnapshot(period: period, observations: rows, notes: [], questions: [], appVersion: "test", generatedAt: now)
        XCTAssertEqual(report.summaries.count, 2)
        XCTAssertEqual(Set(report.summaries.compactMap(\.comparisonLabel)), Set(["Scheduled morning", "User initiated evening"]))
        XCTAssertTrue(report.reviewText.contains("Scheduled morning")); XCTAssertTrue(report.summaryCSV.contains("User initiated evening"))
        try report.validate()
    }

}
