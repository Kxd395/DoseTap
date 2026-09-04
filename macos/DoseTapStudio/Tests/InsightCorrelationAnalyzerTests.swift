import XCTest
@testable import DoseTapStudio

final class InsightCorrelationAnalyzerTests: XCTestCase {
    func testSegmentsByNightTypeSummarizeCountsAndAverages() {
        let analyzer = InsightCorrelationAnalyzer()
        let sessions = [
            makeSession(sessionDate: "2024-09-08", nightType: "work_night", wakeType: "natural", interval: 165, sleepQuality: 4, readiness: 4, trainable: true),
            makeSession(sessionDate: "2024-09-09", nightType: "work_night", wakeType: "alarm", interval: 170, sleepQuality: 5, readiness: 4, trainable: false),
            makeSession(sessionDate: "2024-09-10", nightType: "off_night", wakeType: "natural", interval: 180, sleepQuality: 3, readiness: 5, trainable: true)
        ]

        let segments = analyzer.segmentsByNightType(sessions: sessions)

        let workSegment = segments.first(where: { $0.title == InsightNightTypeFilter.work.rawValue })
        XCTAssertEqual(workSegment?.sessionCount, 2)
        XCTAssertEqual(workSegment?.trainableCount, 1)
        XCTAssertEqual(workSegment?.excludedCount, 1)
        XCTAssertEqual(workSegment?.averageIntervalMinutes, 167.5)
        XCTAssertEqual(workSegment?.averageSleepQuality, 4.5)
    }

    func testSegmentsByWakeTypeGroupNaturalAndAlarmPatterns() {
        let analyzer = InsightCorrelationAnalyzer()
        let sessions = [
            makeSession(sessionDate: "2024-09-08", nightType: "work_night", wakeType: "natural", interval: 165, sleepQuality: 4, readiness: 4, trainable: true),
            makeSession(sessionDate: "2024-09-09", nightType: "work_night", wakeType: "alarm", interval: 175, sleepQuality: 2, readiness: 3, trainable: true),
            makeSession(sessionDate: "2024-09-10", nightType: "off_night", wakeType: "alarm_then_snooze", interval: 178, sleepQuality: 3, readiness: 3, trainable: false)
        ]

        let segments = analyzer.segmentsByWakeType(sessions: sessions)

        let natural = segments.first(where: { $0.title == InsightWakeTypeFilter.natural.rawValue })
        XCTAssertEqual(natural?.sessionCount, 1)
        XCTAssertEqual(natural?.averageReadiness, 4)

        let alarm = segments.first(where: { $0.title == InsightWakeTypeFilter.alarm.rawValue })
        XCTAssertEqual(alarm?.sessionCount, 2)
        XCTAssertEqual(alarm?.excludedCount, 1)
        XCTAssertEqual(alarm?.averageIntervalMinutes, 176.5)
    }

    func testSegmentsByWorkSafetyAndClinicalContextExposeDrivingAndSleepiness() {
        let analyzer = InsightCorrelationAnalyzer()
        let sessions = [
            makeSession(
                sessionDate: "2024-09-08",
                nightType: "work_night",
                wakeType: "alarm",
                interval: 170,
                sleepQuality: 4,
                readiness: 4,
                trainable: true,
                wakeRequirement: "work",
                drivingConfidence: 2,
                daytimeSleepiness: 4,
                sleepDisorders: ["narcolepsy"],
                sleepTherapyDevice: "cpap",
                fastMetabolizer: true
            ),
            makeSession(
                sessionDate: "2024-09-09",
                nightType: "off_night",
                wakeType: "natural",
                interval: 175,
                sleepQuality: 4,
                readiness: 5,
                trainable: true
            )
        ]

        let workSafety = analyzer.segmentsByWorkSafetyContext(sessions: sessions)
        let clinical = analyzer.segmentsByClinicalContext(sessions: sessions)

        XCTAssertEqual(workSafety.first(where: { $0.title == "Work / Safety Context" })?.sessionCount, 1)
        XCTAssertEqual(workSafety.first(where: { $0.title == "Work / Safety Context" })?.averageDrivingConfidence, 2)
        XCTAssertEqual(workSafety.first(where: { $0.title == "Work / Safety Context" })?.averageDaytimeSleepiness, 4)
        XCTAssertEqual(clinical.first(where: { $0.title == "Clinical Context" })?.sessionCount, 1)
    }

    private func makeSession(
        sessionDate: String,
        nightType: String,
        wakeType: String,
        interval: Int,
        sleepQuality: Int,
        readiness: Int,
        trainable: Bool,
        wakeRequirement: String? = nil,
        drivingConfidence: Int? = nil,
        daytimeSleepiness: Int? = nil,
        sleepDisorders: [String] = [],
        sleepTherapyDevice: String? = nil,
        fastMetabolizer: Bool = false
    ) -> InsightSession {
        let formatter = ISO8601DateFormatter()
        let dose1 = formatter.date(from: "\(sessionDate)T22:00:00Z")!
        let dose2 = dose1.addingTimeInterval(TimeInterval(interval * 60))

        let morning = InsightMorningSummary(
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
                sleepTherapyDevice: sleepTherapyDevice,
                drivingConfidence: drivingConfidence,
                daytimeSleepiness: daytimeSleepiness,
                sleepDisorders: sleepDisorders,
                pharmacogenomicFastMetabolizer: fastMetabolizer,
                notes: nil
            )

        return InsightSession(
            id: sessionDate,
            sessionDate: sessionDate,
            startedAt: dose1,
            endedAt: dose2,
            dose1Time: dose1,
            dose2Time: dose2,
            dose2Skipped: false,
            snoozeCount: wakeType == "alarm_then_snooze" ? 1 : 0,
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
            morning: morning,
            medications: [],
            context: InsightSessionContext(
                nextMorningWeekdayIndex: 2,
                nextMorningIsWeekend: false,
                scheduledWakeByUTC: dose2.addingTimeInterval(8 * 60 * 60),
                scheduledWakeMinutesAfterMidnight: 420,
                scheduleDayType: nightType == "off_night" ? "offlike" : "worklike",
                previousScheduleDayType: "offlike",
                nextScheduleDayType: nightType == "off_night" ? "offlike" : "worklike",
                explicitNightType: nightType,
                explicitWakeType: wakeType,
                explicitNextDayDemand: wakeRequirement == "work" ? "shift_13h" : nil,
                dose2Outcome: trainable ? nil : InsightDose2OutcomeContext(
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
                wakeSignal: wakeType == "natural" ? "natural" : "alarm_assisted",
                wakeFinalLoggedAtUTC: dose2.addingTimeInterval(7 * 60 * 60),
                snoozeCount: wakeType == "alarm_then_snooze" ? 1 : 0,
                scheduleMarkers: [],
                wakeRequirement: wakeRequirement,
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
            ),
            whoop: nil,
            rawEvents: [],
            normalizedEvents: [],
            sourceAvailability: InsightSourceAvailability(
                doseEvents: true,
                sleepEvents: false,
                preSleep: true,
                morningCheckIn: true,
                medications: false,
                healthKit: true,
                whoop: false,
                alarmDiagnostics: wakeType != "natural"
            ),
            metricProvenance: ["sleep_efficiency": "healthkit"],
            validationFlags: []
        )
    }
}
