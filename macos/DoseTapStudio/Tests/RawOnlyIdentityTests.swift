import XCTest
@testable import DoseTapStudio

final class RawOnlyIdentityTests: XCTestCase {
    private let date = "2030-04-05"
    private let json = #"{"schemaVersion":2,"exportVersion":"2.8","exportedAtUTC":"2026-09-17T12:00:00Z","sessions":[{"sessionDate":"2030-04-05","identityResolution":{"version":1,"status":"raw_only","sessionIds":["a","b"],"reasons":["multiple_session_identities"]},"rawSourceRecords":[{"sourceTable":"pre_sleep_logs","columns":{"session_id":{"type":"text","text":"a"},"answers_json":{"type":"text","text":"{\"notes\":\"original\"}"},"empty":{"type":"null"},"count":{"type":"integer","integer":9223372036854775807},"fraction":{"type":"real","real":1.25},"bytes":{"type":"blob","blobBase64":"AP8="}}}],"rawEvents":[],"normalizedEvents":[],"medications":[],"checkInSubmissions":[]}] }"#

    func testRawOnlyIdentityRoundTripsAndCannotPairSeparateSessions() throws {
        let importer = Importer()
        let bundle = try importer.parseInsightsBundle(Data(json.utf8))
        let supplement = try XCTUnwrap(bundle.sessions.first)
        let columns = try XCTUnwrap(supplement.rawSourceRecords?.first?.columns)
        XCTAssertEqual(columns["count"]?.integer, Int64.max)
        XCTAssertEqual(columns["answers_json"]?.text, #"{"notes":"original"}"#)
        XCTAssertEqual(columns["bytes"]?.blobBase64, "AP8=")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        XCTAssertEqual(try importer.parseInsightsBundle(encoder.encode(bundle)), bundle)
        let events = try importer.parseEventsCSV("event_type,occurred_at_utc,details,device_time,session_id\ndose1,2030-04-06T02:00:00Z,,\(date),a\ndose2,2030-04-06T05:00:00Z,,\(date),b\n")
        XCTAssertEqual(events.map(\.sessionId), ["a", "b"])
        XCTAssertTrue(InsightSessionBuilder().build(sessions: [], events: events, supplementsBySessionDate: [date: supplement]).isEmpty)
        let report = ImportValidator().validate(sessions: [], events: events, insightBundle: bundle)
        XCTAssertTrue(report.globalFlags.contains { $0.contains("1 date(s) preserved as raw records") })
        XCTAssertFalse(report.globalFlags.contains { $0.contains("count mismatch") || $0.contains("raw payload") })
        XCTAssertFalse(report.sessionFlagsByDate[date, default: []].contains("Supplement exists without base session"))
    }

    func testRawOnlyLeakageIsFlaggedAndStillExcluded() throws {
        let bundle = try Importer().parseInsightsBundle(Data(json.replacingOccurrences(of: #""rawEvents":[]"#, with: #""dose1TimeUTC":"2030-04-06T02:00:00Z","rawEvents":[]"#).utf8))
        let source = try XCTUnwrap(bundle.sessions.first)
        let session = DoseSession(startedUTC: try XCTUnwrap(source.dose1TimeUTC), endedUTC: nil, windowTargetMin: 165, windowActualMin: nil, adherenceFlag: "missing", whoopRecovery: nil, avgHR: nil, sleepEfficiency: nil, notes: nil)
        let report = ImportValidator().validate(sessions: [session], events: [], insightBundle: bundle)
        XCTAssertTrue(report.sessionFlagsByDate[date, default: []].contains("Raw-only date contains derived or selected session values"))
        XCTAssertTrue(report.sessionFlagsByDate[date, default: []].contains("Raw-only date has a derived sessions.csv row"))
        XCTAssertTrue(InsightSessionBuilder().build(sessions: [session], events: [], supplementsBySessionDate: [date: source]).isEmpty)
    }

    func testLegacyAndResolvedDatesRemainAnalyzableButUnknownStatusDoesNot() throws {
        let legacy = InsightSessionSupplement(sessionDate: date, preSleep: nil, morning: nil, medications: [])
        XCTAssertNil(legacy.identityResolution)
        XCTAssertEqual(InsightSessionBuilder().build(sessions: [], events: [], supplementsBySessionDate: [date: legacy]).count, 1)
        for status in ["resolved", "future_status"] {
            let bundle = try Importer().parseInsightsBundle(Data(json.replacingOccurrences(of: "raw_only", with: status).utf8))
            let source = try XCTUnwrap(bundle.sessions.first)
            let nights = InsightSessionBuilder().build(sessions: [], events: [], supplementsBySessionDate: [date: source])
            XCTAssertEqual(nights.count, status == "resolved" ? 1 : 0)
        }
    }
}
