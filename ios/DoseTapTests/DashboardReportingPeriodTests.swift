import XCTest
import DoseCore
@testable import DoseTap

@MainActor
final class DashboardReportingPeriodTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/New_York")!
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func queries() -> DashboardProviderQueries {
        .init(healthEnabled: { true }, whoopEnabled: { false }, whoopConnected: { false },
            prepareHealth: { .ready }, healthHistory: { _ in [] },
            whoopHistory: { _, _ in .init(summaries: [], sleepRecordCount: 0, recoveryRecordCount: 0, recoveryStatus: .completed) })
    }
    private func model(_ reader: DashboardProviderQueries) -> DashboardAnalyticsModel {
        let clock = date("2026-09-30T20:00:00-04:00")
        return .init(now: { clock }, sessionRepo: SessionRepository(storage: .inMemory(), clock: { clock }),
                     timeZone: { self.zone }, providerAccess: DashboardProviderAccess(), providerQueries: reader)
    }

    func testHistoricalCustomCutoffIsSentToBothProviders() async throws {
        var healthWindow: DashboardReportingWindow?, whoopBounds: (Date, Date)?
        var reader = queries(); reader.whoopEnabled = { true }; reader.whoopConnected = { true }
        reader.healthHistory = { healthWindow = $0; return [] }
        reader.whoopHistory = { start, end in
            whoopBounds = (start, end)
            return .init(summaries: [], sleepRecordCount: 0, recoveryRecordCount: 0, recoveryStatus: .completed)
        }
        let model = model(reader), start = date("2026-03-07T18:00:00-05:00"), end = date("2026-03-10T18:00:00-04:00")
        model.customReportingRange = .custom(start: start, endExclusive: end); model.selectedRange = .custom
        await model.performRefresh(days: 730)
        XCTAssertEqual(healthWindow?.healthQueryStart, start)
        XCTAssertEqual(healthWindow?.healthQueryEnd, end)
        XCTAssertEqual(whoopBounds?.0, start); XCTAssertEqual(whoopBounds?.1, end)
        XCTAssertEqual(model.reportingPeriod?.endExclusive, end)
        XCTAssertEqual(model.currentReportWindow?.lastTreatmentDate, "2026-03-09")
        XCTAssertTrue(model.providerSnapshotIsCurrent(.health))
    }

    func testChangedCustomBoundsRejectInFlightPublication() async throws {
        let entered = expectation(description: "Captured old custom query")
        var continuation: CheckedContinuation<[HealthKitService.SleepNightSummary], Never>?
        var reader = queries()
        reader.healthHistory = { _ in await withCheckedContinuation { continuation = $0; entered.fulfill() } }
        let model = model(reader)
        model.customReportingRange = .custom(start: date("2026-03-07T18:00:00-05:00"), endExclusive: date("2026-03-10T18:00:00-04:00"))
        model.selectedRange = .custom
        let old = Task { await model.performRefresh(days: 730) }
        await fulfillment(of: [entered], timeout: 3)
        model.customReportingRange = .custom(start: date("2026-04-07T18:00:00-04:00"), endExclusive: date("2026-04-10T18:00:00-04:00"))
        continuation?.resume(returning: []); await old.value
        XCTAssertNil(model.lastRefresh); XCTAssertNil(model.healthSnapshot); XCTAssertNil(model.reportingPeriod)
        XCTAssertFalse(model.isLoading)
    }

    func testMissingCompletedVisitHasNoGuessedPeriodOrProviderQuery() async {
        var calls = 0, reader = queries(); reader.healthHistory = { _ in calls += 1; return [] }
        let model = model(reader); model.selectedRange = .sinceCompletedVisit
        await model.performRefresh(days: 730)
        XCTAssertEqual(calls, 0); XCTAssertNil(model.reportingPeriod)
        XCTAssertTrue(model.errorMessage?.contains("No completed visit") == true)
        XCTAssertFalse(model.isLoading)
    }

    func testInvalidCustomDraftPreservesSelectionAndPreviouslyReviewedInput() throws {
        let model = model(queries()), before = model.selectedRange
        let now = model.now()
        XCTAssertThrowsError(try model.applyCustomReportingRange(start: now, endExclusive: now, timeZone: zone))
        XCTAssertEqual(model.selectedRange, before); XCTAssertNil(model.customReportingRange)
        XCTAssertThrowsError(try model.applyCustomReportingRange(start: now.addingTimeInterval(-60), endExclusive: now, timeZone: .gmt))
        XCTAssertEqual(model.selectedRange, before); XCTAssertNil(model.customReportingRange)
    }

    func testExclusiveSixPMCutoffDoesNotDiscardEarliestSelectedNight() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let segments = [7, 8, 9].map { day in
            HealthKitService.SleepSegment(start: date("2026-03-0\(day)T22:00:00-\(day == 7 ? "05" : "04"):00"),
                end: date("2026-03-\(String(format: "%02d", day + 1))T06:00:00-04:00"), stage: .asleepCore, source: "Synthetic")
        }
        let values = HealthKitService.dashboardSleepSummaries(segments: segments, days: 3,
            before: date("2026-03-10T18:00:00-04:00"), calendar: calendar)
        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(values.last?.date, calendar.startOfDay(for: date("2026-03-07T22:00:00-05:00")))
    }
}
