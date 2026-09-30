import XCTest
@testable import DoseCore

final class DashboardCompanionPhysicianReportTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func source(_ rows: [[String: Any]] = [], sequence: UInt64 = 4, daytime: [[String: Any]] = []) throws -> CloudDashboardSnapshot {
        .init(sourceID: "synthetic", sequence: sequence, capturedAt: now, sections: try DashboardDataset.allCases.map {
            let values = $0 == .doseEvents ? rows : $0 == .daytimeDiary ? daytime : []
            return .init(dataset: $0, rows: try JSONSerialization.data(withJSONObject: values), rowCount: values.count)
        })
    }
    private func dose(time: String? = "2027-01-15T01:00:00Z") -> [String: Any] {
        var fields = ["id": "dose", "session_id": "night", "session_date": "2027-01-15", "event_type": "dose1"]
        fields["timestamp"] = time
        return ["sourceTable": "dose_events", "columns": fields.mapValues { ["type": "text", "text": $0] }]
    }
    private func period() throws -> PhysicianReportPeriod {
        try .resolve(.sixMonths, ledger: .init(), asOf: now, timeZone: TimeZone(secondsFromGMT: 0)!)
    }
    func testMissingPeriodAndMixedCaptureFailClosed() throws {
        let raw = try source([dose()]), report = try DashboardCompanionProjection(snapshot: raw, now: now)
        XCTAssertThrowsError(try DashboardCompanionPhysicianReport(snapshot: raw, report: report, nights: report.nights,
            period: nil, inspection: .init(), filterDescription: "All", appVersion: "test"))
        XCTAssertThrowsError(try DashboardCompanionPhysicianReport(snapshot: source(sequence: 5), report: report,
            nights: report.nights, period: period(), inspection: .init(), filterDescription: "All", appVersion: "test"))
    }
    func testSelectedIdentityValidationAndNoInventedMidnight() throws {
        let raw = try source([dose(time: nil)]), report = try DashboardCompanionProjection(snapshot: raw, now: now)
        let result = try DashboardCompanionPhysicianReport(snapshot: raw, report: report, nights: report.nights,
            period: period(), inspection: .init(), filterDescription: "All", appVersion: "test")
        XCTAssertTrue(result.preview.observations.allSatisfy { $0.observedAt == nil })
        XCTAssertTrue(result.preview.summaries.allSatisfy { $0.numericContributionCount == 0 })
        XCTAssertThrowsError(try DashboardCompanionPhysicianReport(snapshot: raw, report: report,
            nights: report.nights + report.nights, period: period(), inspection: .init(), filterDescription: "All", appVersion: "test"))
    }
    func testFrozenReportRetainsCoverageAndExportParity() throws {
        let raw = try source([dose()]), report = try DashboardCompanionProjection(snapshot: raw, now: now)
        var inspection = DashboardInspectionState(); inspection.includePartialMetrics = true
        let result = try DashboardCompanionPhysicianReport(snapshot: raw, report: report, nights: report.nights,
            period: period(), inspection: inspection, filterDescription: "Selected nights", appVersion: "test")
        try result.preview.validate()
        XCTAssertEqual(result.preview.includePartialMetrics, true)
        XCTAssertTrue(result.preview.monthlyCoverage.contains { $0.observationCount == 0 })
        XCTAssertTrue(result.preview.coverageDescription.contains("Independent daytime"))
        XCTAssertTrue(result.preview.coverageDescription.contains("WHOOP sleep/recovery metrics are unavailable"))
        XCTAssertTrue(result.preview.contexts!.flatMap(\.lines).contains { $0.contains("sequence 4") })
        XCTAssertTrue(result.preview.notes.isEmpty)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PhysicianReportSnapshot.self, from: result.preview.jsonData())
        XCTAssertEqual(decoded, result.preview)
        XCTAssertTrue(result.preview.detailCSV.contains("dose.interval"))
        XCTAssertTrue(result.preview.summaryCSV.contains("Selected nights"))
        XCTAssertTrue(result.preview.reviewText.contains(result.preview.id.uuidString))
    }
    func testIndependentDaytimeScopeAndMissingnessArePreserved() throws {
        let entry = try DaytimeCheckIn(assessedAt: now.addingTimeInterval(-100), recordedAt: now,
            timeZoneIdentifier: "UTC", response: 0)
        let event = try DaytimeEvent(kind: .struggling, occurredAt: now.addingTimeInterval(-90), recordedAt: now,
            timeZoneIdentifier: "UTC", note: "Reported struggle, not reported sleep")
        func row(_ table: String, _ fields: [String: String]) -> [String: Any] {
            ["sourceTable": table, "columns": fields.mapValues { ["type": "text", "text": $0] }]
        }
        let raw = try source(daytime: [
            row("daytime_checkins", ["revision_id": entry.revisionID.uuidString, "observation_id": entry.id.uuidString, "payload": entry.encoded()]),
            row("daytime_events", ["revision_id": event.revisionID.uuidString, "event_id": event.id.uuidString, "payload": event.encoded()])])
        let report = try DashboardCompanionProjection(snapshot: raw, now: now)
        var inspection = DashboardInspectionState(); inspection.dosePatternFilter = .twoReported
        let value = try DashboardCompanionPhysicianReport(snapshot: raw, report: report, nights: [], period: period(),
            inspection: inspection, filterDescription: "Two reported doses", appVersion: "test")
        let rating = try XCTUnwrap(value.preview.observations.first { $0.metricID == entry.instrumentID })
        XCTAssertEqual(rating.value, 0); XCTAssertEqual(rating.state, .available)
        XCTAssertEqual(rating.observedAt, entry.assessedAt)
        XCTAssertTrue(rating.detail.hasPrefix("Source JSON timestamps use seconds since 1970."))
        let retained = try XCTUnwrap(value.preview.observations.first { $0.id == "daytime-event:" + event.revisionID.uuidString })
        XCTAssertTrue(retained.detailOnly == true); XCTAssertTrue(retained.detail.contains("not reported sleep"))
        XCTAssertTrue(retained.detail.hasPrefix("Source JSON timestamps use seconds since 1970."))
        XCTAssertFalse(value.preview.summaries.contains { $0.metricID == retained.metricID })
        XCTAssertTrue(value.preview.coverageDescription.contains("origin/protocol filters are not inherited"))
    }
    func testMatchingHeadersCannotHideChangedSourceRows() throws {
        let raw = try source([dose()]), report = try DashboardCompanionProjection(snapshot: raw, now: now)
        XCTAssertThrowsError(try DashboardCompanionPhysicianReport(snapshot: source(), report: report,
            nights: report.nights, period: period(), inspection: .init(), filterDescription: "All", appVersion: "test"))
        let captured = try DashboardCompanionPhysicianReport(snapshot: raw, report: report,
            nights: report.nights, period: period(), inspection: .init(), filterDescription: "All", appVersion: "test")
        XCTAssertTrue(captured.matches(snapshot: raw, nights: report.nights, period: try period(), inspection: .init(), filterDescription: "All"))
        XCTAssertFalse(captured.matches(snapshot: raw, nights: [], period: try period(), inspection: .init(), filterDescription: "All"))
    }

    func testDayOnlyNapDoesNotManufactureOccurrenceAndResolvedDuplicateDoesNotContribute() throws {
        var diary = NapDiaryDocument()
        let original = NapEpisode(id: "original", day: "2027-01-15", timeZoneID: "UTC", estimatedSleepMinutes: 0, recordedAt: now)
        var duplicate = NapEpisode(id: "duplicate", day: "2027-01-15", timeZoneID: "UTC", estimatedSleepMinutes: 20, recordedAt: now)
        duplicate.duplicateOf = original.id; duplicate.reason = "Same reported nap"
        diary.episodes = [original, duplicate]
        let payload = String(decoding: try JSONEncoder().encode(diary), as: UTF8.self)
        let raw = try source(daytime: [["sourceTable": "nap_diary", "columns": ["id": ["type": "integer", "integer": 1], "payload": ["type": "text", "text": payload]]]])
        let report = try DashboardCompanionProjection(snapshot: raw, now: now)
        let result = try DashboardCompanionPhysicianReport(snapshot: raw, report: report, nights: [], period: period(),
            inspection: .init(), filterDescription: "All", appVersion: "test")
        let naps = result.preview.observations.filter { $0.metricID == "nap.patient-estimated-sleep" }
        XCTAssertEqual(naps.count, 2)
        XCTAssertTrue(naps.allSatisfy { $0.observedAt == nil })
        XCTAssertEqual(naps.first { $0.id.contains("nap:original:") }?.value, 0)
        XCTAssertEqual(naps.first { $0.id.contains("nap:duplicate:") }?.state, .notApplicable)
        XCTAssertTrue(result.preview.summaries.allSatisfy { $0.numericContributionCount == 0 })
        XCTAssertTrue(result.preview.contexts!.contains { $0.id == "nap-coverage" })
    }

}
