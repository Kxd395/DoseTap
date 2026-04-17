import XCTest
@testable import DoseTapStudio

final class ImportValidatorTests: XCTestCase {
    func testValidatorFlagsImpossibleIntervalsAndDuplicates() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let sessions = [
            DoseSession(
                startedUTC: formatter.date(from: "2024-09-07T20:00:00.000Z")!,
                endedUTC: formatter.date(from: "2024-09-07T18:00:00.000Z")!,
                windowTargetMin: 165,
                windowActualMin: -20,
                adherenceFlag: "ok",
                whoopRecovery: nil,
                avgHR: nil,
                sleepEfficiency: nil,
                notes: nil
            )
        ]

        let events = [
            DoseEvent(
                eventType: .dose1_taken,
                occurredAtUTC: formatter.date(from: "2024-09-07T20:00:00.000Z")!,
                details: nil,
                deviceTime: nil
            ),
            DoseEvent(
                eventType: .lights_out,
                occurredAtUTC: formatter.date(from: "2024-09-07T19:45:00.000Z")!,
                details: nil,
                deviceTime: nil
            ),
            DoseEvent(
                eventType: .lights_out,
                occurredAtUTC: formatter.date(from: "2024-09-07T19:50:00.000Z")!,
                details: nil,
                deviceTime: nil
            ),
            DoseEvent(
                eventType: .wake_final,
                occurredAtUTC: formatter.date(from: "2024-09-07T23:45:00.000Z")!,
                details: nil,
                deviceTime: nil
            ),
            DoseEvent(
                eventType: .wake_final,
                occurredAtUTC: formatter.date(from: "2024-09-07T23:50:00.000Z")!,
                details: nil,
                deviceTime: nil
            )
        ]

        let report = ImportValidator().validate(sessions: sessions, events: events, insightBundle: nil)
        let flags = report.sessionFlagsByDate["2024-09-07"] ?? []

        XCTAssertTrue(flags.contains("Impossible negative interval"))
        XCTAssertTrue(flags.contains("Session ended before it started"))
        XCTAssertTrue(flags.contains("Duplicate lights-out logs"))
        XCTAssertTrue(flags.contains("Duplicate wake-final logs"))
        XCTAssertTrue(flags.contains("Session marked ok but Dose 2 outcome is missing"))
    }

    func testValidatorFlagsSupplementWithoutBaseSessionAndCountMismatch() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let sessions = [
            DoseSession(
                startedUTC: formatter.date(from: "2024-09-07T20:00:00.000Z")!,
                endedUTC: nil,
                windowTargetMin: 165,
                windowActualMin: nil,
                adherenceFlag: "missed",
                whoopRecovery: nil,
                avgHR: nil,
                sleepEfficiency: nil,
                notes: nil
            )
        ]

        let bundle = InsightBundle(
            schemaVersion: 1,
            exportedAtUTC: formatter.date(from: "2024-09-08T12:00:00.000Z")!,
            sessions: [
                InsightSessionSupplement(
                    sessionDate: "2024-09-07",
                    preSleep: nil,
                    morning: nil,
                    medications: []
                ),
                InsightSessionSupplement(
                    sessionDate: "2024-09-09",
                    preSleep: nil,
                    morning: nil,
                    medications: []
                )
            ]
        )

        let report = ImportValidator().validate(sessions: sessions, events: [], insightBundle: bundle)

        XCTAssertTrue(report.globalFlags.contains("Session count mismatch: sessions.csv has 1, insights bundle has 2"))
        XCTAssertEqual(report.sessionFlagsByDate["2024-09-09"], ["Supplement exists without base session"])
    }

    func testValidatorUsesMissingDataFixture() async throws {
        let importer = Importer()
        let folder = try FixtureLoader.folder(named: "missing-data-nights")

        let sessions = try await importer.loadSessions(from: folder)
        let events = try await importer.loadEvents(from: folder)
        let bundle = try await importer.loadInsightsBundle(from: folder)

        let report = ImportValidator().validate(sessions: sessions, events: events, insightBundle: bundle)
        let flags = report.sessionFlagsByDate["2024-09-14"] ?? []

        XCTAssertTrue(flags.contains("Session marked ok but Dose 2 outcome is missing"))
    }

    func testValidatorUsesDuplicateEventsFixture() async throws {
        let importer = Importer()
        let folder = try FixtureLoader.folder(named: "duplicate-event-nights")

        let sessions = try await importer.loadSessions(from: folder)
        let events = try await importer.loadEvents(from: folder)
        let bundle = try await importer.loadInsightsBundle(from: folder)

        let report = ImportValidator().validate(sessions: sessions, events: events, insightBundle: bundle)
        let flags = report.sessionFlagsByDate["2024-09-15"] ?? []

        XCTAssertTrue(flags.contains("Duplicate lights-out logs"))
        XCTAssertTrue(flags.contains("Duplicate wake-final logs"))
    }

    func testValidatorUsesContradictoryDataFixture() async throws {
        let importer = Importer()
        let folder = try FixtureLoader.folder(named: "contradictory-data-nights")

        let sessions = try await importer.loadSessions(from: folder)
        let events = try await importer.loadEvents(from: folder)
        let bundle = try await importer.loadInsightsBundle(from: folder)

        let report = ImportValidator().validate(sessions: sessions, events: events, insightBundle: bundle)
        let flags = report.sessionFlagsByDate["2024-09-16"] ?? []

        XCTAssertTrue(report.globalFlags.contains("Session count mismatch: sessions.csv has 1, insights bundle has 2"))
        XCTAssertEqual(report.sessionFlagsByDate["2024-09-18"], ["Supplement exists without base session"])
        XCTAssertTrue(flags.contains("Conflicting Dose 2 taken and skipped events"))
        XCTAssertTrue(flags.contains("Session interval mismatches event timeline"))
    }
}
