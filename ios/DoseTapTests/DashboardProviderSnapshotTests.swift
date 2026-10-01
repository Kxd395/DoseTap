import XCTest
import DoseCore
import HealthKit
@testable import DoseTap

@MainActor
final class DashboardProviderSnapshotTests: XCTestCase {
    func testFirstLocalRecordsAreVisibleWhileProviderPreparationIsSuspended() async throws {
        let instant = Date(timeIntervalSince1970: 1_790_000_000)
        let storage = EventStorage.inMemory()
        storage.insertDoseEvent(eventType: "dose1", timestamp: instant, sessionKey: "2026-09-21", metadata: nil)
        let entered = expectation(description: "Provider suspended")
        var resume: CheckedContinuation<HealthReadPreparation, Never>?
        let reader = DashboardProviderQueries(healthEnabled: { true }, whoopEnabled: { false }, whoopConnected: { false },
            prepareHealth: { await withCheckedContinuation { resume = $0; entered.fulfill() } },
            healthHistory: { _ in [] }, whoopHistory: { _, _ in self.whoopResult([]) })
        let model = DashboardAnalyticsModel(now: { instant }, sessionRepo: SessionRepository(storage: storage), providerQueries: reader)
        let refresh = Task { await model.performRefresh(days: 30) }
        await fulfillment(of: [entered], timeout: 3)
        XCTAssertTrue(model.nights.contains { $0.dose1Time == instant }, "Local records must not wait for provider access or network requests")
        XCTAssertTrue(model.isLoading)
        XCTAssertFalse(model.providerAssociationsReady); XCTAssertFalse(model.contextReadReady)
        XCTAssertFalse(model.doseReviewReadReady); XCTAssertNil(model.lastRefresh)
        resume?.resume(returning: .ready); await refresh.value
        XCTAssertFalse(model.isLoading); XCTAssertTrue(model.providerAssociationsReady)
        XCTAssertEqual(model.nights.count, 1)
    }

    func testTransientFailureRetainsSuccessfulQueryWhileRefreshingLocalRecords() async throws {
        let first = Date(timeIntervalSince1970: 1_790_000_000)
        var clock = first, failing = false
        let storage = EventStorage.inMemory(), access = DashboardProviderAccess()
        let reader = DashboardProviderQueries(healthEnabled: { true }, whoopEnabled: { false }, whoopConnected: { false },
            prepareHealth: { .ready }, healthHistory: { _ in
                if failing { throw URLError(.notConnectedToInternet) }
                return [self.summary(first)]
            }, whoopHistory: { _, _ in self.whoopResult([]) })
        let model = DashboardAnalyticsModel(now: { clock }, sessionRepo: SessionRepository(storage: storage),
            providerAccess: access, providerQueries: reader)
        await model.performRefresh(days: 30)
        let originalWindow = try XCTUnwrap(model.healthQueryWindow)
        clock = first.addingTimeInterval(86400); failing = true
        storage.insertDoseEvent(eventType: "dose1", timestamp: clock, sessionKey: "2026-09-22", metadata: nil)
        await model.performRefresh(days: 30)
        XCTAssertEqual(model.nights.filter { $0.healthSummary != nil }.count, 1)
        XCTAssertTrue(model.nights.contains { $0.dose1Time == clock })
        XCTAssertEqual(model.healthQueryWindow?.asOf, originalWindow.asOf)
        XCTAssertTrue(model.healthQueryDescription.contains("Stale"))
    }

    func testEmptySuccessReplacesPreviousSnapshot() async {
        let f = Fixture(); let model = f.model()
        await model.performRefresh(days: 30)
        f.health = []; f.whoop = []
        await model.performRefresh(days: 30)
        XCTAssertTrue(model.nights.isEmpty)
        XCTAssertNotNil(model.healthQueryWindow)
        XCTAssertNil(model.healthSnapshot?.failedAttemptAt)
    }

    func testPreparationFailureRetainsButUnavailableClears() async {
        let f = Fixture(); let model = f.model()
        await model.performRefresh(days: 30)
        f.preparation = .transientFailure
        await model.performRefresh(days: 30)
        XCTAssertEqual(model.nights.filter { $0.healthSummary != nil }.count, 1)
        XCTAssertNotNil(model.healthSnapshot?.failedAttemptAt)
        f.preparation = .unavailable
        await model.performRefresh(days: 30)
        XCTAssertNil(model.healthSnapshot)
        XCTAssertTrue(model.nights.allSatisfy { $0.healthSummary == nil })
    }

    func testProvidersRefreshIndependentlyAndPartialRecoveryNeverReusesOldValues() async {
        let f = Fixture(); let model = f.model()
        await model.performRefresh(days: 30)
        f.healthError = URLError(.timedOut); f.whoop[0].recoveryScore = nil; f.partial = true
        await model.performRefresh(days: 30)
        XCTAssertNotNil(model.healthSnapshot?.failedAttemptAt)
        XCTAssertNil(model.whoopSnapshot?.failedAttemptAt)
        XCTAssertTrue(model.whoopSnapshot?.isPartial == true)
        XCTAssertNil(model.nights.first { $0.whoopSummary != nil }?.whoopSummary?.recoveryScore)
        XCTAssertTrue(model.whoopQueryDescription.contains("recovery"))
        f.whoopError = WHOOPError.httpError(503)
        await model.performRefresh(days: 30)
        XCTAssertNotNil(model.whoopSnapshot?.failedAttemptAt)
        XCTAssertTrue(model.errorMessage?.contains("Apple Health") == true)
        XCTAssertTrue(model.errorMessage?.contains("WHOOP") == true)
    }

    func testDeniedAndNonTransientFailuresClearInsteadOfRetaining() async {
        let f = Fixture(); let model = f.model()
        await model.performRefresh(days: 30)
        f.healthError = NSError(domain: HKErrorDomain, code: HKError.Code.errorAuthorizationDenied.rawValue)
        f.whoopError = WHOOPError.httpError(403)
        await model.performRefresh(days: 30)
        XCTAssertNil(model.healthSnapshot); XCTAssertNil(model.whoopSnapshot)
        XCTAssertNil(model.healthQueryWindow); XCTAssertTrue(model.nights.isEmpty)
    }

    func testRangeFailureRetainsOriginalBoundsAndTimezoneChangeDropsSnapshot() async {
        let f = Fixture(); let model = f.model()
        await model.performRefresh(days: 30)
        let first = model.healthQueryWindow?.asOf
        f.clock = f.clock.addingTimeInterval(86400); model.selectedRange = .year
        f.healthError = URLError(.timedOut)
        await model.performRefresh(days: 30)
        XCTAssertEqual(model.healthQueryWindow?.range, .month)
        XCTAssertEqual(model.healthQueryWindow?.asOf, first)
        XCTAssertTrue(model.healthQueryDescription.contains("selected range has changed"))
        f.zone = TimeZone(identifier: "America/New_York")!
        await model.performRefresh(days: 30)
        XCTAssertNil(model.healthSnapshot); XCTAssertNil(model.healthQueryWindow)
    }

    func testAccessInvalidationAndLocalOnlyRefreshCannotRestoreCachedData() async {
        let f = Fixture(); let model = f.model()
        await model.performRefresh(days: 30)
        f.access.invalidate(.health)
        XCTAssertNil(model.healthSnapshot)
        f.healthError = URLError(.timedOut)
        await model.performRefresh(days: 30)
        XCTAssertNil(model.healthSnapshot)
        XCTAssertTrue(model.nights.allSatisfy { $0.healthSummary == nil })
        await model.performRefresh(days: 30, includeProviders: false)
        XCTAssertNil(model.whoopSnapshot); XCTAssertTrue(model.nights.isEmpty)
    }

    func testCancelledQueryPreservesCommittedSnapshot() async {
        let f = Fixture(); let model = f.model()
        await model.performRefresh(days: 30)
        let before = model.lastRefresh
        f.clock = f.clock.addingTimeInterval(86400); f.healthError = CancellationError()
        await model.performRefresh(days: 30)
        XCTAssertEqual(model.lastRefresh, before)
        XCTAssertNil(model.healthSnapshot?.failedAttemptAt)
        XCTAssertEqual(model.nights.filter { $0.healthSummary != nil }.count, 1)
    }

    func testSupersededSuccessCannotOverwriteNewSnapshot() async {
        let f = Fixture(), entered = expectation(description: "Second query suspended")
        var continuation: CheckedContinuation<[HealthKitService.SleepNightSummary], Never>?
        var calls = 0
        var queries = DashboardProviderQueries(healthEnabled: { true }, whoopEnabled: { false }, whoopConnected: { false },
            prepareHealth: { .ready }, healthHistory: { _ in f.health }, whoopHistory: { _, _ in self.whoopResult([]) })
        queries.healthHistory = { _ in
            calls += 1
            if calls == 2 { return await withCheckedContinuation { continuation = $0; entered.fulfill() } }
            return [self.summary(f.clock)]
        }
        let model = DashboardAnalyticsModel(now: { f.clock }, sessionRepo: SessionRepository(storage: EventStorage.inMemory()),
            timeZone: { f.zone }, providerAccess: f.access, providerQueries: queries)
        await model.performRefresh(days: 30)
        XCTAssertTrue(model.providerSnapshotIsCurrent(.health))
        let old = Task { await model.performRefresh(days: 30) }
        await fulfillment(of: [entered], timeout: 3)
        XCTAssertFalse(model.providerSnapshotIsCurrent(.health))
        f.clock = f.clock.addingTimeInterval(86400)
        await model.performRefresh(days: 30)
        continuation?.resume(returning: []); await old.value
        XCTAssertEqual(model.healthSnapshot?.window.asOf, f.clock)
        XCTAssertEqual(model.nights.filter { $0.healthSummary != nil }.count, 1)
        XCTAssertTrue(model.providerSnapshotIsCurrent(.health))
        model.selectedRange = .year
        XCTAssertFalse(model.providerSnapshotIsCurrent(.health))
    }

    private func whoopResult(_ rows: [WHOOPNightSummary]) -> WHOOPNightFetchResult {
        .init(summaries: rows, sleepRecordCount: rows.count, recoveryRecordCount: 0, recoveryStatus: .completed)
    }

    @MainActor
    private final class Fixture {
        var clock = Date(timeIntervalSince1970: 1_790_000_000), zone = TimeZone(secondsFromGMT: 0)!
        let access = DashboardProviderAccess()
        var preparation: HealthReadPreparation = .ready, healthError: Error?, whoopError: Error?
        var health: [HealthKitService.SleepNightSummary], whoop: [WHOOPNightSummary], partial = false
        init() {
            health = [.init(date: clock, bedTime: nil, sleepOnset: nil, firstWake: nil, finalWake: nil,
                            ttfwMinutes: nil, totalSleepMinutes: 420, wakeCount: 0, source: "Synthetic")]
            whoop = [.init(date: clock, sleepId: "synthetic", totalSleepMinutes: 420, remMinutes: 90,
                deepMinutes: 70, lightMinutes: 260, awakeMinutes: 20, inBedMinutes: 440, disturbanceCount: 2,
                sleepEfficiency: 95, sleepPerformance: nil, sleepConsistency: nil, respiratoryRate: nil,
                sleepNeedBaselineMinutes: nil, sleepNeedDebtMinutes: nil, sleepNeedStrainMinutes: nil,
                sleepNeedNapMinutes: nil, recoveryScore: 60, hrvMs: nil)]
        }
        func model() -> DashboardAnalyticsModel {
            let queries = DashboardProviderQueries(healthEnabled: { true }, whoopEnabled: { true }, whoopConnected: { true },
                prepareHealth: { self.preparation }, healthHistory: { _ in
                    if let error = self.healthError { throw error }; return self.health
                }, whoopHistory: { _, _ in
                    if let error = self.whoopError { throw error }
                    return .init(summaries: self.whoop, sleepRecordCount: self.whoop.count,
                        recoveryRecordCount: self.partial ? nil : 1, recoveryStatus: self.partial ? .failed : .completed)
                })
            return DashboardAnalyticsModel(now: { self.clock }, sessionRepo: SessionRepository(storage: EventStorage.inMemory()),
                timeZone: { self.zone }, providerAccess: access, providerQueries: queries)
        }
    }

    private func summary(_ date: Date) -> HealthKitService.SleepNightSummary {
        .init(date: date, bedTime: nil, sleepOnset: nil, firstWake: nil, finalWake: nil,
              ttfwMinutes: nil, totalSleepMinutes: 420, wakeCount: 0, source: "Synthetic")
    }
}
