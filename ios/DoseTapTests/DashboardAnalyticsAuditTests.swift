import XCTest
@testable import DoseTap
import DoseCore

@MainActor
final class DashboardAnalyticsAuditTests: XCTestCase {
    func testFoodAnalyticsUseCompletedLogsExplicitDaysAndIndependentCounts() {
        let first = date("2026-09-01")
        var answers = DoseTap.PreSleepLogAnswers()
        answers.lastFood = .init(finishedAt: first.addingTimeInterval(-7199), highFat: true)
        var yes = night("2026-09-01", answers: answers)
        var diary = NightOutcomeDiary(); diary.dayType = .dayOff; diary.sleepiness = 0; yes.outcome = diary
        let model = DashboardAnalyticsModel(); model.selectedRange = .all
        model.nights = [yes, night("2026-09-02", answers: answers, completion: "partial"), night("2026-09-03")]
        XCTAssertEqual(model.foodDiaryAnalytics().food.count, 1)
        XCTAssertEqual(model.foodDiaryAnalytics().missingFoodCount, 2)
        XCTAssertEqual(model.foodDiaryAnalytics().interval(dose: 1).median!, 7199 / 60.0, accuracy: 0.001)
        XCTAssertEqual(model.foodDiaryAnalytics(day: .dayOff).nightCount, 1)
        XCTAssertEqual(model.foodDiaryAnalytics().sleepiness(highFat: true).median, 0)
        model.sleepSource = .whoop
        XCTAssertEqual(model.foodDiaryAnalytics().sleepAfterDose2(highFat: true).count, 0)
    }

    func testWakeComparisonUsesIndependentCountsExplicitDayAndNoProviderSubstitution() {
        let model = DashboardAnalyticsModel(now: { self.date("2026-09-07").addingTimeInterval(22 * 3600) })
        model.selectedRange = .all
        var natural = night("2026-09-01")
        var diary = NightOutcomeDiary(); diary.wakeMethod = .natural; diary.backupAlarmSet = true
        diary.dayType = .dayOff; diary.sleepiness = 0; diary.assessedAt = date("2026-09-02")
        natural.outcome = diary
        var alarm = night("2026-09-02"); diary.wakeMethod = .alarm; diary.sleepiness = nil; diary.assessedAt = nil
        diary.dayType = .workday; alarm.outcome = diary
        model.nights = [natural, alarm, night("2026-09-03", interval: nil, skipped: true)]
        XCTAssertEqual(model.wakeComparisonNights(day: .dayOff).count, 1)
        XCTAssertEqual(model.wakeMetric(.sleepiness, kind: .natural, day: nil).median, 0)
        XCTAssertEqual(model.wakeMetric(.sleepiness, kind: .alarm, day: nil).count, 0)
        XCTAssertEqual(model.wakeMetric(.interval, kind: .alarm, day: nil).count, 1)
        XCTAssertEqual(model.wakeMetric(.totalSleep, kind: .natural, day: nil).count, 0)
        XCTAssertEqual(natural.effectiveWakeMethod, .natural, "A backup alarm does not reclassify natural waking")
        model.sleepSource = .whoop
        XCTAssertEqual(model.wakeMetric(.sleepAfterDose2, kind: .natural, day: nil).count, 0)
        XCTAssertEqual(model.skippedDose2Count, 1)
    }

    private func date(_ key: String) -> Date { AppFormatters.sessionDate.date(from: key)! }

    func testPostDoseEstimateUsesMeasuredStagesAndSelectedProviderOnly() throws {
        let start = date("2026-09-01")
        func segment(_ a: Double, _ b: Double, _ stage: HealthKitService.SleepStage) -> HealthKitService.SleepSegment {
            .init(start: start.addingTimeInterval(a * 60), end: start.addingTimeInterval(b * 60), stage: stage, source: "Test Watch")
        }
        let health = try XCTUnwrap(HealthKitService.sleepNightSummary(from: [segment(0, 300, .asleepCore),
            segment(300, 320, .awake), segment(320, 600, .asleepREM)], nightStart: start))
        var observed = night("2026-09-01", health: health)
        var answers = NightOutcomeDiary(); answers.wakeMethod = .natural; observed.outcome = answers
        XCTAssertEqual(observed.postDoseSleep?.asleepMinutes, 400)
        XCTAssertEqual(observed.postDoseSleep?.coveredMinutes, 420)
        let model = DashboardAnalyticsModel(); model.selectedRange = .all; model.nights = [observed]
        XCTAssertEqual(model.wakeMetric(.sleepAfterDose2, kind: .natural, day: nil).count, 1)
        model.sleepSource = .whoop
        XCTAssertEqual(model.wakeMetric(.sleepAfterDose2, kind: .natural, day: nil).count, 0)
    }

    func testRangeIncludesFirstCivilNightAndExcludesFutureAndMalformedKeys() {
        let model = DashboardAnalyticsModel(now: { self.date("2026-09-04").addingTimeInterval(22 * 3600) })
        model.selectedRange = .week
        model.nights = ["2026-08-28", "2026-08-29", "2026-09-04", "2026-09-05", "invalid"].map { night($0) }
        XCTAssertEqual(model.populatedNights.map(\.sessionDate), ["2026-09-04", "2026-08-29"])
        XCTAssertEqual(model.priorPeriodNights.map(\.sessionDate), ["2026-08-28"])
    }

    func testMorningKeepsPreviousEveningAsCurrentNight() {
        let model = DashboardAnalyticsModel(now: { self.date("2026-09-05").addingTimeInterval(7 * 3600) })
        model.selectedRange = .week
        model.nights = [night("2026-08-29"), night("2026-09-05")]
        XCTAssertEqual(model.populatedNights.map(\.sessionDate), ["2026-08-29"])
    }

    func testCivilRangeAcrossSpringAndFallDST() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        for components in [DateComponents(year: 2026, month: 3, day: 10), DateComponents(year: 2026, month: 11, day: 3)] {
            let anchor = calendar.date(from: components)!.addingTimeInterval(22 * 3600)
            let start = DashboardDateRange.week.cutoffDate(from: anchor, calendar: calendar)
            XCTAssertEqual(calendar.component(.hour, from: start), 0)
            XCTAssertEqual(calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: anchor)).day, 6)
            let prior = DashboardDateRange.week.priorPeriodCutoff(from: anchor, calendar: calendar)
            XCTAssertEqual(prior.end, start)
            XCTAssertEqual(calendar.dateComponents([.day], from: prior.start, to: prior.end).day, 7)
        }
    }

    func testPendingMissingSkippedAndInvalidIntervalsHaveDistinctDenominators() {
        let current = date("2026-09-04").addingTimeInterval(23 * 3600)
        let model = DashboardAnalyticsModel(now: { current })
        model.selectedRange = .all
        model.nights = [night("2026-09-04", dose1: current.addingTimeInterval(-3600), interval: nil),
                        night("2026-09-03", interval: nil), night("2026-09-02", interval: nil, skipped: true),
                        night("2026-09-01", interval: -10), night("2026-08-31", interval: 239.9)]
        XCTAssertEqual(model.pendingDose2OutcomeCount, 1)
        XCTAssertEqual(model.missingDose2OutcomeCount, 1)
        XCTAssertEqual(model.eligibleDose2OutcomeCount, 4)
        XCTAssertEqual(model.completionRate, 75)
        XCTAssertEqual(model.onTimePercentage, 100)
        XCTAssertEqual(model.averageIntervalMinutes ?? 0, 239.9, accuracy: 0.001)
        XCTAssertEqual(model.doseEffectivenessReport.totalNights, 1)
    }

    func testCanonicalDoseProjectionDoesNotInventDose1() {
        let timestamp = date("2026-09-01")
        let orphan = StoredDoseEvent(id: "orphan", eventType: "dose_2_(late)", timestamp: timestamp, sessionDate: "2026-09-01")
        let extra = StoredDoseEvent(id: "extra", eventType: "dose_3_taken", timestamp: timestamp, sessionDate: "2026-09-01")
        let result = DashboardAnalyticsModel.deriveDoseMetrics(from: [extra, orphan])
        XCTAssertNil(result.dose1Time)
        XCTAssertEqual(result.dose2Time, timestamp)
        XCTAssertEqual(result.extraDoseCount, 1)
        XCTAssertEqual(result.snoozeCount, 0)
    }

    func testAllTimeRefreshIncludesOldLocalRecordsWithoutSyntheticEmptyNights() async {
        let storage = EventStorage.inMemory()
        let repository = SessionRepository(storage: storage)
        storage.insertDoseEvent(eventType: "dose1", timestamp: date("2020-01-01"), sessionKey: "2020-01-01", metadata: nil)
        let model = DashboardAnalyticsModel(sessionRepo: repository)
        model.selectedRange = .all
        await model.performRefresh(days: 730, includeProviders: false)
        XCTAssertTrue(model.populatedNights.contains { $0.sessionDate == "2020-01-01" })
        XCTAssertLessThan(model.nights.count, 3)
        XCTAssertFalse(model.isLoading)
    }

    func testWHOOPNightSummariesExcludeNapsAndUndatedRecords() throws {
        let json = #"[{"id":"nap","nap":true,"start":"2026-09-01T20:00:00Z","score":{"stage_summary":{"total_light_sleep_time_milli":600000}}},{"id":"undated","score":{"stage_summary":{"total_light_sleep_time_milli":600000}}},{"id":"night","nap":false,"start":"2026-09-01T23:00:00Z","score":{"stage_summary":{"total_light_sleep_time_milli":600000}}}]"#
        let sleeps = try WHOOPService.makeAPIDecoder().decode([WHOOPSleep].self, from: Data(json.utf8))
        let summaries = WHOOPService.makeNightSummaries(sleeps: sleeps, recoveries: [])
        XCTAssertEqual(summaries.map(\.sleepId), ["night"])
        let partial = try XCTUnwrap(summaries.first)
        XCTAssertFalse(partial.hasCompleteSleepStages)
        XCTAssertFalse(partial.hasAwakeData)
        XCTAssertFalse(partial.hasDisturbanceData)
        let model = DashboardAnalyticsModel()
        model.selectedRange = .all
        model.nights = [night("2026-09-01", whoop: partial)]
        XCTAssertNil(model.averageWhoopSleepMinutes)
        XCTAssertNil(model.averageWhoopDeepMinutes)
        XCTAssertNil(model.averageWhoopLightMinutes)
        XCTAssertNil(model.averageWhoopAwakeMinutes)
        XCTAssertNil(model.averageWhoopDisturbances)
    }

    func testUnansweredLifestyleFieldsAndSkippedLogsAreNotNegativeAnswers() {
        let model = DashboardAnalyticsModel()
        model.selectedRange = .all
        model.nights = [night("2026-09-01", answers: .init(stressLevel: 3), quality: 1),
                        night("2026-09-02", answers: .init(stimulants: .coffee, alcohol: .one), quality: 4),
                        night("2026-09-03", answers: .init(stimulants: DoseTap.PreSleepLogAnswers.Stimulants.none, alcohol: DoseTap.PreSleepLogAnswers.AlcoholLevel.none), completion: "skipped", quality: 5),
                        night("2026-09-04", answers: .init(stimulants: DoseTap.PreSleepLogAnswers.Stimulants.none, alcohol: DoseTap.PreSleepLogAnswers.AlcoholLevel.none), quality: 2)]
        XCTAssertEqual(model.caffeineRate, 50)
        XCTAssertEqual(model.alcoholRate, 50)
        XCTAssertNil(model.screenTimeRate)
        XCTAssertEqual(model.sleepQualityByAlcohol.without, 2)
        XCTAssertEqual(model.preSleepLogRate ?? 0, 75, accuracy: 0.001)
    }

    func testSleepSourceChoiceNeverFallsBackToAnotherProvider() {
        let model = DashboardAnalyticsModel()
        model.selectedRange = .all
        let health = HealthKitService.SleepNightSummary(date: date("2026-09-01"), bedTime: nil, sleepOnset: nil,
            firstWake: nil, finalWake: nil, ttfwMinutes: nil, totalSleepMinutes: 420, wakeCount: 0, source: "fixture")
        model.nights = [night("2026-09-01", health: health)]
        model.sleepSource = .appleHealth
        XCTAssertEqual(model.averageSleepMinutes, 420)
        model.sleepSource = .whoop
        XCTAssertNil(model.averageSleepMinutes)
        XCTAssertEqual(model.sleepSampleCount, 0)
    }

    func testWeekdayChartKeepsRealZeroAndOmitsUnobservedWeekdays() {
        let model = DashboardAnalyticsModel()
        model.selectedRange = .all
        model.nights = [night("2026-09-01", interval: 260)]
        XCTAssertEqual(model.weekdayTimingValues.count, 1)
        XCTAssertEqual(model.weekdayTimingValues.first?.value, 0)
        XCTAssertEqual(model.weekdayTimingValues.first?.count, 1)
        XCTAssertTrue(model.screenSleepValues.isEmpty)
    }

    func testTonightWeekUsesSevenFinishedNightsAndNeverCountsOrphanDose2() {
        let first = date("2026-08-29")
        let valid = DoseTap.SessionSummary(sessionDate: "2026-08-29", dose1Time: first, dose2Time: first.addingTimeInterval(180 * 60))
        let orphan = DoseTap.SessionSummary(sessionDate: "2026-09-01", dose2Time: date("2026-09-01"))
        let old = DoseTap.SessionSummary(sessionDate: "2020-01-01", dose1Time: date("2020-01-01"))
        let result = WeeklyRecordedDoseMetrics(sessions: [valid, orphan, old, DoseTap.SessionSummary(sessionDate: "2026-09-05")], currentNight: "2026-09-05")
        XCTAssertEqual(result.sessions.count, 2)
        XCTAssertEqual(result.tracked, 1)
        XCTAssertEqual(result.recorded, 1)
        XCTAssertEqual(result.missing, 0)
    }

    func testRateComparisonsUsePercentagePointsIncludingZeroBaseline() {
        let rate = DashboardAnalyticsModel.PeriodDelta(metricName: "Recorded On-Time %", current: 75, prior: 50)
        XCTAssertEqual(rate.delta, 25)
        XCTAssertEqual(rate.deltaUnit, "pp")
        let zero = DashboardAnalyticsModel.PeriodDelta(metricName: "Recorded On-Time %", current: 25, prior: 0)
        XCTAssertEqual(zero.delta, 25)
        XCTAssertNil(DashboardAnalyticsModel.PeriodDelta(metricName: "Avg Interval", current: 180, prior: 0).delta)
    }

    func testRecordedPairTakesPrecedenceOverHistoricalSkipInTimingComparison() {
        let model = DashboardAnalyticsModel()
        model.selectedRange = .all
        model.nights = [night("2026-09-01", interval: 180, skipped: true)]
        XCTAssertEqual(model.onTimePercentage, 100)
        XCTAssertEqual(model.skippedDose2Count, 0)
        XCTAssertEqual(model.doseEffectivenessReport.acceptableZone.count, 1)
        XCTAssertEqual(model.doseEffectivenessReport.nonCompliant.count, 0)
    }

    func testFinishedNightStreakStopsAtGapsAndIgnoresActiveNight() {
        let model = DashboardAnalyticsModel(now: { self.date("2026-09-05").addingTimeInterval(22 * 3600) })
        model.selectedRange = .week
        model.nights = [night("2026-09-05", interval: nil), night("2026-09-04"), night("2026-09-03"), night("2026-09-01")]
        XCTAssertEqual(model.finishedNightStreak, 2)
        model.nights.removeAll { $0.sessionDate == "2026-09-04" }
        XCTAssertEqual(model.finishedNightStreak, 0)
        model.nights = (1...10).map { offset in
            night(AppFormatters.sessionDate.string(from: Calendar.current.date(byAdding: .day, value: -offset, to: date("2026-09-05"))!))
        }
        XCTAssertEqual(model.finishedNightStreak, 6, "The current selected night is not finished")
        model.selectedRange = .all
        XCTAssertEqual(model.finishedNightStreak, 10)
        model.nights[0] = night("2026-09-04", interval: 240)
        XCTAssertEqual(model.finishedNightStreak, 10)
        model.nights[0] = night("2026-09-04", interval: 240.001)
        XCTAssertEqual(model.finishedNightStreak, 0)
    }

    func testNightCoverageCountsCompletedCategoriesWithoutCallingThemConfidence() {
        let partial = night("2026-09-01", interval: nil, answers: .init(stressLevel: 3), completion: "skipped")
        XCTAssertEqual(partial.dataCategoryCount, 0)
        let recorded = night("2026-09-01", answers: .init(stressLevel: 3), quality: 4)
        XCTAssertEqual(recorded.dataCategoryCount, 3)
        XCTAssertEqual(recorded.dataCompletenessScore, 0.75)
    }

    private func night(_ key: String, dose1: Date? = nil, interval: Double? = 180, skipped: Bool = false, answers: DoseTap.PreSleepLogAnswers? = nil, completion: String = "complete", health: HealthKitService.SleepNightSummary? = nil, quality: Double? = nil, whoop: WHOOPNightSummary? = nil) -> DashboardNightAggregate {
        let first = dose1 ?? date("2026-09-01")
        return DashboardNightAggregate(sessionDate: key, dose1Time: first,
            dose2Time: interval.map { first.addingTimeInterval($0 * 60) }, dose2Skipped: skipped,
            snoozeCount: 0, extraDoseCount: 0, events: [], morningCheckIn: quality.map { .init(id: key, sessionId: key, timestamp: first, sessionDate: key, sleepQuality: $0) }, preSleepLog: answers.map { .init(id: key, sessionId: key, createdAtUtc: "", localOffsetMinutes: 0, completionState: completion, answers: $0) },
            healthSummary: health, whoopSummary: whoop, duplicateClusterCount: 0,
            napSummary: .init(count: 0, totalMinutes: 0))
    }
}
