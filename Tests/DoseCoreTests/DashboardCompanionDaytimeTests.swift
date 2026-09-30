import XCTest
@testable import DoseCore

final class DashboardCompanionDaytimeTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func period() throws -> PhysicianReportPeriod {
        try .resolve(.custom(start: now.addingTimeInterval(-86400), endExclusive: now), ledger: .init(), asOf: now,
            timeZone: TimeZone(secondsFromGMT: 0)!)
    }
    func snapshot(_ observations: [DaytimeCheckIn]) throws -> CloudDashboardSnapshot {
        let rows = try observations.map { value in
            ["sourceTable": "daytime_checkins", "columns": [
                "revision_id": ["type": "text", "text": value.revisionID.uuidString],
                "observation_id": ["type": "text", "text": value.id.uuidString],
                "payload": ["type": "text", "text": try value.encoded()]]] as [String: Any]
        }
        var value = CloudDashboardSnapshot(sourceID: "synthetic", sequence: 1, capturedAt: now,
            sections: DashboardDataset.allCases.map { .init(dataset: $0, rows: Data("[]".utf8), rowCount: 0) })
        value.sections[value.sections.firstIndex { $0.dataset == .daytimeDiary }!] = .init(dataset: .daytimeDiary,
            rows: try JSONSerialization.data(withJSONObject: rows), rowCount: rows.count)
        return value
    }
    func testCurrentRevisionAndHalfOpenOccurrenceBounds() throws {
        let first = try DaytimeCheckIn(assessedAt: now.addingTimeInterval(-3600), recordedAt: now.addingTimeInterval(-1800), timeZoneIdentifier: "UTC", response: 2)
        let correction = try first.corrected(response: 5, status: .answered, reason: "Correction", recordedAt: now)
        let excluded = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 10)
        let result = try DashboardCompanionDaytime(snapshot: snapshot([first, correction, excluded]), period: period())
        XCTAssertEqual(result.observations.map(\.response), [5])
        XCTAssertEqual(result.observations.first?.revisionID, correction.revisionID)
        XCTAssertEqual(result.analysis.answeredCount, 1)
    }
    func testEmptyMeansNoCollectedRowsNotZeroSymptoms() throws {
        let result = try DashboardCompanionDaytime(snapshot: snapshot([]), period: period())
        XCTAssertFalse(result.hasObservationRecords)
        XCTAssertNil(result.napDocument)
        XCTAssertTrue(result.observations.isEmpty)
    }
    func testStalePeriodCaptureFailsClosed() throws {
        let stale = try PhysicianReportPeriod.resolve(.days7, ledger: .init(), asOf: now.addingTimeInterval(-1), timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertThrowsError(try DashboardCompanionDaytime(snapshot: snapshot([]), period: stale))
    }
    func testIdentityMismatchInPayloadRejected() throws {
        let row = try DaytimeCheckIn(assessedAt: now.addingTimeInterval(-60), recordedAt: now, timeZoneIdentifier: "UTC", response: 3)
        var value = try snapshot([row]); let index = value.sections.firstIndex { $0.dataset == .daytimeDiary }!
        let raw = String(decoding: value.sections[index].rows!, as: UTF8.self).replacingOccurrences(of: row.id.uuidString, with: "different")
        value.sections[index] = .init(dataset: .daytimeDiary, rows: Data(raw.utf8), rowCount: 1)
        XCTAssertThrowsError(try DashboardCompanionDaytime(snapshot: value, period: period()))
    }
    func testOriginsStaySeparateAndUnknownContextNotPooled() throws {
        let a = try DaytimeCheckIn(assessedAt: now.addingTimeInterval(-60), recordedAt: now, timeZoneIdentifier: "UTC", response: 3)
        let b = try DaytimeCheckIn(assessedAt: now.addingTimeInterval(-120), recordedAt: now, timeZoneIdentifier: "UTC", response: 8, origin: .symptomTriggered)
        let value = try DashboardCompanionDaytime(snapshot: snapshot([a,b]), period: period())
        XCTAssertEqual(value.analysis.groups.count, 2)
        XCTAssertNotEqual(value.contexts[a.id]?.groupingKey, value.contexts[b.id]?.groupingKey)
    }
    func testNapSourceDocumentRetainsUnknownAsleepAndFrozenTimer() throws {
        var value = try snapshot([])
        var doc = NapDiaryDocument()
        doc.episodes = [NapEpisode(day: NapEpisode.day(now.addingTimeInterval(-600), "UTC"), timeZoneID: "UTC",
            start: now.addingTimeInterval(-600), end: now.addingTimeInterval(-300), recordedAt: now)]
        let payload = String(decoding: try JSONEncoder().encode(doc), as: UTF8.self)
        let rows: [[String: Any]] = [["sourceTable": "nap_diary", "columns": ["id": ["type": "integer", "integer": 1], "payload": ["type": "text", "text": payload]]]]
        value.sections[value.sections.firstIndex { $0.dataset == .daytimeDiary }!] = .init(dataset: .daytimeDiary, rows: try JSONSerialization.data(withJSONObject: rows), rowCount: 1)
        let result = try DashboardCompanionDaytime(snapshot: value, period: period())
        XCTAssertEqual(result.naps.count, 1)
        XCTAssertNil(result.napDays.first?.estimatedMinutes)
        XCTAssertEqual(result.naps.first?.restMinutes, 5)
        XCTAssertEqual(try DashboardCompanionDaytime.earliestEvidenceAt(in: value), now.addingTimeInterval(-600))
    }
    func testCSVUsesSelectedIDsAndPreservesDefinition() throws {
        let a = try DaytimeCheckIn(assessedAt: now.addingTimeInterval(-60), recordedAt: now, timeZoneIdentifier: "UTC", response: 3)
        let b = try DaytimeCheckIn(assessedAt: now.addingTimeInterval(-120), recordedAt: now, timeZoneIdentifier: "UTC", response: 8)
        let value = try DashboardCompanionDaytime(snapshot: snapshot([a,b]), period: period())
        let csv = value.csv(observationIDs: [a.id], filterDescription: "Selected observation")
        XCTAssertTrue(csv.contains(a.id.uuidString)); XCTAssertFalse(csv.contains(b.id.uuidString))
        XCTAssertTrue(csv.contains("custom-0-10-v1")); XCTAssertTrue(csv.contains("period_end_exclusive"))
    }

}
