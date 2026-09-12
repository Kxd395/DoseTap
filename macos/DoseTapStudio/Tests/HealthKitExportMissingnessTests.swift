import XCTest
import DoseCore
@testable import DoseTapStudio

final class HealthKitExportMissingnessTests: XCTestCase {
    private let biometricsJSON = #"{"averageHeartRate":64,"respiratoryRate":14,"hrvMs":37,"restingHeartRate":56,"sources":["Apple Watch"]}"#

    func testBiometricsOnlyHealthOmitsSleepFactsAndReportValues() throws {
        let health = try JSONDecoder().decode(InsightHealthKitSummary.self, from: Data(biometricsJSON.utf8))
        XCTAssertEqual(try JSONDecoder().decode(InsightHealthKitSummary.self, from: JSONEncoder().encode(health)), health)
        try assertMissingSleep(makeNight(health: health))
        let explicitNull = try JSONDecoder().decode(InsightHealthKitSummary.self, from: Data(#"{"totalSleepMinutes":null,"wakeCount":null,"sources":[]}"#.utf8))
        XCTAssertNil(explicitNull.totalSleepMinutes); XCTAssertNil(explicitNull.wakeCount)
        if let path = ProcessInfo.processInfo.environment["DOSETAP_IOS_HEALTH_EXPORT_FIXTURE"] {
            let bundle = try Importer().parseInsightsBundle(Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("insights_bundle.json")))
            let supplement = try XCTUnwrap(bundle.sessions.first { $0.sessionDate == "2026-09-11" })
            let night = try XCTUnwrap(InsightSessionBuilder().build(sessions: [], events: [], supplementsBySessionDate: [supplement.sessionDate: supplement]).first)
            try assertMissingSleep(night)
        }
    }

    func testLegacyNumericValuesAndObservedZeroRetainMeasurementDenominators() throws {
        let missing = try JSONDecoder().decode(InsightHealthKitSummary.self, from: Data(biometricsJSON.utf8))
        let numeric = try [0, 420].map { value in
            try JSONDecoder().decode(InsightHealthKitSummary.self, from: Data("{\"totalSleepMinutes\":\(value),\"wakeCount\":\(value == 0 ? 0 : 2),\"sources\":[]}".utf8))
        }
        let nights = ([missing] + numeric).enumerated().map { makeNight(health: $0.element, day: "2026-09-\(10 + $0.offset)") }
        XCTAssertEqual(nights.compactMap(\.totalSleepMinutes), [0, 420])
        XCTAssertEqual(nights.compactMap(\.wakeDisruptionCount), [0, 2])
        XCTAssertEqual(nights[1].normalizedFacts.first { $0.key == "total_sleep_minutes" }?.numericValue, 0)
        XCTAssertEqual(nights[1].normalizedFacts.first { $0.key == "wake_count" }?.numericValue, 0)
        let segment = try XCTUnwrap(InsightCorrelationAnalyzer().segmentsByWorkSafetyContext(sessions: nights).first)
        XCTAssertEqual(segment.averageTotalSleepMinutes, 210) // Two measurements, not three provider objects.
        XCTAssertTrue(InsightReportBuilder().buildProviderSummary(sessions: nights).contains("Average total sleep: 3h 30m"))
        let zeroCSV = try csvValues(nights[1])
        XCTAssertEqual(zeroCSV["total_sleep_minutes"], "0.0"); XCTAssertEqual(zeroCSV["wake_disruption_count"], "0")
    }

    func testHealthObjectMissingSleepNeverBorrowsWhoopStages() throws {
        let health = try JSONDecoder().decode(InsightHealthKitSummary.self, from: Data(biometricsJSON.utf8))
        let whoop = try JSONDecoder().decode(InsightWHOOPSummary.self, from: Data(#"{"sleepId":"whoop","totalSleepMinutes":480,"remMinutes":100,"deepMinutes":80,"lightMinutes":300,"awakeMinutes":10,"inBedMinutes":490,"disturbanceCount":2}"#.utf8))
        let mixed = makeNight(health: health, whoop: whoop)
        try assertMissingSleep(mixed)
        XCTAssertNil(mixed.restorativeSleepMinutes); XCTAssertNil(mixed.coreOrLightSleepMinutes)
        XCTAssertNil(mixed.deepSleepRatio); XCTAssertNil(mixed.remSleepRatio)
        XCTAssertEqual(mixed.whoop?.totalSleepMinutes, 480)
        XCTAssertEqual(try csvValues(mixed)["light_sleep_minutes"], "300") // Explicit WHOOP field remains.
        let totalOnly = try JSONDecoder().decode(InsightHealthKitSummary.self, from: Data(#"{"totalSleepMinutes":420,"wakeCount":2,"sources":[]}"#.utf8))
        let partial = makeNight(health: totalOnly, whoop: whoop)
        XCTAssertEqual(partial.totalSleepMinutes, 420)
        XCTAssertNil(partial.deepSleepRatio); XCTAssertNil(partial.remSleepRatio)
        XCTAssertNil(partial.restorativeSleepMinutes); XCTAssertNil(partial.coreOrLightSleepMinutes)
        let whoopOnly = makeNight(health: nil, whoop: whoop)
        XCTAssertEqual(whoopOnly.totalSleepMinutes, 480); XCTAssertEqual(whoopOnly.wakeDisruptionCount, 2)
        XCTAssertEqual(whoopOnly.restorativeSleepMinutes, 180); XCTAssertEqual(whoopOnly.coreOrLightSleepMinutes, 300)
        let csv = try csvValues(whoopOnly)
        XCTAssertEqual(csv["awake_minutes"], "10"); XCTAssertEqual(csv["in_bed_minutes"], "490")
        XCTAssertEqual(csv["deep_sleep_minutes"], "80"); XCTAssertEqual(csv["rem_sleep_minutes"], "100")
    }

    private func makeNight(health: InsightHealthKitSummary?, whoop: InsightWHOOPSummary? = nil, day: String = "2026-09-11") -> InsightSession {
        let supplement = InsightSessionSupplement(sessionDate: day, preSleep: nil, morning: nil, medications: [], healthKit: health, whoop: whoop)
        return InsightSessionBuilder().build(sessions: [], events: [], supplementsBySessionDate: [day: supplement])[0]
    }

    private func assertMissingSleep(_ night: InsightSession, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertNil(night.totalSleepMinutes, file: file, line: line); XCTAssertNil(night.wakeDisruptionCount, file: file, line: line)
        XCTAssertEqual(night.averageHeartRate, 64, file: file, line: line)
        XCTAssertEqual(night.respiratoryRate, 14, file: file, line: line)
        XCTAssertEqual(night.hrvMs, 37, file: file, line: line); XCTAssertEqual(night.restingHeartRate, 56, file: file, line: line)
        XCTAssertFalse(night.normalizedFacts.contains { ["total_sleep_minutes", "wake_count"].contains($0.key) }, file: file, line: line)
        let csv = try csvValues(night)
        for key in ["total_sleep_minutes", "wake_disruption_count", "awake_minutes", "waso_minutes", "in_bed_minutes", "core_sleep_minutes", "deep_sleep_minutes", "rem_sleep_minutes"] {
            XCTAssertEqual(csv[key], "", key, file: file, line: line)
        }
        XCTAssertTrue(InsightReportBuilder().buildProviderSummary(sessions: [night]).contains("Average total sleep: —"), file: file, line: line)
    }

    private func csvValues(_ night: InsightSession) throws -> [String: String] {
        let rows = try ReportCSV.rows(InsightReportBuilder().buildSessionCSV(sessions: [night]))
        return Dictionary(uniqueKeysWithValues: zip(rows[0], rows[1]))
    }
}
