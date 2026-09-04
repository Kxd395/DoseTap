import XCTest
@testable import DoseTapStudio

final class InsightRecommendationEngineTests: XCTestCase {
    func testRecommendationPrefersBestScoringTimingBandWithinComparableCohort() {
        let engine = InsightRecommendationEngine()
        let sessions = [
            makeSession(sessionDate: "2024-09-08", intervalMinutes: 160, sleepQuality: 3, readiness: 3),
            makeSession(sessionDate: "2024-09-09", intervalMinutes: 162, sleepQuality: 4, readiness: 4),
            makeSession(sessionDate: "2024-09-10", intervalMinutes: 170, sleepQuality: 5, readiness: 5),
            makeSession(sessionDate: "2024-09-11", intervalMinutes: 172, sleepQuality: 5, readiness: 5),
            makeSession(sessionDate: "2024-09-12", intervalMinutes: 175, sleepQuality: 4, readiness: 5)
        ]

        let result = engine.recommend(sessions: sessions, mode: .restfulSleep)

        XCTAssertEqual(result.recommendedBand?.label, "166-180")
        XCTAssertEqual(result.confidenceBucket, .medium)
        XCTAssertEqual(result.nightsUsed, 5)
        XCTAssertEqual(
            result.cohortKey,
            "work__natural__baseline_demand__wake_req_self__baseline_commute__no_sleep_therapy__baseline_metabolism__baseline_clinical__baseline_stress__baseline_pain__baseline_disruption"
        )
        XCTAssertTrue(result.cohortDescription.contains("mostly work nights"))
        XCTAssertFalse(result.topFactors.isEmpty)
        XCTAssertEqual(result.matchedNights.count, 5)
        XCTAssertTrue(result.disclaimer.contains("Observational insight only"))
        XCTAssertTrue(sessions[0].classification.tags.contains(.workNight))
    }

    func testRecommendationReturnsInsufficientWhenSampleIsTooThin() {
        let engine = InsightRecommendationEngine()
        let sessions = [
            makeSession(sessionDate: "2024-09-08", intervalMinutes: 160, sleepQuality: 4, readiness: 4)
        ]

        let result = engine.recommend(sessions: sessions, mode: .nextDayFunction)

        XCTAssertNil(result.recommendedBand)
        XCTAssertEqual(result.confidenceBucket, .insufficient)
    }

    func testClassificationTagsTransitionIntoWorkBlock() {
        let session = makeSession(
            sessionDate: "2024-09-08",
            intervalMinutes: 165,
            sleepQuality: 4,
            readiness: 4,
            context: InsightSessionContext(
                nextMorningWeekdayIndex: 1,
                nextMorningIsWeekend: true,
                scheduledWakeByUTC: ISO8601DateFormatter().date(from: "2024-09-09T08:00:00Z"),
                scheduledWakeMinutesAfterMidnight: 480,
                scheduleDayType: "offlike",
                previousScheduleDayType: "offlike",
                nextScheduleDayType: "worklike",
                explicitNightType: "transition_into_work_block",
                explicitWakeType: "alarm",
                explicitNextDayDemand: "shift_13h",
                wakeSignal: "alarm_assisted",
                wakeFinalLoggedAtUTC: nil,
                snoozeCount: 1,
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

        XCTAssertTrue(session.classification.tags.contains(.workNight))
        XCTAssertTrue(session.classification.tags.contains(.transitionIntoWorkBlock))
        XCTAssertTrue(session.classification.tags.contains(.highDemandNextDay))
    }

    func testClassificationAddsRecoveryAndClinicalContextTags() {
        let formatter = ISO8601DateFormatter()
        let session = makeSession(
            sessionDate: "2024-09-08",
            intervalMinutes: 168,
            sleepQuality: 4,
            readiness: 4,
            context: InsightSessionContext(
                nextMorningWeekdayIndex: 2,
                nextMorningIsWeekend: false,
                scheduledWakeByUTC: formatter.date(from: "2024-09-09T07:00:00Z"),
                scheduledWakeMinutesAfterMidnight: 420,
                scheduleDayType: "offlike",
                previousScheduleDayType: "worklike",
                nextScheduleDayType: "offlike",
                explicitNightType: "recovery_night",
                explicitWakeType: "alarm",
                explicitNextDayDemand: "recovery_day",
                wakeSignal: "alarm_assisted",
                wakeFinalLoggedAtUTC: nil,
                snoozeCount: 0,
                scheduleMarkers: [],
                wakeRequirement: "work",
                shiftStartAtUTC: formatter.date(from: "2024-09-08T19:00:00Z"),
                shiftEndAtUTC: formatter.date(from: "2024-09-09T08:00:00Z"),
                nextRequiredWakeAtUTC: formatter.date(from: "2024-09-09T16:00:00Z"),
                commuteMinutes: 55,
                lateMealType: "heavy_meal",
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

        let enriched = InsightSession(
            id: session.id,
            sessionDate: session.sessionDate,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            dose1Time: session.dose1Time,
            dose2Time: session.dose2Time,
            dose2Skipped: session.dose2Skipped,
            snoozeCount: session.snoozeCount,
            adherenceFlag: session.adherenceFlag,
            sleepEfficiency: session.sleepEfficiency,
            whoopRecovery: session.whoopRecovery,
            averageHeartRate: session.averageHeartRate,
            notes: session.notes,
            events: session.events,
            preSleep: session.preSleep,
            morning: InsightMorningSummary(
                submittedAtUTC: formatter.date(from: "2024-09-09T15:00:00Z")!,
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
                sleepTherapyDevice: "cpap",
                sleepTherapyCompliance: 92,
                drivingConfidence: 2,
                daytimeSleepiness: 4,
                cataplexyBurden: "moderate",
                sleepDisorders: ["narcolepsy", "shift_work_disorder"],
                sleepDisorderNotes: "Shift block week",
                coMedicationNotes: "Morning stimulant",
                pharmacogenomicFastMetabolizer: true,
                pharmacogenomicClinicianReviewed: true,
                pharmacogenomicNotes: "Clinician reviewed",
                notes: nil
            ),
            medications: session.medications,
            context: session.context,
            healthKit: session.healthKit,
            whoop: session.whoop,
            rawEvents: session.rawEvents,
            normalizedEvents: session.normalizedEvents,
            sourceAvailability: session.sourceAvailability,
            metricProvenance: session.metricProvenance,
            validationFlags: session.validationFlags
        )

        XCTAssertTrue(enriched.classification.tags.contains(InsightNightTag.postShiftRecoveryNight))
        XCTAssertTrue(enriched.classification.tags.contains(InsightNightTag.forcedWakeNight))
        XCTAssertTrue(enriched.classification.tags.contains(InsightNightTag.workSafetyContextNight))
        XCTAssertTrue(enriched.classification.tags.contains(InsightNightTag.clinicalContextNight))
        XCTAssertTrue(enriched.classification.tags.contains(InsightNightTag.sleepTherapyNight))
        XCTAssertTrue(enriched.classification.tags.contains(InsightNightTag.fastMetabolizerReferenceNight))
        XCTAssertTrue(enriched.classification.tags.contains(InsightNightTag.highSleepinessDay))
        XCTAssertTrue(enriched.classification.tags.contains(InsightNightTag.lowDrivingConfidenceDay))
        XCTAssertTrue(enriched.comparableCohortKey.contains("post_shift_recovery"))
        XCTAssertTrue(enriched.comparableCohortKey.contains("wake_req_work"))
        XCTAssertTrue(enriched.comparableCohortKey.contains("sleep_therapy"))
        XCTAssertTrue(enriched.comparableCohortKey.contains("fast_met_ref"))
    }

    func testExplicitFirstNightOffAfterWorkBlockOverridesHeuristicScheduleClassification() {
        let formatter = ISO8601DateFormatter()
        let session = makeSession(
            sessionDate: "2024-09-12",
            intervalMinutes: 170,
            sleepQuality: 4,
            readiness: 4,
            context: InsightSessionContext(
                nextMorningWeekdayIndex: 5,
                nextMorningIsWeekend: false,
                scheduledWakeByUTC: formatter.date(from: "2024-09-13T14:00:00Z"),
                scheduledWakeMinutesAfterMidnight: 600,
                scheduleDayType: "worklike",
                previousScheduleDayType: "worklike",
                nextScheduleDayType: "offlike",
                explicitNightType: nil,
                firstNightOffAfterWorkBlock: true,
                explicitWakeType: "natural",
                explicitNextDayDemand: "recovery_day",
                wakeSignal: "likely_natural",
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

        XCTAssertTrue(session.classification.tags.contains(.transitionOutOfWorkBlock))
        XCTAssertTrue(session.classification.tags.contains(.postShiftRecoveryNight))
        XCTAssertTrue(session.comparableCohortKey.contains("post_shift_recovery"))
    }

    func testWorkNightSafetyUsesDrivingSleepinessAndCataplexySignals() {
        let engine = InsightRecommendationEngine()
        let formatter = ISO8601DateFormatter()

        func workSafetySession(
            sessionDate: String,
            intervalMinutes: Int,
            readiness: Int,
            mentalClarity: Int,
            inertia: String,
            drivingConfidence: Int,
            daytimeSleepiness: Int,
            cataplexyBurden: String
        ) -> InsightSession {
            let dose1 = formatter.date(from: "\(sessionDate)T22:00:00Z")!
            let dose2 = dose1.addingTimeInterval(TimeInterval(intervalMinutes * 60))

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
                sleepEfficiency: 88,
                whoopRecovery: 74,
                averageHeartRate: 61,
                notes: nil,
                events: [],
                preSleep: InsightPreSleepSummary(
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
                ),
                morning: InsightMorningSummary(
                    submittedAtUTC: dose2.addingTimeInterval(8 * 60 * 60),
                    sleepQuality: 4,
                    feelRested: "mostly",
                    grogginess: "mild",
                    sleepInertiaDuration: inertia,
                    dreamRecall: "some",
                    mentalClarity: mentalClarity,
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
                    drivingConfidence: drivingConfidence,
                    daytimeSleepiness: daytimeSleepiness,
                    cataplexyBurden: cataplexyBurden,
                    notes: nil
                ),
                medications: [],
                context: InsightSessionContext(
                    nextMorningWeekdayIndex: 2,
                    nextMorningIsWeekend: false,
                    scheduledWakeByUTC: dose2.addingTimeInterval(8 * 60 * 60),
                    scheduledWakeMinutesAfterMidnight: 420,
                    scheduleDayType: "worklike",
                    previousScheduleDayType: "worklike",
                    nextScheduleDayType: "worklike",
                    explicitNightType: "work_night",
                    explicitWakeType: "alarm",
                    explicitNextDayDemand: "shift_13h",
                    wakeSignal: "alarm_assisted",
                    wakeFinalLoggedAtUTC: nil,
                    snoozeCount: 0,
                    scheduleMarkers: [],
                    wakeRequirement: "commute",
                    commuteMinutes: 60,
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
                healthKit: InsightHealthKitSummary(
                    totalSleepMinutes: 420,
                    ttfwMinutes: 160,
                    wakeCount: 1,
                    bedTimeUTC: dose1,
                    sleepOnsetUTC: dose1.addingTimeInterval(10 * 60),
                    finalWakeUTC: dose2.addingTimeInterval(7 * 60 * 60),
                    averageHeartRate: 61,
                    respiratoryRate: 14,
                    hrvMs: 45,
                    restingHeartRate: 55,
                    sources: ["Apple Watch"]
                )
            )
        }

        let result = engine.recommend(
            sessions: [
                workSafetySession(sessionDate: "2024-09-08", intervalMinutes: 170, readiness: 5, mentalClarity: 5, inertia: "5-15 minutes", drivingConfidence: 5, daytimeSleepiness: 1, cataplexyBurden: "none"),
                workSafetySession(sessionDate: "2024-09-09", intervalMinutes: 172, readiness: 4, mentalClarity: 4, inertia: "5-15 minutes", drivingConfidence: 4, daytimeSleepiness: 2, cataplexyBurden: "mild"),
                workSafetySession(sessionDate: "2024-09-10", intervalMinutes: 220, readiness: 2, mentalClarity: 2, inertia: "30-60 minutes", drivingConfidence: 1, daytimeSleepiness: 5, cataplexyBurden: "severe"),
                workSafetySession(sessionDate: "2024-09-11", intervalMinutes: 225, readiness: 2, mentalClarity: 2, inertia: ">1 hour", drivingConfidence: 1, daytimeSleepiness: 4, cataplexyBurden: "severe")
            ],
            mode: .workNightSafety
        )

        XCTAssertEqual(result.recommendedBand?.label, "166-180")
        XCTAssertTrue(result.topFactors.contains { $0.contains("driving confidence") || $0.contains("daytime sleepiness") })
    }

    func testReasonMismatchExcludesNightFromTraining() {
        let session = makeSession(
            sessionDate: "2024-09-08",
            intervalMinutes: 170,
            sleepQuality: 4,
            readiness: 4,
            context: InsightSessionContext(
                nextMorningWeekdayIndex: 2,
                nextMorningIsWeekend: false,
                scheduledWakeByUTC: ISO8601DateFormatter().date(from: "2024-09-09T08:00:00Z"),
                scheduledWakeMinutesAfterMidnight: 480,
                scheduleDayType: "worklike",
                previousScheduleDayType: "offlike",
                nextScheduleDayType: "worklike",
                alarm: nil,
                dose2Outcome: InsightDose2OutcomeContext(
                    takenSource: "manual",
                    takenAmountMg: 4500,
                    takenEarly: false,
                    takenLate: false,
                    liveTakenReason: "ate_too_late",
                    liveTakenReasonNotes: nil,
                    morningTakenReason: "pain_disruption",
                    morningTakenReasonNotes: nil,
                    takenReason: "pain_disruption",
                    takenReasonNotes: nil,
                    hasExtraDose: false,
                    liveSkipReason: nil,
                    liveSkipReasonNotes: nil,
                    morningSkipReason: nil,
                    morningSkipReasonNotes: nil,
                    skipReason: nil,
                    skipReasonNotes: nil,
                    skipSource: nil,
                    reasonMismatch: true
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

        XCTAssertTrue(session.hasDose2ReasonMismatch)
        XCTAssertTrue(session.qualityFlags.contains("Dose 2 reason mismatch between live and morning logs"))
        XCTAssertTrue(session.classification.exclusionReasons.contains("Dose 2 reason mismatch between live and morning logs"))
        XCTAssertFalse(session.countsTowardRecommendationTraining)
    }

    func testRecommendationIncludesExcludedComparableNights() {
        let engine = InsightRecommendationEngine()
        let matched = makeSession(sessionDate: "2024-09-08", intervalMinutes: 170, sleepQuality: 4, readiness: 4)
        let excluded = makeSession(
            sessionDate: "2024-09-09",
            intervalMinutes: 172,
            sleepQuality: 4,
            readiness: 4,
            context: InsightSessionContext(
                nextMorningWeekdayIndex: 2,
                nextMorningIsWeekend: false,
                scheduledWakeByUTC: ISO8601DateFormatter().date(from: "2024-09-10T08:00:00Z"),
                scheduledWakeMinutesAfterMidnight: 480,
                scheduleDayType: "worklike",
                previousScheduleDayType: "offlike",
                nextScheduleDayType: "worklike",
                alarm: nil,
                dose2Outcome: InsightDose2OutcomeContext(
                    takenSource: "manual",
                    takenAmountMg: 4500,
                    takenEarly: false,
                    takenLate: false,
                    liveTakenReason: "ate_too_late",
                    liveTakenReasonNotes: nil,
                    morningTakenReason: "pain_disruption",
                    morningTakenReasonNotes: nil,
                    takenReason: "pain_disruption",
                    takenReasonNotes: nil,
                    hasExtraDose: false,
                    liveSkipReason: nil,
                    liveSkipReasonNotes: nil,
                    morningSkipReason: nil,
                    morningSkipReasonNotes: nil,
                    skipReason: nil,
                    skipReasonNotes: nil,
                    skipSource: nil,
                    reasonMismatch: true
                ),
                wakeSignal: "likely_natural",
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

        let result = engine.recommend(sessions: [matched, excluded], mode: .restfulSleep)

        XCTAssertEqual(result.excludedNights.count, 1)
        XCTAssertEqual(result.excludedNights.first?.sessionDate, "2024-09-09")
        XCTAssertTrue(result.excludedNights.first?.exclusionReasons.contains("Dose 2 reason mismatch between live and morning logs") == true)
    }

    func testRestfulSleepScoringUsesBiometricBands() {
        let engine = InsightRecommendationEngine()
        let sessions = [
            makeSession(
                sessionDate: "2024-09-08",
                intervalMinutes: 160,
                sleepQuality: 4,
                readiness: 4,
                healthKit: InsightHealthKitSummary(
                    totalSleepMinutes: 430,
                    ttfwMinutes: 165,
                    wakeCount: 2,
                    coreSleepMinutes: 250,
                    deepSleepMinutes: 55,
                    remSleepMinutes: 65,
                    bedTimeUTC: ISO8601DateFormatter().date(from: "2024-09-08T22:00:00Z"),
                    sleepOnsetUTC: ISO8601DateFormatter().date(from: "2024-09-08T22:10:00Z"),
                    finalWakeUTC: ISO8601DateFormatter().date(from: "2024-09-09T07:20:00Z"),
                    averageHeartRate: 61,
                    respiratoryRate: 15.4,
                    hrvMs: 36,
                    restingHeartRate: 59,
                    sources: ["Apple Watch"]
                )
            ),
            makeSession(
                sessionDate: "2024-09-09",
                intervalMinutes: 162,
                sleepQuality: 4,
                readiness: 4,
                healthKit: InsightHealthKitSummary(
                    totalSleepMinutes: 425,
                    ttfwMinutes: 160,
                    wakeCount: 2,
                    coreSleepMinutes: 248,
                    deepSleepMinutes: 56,
                    remSleepMinutes: 64,
                    bedTimeUTC: ISO8601DateFormatter().date(from: "2024-09-09T22:00:00Z"),
                    sleepOnsetUTC: ISO8601DateFormatter().date(from: "2024-09-09T22:08:00Z"),
                    finalWakeUTC: ISO8601DateFormatter().date(from: "2024-09-10T07:18:00Z"),
                    averageHeartRate: 60,
                    respiratoryRate: 15.2,
                    hrvMs: 38,
                    restingHeartRate: 58,
                    sources: ["Apple Watch"]
                )
            ),
            makeSession(
                sessionDate: "2024-09-10",
                intervalMinutes: 170,
                sleepQuality: 4,
                readiness: 4,
                healthKit: InsightHealthKitSummary(
                    totalSleepMinutes: 440,
                    ttfwMinutes: 170,
                    wakeCount: 1,
                    coreSleepMinutes: 240,
                    deepSleepMinutes: 70,
                    remSleepMinutes: 80,
                    bedTimeUTC: ISO8601DateFormatter().date(from: "2024-09-10T22:00:00Z"),
                    sleepOnsetUTC: ISO8601DateFormatter().date(from: "2024-09-10T22:09:00Z"),
                    finalWakeUTC: ISO8601DateFormatter().date(from: "2024-09-11T07:25:00Z"),
                    averageHeartRate: 58,
                    respiratoryRate: 13.8,
                    hrvMs: 54,
                    restingHeartRate: 53,
                    sources: ["Apple Watch"]
                )
            ),
            makeSession(
                sessionDate: "2024-09-11",
                intervalMinutes: 172,
                sleepQuality: 4,
                readiness: 4,
                healthKit: InsightHealthKitSummary(
                    totalSleepMinutes: 445,
                    ttfwMinutes: 168,
                    wakeCount: 1,
                    coreSleepMinutes: 238,
                    deepSleepMinutes: 72,
                    remSleepMinutes: 82,
                    bedTimeUTC: ISO8601DateFormatter().date(from: "2024-09-11T22:00:00Z"),
                    sleepOnsetUTC: ISO8601DateFormatter().date(from: "2024-09-11T22:07:00Z"),
                    finalWakeUTC: ISO8601DateFormatter().date(from: "2024-09-12T07:26:00Z"),
                    averageHeartRate: 58,
                    respiratoryRate: 13.7,
                    hrvMs: 56,
                    restingHeartRate: 52,
                    sources: ["Apple Watch"]
                )
            )
        ]

        let result = engine.recommend(sessions: sessions, mode: .restfulSleep)

        XCTAssertEqual(result.recommendedBand?.label, "166-180")
        XCTAssertTrue(result.topFactors.contains { $0.contains("HRV") || $0.contains("resting HR") || $0.contains("respiratory rate") || $0.contains("sleep-stage balance") })
        XCTAssertTrue(result.candidates.contains { $0.band.label == "166-180" && ($0.averageHRV ?? 0) > 50 && ($0.averageSleepStageBalance ?? 0) > 0.8 })
    }

    func testRecommendationNeverLeavesPrescribedWindow() {
        let engine = InsightRecommendationEngine()
        let sessions = [
            makeSession(sessionDate: "2024-09-08", intervalMinutes: 160, sleepQuality: 4, readiness: 4),
            makeSession(sessionDate: "2024-09-09", intervalMinutes: 172, sleepQuality: 5, readiness: 5),
            makeSession(sessionDate: "2024-09-10", intervalMinutes: 174, sleepQuality: 4, readiness: 4),
            makeSession(sessionDate: "2024-09-11", intervalMinutes: 225, sleepQuality: 2, readiness: 2),
            makeSession(sessionDate: "2024-09-12", intervalMinutes: 260, sleepQuality: 5, readiness: 5)
        ]

        let result = engine.recommend(sessions: sessions, mode: .restfulSleep)
        guard let recommendedBand = result.recommendedBand else {
            XCTFail("Expected a bounded recommendation")
            return
        }

        XCTAssertTrue(InsightRecommendationEngine.defaultBands.contains { $0.label == recommendedBand.label })
        XCTAssertGreaterThanOrEqual(recommendedBand.minMinutes, 150)
        XCTAssertLessThanOrEqual(recommendedBand.maxMinutes, 240)
    }

    func testWorkNightSafetyTracksAlarmDependenceAndSkipLateRiskByBand() {
        let engine = InsightRecommendationEngine()
        let formatter = ISO8601DateFormatter()

        func workNight(sessionDate: String, intervalMinutes: Int, readiness: Int = 4, drivingConfidence: Int = 4, daytimeSleepiness: Int = 2) -> InsightSession {
            let dose1 = formatter.date(from: "\(sessionDate)T22:00:00Z")!
            let dose2 = dose1.addingTimeInterval(TimeInterval(intervalMinutes * 60))

            return InsightSession(
                id: sessionDate,
                sessionDate: sessionDate,
                startedAt: dose1,
                endedAt: dose2,
                dose1Time: dose1,
                dose2Time: dose2,
                dose2Skipped: false,
                snoozeCount: 1,
                adherenceFlag: "ok",
                sleepEfficiency: 88,
                whoopRecovery: 76,
                averageHeartRate: 60,
                notes: nil,
                events: [],
                preSleep: InsightPreSleepSummary(
                    sessionId: sessionDate,
                    completionState: "complete",
                    loggedAtUTC: "\(sessionDate)T21:25:00Z",
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
                ),
                morning: InsightMorningSummary(
                    submittedAtUTC: dose2.addingTimeInterval(8 * 60 * 60),
                    sleepQuality: 4,
                    feelRested: "mostly",
                    grogginess: "mild",
                    sleepInertiaDuration: "5-15 minutes",
                    dreamRecall: "some",
                    mentalClarity: readiness,
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
                    drivingConfidence: drivingConfidence,
                    daytimeSleepiness: daytimeSleepiness,
                    cataplexyBurden: "mild",
                    notes: nil
                ),
                medications: [],
                context: InsightSessionContext(
                    nextMorningWeekdayIndex: 2,
                    nextMorningIsWeekend: false,
                    scheduledWakeByUTC: dose2.addingTimeInterval(8 * 60 * 60),
                    scheduledWakeMinutesAfterMidnight: 420,
                    scheduleDayType: "worklike",
                    previousScheduleDayType: "worklike",
                    nextScheduleDayType: "worklike",
                    explicitNightType: "work_night",
                    explicitWakeType: "alarm",
                    explicitNextDayDemand: "shift_13h",
                    explicitDose2WakeMethod: "alarm",
                    alarm: InsightAlarmContext(
                        scheduledForUTC: dose2,
                        firstFireAtUTC: dose2,
                        acknowledgedAtUTC: dose2.addingTimeInterval(60),
                        acknowledgementAction: "open",
                        followUpDeliveredCount: 1
                    ),
                    wakeSignal: "alarm_assisted",
                    wakeFinalLoggedAtUTC: dose2.addingTimeInterval(6 * 60 * 60),
                    snoozeCount: 1,
                    scheduleMarkers: [],
                    wakeRequirement: "work",
                    commuteMinutes: 50,
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
                healthKit: InsightHealthKitSummary(
                    totalSleepMinutes: 430,
                    ttfwMinutes: 170,
                    wakeCount: 1,
                    coreSleepMinutes: 245,
                    deepSleepMinutes: 65,
                    remSleepMinutes: 78,
                    bedTimeUTC: dose1,
                    sleepOnsetUTC: dose1.addingTimeInterval(10 * 60),
                    finalWakeUTC: dose2.addingTimeInterval(7 * 60 * 60),
                    averageHeartRate: 60,
                    respiratoryRate: 14,
                    hrvMs: 48,
                    restingHeartRate: 54,
                    sources: ["Apple Watch"]
                )
            )
        }

        func skippedWorkNight(sessionDate: String, scheduledIntervalMinutes: Int) -> InsightSession {
            let dose1 = formatter.date(from: "\(sessionDate)T22:00:00Z")!
            let scheduled = dose1.addingTimeInterval(TimeInterval(scheduledIntervalMinutes * 60))

            return InsightSession(
                id: sessionDate,
                sessionDate: sessionDate,
                startedAt: dose1,
                endedAt: nil,
                dose1Time: dose1,
                dose2Time: nil,
                dose2Skipped: true,
                snoozeCount: 2,
                adherenceFlag: "missed",
                sleepEfficiency: nil,
                whoopRecovery: nil,
                averageHeartRate: nil,
                notes: nil,
                events: [],
                preSleep: nil,
                morning: InsightMorningSummary(
                    submittedAtUTC: scheduled.addingTimeInterval(7 * 60 * 60),
                    sleepQuality: 2,
                    feelRested: "not_really",
                    grogginess: "high",
                    sleepInertiaDuration: "30-60 minutes",
                    dreamRecall: "none",
                    mentalClarity: 2,
                    mood: "flat",
                    anxietyLevel: "moderate",
                    stressLevel: 3,
                    stressDrivers: ["work"],
                    readinessForDay: 2,
                    hadSleepParalysis: false,
                    hadHallucinations: false,
                    hadAutomaticBehavior: false,
                    fellOutOfBed: false,
                    hadConfusionOnWaking: false,
                    drivingConfidence: 2,
                    daytimeSleepiness: 4,
                    cataplexyBurden: "moderate",
                    notes: nil
                ),
                medications: [],
                context: InsightSessionContext(
                    nextMorningWeekdayIndex: 2,
                    nextMorningIsWeekend: false,
                    scheduledWakeByUTC: scheduled.addingTimeInterval(8 * 60 * 60),
                    scheduledWakeMinutesAfterMidnight: 420,
                    scheduleDayType: "worklike",
                    previousScheduleDayType: "worklike",
                    nextScheduleDayType: "worklike",
                    explicitNightType: "work_night",
                    explicitWakeType: "alarm",
                    explicitNextDayDemand: "shift_13h",
                    explicitDose2WakeMethod: "alarm",
                    alarm: InsightAlarmContext(
                        scheduledForUTC: scheduled,
                        firstFireAtUTC: scheduled,
                        acknowledgedAtUTC: scheduled.addingTimeInterval(5 * 60),
                        acknowledgementAction: "dismiss",
                        followUpDeliveredCount: 2
                    ),
                    dose2Outcome: InsightDose2OutcomeContext(
                        takenSource: nil,
                        takenAmountMg: nil,
                        takenEarly: false,
                        takenLate: false,
                        liveTakenReason: nil,
                        liveTakenReasonNotes: nil,
                        morningTakenReason: nil,
                        morningTakenReasonNotes: nil,
                        takenReason: nil,
                        takenReasonNotes: nil,
                        hasExtraDose: false,
                        liveSkipReason: "slept_through",
                        liveSkipReasonNotes: nil,
                        morningSkipReason: "slept_through",
                        morningSkipReasonNotes: nil,
                        skipReason: "slept_through",
                        skipReasonNotes: nil,
                        skipSource: "live",
                        reasonMismatch: false
                    ),
                    wakeSignal: "alarm_assisted",
                    wakeFinalLoggedAtUTC: scheduled.addingTimeInterval(6 * 60 * 60),
                    snoozeCount: 2,
                    scheduleMarkers: [],
                    wakeRequirement: "work",
                    commuteMinutes: 50,
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
        }

        let result = engine.recommend(
            sessions: [
                workNight(sessionDate: "2024-09-08", intervalMinutes: 170),
                workNight(sessionDate: "2024-09-09", intervalMinutes: 172),
                skippedWorkNight(sessionDate: "2024-09-10", scheduledIntervalMinutes: 171),
                workNight(sessionDate: "2024-09-11", intervalMinutes: 190),
                workNight(sessionDate: "2024-09-12", intervalMinutes: 192)
            ],
            mode: .workNightSafety
        )

        XCTAssertEqual(result.recommendedBand?.label, "181-210")
        guard let alarmBand = result.candidates.first(where: { $0.band.label == "166-180" }),
              let naturalBand = result.candidates.first(where: { $0.band.label == "181-210" }) else {
            XCTFail("Expected both timing bands in the comparison output")
            return
        }
        XCTAssertEqual(alarmBand.alarmDependenceRate ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(alarmBand.skipLateRiskRate ?? 0, 1.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(naturalBand.alarmDependenceRate ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(naturalBand.skipLateRiskRate ?? 1, 0.0, accuracy: 0.001)
        XCTAssertTrue(result.topFactors.contains { $0.contains("skip / late risk") })
    }

    private func makeSession(
        sessionDate: String,
        intervalMinutes: Int,
        sleepQuality: Int,
        readiness: Int,
        context: InsightSessionContext? = nil,
        healthKit: InsightHealthKitSummary? = nil,
        whoop: InsightWHOOPSummary? = nil
    ) -> InsightSession {
        let formatter = ISO8601DateFormatter()
        let dose1 = formatter.date(from: "\(sessionDate)T22:00:00Z")!
        let dose2 = dose1.addingTimeInterval(TimeInterval(intervalMinutes * 60))

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
            sleepEfficiency: 88,
            whoopRecovery: 74,
            averageHeartRate: 61,
            notes: nil,
            events: [],
            preSleep: InsightPreSleepSummary(
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
            ),
            morning: InsightMorningSummary(
                submittedAtUTC: dose2.addingTimeInterval(8 * 60 * 60),
                sleepQuality: Double(sleepQuality),
                feelRested: "mostly",
                grogginess: "mild",
                sleepInertiaDuration: "5-15 minutes",
                dreamRecall: "some",
                mentalClarity: readiness,
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
            context: context ?? InsightSessionContext(
                nextMorningWeekdayIndex: 2,
                nextMorningIsWeekend: false,
                scheduledWakeByUTC: dose2.addingTimeInterval(8 * 60 * 60),
                scheduledWakeMinutesAfterMidnight: 390,
                scheduleDayType: "worklike",
                previousScheduleDayType: "offlike",
                nextScheduleDayType: "worklike",
                wakeSignal: "likely_natural",
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
            healthKit: healthKit,
            whoop: whoop
        )
    }
}
