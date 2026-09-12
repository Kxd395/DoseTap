import XCTest
@testable import DoseTapStudio

final class WHOOPExportStatusTests: XCTestCase {
    private let warning = "WHOOP sleep was fetched, but recovery could not be fetched; available sleep data is retained."
    private let partial = #"{"version":1,"sleepStatus":"completed","recoveryStatus":"failed","queryStartUTC":"2026-09-10T18:00:00Z","queryEndUTC":"2026-09-12T12:00:00Z","sleepRecordCount":2,"eligibleNightCount":1}"#

    func testFetchStatusesRoundTripWithoutChangingSessionData() throws {
        let original = try fixtureObject()
        let originalBundle = try Importer().parseInsightsBundle(JSONSerialization.data(withJSONObject: original))
        let cases = [partial,
            #"{"version":1,"sleepStatus":"not_attempted","recoveryStatus":"not_attempted","notAttemptedReason":"disconnected"}"#,
            #"{"version":1,"sleepStatus":"completed","recoveryStatus":"completed","sleepRecordCount":0,"recoveryRecordCount":0,"eligibleNightCount":0}"#,
            #"{"version":1,"sleepStatus":"completed","recoveryStatus":"completed","sleepRecordCount":3,"recoveryRecordCount":2,"eligibleNightCount":2}"#,
            #"{"version":1,"sleepStatus":"failed","recoveryStatus":"not_attempted"}"#,
            #"{"version":2,"sleepStatus":"future_sleep_state","recoveryStatus":"future_recovery_state"}"#]
        for json in cases {
            let status = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! NSDictionary
            var wire = original; wire["whoopEnrichment"] = status
            let bundle = try Importer().parseInsightsBundle(JSONSerialization.data(withJSONObject: wire))
            XCTAssertEqual(bundle.sessions, originalBundle.sessions, "Fetch evidence must not rewrite observations")
            XCTAssertEqual(try encodedObject(bundle)["whoopEnrichment"] as? NSDictionary, status)
        }
        XCTAssertNil(try encodedObject(originalBundle)["whoopEnrichment"], "Legacy absence stays not captured")
        var local = original; local["exportWarnings"] = ["Local snapshot only; provider enrichment was not fetched."]
        XCTAssertNil(try encodedObject(Importer().parseInsightsBundle(JSONSerialization.data(withJSONObject: local)))["whoopEnrichment"])
    }

    @MainActor
    func testRawCopyAndExistingWarningsPreservePartialRecoveryEvidence() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: FixtureLoader.folder(named: "clean-nights"), to: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        var wire = try fixtureObject()
        wire["whoopEnrichment"] = try JSONSerialization.jsonObject(with: Data(partial.utf8))
        wire["exportWarnings"] = [warning]
        wire["futureRawProviderField"] = "RAW-PROVIDER-SENTINEL"
        let source = try JSONSerialization.data(withJSONObject: wire, options: [.prettyPrinted, .sortedKeys])
        try source.write(to: folder.appendingPathComponent("insights_bundle.json"))
        let store = DataStore(); await store.loadAll(from: folder)
        XCTAssertEqual(store.importedInsightsBundleData, source, "Imported bundle copy must retain exact bytes")
        XCTAssertTrue(store.validationReport.globalFlags.contains(warning))
        let bundle = try XCTUnwrap(store.importedInsightsBundle)
        XCTAssertEqual(try encodedObject(bundle)["whoopEnrichment"] as? NSDictionary, wire["whoopEnrichment"] as? NSDictionary)
        XCTAssertNotNil(bundle.importMetadata)
        let builder = InsightReportBuilder()
        let reports = [builder.buildProviderSummary(sessions: store.insightSessions, bundle: bundle, redaction: .clinicianSafe)]
            + InsightRecommendationMode.allCases.map { builder.buildRecommendationPackage(sessions: store.insightSessions, mode: $0, bundle: bundle, redaction: .clinicianSafe) }
        for report in reports {
            XCTAssertTrue(report.contains(warning))
            XCTAssertFalse(report.contains("RAW-PROVIDER-SENTINEL"))
            XCTAssertFalse(report.contains("2026-09-10T18:00:00Z"))
        }
    }

    func testOptionalProductionFixtureRetainsFetchMetadata() throws {
        // Synthetic coverage always runs; the production archive extends it when available.
        var wire = try fixtureObject()
        wire["whoopEnrichment"] = try JSONSerialization.jsonObject(with: Data(partial.utf8))
        let data: Data
        if let path = ProcessInfo.processInfo.environment["DOSETAP_IOS_WHOOP_EXPORT_FIXTURE"] {
            data = try Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("insights_bundle.json"))
        } else {
            data = try JSONSerialization.data(withJSONObject: wire)
        }
        let source = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let expected = try XCTUnwrap(source["whoopEnrichment"] as? NSDictionary)
        let bundle = try Importer().parseInsightsBundle(data)
        XCTAssertEqual(try encodedObject(bundle)["whoopEnrichment"] as? NSDictionary, expected)
        XCTAssertEqual(bundle.exportWarnings, source["exportWarnings"] as? [String])
    }

    private func fixtureObject() throws -> [String: Any] {
        let path = try FixtureLoader.folder(named: "clean-nights").appendingPathComponent("insights_bundle.json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String: Any]
    }

    private func encodedObject(_ bundle: InsightBundle) throws -> [String: Any] {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return try JSONSerialization.jsonObject(with: encoder.encode(bundle)) as! [String: Any]
    }
}
