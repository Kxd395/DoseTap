import XCTest
import DoseCore
@testable import DoseTapStudio

final class RawOnlyIdentityTests: XCTestCase {
    private struct LegacyRequiredLayout: Decodable { let sessions: [InsightSessionSupplement] }
    private let date = "2030-04-05"
    private let json = #"{"schemaVersion":3,"exportVersion":"2.8","exportedAtUTC":"2026-09-17T12:00:00Z","dateGroups":[{"sessionDate":"2030-04-05","identityResolution":{"version":1,"status":"raw_only","sessionIds":["a","b"],"reasons":["multiple_session_identities"]},"rawSourceRecords":[{"sourceTable":"pre_sleep_logs","columns":{"session_id":{"type":"text","text":"a"},"answers_json":{"type":"text","text":"{\"notes\":\"original\"}"},"empty":{"type":"null"},"count":{"type":"integer","integer":9223372036854775807},"fraction":{"type":"real","real":1.25},"bytes":{"type":"blob","blobBase64":"AP8="}}}],"rawEvents":[],"normalizedEvents":[],"medications":[],"checkInSubmissions":[]}] }"#

    func testSchemaThreeRequiresDateGroupsAndBlocksLegacyLayoutDecoders() throws {
        let importer = Importer(), data = Data(json.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(LegacyRequiredLayout.self, from: data))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(importer.parseInsightsBundle(data))) as? [String: Any])
        XCTAssertNil(object["sessions"]); XCTAssertNotNil(object["dateGroups"])
        for invalid in [json.replacingOccurrences(of: #""schemaVersion":3"#, with: #""schemaVersion":999"#),
                        json.replacingOccurrences(of: "dateGroups", with: "sessions"),
                        json.replacingOccurrences(of: #""dateGroups":"#, with: #""sessions":[],"dateGroups":"#),
                        json.replacingOccurrences(of: "identityResolution", with: "missingIdentity")] {
            XCTAssertThrowsError(try importer.parseInsightsBundle(Data(invalid.utf8)))
        }
        for version in [1, 2] {
            let legacy = json.replacingOccurrences(of: #""schemaVersion":3"#, with: "\"schemaVersion\":\(version)").replacingOccurrences(of: "dateGroups", with: "sessions")
            let restored = try importer.parseInsightsBundle(Data(legacy.utf8))
            let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(restored)) as? [String: Any])
            XCTAssertEqual(restored.schemaVersion, version)
            XCTAssertNotNil(encoded["sessions"]); XCTAssertNil(encoded["dateGroups"])
        }
    }

    func testSchemaFourUsesIdentityLayoutAndKeepsUnavailableTarget() throws {
        let value = json.replacingOccurrences(of: "\"schemaVersion\":3", with: "\"schemaVersion\":4").replacingOccurrences(of: "\"rawEvents\":[]", with: #""doseTimingReview":{"version":1,"status":"needs_review","reason":"identity_unresolved"},"rawEvents":[]"#)
        let importer = Importer()
        XCTAssertEqual(try importer.parseInsightsBundle(Data(value.utf8)).schemaVersion, 4)
        XCTAssertThrowsError(try importer.parseInsightsBundle(Data(value.replacingOccurrences(of: "dateGroups", with: "sessions").utf8)))
        XCTAssertThrowsError(try importer.parseInsightsBundle(Data(value.replacingOccurrences(of: "identityResolution", with: "missingIdentity").utf8)))
    }

    func testReviewedConflictCannotReenterStudioSpacingAnalytics() throws {
        let events: [[String: Any]] = [("a", "dose1", "2030-04-06T02:00:00Z"), ("b", "dose2", "2030-04-06T05:00:00Z"), ("c", "dose2", "2030-04-06T06:00:00Z")].map {
            ["id": $0.0, "kind": "dose", "sourceTable": "dose_events", "eventType": $0.1, "occurredAtUTC": $0.2]
        }
        let group: [String: Any] = ["sessionDate": date, "identityResolution": ["version": 1, "status": "resolved", "sessionIds": ["s"], "reasons": []], "rawEvents": events, "normalizedEvents": [], "medications": []]
        let original = try JSONSerialization.data(withJSONObject: ["schemaVersion": 3, "exportedAtUTC": "2030-04-06T10:00:00Z", "dateGroups": [group]])
        let exported = try StudioDoseTimingExport.prepare(bundleData: original)
        let importer = Importer(), bundle = try importer.parseInsightsBundle(exported.bundleData)
        let raw = try importer.parseEventsCSV("event_type,occurred_at_utc,details,device_time\ndose1,2030-04-06T02:00:00.000Z,,\(date)\ndose2,2030-04-06T05:00:00.000Z,,\(date)\ndose2,2030-04-06T06:00:00.000Z,,\(date)\n")
        let nights = InsightSessionBuilder().build(sessions: try importer.parseSessionsCSV(exported.sessionsCSV), events: raw, supplementsBySessionDate: [date: try XCTUnwrap(bundle.sessions.first)])
        let night = try XCTUnwrap(nights.first)
        XCTAssertEqual(night.events.count, 3)
        XCTAssertEqual(night.doseTimingReview?.reason, "conflicting_dose_records")
        XCTAssertFalse(night.isOnTimeDose2)
        XCTAssertFalse(night.isLateDose2)
        XCTAssertNil(night.intervalMinutes)
        XCTAssertNil(night.anchoredIntervalMinutes)
        XCTAssertEqual(StudioDoseTimingSummary(intervalSeconds: nights.map(\.recordedIntervalSeconds)).pairCount, 0)
    }

    func testIOSRawOnlyArchiveRoundTrip() async throws {
        guard let path = ProcessInfo.processInfo.environment["DOSETAP_IOS_RAW_ONLY_FIXTURE"] else {
            throw XCTSkip("Set DOSETAP_IOS_RAW_ONLY_FIXTURE to the extracted synthetic iOS archive.")
        }
        let importer = Importer(), folder = URL(fileURLWithPath: path, isDirectory: true)
        let data = try XCTUnwrap(importer.loadInsightsBundleData(from: folder))
        let bundle = try importer.parseInsightsBundle(data)
        let raw = try XCTUnwrap(bundle.sessions.first { $0.sessionDate == date })
        XCTAssertTrue([3, 4].contains(bundle.schemaVersion)); XCTAssertEqual(raw.identityResolution?.status, "raw_only")
        XCTAssertEqual(raw.rawEvents.count, 4); XCTAssertEqual(raw.rawSourceRecords?.count, 5)
        let events = try await importer.loadEvents(from: folder)
        let sessions = try await importer.loadSessions(from: folder)
        let groups = Dictionary(uniqueKeysWithValues: bundle.sessions.map { ($0.sessionDate, $0) })
        let nights = InsightSessionBuilder().build(sessions: sessions, events: events, supplementsBySessionDate: groups)
        XCTAssertEqual(nights.map(\.sessionDate), ["2030-04-06"])
        XCTAssertThrowsError(try JSONDecoder().decode(LegacyRequiredLayout.self, from: data))
    }

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
