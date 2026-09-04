import XCTest
@testable import DoseTapStudio

final class InsightReportBuilderTests: XCTestCase {
    func testProviderSummaryIncludesKeyMetrics() {
        let builder = InsightReportBuilder()
        let sessions = [
            makeSession(
                sessionDate: "2024-09-08",
                intervalMinutes: 165,
                late: false,
                skipped: false,
                stress: 2,
                sleepQuality: 4,
                readiness: 4
            ),
            makeSession(
                sessionDate: "2024-09-07",
                intervalMinutes: 250,
                late: true,
                skipped: false,
                stress: 5,
                sleepQuality: 2,
                readiness: 2,
                context: InsightSessionContext(
                    nextMorningWeekdayIndex: 1,
                    nextMorningIsWeekend: true,
                    scheduledWakeByUTC: ISO8601DateFormatter().date(from: "2024-09-08T08:00:00Z"),
                    scheduledWakeMinutesAfterMidnight: 480,
                    scheduleDayType: "offlike",
                    previousScheduleDayType: "worklike",
                    nextScheduleDayType: "worklike",
                    explicitNightType: "off_night",
                    explicitNextDayDemand: "shift_13h",
                    wakeSignal: "alarm_assisted",
                    wakeFinalLoggedAtUTC: ISO8601DateFormatter().date(from: "2024-09-08T09:30:00Z"),
                    snoozeCount: 2,
                    scheduleMarkers: ["schedule"],
                    lateMealEndedAtUTC: ISO8601DateFormatter().date(from: "2024-09-08T00:30:00Z"),
                    lateMealMinutesBeforeDose1: 90,
                    lateMealMinutesBeforeDose2: 340,
                    caffeineLastIntakeAtUTC: ISO8601DateFormatter().date(from: "2024-09-07T22:15:00Z"),
                    caffeineMinutesBeforeDose1: 105,
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
        ]

        let summary = builder.buildProviderSummary(sessions: sessions)

        XCTAssertTrue(summary.contains("Included nights: 2"))
        XCTAssertTrue(summary.contains("Late Dose 2 nights: 1"))
        XCTAssertTrue(summary.contains("Average morning sleep quality: 3.0 / 5"))
        XCTAssertTrue(summary.contains("High-stress pre-sleep nights: 1"))
        XCTAssertTrue(summary.contains("Alarm-assisted wake nights: 1"))
        XCTAssertTrue(summary.contains("Schedule-marker nights: 1"))
        XCTAssertTrue(summary.contains("Morning-reconciled Dose 2 nights: 0"))
        XCTAssertTrue(summary.contains("Trainable nights: 1"))
    }

    func testSessionCSVIncludesEscapedNotes() {
        let builder = InsightReportBuilder()
        let sessions = [
            makeSession(
                sessionDate: "2024-09-08",
                intervalMinutes: 165,
                late: false,
                skipped: false,
                stress: 3,
                sleepQuality: 4,
                readiness: 4,
                notes: "Needs, commas"
            )
        ]

        let csv = builder.buildSessionCSV(sessions: sessions)

        XCTAssertTrue(csv.contains("session_date,dose1_utc"))
        XCTAssertTrue(csv.contains("\"Needs, commas\""))
    }

    func testProviderSummaryAndCSVIncludeImportedBiometrics() {
        let builder = InsightReportBuilder()
        let bundle = InsightBundle(
            schemaVersion: 2,
            exportVersion: "2.2",
            appVersion: "1.0",
            exportedAtUTC: ISO8601DateFormatter().date(from: "2024-09-09T12:00:00Z") ?? Date(),
            importMetadata: InsightBundleImportMetadata(
                fileName: "insights_bundle.json",
                byteCount: 4096,
                sha256Hex: "abc123def456",
                importedAtUTC: ISO8601DateFormatter().date(from: "2024-09-10T12:00:00Z") ?? Date()
            ),
            sessions: []
        )
        let sessions = [
            makeSession(
                sessionDate: "2024-09-08",
                intervalMinutes: 165,
                late: false,
                skipped: false,
                stress: 2,
                sleepQuality: 4,
                readiness: 4,
                healthKit: InsightHealthKitSummary(
                    totalSleepMinutes: 420,
                    ttfwMinutes: 180,
                    wakeCount: 2,
                    bedTimeUTC: nil,
                    sleepOnsetUTC: nil,
                    finalWakeUTC: nil,
                    averageHeartRate: 61.2,
                    respiratoryRate: 14.3,
                    hrvMs: 48.1,
                    restingHeartRate: 56.0,
                    sources: ["Apple Watch"]
                ),
                whoop: InsightWHOOPSummary(
                    sleepId: "sleep-1",
                    totalSleepMinutes: 415,
                    remMinutes: 90,
                    deepMinutes: 75,
                    lightMinutes: 250,
                    awakeMinutes: 20,
                    inBedMinutes: 435,
                    disturbanceCount: 4,
                    sleepEfficiency: 91.0,
                    sleepPerformance: 92.0,
                    sleepConsistency: 84.0,
                    respiratoryRate: 14.0,
                    recoveryScore: 78.0,
                    hrvMs: 50.2,
                    restingHeartRate: 55.0,
                    sleepNeedBaselineMinutes: 480,
                    sleepNeedDebtMinutes: 25,
                    sleepNeedStrainMinutes: 15,
                    sleepNeedNapMinutes: 0,
                    spo2Percentage: 97.0,
                    skinTempCelsius: 0.2
                ),
                context: InsightSessionContext(
                    nextMorningWeekdayIndex: 2,
                    nextMorningIsWeekend: false,
                    scheduledWakeByUTC: ISO8601DateFormatter().date(from: "2024-09-09T06:30:00Z"),
                    scheduledWakeMinutesAfterMidnight: 390,
                    scheduleDayType: "worklike",
                    previousScheduleDayType: "offlike",
                    nextScheduleDayType: "worklike",
                    explicitNightType: "work_night",
                    explicitWakeType: "natural",
                    explicitNextDayDemand: "shift_13h",
                    explicitDose2WakeMethod: "alarm",
                    explicitBackToSleepDuration: "15_30m",
                    alarm: InsightAlarmContext(
                        scheduledForUTC: ISO8601DateFormatter().date(from: "2024-09-09T01:00:00Z"),
                        firstFireAtUTC: ISO8601DateFormatter().date(from: "2024-09-09T01:00:04Z"),
                        acknowledgedAtUTC: ISO8601DateFormatter().date(from: "2024-09-09T01:02:00Z"),
                        acknowledgementAction: "stop",
                        followUpDeliveredCount: 1
                    ),
                    dose2Outcome: InsightDose2OutcomeContext(
                        takenSource: "manual",
                        takenAmountMg: 4500,
                        takenEarly: false,
                        takenLate: false,
                        liveTakenReason: "ate_too_late",
                        liveTakenReasonNotes: "Tapped live after late meal.",
                        morningTakenReason: "ate_too_late",
                        morningTakenReasonNotes: "Had food too close to bedtime.",
                        takenReason: "ate_too_late",
                        takenReasonNotes: "Had food too close to bedtime.",
                        hasExtraDose: false,
                        liveSkipReason: nil,
                        liveSkipReasonNotes: nil,
                        morningSkipReason: nil,
                        morningSkipReasonNotes: nil,
                        skipReason: nil,
                        skipReasonNotes: nil,
                        skipSource: nil,
                        reasonMismatch: false
                    ),
                    wakeSignal: "likely_natural",
                    wakeFinalLoggedAtUTC: nil,
                    snoozeCount: 0,
                    scheduleMarkers: ["schedule"],
                    lateMealEndedAtUTC: nil,
                    lateMealMinutesBeforeDose1: 100,
                    lateMealMinutesBeforeDose2: 265,
                    caffeineLastIntakeAtUTC: nil,
                    caffeineMinutesBeforeDose1: 180,
                    alcoholLastDrinkAtUTC: nil,
                    alcoholMinutesBeforeDose1: nil,
                    exerciseLastAtUTC: nil,
                    exerciseMinutesBeforeDose1: nil,
                    napLastEndAtUTC: nil,
                    napMinutesBeforeDose1: nil,
                    screensLastUsedAtUTC: nil,
                    screenMinutesBeforeDose1: 40
                )
            )
        ]

        let summary = builder.buildProviderSummary(sessions: sessions, bundle: bundle)
        let csv = builder.buildSessionCSV(sessions: sessions)
        let factsCSV = builder.buildMetricFactsCSV(sessions: sessions)

        XCTAssertTrue(summary.contains("Apple Health nights: 1"))
        XCTAssertTrue(summary.contains("WHOOP nights: 1"))
        XCTAssertTrue(summary.contains("Bundle SHA-256: abc123def456"))
        XCTAssertTrue(summary.contains("Average WHOOP recovery: 70.0%"))
        XCTAssertTrue(summary.contains("Likely natural wake nights: 1"))
        XCTAssertTrue(summary.contains("Morning-reconciled Dose 2 nights: 0"))
        XCTAssertTrue(summary.contains("Dose 2 timing-exception nights: 1"))
        XCTAssertTrue(summary.contains("Dose 2 reason-mismatch nights: 0"))
        XCTAssertTrue(summary.contains("High-confidence nights: 0"))
        XCTAssertTrue(csv.contains("total_sleep_minutes,sleep_efficiency,sleep_performance,sleep_consistency,whoop_recovery,avg_hr,hrv_ms,wake_disruption_count,awake_minutes,waso_minutes"))
        XCTAssertTrue(csv.contains("schedule_day_type"))
        XCTAssertTrue(csv.contains("explicit_night_type"))
        XCTAssertTrue(csv.contains("explicit_next_day_demand"))
        XCTAssertTrue(csv.contains("explicit_dose2_wake_method"))
        XCTAssertTrue(csv.contains("explicit_back_to_sleep_duration"))
        XCTAssertTrue(csv.contains("alarm_scheduled_for_utc"))
        XCTAssertTrue(csv.contains("alarm_first_fire_utc"))
        XCTAssertTrue(csv.contains("alarm_acknowledged_utc"))
        XCTAssertTrue(csv.contains("alarm_ack_action"))
        XCTAssertTrue(csv.contains("dose2_taken_source,dose2_live_taken_reason,dose2_morning_taken_reason,dose2_taken_reason,dose2_taken_reason_notes,dose2_live_skip_reason,dose2_morning_skip_reason,dose2_skip_reason,dose2_skip_reason_notes,dose2_skip_source,dose2_reason_mismatch"))
        XCTAssertTrue(csv.contains("comparable_cohort_key,confidence_bucket,training_eligible,quality_flags,export_exclusion_reasons,metric_provenance"))
        XCTAssertTrue(csv.contains("2024-09-09T01:00:00"))
        XCTAssertTrue(csv.contains("2024-09-09T01:00:04"))
        XCTAssertTrue(csv.contains("2024-09-09T01:02:00"))
        XCTAssertTrue(csv.contains("stop,1,manual"))
        XCTAssertTrue(csv.contains("ate_too_late"))
        XCTAssertTrue(csv.contains("work__natural__shift_13h"))
        XCTAssertTrue(csv.contains("wake_req_self"))
        XCTAssertTrue(factsCSV.contains("session_date,category,metric_key"))
        XCTAssertTrue(factsCSV.contains("sleep_performance"))
        XCTAssertTrue(factsCSV.contains("whoop"))
        XCTAssertTrue(factsCSV.contains("average_heart_rate"))
    }

    func testRecommendationPackageAndCSVIncludeCohortAndMatchedNights() {
        let builder = InsightReportBuilder()
        let sessions = [
            makeSession(
                sessionDate: "2024-09-08",
                intervalMinutes: 170,
                late: false,
                skipped: false,
                stress: 2,
                sleepQuality: 4,
                readiness: 4,
                healthKit: InsightHealthKitSummary(
                    totalSleepMinutes: 430,
                    ttfwMinutes: 165,
                    wakeCount: 1,
                    bedTimeUTC: ISO8601DateFormatter().date(from: "2024-09-08T22:00:00Z"),
                    sleepOnsetUTC: ISO8601DateFormatter().date(from: "2024-09-08T22:08:00Z"),
                    finalWakeUTC: ISO8601DateFormatter().date(from: "2024-09-09T07:18:00Z"),
                    averageHeartRate: 60,
                    respiratoryRate: 14.0,
                    hrvMs: 48,
                    restingHeartRate: 55,
                    sources: ["Apple Watch"]
                )
            ),
            makeSession(
                sessionDate: "2024-09-09",
                intervalMinutes: 172,
                late: false,
                skipped: false,
                stress: 2,
                sleepQuality: 5,
                readiness: 5,
                healthKit: InsightHealthKitSummary(
                    totalSleepMinutes: 440,
                    ttfwMinutes: 168,
                    wakeCount: 1,
                    bedTimeUTC: ISO8601DateFormatter().date(from: "2024-09-09T22:00:00Z"),
                    sleepOnsetUTC: ISO8601DateFormatter().date(from: "2024-09-09T22:07:00Z"),
                    finalWakeUTC: ISO8601DateFormatter().date(from: "2024-09-10T07:24:00Z"),
                    averageHeartRate: 58,
                    respiratoryRate: 13.7,
                    hrvMs: 54,
                    restingHeartRate: 52,
                    sources: ["Apple Watch"]
                )
            ),
            makeSession(
                sessionDate: "2024-09-10",
                intervalMinutes: 160,
                late: false,
                skipped: false,
                stress: 2,
                sleepQuality: 3,
                readiness: 3
            )
        ]

        let package = builder.buildRecommendationPackage(
            sessions: sessions,
            mode: .restfulSleep
        )
        let csv = builder.buildRecommendationComparisonCSV(
            sessions: sessions,
            mode: .restfulSleep
        )

        XCTAssertTrue(package.contains("DoseTap Timing Insight Review Package"))
        XCTAssertTrue(package.contains("Top factors"))
        XCTAssertTrue(package.contains("Matched nights"))
        XCTAssertTrue(package.contains("Clinical note"))
        XCTAssertTrue(package.contains("Observational insight only"))
        XCTAssertTrue(package.contains("Scoring basis"))
        XCTAssertTrue(package.contains("HRV"))
        XCTAssertTrue(package.contains("risk"))
        XCTAssertTrue(package.contains("stage"))
        XCTAssertTrue(csv.contains("session_date,row_type,mode,cohort_key,timing_band"))
        XCTAssertTrue(csv.contains("matched"))
        XCTAssertTrue(csv.contains("Restful Sleep Insight"))
    }

    func testRedactedExportsRemoveFreeTextTimestampsAndFingerprint() {
        let builder = InsightReportBuilder()
        let bundle = InsightBundle(
            schemaVersion: 2,
            exportVersion: "2.3",
            appVersion: "1.5",
            exportedAtUTC: ISO8601DateFormatter().date(from: "2024-09-09T12:00:00Z") ?? Date(),
            importMetadata: InsightBundleImportMetadata(
                fileName: "insights_bundle.json",
                byteCount: 2048,
                sha256Hex: "secretfingerprint",
                importedAtUTC: ISO8601DateFormatter().date(from: "2024-09-10T12:00:00Z") ?? Date()
            ),
            sessions: []
        )
        let session = makeSession(
            sessionDate: "2024-09-08",
            intervalMinutes: 170,
            late: false,
            skipped: false,
            stress: 2,
            sleepQuality: 4,
            readiness: 4,
            notes: "Private narrative note",
            context: InsightSessionContext(
                nextMorningWeekdayIndex: 2,
                nextMorningIsWeekend: false,
                scheduledWakeByUTC: ISO8601DateFormatter().date(from: "2024-09-09T06:30:00Z"),
                scheduledWakeMinutesAfterMidnight: 390,
                scheduleDayType: "worklike",
                previousScheduleDayType: "offlike",
                nextScheduleDayType: "worklike",
                explicitNightType: "work_night",
                explicitWakeType: "alarm",
                explicitNextDayDemand: "shift_13h",
                explicitDose2WakeMethod: "alarm",
                alarm: InsightAlarmContext(
                    scheduledForUTC: ISO8601DateFormatter().date(from: "2024-09-09T01:00:00Z"),
                    firstFireAtUTC: ISO8601DateFormatter().date(from: "2024-09-09T01:00:04Z"),
                    acknowledgedAtUTC: ISO8601DateFormatter().date(from: "2024-09-09T01:02:00Z"),
                    acknowledgementAction: "stop",
                    followUpDeliveredCount: 1
                ),
                dose2Outcome: InsightDose2OutcomeContext(
                    takenSource: "manual",
                    takenAmountMg: 4500,
                    takenEarly: false,
                    takenLate: false,
                    liveTakenReason: "ate_too_late",
                    liveTakenReasonNotes: "private live note",
                    morningTakenReason: "ate_too_late",
                    morningTakenReasonNotes: "private morning note",
                    takenReason: "ate_too_late",
                    takenReasonNotes: "private taken note",
                    hasExtraDose: false,
                    liveSkipReason: nil,
                    liveSkipReasonNotes: nil,
                    morningSkipReason: nil,
                    morningSkipReasonNotes: nil,
                    skipReason: nil,
                    skipReasonNotes: nil,
                    skipSource: nil,
                    reasonMismatch: false
                ),
                wakeSignal: "alarm_assisted",
                wakeFinalLoggedAtUTC: nil,
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
            )
        )

        let summary = builder.buildProviderSummary(
            sessions: [session],
            bundle: bundle,
            redaction: .clinicianSafe
        )
        let package = builder.buildRecommendationPackage(
            sessions: [session, makeSession(sessionDate: "2024-09-09", intervalMinutes: 172, late: false, skipped: false, stress: 2, sleepQuality: 5, readiness: 5)],
            mode: .restfulSleep,
            bundle: bundle,
            redaction: .clinicianSafe
        )
        let csv = builder.buildSessionCSV(
            sessions: [session],
            redaction: .clinicianSafe
        )

        XCTAssertTrue(summary.contains("Bundle SHA-256: redacted"))
        XCTAssertTrue(summary.contains("Redaction applied"))
        XCTAssertFalse(summary.contains("secretfingerprint"))
        XCTAssertTrue(package.contains("redacted"))
        XCTAssertTrue(csv.contains("[redacted]"))
        XCTAssertFalse(csv.contains("2024-09-09T01:00:00"))
        XCTAssertFalse(csv.contains("Private narrative note"))
    }

    private func makeSession(
        sessionDate: String,
        intervalMinutes: Int,
        late: Bool,
        skipped: Bool,
        stress: Int,
        sleepQuality: Int,
        readiness: Int,
        notes: String? = nil,
        healthKit: InsightHealthKitSummary? = nil,
        whoop: InsightWHOOPSummary? = nil,
        context: InsightSessionContext? = nil
    ) -> InsightSession {
        let dose1 = ISO8601DateFormatter().date(from: "\(sessionDate)T22:00:00Z")!
        let dose2 = dose1.addingTimeInterval(TimeInterval(intervalMinutes * 60))

        return InsightSession(
            id: sessionDate,
            sessionDate: sessionDate,
            startedAt: dose1,
            endedAt: dose2,
            dose1Time: dose1,
            dose2Time: skipped ? nil : dose2,
            dose2Skipped: skipped,
            snoozeCount: 0,
            adherenceFlag: late ? "late" : "ok",
            sleepEfficiency: 85,
            whoopRecovery: 70,
            averageHeartRate: 62,
            notes: notes,
            events: [],
            preSleep: InsightPreSleepSummary(
                sessionId: sessionDate,
                completionState: "complete",
                loggedAtUTC: "\(sessionDate)T21:30:00Z",
                stressLevel: stress,
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
            ),
            morning: InsightMorningSummary(
                submittedAtUTC: dose2.addingTimeInterval(8 * 60 * 60),
                sleepQuality: Double(sleepQuality),
                feelRested: "mostly",
                grogginess: "mild",
                sleepInertiaDuration: "fiveToFifteen",
                dreamRecall: "some",
                mentalClarity: sleepQuality,
                mood: "steady",
                anxietyLevel: "low",
                stressLevel: 2,
                stressDrivers: [],
                readinessForDay: readiness,
                hadSleepParalysis: false,
                hadHallucinations: false,
                hadAutomaticBehavior: false,
                fellOutOfBed: false,
                hadConfusionOnWaking: false,
                notes: nil
            ),
            medications: [],
            context: context,
            healthKit: healthKit,
            whoop: whoop
        )
    }
}
