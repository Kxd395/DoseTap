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

    private func night(_ key: String, dose1: Date? = nil, interval: Double? = 180, skipped: Bool = false) -> DashboardNightAggregate {
        let first = dose1 ?? date("2026-09-01")
        return DashboardNightAggregate(sessionDate: key, dose1Time: first,
            dose2Time: interval.map { first.addingTimeInterval($0 * 60) }, dose2Skipped: skipped,
            snoozeCount: 0, extraDoseCount: 0, events: [], morningCheckIn: nil, preSleepLog: nil,
            healthSummary: nil, whoopSummary: nil, duplicateClusterCount: 0,
            napSummary: .init(count: 0, totalMinutes: 0))
    }
}
