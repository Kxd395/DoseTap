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

    func testValidatorUsesExportedCanonicalNightForAfterMidnightDose2() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let session = DoseSession(
            startedUTC: formatter.date(from: "2026-08-30T02:00:00.000Z")!,
            endedUTC: formatter.date(from: "2026-08-30T05:00:00.000Z")!,
            windowTargetMin: 165,
            windowActualMin: 180,
            adherenceFlag: "ok",
            whoopRecovery: nil,
            avgHR: nil,
            sleepEfficiency: nil,
            notes: nil
        )
        let events = [
            DoseEvent(
                eventType: .dose1_taken,
                occurredAtUTC: formatter.date(from: "2026-08-30T02:00:00.000Z")!,
                details: nil,
                deviceTime: "2026-08-29"
            ),
            DoseEvent(
                eventType: .dose2_taken,
                occurredAtUTC: formatter.date(from: "2026-08-30T05:00:00.000Z")!,
                details: nil,
                deviceTime: "2026-08-29"
            )
        ]

        let report = ImportValidator().validate(sessions: [session], events: events, insightBundle: nil)

        XCTAssertNil(report.sessionFlagsByDate["2026-08-29"])
        XCTAssertFalse(
            report.sessionFlagsByDate.values.flatMap { $0 }.contains("Session marked ok but Dose 2 outcome is missing")
        )
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

    func testValidatorFlagsWHOOPConsentWithoutWHOOPSummaries() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let bundle = InsightBundle(
            schemaVersion: 2,
            exportVersion: "2.2",
            appVersion: "0.4.12 (14)",
            exportedAtUTC: formatter.date(from: "2026-06-18T01:00:46.000Z")!,
            timeZoneIdentifier: "America/New_York",
            localOffsetMinutes: -240,
            consent: InsightConsentState(
                appleHealthEnabled: true,
                appleHealthAvailable: true,
                appleHealthAuthorized: true,
                whoopEnabled: true,
                whoopConnected: true
            ),
            sessions: [
                InsightSessionSupplement(
                    sessionDate: "2026-06-16",
                    sourceAvailability: InsightSourceAvailability(
                        doseEvents: true,
                        sleepEvents: true,
                        preSleep: false,
                        morningCheckIn: false,
                        medications: false,
                        healthKit: true,
                        whoop: false,
                        alarmDiagnostics: false
                    ),
                    preSleep: nil,
                    morning: nil,
                    medications: [],
                    healthKit: InsightHealthKitSummary(
                        totalSleepMinutes: 420,
                        ttfwMinutes: 20,
                        wakeCount: 1,
                        bedTimeUTC: nil,
                        sleepOnsetUTC: nil,
                        finalWakeUTC: nil,
                        averageHeartRate: nil,
                        respiratoryRate: nil,
                        hrvMs: nil,
                        restingHeartRate: nil,
                        sources: ["Apple Health"]
                    ),
                    whoop: nil
                )
            ]
        )

        let report = ImportValidator().validate(sessions: [], events: [], insightBundle: bundle)

        XCTAssertTrue(
            report.globalFlags.contains("WHOOP is enabled or connected but no WHOOP session summaries were imported")
        )
    }

    func testValidatorFlagsMissingRawCheckInPayloadsAndNormalizedSubmissions() {
        let bundle = InsightBundle(
            schemaVersion: 2,
            exportVersion: "2.2",
            appVersion: "0.4.12 (14)",
            exportedAtUTC: testDate,
            sessions: [
                InsightSessionSupplement(
                    sessionDate: "2026-06-16",
                    preSleep: makePreSleep(rawAnswersJson: nil),
                    morning: makeMorning(),
                    medications: []
                )
            ]
        )

        let report = ImportValidator().validate(sessions: [], events: [], insightBundle: bundle)

        XCTAssertTrue(
            report.globalFlags.contains("Pre-sleep raw payloads missing: 1 of 1 pre-sleep sessions")
        )
        XCTAssertTrue(
            report.globalFlags.contains(
                "Morning raw payload fields missing from every session: rawPhysicalSymptomsJson, rawRespiratorySymptomsJson, rawSleepTherapyJson, rawSleepEnvironmentJson, rawStressContextJson, rawTimingContextJson"
            )
        )
        XCTAssertTrue(
            report.globalFlags.contains("No normalized check-in submissions were imported despite pre-sleep or morning summaries")
        )
    }

    func testValidatorAcceptsCurrentRawCheckInPayloadShape() {
        let bundle = InsightBundle(
            schemaVersion: 2,
            exportVersion: "2.2",
            appVersion: "0.4.12 (14)",
            exportedAtUTC: testDate,
            sessions: [
                InsightSessionSupplement(
                    sessionDate: "2026-06-16",
                    preSleep: makePreSleep(rawAnswersJson: #"{"stressLevel":3}"#),
                    morning: makeMorning(
                        rawPhysicalSymptomsJson: #"{"painEntries":[]}"#,
                        rawRespiratorySymptomsJson: #"{"congestionBurden":"none"}"#,
                        rawSleepTherapyJson: #"{"device":"cpap"}"#,
                        rawSleepEnvironmentJson: #"{"noiseLevel":"quiet"}"#,
                        rawStressContextJson: #"{"stressProgression":"better"}"#,
                        rawTimingContextJson: #"{"nightType":"work_night"}"#
                    ),
                    medications: [],
                    checkInSubmissions: [
                        InsightCheckInSubmission(
                            id: "morning:2026-06-16",
                            sourceRecordId: "morning-2026-06-16",
                            sessionId: "2026-06-16",
                            sessionDate: "2026-06-16",
                            checkInType: "morning",
                            questionnaireVersion: "morning-v2",
                            submittedAtUTC: testDate,
                            localOffsetMinutes: -240,
                            responsesJson: #"{"sleep.quality":4.25}"#
                        )
                    ]
                )
            ]
        )

        let report = ImportValidator().validate(sessions: [], events: [], insightBundle: bundle)

        XCTAssertFalse(report.globalFlags.contains { $0.hasPrefix("Pre-sleep raw payloads missing") })
        XCTAssertFalse(report.globalFlags.contains { $0.hasPrefix("Morning raw payload fields missing") })
        XCTAssertFalse(report.globalFlags.contains("No normalized check-in submissions were imported despite pre-sleep or morning summaries"))
    }

    func testValidatorDoesNotRequireUnusedOptionalMorningRawFamilies() {
        let bundle = InsightBundle(
            schemaVersion: 2,
            exportVersion: "2.2",
            appVersion: "0.4.12 (14)",
            exportedAtUTC: testDate,
            sessions: [
                InsightSessionSupplement(
                    sessionDate: "2026-06-16",
                    preSleep: nil,
                    morning: makeMorning(),
                    medications: [],
                    checkInSubmissions: [
                        InsightCheckInSubmission(
                            id: "morning:2026-06-16",
                            sourceRecordId: "morning-2026-06-16",
                            sessionId: "2026-06-16",
                            sessionDate: "2026-06-16",
                            checkInType: "morning",
                            questionnaireVersion: "morning-v2",
                            submittedAtUTC: testDate,
                            localOffsetMinutes: -240,
                            responsesJson: #"{"respiratory.any":false,"sleep_therapy.used":false,"sleep.quality":3}"#
                        )
                    ]
                )
            ]
        )

        let report = ImportValidator().validate(sessions: [], events: [], insightBundle: bundle)

        XCTAssertFalse(report.globalFlags.contains { $0.hasPrefix("Morning raw payload") })
    }

    func testValidatorFlagsMissingRawFamiliesRequiredByNormalizedAnswers() {
        let bundle = InsightBundle(
            schemaVersion: 2,
            exportVersion: "2.2",
            appVersion: "0.4.12 (14)",
            exportedAtUTC: testDate,
            sessions: [
                InsightSessionSupplement(
                    sessionDate: "2026-06-16",
                    preSleep: nil,
                    morning: makeMorning(),
                    medications: [],
                    checkInSubmissions: [
                        InsightCheckInSubmission(
                            id: "morning:2026-06-16",
                            sourceRecordId: "morning-2026-06-16",
                            sessionId: "2026-06-16",
                            sessionDate: "2026-06-16",
                            checkInType: "morning",
                            questionnaireVersion: "morning-v2",
                            submittedAtUTC: testDate,
                            localOffsetMinutes: -240,
                            responsesJson: #"{"respiratory.any":true,"sleep_therapy.used":true,"sleep_therapy.device":"cpap"}"#
                        )
                    ]
                )
            ]
        )

        let report = ImportValidator().validate(sessions: [], events: [], insightBundle: bundle)

        XCTAssertTrue(
            report.globalFlags.contains(
                "Morning raw payload coverage is incomplete for required normalized answers: rawRespiratorySymptomsJson 0/1 missing 2026-06-16; rawSleepTherapyJson 0/1 missing 2026-06-16"
            )
        )
    }

    func testValidatorFlagsRequiredMorningRawPayloadMissingForSpecificSession() {
        let bundle = InsightBundle(
            schemaVersion: 2,
            exportVersion: "2.2",
            appVersion: "0.4.12 (14)",
            exportedAtUTC: testDate,
            sessions: [
                InsightSessionSupplement(
                    sessionDate: "2026-06-16",
                    preSleep: nil,
                    morning: makeMorning(rawPhysicalSymptomsJson: #"{"painEntries":[]}"#),
                    medications: [],
                    checkInSubmissions: [
                        InsightCheckInSubmission(
                            id: "morning:2026-06-16",
                            sourceRecordId: "morning-2026-06-16",
                            sessionId: "2026-06-16",
                            sessionDate: "2026-06-16",
                            checkInType: "morning",
                            questionnaireVersion: "morning-v2",
                            submittedAtUTC: testDate,
                            localOffsetMinutes: -240,
                            responsesJson: #"{"pain.any":true}"#
                        )
                    ]
                ),
                InsightSessionSupplement(
                    sessionDate: "2026-06-17",
                    preSleep: nil,
                    morning: makeMorning(),
                    medications: [],
                    checkInSubmissions: [
                        InsightCheckInSubmission(
                            id: "morning:2026-06-17",
                            sourceRecordId: "morning-2026-06-17",
                            sessionId: "2026-06-17",
                            sessionDate: "2026-06-17",
                            checkInType: "morning",
                            questionnaireVersion: "morning-v2",
                            submittedAtUTC: testDate,
                            localOffsetMinutes: -240,
                            responsesJson: #"{"pain.any":true}"#
                        )
                    ]
                )
            ]
        )

        let report = ImportValidator().validate(sessions: [], events: [], insightBundle: bundle)

        XCTAssertTrue(
            report.globalFlags.contains(
                "Morning raw payload coverage is incomplete for required normalized answers: rawPhysicalSymptomsJson 1/2 missing 2026-06-17"
            )
        )
    }

    private var testDate: Date {
        Date(timeIntervalSince1970: 1_781_670_000)
    }

    private func makePreSleep(rawAnswersJson: String?) -> InsightPreSleepSummary {
        InsightPreSleepSummary(
            sessionId: "2026-06-16",
            completionState: "complete",
            loggedAtUTC: "2026-06-17T00:40:00Z",
            rawAnswersJson: rawAnswersJson,
            stressLevel: 3,
            stressDrivers: ["work"],
            laterReason: nil,
            bodyPain: nil,
            caffeineSources: [],
            alcohol: "none",
            exercise: "none",
            napToday: "no",
            lateMeal: "no",
            screensInBed: "no",
            roomTemp: "cool",
            noiseLevel: "quiet",
            sleepAids: [],
            notes: nil
        )
    }

    private func makeMorning(
        rawPhysicalSymptomsJson: String? = nil,
        rawRespiratorySymptomsJson: String? = nil,
        rawSleepTherapyJson: String? = nil,
        rawSleepEnvironmentJson: String? = nil,
        rawStressContextJson: String? = nil,
        rawTimingContextJson: String? = nil
    ) -> InsightMorningSummary {
        InsightMorningSummary(
            submittedAtUTC: testDate,
            sleepQuality: 4.25,
            rawPhysicalSymptomsJson: rawPhysicalSymptomsJson,
            rawRespiratorySymptomsJson: rawRespiratorySymptomsJson,
            rawSleepTherapyJson: rawSleepTherapyJson,
            rawSleepEnvironmentJson: rawSleepEnvironmentJson,
            rawStressContextJson: rawStressContextJson,
            rawTimingContextJson: rawTimingContextJson,
            feelRested: "mostly",
            grogginess: "mild",
            sleepInertiaDuration: "fiveToFifteen",
            dreamRecall: "some",
            mentalClarity: 4,
            mood: "steady",
            anxietyLevel: "low",
            stressLevel: 2,
            stressDrivers: ["work"],
            readinessForDay: 4,
            hadSleepParalysis: false,
            hadHallucinations: false,
            hadAutomaticBehavior: false,
            fellOutOfBed: false,
            hadConfusionOnWaking: false
        )
    }
}
