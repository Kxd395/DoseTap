import XCTest
@testable import DoseTapStudio

final class InsightCoverageSummaryTests: XCTestCase {
    func testCoverageSummaryCountsAvailabilityAndReadiness() {
        let sessions = [
            makeSession(
                sessionDate: "2024-09-08",
                wakeType: "natural",
                nightType: "work_night",
                withMorning: true,
                withPreSleep: true,
                withHealthKit: true,
                withWhoop: false,
                validationFlags: []
            ),
            makeSession(
                sessionDate: "2024-09-09",
                wakeType: "alarm_then_snooze",
                nightType: "off_night",
                withMorning: false,
                withPreSleep: true,
                withHealthKit: false,
                withWhoop: true,
                validationFlags: ["Missing morning check-in"]
            ),
            makeSession(
                sessionDate: "2024-09-10",
                wakeType: nil,
                nightType: "transition_into_work_block",
                withMorning: true,
                withPreSleep: false,
                withHealthKit: false,
                withWhoop: false,
                validationFlags: ["Low data completeness"]
            )
        ]

        let summary = InsightCoverageSummary(
            sessions: sessions,
            validationReport: ImportValidationReport(
                globalFlags: ["Session count mismatch"],
                sessionFlagsByDate: ["2024-09-10": ["Missing Dose 2 outcome"]]
            )
        )

        XCTAssertEqual(summary.totalNights, 3)
        XCTAssertEqual(summary.trainableNights, 1)
        XCTAssertEqual(summary.importIssueNights, 1)
        XCTAssertEqual(summary.missingMorningNights, 1)
        XCTAssertEqual(summary.missingPreSleepNights, 1)
        XCTAssertEqual(summary.missingWearableNights, 1)
        XCTAssertEqual(summary.naturalWakeNights, 1)
        XCTAssertEqual(summary.alarmWakeNights, 1)
        XCTAssertEqual(summary.workNights, 1)
        XCTAssertEqual(summary.offNights, 1)
        XCTAssertEqual(summary.transitionNights, 1)
        XCTAssertEqual(summary.workSafetyContextNights, 0)
        XCTAssertEqual(summary.clinicalContextNights, 0)
        XCTAssertEqual(summary.rows.first(where: { $0.key == "morning" })?.availableCount, 2)
        XCTAssertEqual(summary.rows.first(where: { $0.key == "clinical_context" })?.availableCount, 0)
        XCTAssertEqual(summary.readiness, .limited)
    }

    func testInsightSessionMatchesExtendedContextFilters() {
        let session = makeSession(
            sessionDate: "2024-09-08",
            wakeType: "natural",
            nightType: "work_night",
            withMorning: true,
            withPreSleep: true,
            withHealthKit: true,
            withWhoop: false,
            validationFlags: []
        )

        var filters = InsightFilterState()
        filters.nightType = .work
        filters.wakeType = .natural
        filters.schedule = .worklike
        filters.trainableOnly = true

        XCTAssertTrue(session.matches(filters: filters))

        filters.wakeType = .alarm
        XCTAssertFalse(session.matches(filters: filters))

        filters.wakeType = .natural
        filters.workSafetyContextOnly = true
        XCTAssertFalse(session.matches(filters: filters))
    }

    private func makeSession(
        sessionDate: String,
        wakeType: String?,
        nightType: String?,
        withMorning: Bool,
        withPreSleep: Bool,
        withHealthKit: Bool,
        withWhoop: Bool,
        validationFlags: [String]
    ) -> InsightSession {
        let formatter = ISO8601DateFormatter()
        let dose1 = formatter.date(from: "\(sessionDate)T22:00:00Z")!
        let dose2 = dose1.addingTimeInterval(170 * 60)

        let morning: InsightMorningSummary? = withMorning
            ? InsightMorningSummary(
                submittedAtUTC: dose2.addingTimeInterval(8 * 60 * 60),
                sleepQuality: 4,
                feelRested: "mostly",
                grogginess: "mild",
                sleepInertiaDuration: "5-15 minutes",
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
            )
            : nil

        let preSleep: InsightPreSleepSummary? = withPreSleep
            ? InsightPreSleepSummary(
                sessionId: sessionDate,
                completionState: "complete",
                loggedAtUTC: "\(sessionDate)T21:30:00Z",
                stressLevel: 2,
                stressDrivers: [],
                laterReason: nil,
                bodyPain: nil,
                caffeineSources: [],
                alcohol: nil,
                exercise: nil,
                napToday: nil,
                lateMeal: nil,
                screensInBed: nil,
                roomTemp: nil,
                noiseLevel: nil,
                sleepAids: [],
                notes: nil
            )
            : nil

        return InsightSession(
            id: sessionDate,
            sessionDate: sessionDate,
            startedAt: dose1,
            endedAt: dose2,
            dose1Time: dose1,
            dose2Time: dose2,
            dose2Skipped: false,
            snoozeCount: 0,
            adherenceFlag: "ok",
            sleepEfficiency: withWhoop ? 90 : nil,
            whoopRecovery: withWhoop ? 78 : nil,
            averageHeartRate: withHealthKit ? 61 : nil,
            notes: nil,
            events: [],
            preSleep: preSleep,
            morning: morning,
            medications: [],
            context: InsightSessionContext(
                nextMorningWeekdayIndex: 2,
                nextMorningIsWeekend: false,
                scheduledWakeByUTC: dose2.addingTimeInterval(8 * 60 * 60),
                scheduledWakeMinutesAfterMidnight: 390,
                scheduleDayType: "worklike",
                previousScheduleDayType: "offlike",
                nextScheduleDayType: "worklike",
                explicitNightType: nightType,
                explicitWakeType: wakeType,
                wakeSignal: wakeType == "natural" ? "natural" : (wakeType == nil ? "" : "alarm_assisted"),
                wakeFinalLoggedAtUTC: dose2.addingTimeInterval(6 * 60 * 60),
                snoozeCount: 0,
                scheduleMarkers: [],
                lateMealEndedAtUTC: nil,
                lateMealMinutesBeforeDose1: nil,
                lateMealMinutesBeforeDose2: nil,
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
            ),
            healthKit: withHealthKit
                ? InsightHealthKitSummary(
                    totalSleepMinutes: 420,
                    ttfwMinutes: 170,
                    wakeCount: 1,
                    bedTimeUTC: dose1,
                    sleepOnsetUTC: dose1.addingTimeInterval(15 * 60),
                    finalWakeUTC: dose2.addingTimeInterval(7 * 60 * 60),
                    averageHeartRate: 61,
                    respiratoryRate: 14,
                    hrvMs: 45,
                    restingHeartRate: 56,
                    sources: ["Apple Watch"]
                )
                : nil,
            whoop: withWhoop
                ? InsightWHOOPSummary(
                    sleepId: "sleep-\(sessionDate)",
                    totalSleepMinutes: 415,
                    remMinutes: 90,
                    deepMinutes: 70,
                    lightMinutes: 255,
                    awakeMinutes: 20,
                    disturbanceCount: 2,
                    sleepEfficiency: 90,
                    respiratoryRate: 14,
                    recoveryScore: 78,
                    hrvMs: 52,
                    restingHeartRate: 56
                )
                : nil,
            rawEvents: [
                InsightBundleEvent(
                    kind: "dose",
                    eventType: "dose2",
                    occurredAtUTC: dose2,
                    details: nil,
                    source: "manual",
                    deviceTime: sessionDate
                )
            ],
            normalizedEvents: [
                InsightBundleEvent(
                    kind: "dose",
                    eventType: "dose2_taken",
                    occurredAtUTC: dose2,
                    details: nil,
                    source: "manual",
                    deviceTime: sessionDate
                )
            ],
            sourceAvailability: InsightSourceAvailability(
                doseEvents: true,
                sleepEvents: false,
                preSleep: withPreSleep,
                morningCheckIn: withMorning,
                medications: false,
                healthKit: withHealthKit,
                whoop: withWhoop,
                alarmDiagnostics: false
            ),
            metricProvenance: withWhoop ? ["total_sleep_minutes": "whoop"] : [:],
            validationFlags: validationFlags
        )
    }
}
