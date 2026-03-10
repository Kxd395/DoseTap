import XCTest
@testable import DoseTapStudio

final class InsightSessionBuilderTests: XCTestCase {
    func testBuilderCreatesLateSessionFromDoseEvents() {
        let builder = InsightSessionBuilder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let session = DoseSession(
            startedUTC: formatter.date(from: "2024-09-07T20:00:00.000Z")!,
            endedUTC: formatter.date(from: "2024-09-08T00:20:00.000Z")!,
            windowTargetMin: 165,
            windowActualMin: 260,
            adherenceFlag: "late",
            whoopRecovery: 72,
            avgHR: 64,
            sleepEfficiency: 85,
            notes: "late night"
        )

        let events = [
            DoseEvent(
                eventType: .dose1_taken,
                occurredAtUTC: formatter.date(from: "2024-09-07T20:00:00.000Z")!,
                details: nil,
                deviceTime: nil
            ),
            DoseEvent(
                eventType: .dose2_taken,
                occurredAtUTC: formatter.date(from: "2024-09-08T00:20:00.000Z")!,
                details: nil,
                deviceTime: nil
            ),
            DoseEvent(
                eventType: .bathroom,
                occurredAtUTC: formatter.date(from: "2024-09-07T22:30:00.000Z")!,
                details: "break",
                deviceTime: nil
            ),
        ]

        let insightSessions = builder.build(sessions: [session], events: events)

        XCTAssertEqual(insightSessions.count, 1)
        XCTAssertEqual(insightSessions[0].intervalMinutes, 260)
        XCTAssertTrue(insightSessions[0].isLateDose2)
        XCTAssertEqual(insightSessions[0].bathroomCount, 1)
        XCTAssertFalse(insightSessions[0].dose2Skipped)
    }

    func testBuilderMarksSkippedNightWithoutDose2Timestamp() {
        let builder = InsightSessionBuilder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let session = DoseSession(
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

        let events = [
            DoseEvent(
                eventType: .dose1_taken,
                occurredAtUTC: formatter.date(from: "2024-09-07T20:00:00.000Z")!,
                details: nil,
                deviceTime: nil
            ),
            DoseEvent(
                eventType: .dose2_skipped,
                occurredAtUTC: formatter.date(from: "2024-09-07T23:30:00.000Z")!,
                details: nil,
                deviceTime: nil
            ),
        ]

        let insightSessions = builder.build(sessions: [session], events: events)

        XCTAssertEqual(insightSessions.count, 1)
        XCTAssertTrue(insightSessions[0].dose2Skipped)
        XCTAssertNil(insightSessions[0].dose2Time)
        XCTAssertFalse(insightSessions[0].isMissingOutcome)
    }

    func testBuilderAppliesInsightsSupplement() {
        let builder = InsightSessionBuilder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let session = DoseSession(
            startedUTC: formatter.date(from: "2024-09-07T20:00:00.000Z")!,
            endedUTC: formatter.date(from: "2024-09-08T00:00:00.000Z")!,
            windowTargetMin: 165,
            windowActualMin: 240,
            adherenceFlag: "ok",
            whoopRecovery: nil,
            avgHR: nil,
            sleepEfficiency: nil,
            notes: nil
        )

        let supplement = InsightSessionSupplement(
            sessionDate: "2024-09-07",
            preSleep: InsightPreSleepSummary(
                sessionId: "session-1",
                completionState: "complete",
                loggedAtUTC: "2024-09-07T19:40:00Z",
                stressLevel: 4,
                stressDrivers: ["work"],
                laterReason: nil,
                bodyPain: "mild",
                caffeineSources: ["coffee"],
                alcohol: "none",
                exercise: "light",
                napToday: "no",
                lateMeal: "no",
                screensInBed: "yes",
                roomTemp: "cool",
                noiseLevel: "quiet",
                sleepAids: [],
                notes: "Tense night"
            ),
            morning: InsightMorningSummary(
                submittedAtUTC: formatter.date(from: "2024-09-08T10:00:00.000Z")!,
                sleepQuality: 4,
                feelRested: "mostly",
                grogginess: "mild",
                sleepInertiaDuration: "fiveToFifteen",
                dreamRecall: "some",
                mentalClarity: 4,
                mood: "steady",
                anxietyLevel: "low",
                stressLevel: 2,
                stressDrivers: [],
                readinessForDay: 4,
                hadSleepParalysis: false,
                hadHallucinations: false,
                hadAutomaticBehavior: false,
                fellOutOfBed: false,
                hadConfusionOnWaking: false,
                notes: nil
            ),
            medications: [
                InsightMedicationSummary(
                    id: "med-1",
                    medicationId: "adderall",
                    doseMg: 10,
                    doseUnit: "mg",
                    formulation: "ir",
                    takenAtUTC: formatter.date(from: "2024-09-08T11:00:00.000Z")!,
                    notes: nil
                )
            ]
        )

        let insightSessions = builder.build(
            sessions: [session],
            events: [],
            supplementsBySessionDate: ["2024-09-07": supplement]
        )

        XCTAssertEqual(insightSessions.count, 1)
        XCTAssertEqual(insightSessions[0].preSleep?.stressLevel, 4)
        XCTAssertEqual(insightSessions[0].morning?.sleepQuality, 4)
        XCTAssertEqual(insightSessions[0].medicationCount, 1)
    }
}
