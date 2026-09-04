import XCTest
@testable import DoseTapStudio

final class InsightSessionBuilderTests: XCTestCase {
    func testTimingBoundaryUsesOccurrenceSecondsRatherThanTruncatedMinutes() {
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        for (seconds, onTime, late) in [(8999.0, false, false), (9000, true, false), (14399, true, false), (14400, false, true), (14430, false, true)] {
            let second = first.addingTimeInterval(seconds)
            let session = DoseSession(startedUTC: first, endedUTC: second, windowTargetMin: 165, windowActualMin: Int(seconds / 60), adherenceFlag: "ok", whoopRecovery: nil, avgHR: nil, sleepEfficiency: nil, notes: nil)
            let events = [DoseEvent(eventType: .dose1_taken, occurredAtUTC: first, details: nil, deviceTime: nil), DoseEvent(eventType: .dose2_taken, occurredAtUTC: second, details: nil, deviceTime: nil)]
            let result = InsightSessionBuilder().build(sessions: [session], events: events)
            XCTAssertEqual(result.count, 1)
            XCTAssertEqual(result.first?.isOnTimeDose2, onTime, "seconds: \(seconds)")
            XCTAssertEqual(result.first?.isLateDose2, late, "seconds: \(seconds)")
        }
    }

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

    func testBuilderKeepsAfterMidnightDose2WithExportedCanonicalNight() {
        withTimeZone("America/New_York") {
            let builder = InsightSessionBuilder()
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

            let insightSessions = builder.build(sessions: [session], events: events)

            XCTAssertEqual(insightSessions.count, 1)
            XCTAssertEqual(insightSessions[0].sessionDate, "2026-08-29")
            XCTAssertEqual(insightSessions[0].intervalMinutes, 180)
            XCTAssertFalse(insightSessions[0].isMissingOutcome)
        }
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
            ],
            context: InsightSessionContext(
                nextMorningWeekdayIndex: 1,
                nextMorningIsWeekend: true,
                wakeSignal: "alarm_assisted",
                wakeFinalLoggedAtUTC: formatter.date(from: "2024-09-08T09:10:00.000Z"),
                snoozeCount: 1,
                scheduleMarkers: ["schedule"],
                lateMealEndedAtUTC: formatter.date(from: "2024-09-07T19:30:00.000Z"),
                lateMealMinutesBeforeDose1: 30,
                lateMealMinutesBeforeDose2: 270,
                caffeineLastIntakeAtUTC: nil,
                caffeineMinutesBeforeDose1: nil,
                alcoholLastDrinkAtUTC: nil,
                alcoholMinutesBeforeDose1: nil,
                exerciseLastAtUTC: nil,
                exerciseMinutesBeforeDose1: nil,
                napLastEndAtUTC: nil,
                napMinutesBeforeDose1: nil,
                screensLastUsedAtUTC: nil,
                screenMinutesBeforeDose1: nil
            )
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
        XCTAssertEqual(insightSessions[0].context?.wakeSignal, "alarm_assisted")
        XCTAssertEqual(insightSessions[0].context?.lateMealMinutesBeforeDose1, 30)
        XCTAssertEqual(insightSessions[0].classification.confidenceBucket, .insufficient)
        XCTAssertFalse(insightSessions[0].countsTowardRecommendationTraining)
    }

    func testBuilderFallsBackToImportedHealthAndWhoopSummaries() {
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
            preSleep: nil,
            morning: nil,
            medications: [],
            healthKit: InsightHealthKitSummary(
                totalSleepMinutes: 420,
                ttfwMinutes: 180,
                wakeCount: 2,
                awakeMinutes: 25,
                wakeAfterSleepOnsetMinutes: 18,
                inBedMinutes: 446,
                coreSleepMinutes: 255,
                deepSleepMinutes: 70,
                remSleepMinutes: 95,
                bedTimeUTC: formatter.date(from: "2024-09-08T00:15:00.000Z"),
                sleepOnsetUTC: formatter.date(from: "2024-09-08T00:25:00.000Z"),
                finalWakeUTC: formatter.date(from: "2024-09-08T07:30:00.000Z"),
                averageHeartRate: 61.4,
                respiratoryRate: 14.2,
                hrvMs: 42.1,
                restingHeartRate: 57.3,
                sources: ["Apple Watch"]
            ),
            whoop: InsightWHOOPSummary(
                sleepId: "sleep-1",
                totalSleepMinutes: 415,
                remMinutes: 95,
                deepMinutes: 70,
                lightMinutes: 250,
                awakeMinutes: 20,
                inBedMinutes: 435,
                disturbanceCount: 4,
                sleepEfficiency: 91.0,
                sleepPerformance: 93.0,
                sleepConsistency: 82.0,
                respiratoryRate: 14.0,
                recoveryScore: 78.0,
                hrvMs: 50.2,
                restingHeartRate: 56.0,
                sleepNeedBaselineMinutes: 430,
                sleepNeedDebtMinutes: 15,
                sleepNeedStrainMinutes: 10,
                sleepNeedNapMinutes: 0,
                spo2Percentage: 97.0,
                skinTempCelsius: 0.3
            )
        )

        let insightSessions = builder.build(
            sessions: [session],
            events: [],
            supplementsBySessionDate: ["2024-09-07": supplement]
        )

        XCTAssertEqual(insightSessions.count, 1)
        XCTAssertEqual(insightSessions[0].averageHeartRate, 61.4)
        XCTAssertEqual(insightSessions[0].sleepEfficiency, 91.0)
        XCTAssertEqual(insightSessions[0].whoopRecovery, 78)
        XCTAssertEqual(insightSessions[0].healthKit?.wakeAfterSleepOnsetMinutes, 18)
        XCTAssertEqual(insightSessions[0].healthKit?.sources, ["Apple Watch"])
        XCTAssertEqual(insightSessions[0].whoop?.sleepId, "sleep-1")
        XCTAssertEqual(insightSessions[0].whoop?.sleepPerformance, 93.0)
        XCTAssertEqual(insightSessions[0].whoop?.spo2Percentage, 97.0)
        XCTAssertEqual(insightSessions[0].classification.confidenceBucket, .low)
    }

    func testBuilderMatchesSupplementAcrossSpringForwardBoundaryInNewYork() {
        withTimeZone("America/New_York") {
            let builder = InsightSessionBuilder()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let session = DoseSession(
                startedUTC: formatter.date(from: "2024-03-10T04:30:00.000Z")!,
                endedUTC: formatter.date(from: "2024-03-10T07:20:00.000Z")!,
                windowTargetMin: 165,
                windowActualMin: 170,
                adherenceFlag: "ok",
                whoopRecovery: nil,
                avgHR: nil,
                sleepEfficiency: nil,
                notes: nil
            )

            let supplement = InsightSessionSupplement(
                sessionDate: "2024-03-09",
                preSleep: nil,
                morning: nil,
                medications: [],
                healthKit: InsightHealthKitSummary(
                    totalSleepMinutes: 410,
                    ttfwMinutes: 175,
                    wakeCount: 1,
                    coreSleepMinutes: 235,
                    deepSleepMinutes: 62,
                    remSleepMinutes: 78,
                    bedTimeUTC: formatter.date(from: "2024-03-10T04:45:00.000Z"),
                    sleepOnsetUTC: formatter.date(from: "2024-03-10T04:55:00.000Z"),
                    finalWakeUTC: formatter.date(from: "2024-03-10T11:10:00.000Z"),
                    averageHeartRate: 60.5,
                    respiratoryRate: 14.2,
                    hrvMs: 46.0,
                    restingHeartRate: 56.0,
                    sources: ["Apple Watch"]
                )
            )

            let insightSessions = builder.build(
                sessions: [session],
                events: [],
                supplementsBySessionDate: ["2024-03-09": supplement]
            )

            XCTAssertEqual(insightSessions.count, 1)
            XCTAssertEqual(insightSessions[0].sessionDate, "2024-03-09")
            XCTAssertEqual(insightSessions[0].healthKit?.totalSleepMinutes, 410)
        }
    }

    func testBuilderMatchesSupplementAcrossFallBackBoundaryInNewYork() {
        withTimeZone("America/New_York") {
            let builder = InsightSessionBuilder()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let session = DoseSession(
                startedUTC: formatter.date(from: "2024-11-03T03:30:00.000Z")!,
                endedUTC: formatter.date(from: "2024-11-03T06:20:00.000Z")!,
                windowTargetMin: 165,
                windowActualMin: 170,
                adherenceFlag: "ok",
                whoopRecovery: nil,
                avgHR: nil,
                sleepEfficiency: nil,
                notes: nil
            )

            let supplement = InsightSessionSupplement(
                sessionDate: "2024-11-02",
                preSleep: nil,
                morning: nil,
                medications: [],
                whoop: InsightWHOOPSummary(
                    sleepId: "dst-fall",
                    totalSleepMinutes: 420,
                    remMinutes: 88,
                    deepMinutes: 72,
                    lightMinutes: 260,
                    awakeMinutes: 18,
                    inBedMinutes: 438,
                    disturbanceCount: 2,
                    sleepEfficiency: 91.0,
                    sleepPerformance: 93.0,
                    sleepConsistency: 86.0,
                    respiratoryRate: 13.9,
                    recoveryScore: 80.0,
                    hrvMs: 52.0,
                    restingHeartRate: 54.0
                )
            )

            let insightSessions = builder.build(
                sessions: [session],
                events: [],
                supplementsBySessionDate: ["2024-11-02": supplement]
            )

            XCTAssertEqual(insightSessions.count, 1)
            XCTAssertEqual(insightSessions[0].sessionDate, "2024-11-02")
            XCTAssertEqual(insightSessions[0].whoop?.sleepId, "dst-fall")
        }
    }

    private func withTimeZone(_ identifier: String, run block: () -> Void) {
        let original = NSTimeZone.default
        guard let zone = TimeZone(identifier: identifier) else {
            XCTFail("Missing timezone \(identifier)")
            return
        }
        NSTimeZone.default = zone
        defer { NSTimeZone.default = original }
        block()
    }
}
