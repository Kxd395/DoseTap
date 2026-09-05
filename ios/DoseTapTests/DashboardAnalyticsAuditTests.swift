import XCTest
@testable import DoseTap
import DoseCore

@MainActor
final class DashboardAnalyticsAuditTests: XCTestCase {
    private func date(_ key: String) -> Date { AppFormatters.sessionDate.date(from: key)! }

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
        XCTAssertEqual(WHOOPService.makeNightSummaries(sleeps: sleeps, recoveries: []).map(\.sleepId), ["night"])
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

    private func night(_ key: String, dose1: Date? = nil, interval: Double? = 180, skipped: Bool = false, answers: DoseTap.PreSleepLogAnswers? = nil, completion: String = "complete", health: HealthKitService.SleepNightSummary? = nil, quality: Double? = nil) -> DashboardNightAggregate {
        let first = dose1 ?? date("2026-09-01")
        return DashboardNightAggregate(sessionDate: key, dose1Time: first,
            dose2Time: interval.map { first.addingTimeInterval($0 * 60) }, dose2Skipped: skipped,
            snoozeCount: 0, extraDoseCount: 0, events: [], morningCheckIn: quality.map { .init(id: key, sessionId: key, timestamp: first, sessionDate: key, sleepQuality: $0) }, preSleepLog: answers.map { .init(id: key, sessionId: key, createdAtUtc: "", localOffsetMinutes: 0, completionState: completion, answers: $0) },
            healthSummary: health, whoopSummary: nil, duplicateClusterCount: 0,
            napSummary: .init(count: 0, totalMinutes: 0))
    }
}
