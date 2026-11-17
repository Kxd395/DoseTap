import XCTest
import Combine
import DoseCore
@testable import DoseTap

@MainActor
final class DashboardProviderAccessTests: XCTestCase {
    func testSamePreferenceValueDoesNotInvalidate() {
        let settings = UserSettingsManager.shared
        let health = settings.healthKitEnabled, whoop = settings.whoopEnabled
        let before = DashboardProviderAccess.shared.revision
        settings.healthKitEnabled = health; settings.whoopEnabled = whoop
        XCTAssertEqual(DashboardProviderAccess.shared.revision, before)
    }

    func testKnownHealthAccessLossClearsProvider() {
        let health = HealthKitService.shared, original = HealthKitService.shared.isAuthorized
        health.isAuthorized = true
        defer { health.isAuthorized = original }
        let model = DashboardAnalyticsModel(); model.nights = [row(local: true)]
        health.isAuthorized = false
        XCTAssertNil(model.nights.first?.healthSummary)
        XCTAssertNotNil(model.nights.first?.dose1Time)
    }

    func testWHOOPDisableAndDisconnectPreserveHealthAndLocalData() throws {
        let settings = UserSettingsManager.shared, service = WHOOPService.shared
        let enabled = settings.whoopEnabled, connected = service.isConnected
        defer { settings.whoopEnabled = enabled; service.isConnected = connected }
        for disconnect in [false, true] {
            settings.whoopEnabled = true; service.isConnected = true
            let model = DashboardAnalyticsModel()
            var mixed = row(local: true); mixed.whoopSummary = try whoopSummary()
            model.nights = [mixed]
            if disconnect { service.isConnected = false } else { settings.whoopEnabled = false }
            XCTAssertNil(model.nights.first?.whoopSummary)
            XCTAssertNotNil(model.nights.first?.healthSummary)
            XCTAssertNotNil(model.nights.first?.dose1Time)
        }
    }

    func testOffOnEpochRejectsSuspendedHealthResultAndSettlesLoading() async {
        let access = DashboardProviderAccess(), entered = expectation(description: "History suspended")
        var continuation: CheckedContinuation<[HealthKitService.SleepNightSummary], Never>?
        var reader = queries()
        reader.healthHistory = { _ in await withCheckedContinuation { continuation = $0; entered.fulfill() } }
        let model = model(access: access, reader: reader)
        model.nights = [row(local: true)]
        let task = Task { await model.performRefresh(days: 30) }
        await fulfillment(of: [entered], timeout: 3)
        access.invalidate(.health); access.invalidate(.health)
        continuation?.resume(returning: [row(local: false).healthSummary!])
        await task.value
        XCTAssertNil(model.nights.first?.healthSummary)
        XCTAssertNotNil(model.nights.first?.dose1Time)
        XCTAssertNil(model.healthQueryWindow); XCTAssertNil(model.lastRefresh)
        XCTAssertFalse(model.isLoading)
    }

    func testInvalidationDuringAuthorizationPreventsHistoryQuery() async {
        let access = DashboardProviderAccess(), entered = expectation(description: "Authorization suspended")
        var continuation: CheckedContinuation<Bool, Never>?
        var historyQueries = 0, reader = queries()
        reader.prepareHealth = { await withCheckedContinuation { continuation = $0; entered.fulfill() } }
        reader.healthHistory = { _ in historyQueries += 1; return [] }
        let model = model(access: access, reader: reader)
        let task = Task { await model.performRefresh(days: 30) }
        await fulfillment(of: [entered], timeout: 3)
        access.invalidate(.health); continuation?.resume(returning: true)
        await task.value
        XCTAssertEqual(historyQueries, 0); XCTAssertNil(model.lastRefresh); XCTAssertFalse(model.isLoading)
    }

    func testConnectionEpochRejectsSuspendedWHOOPResult() async throws {
        let access = DashboardProviderAccess(), entered = expectation(description: "WHOOP suspended")
        var continuation: CheckedContinuation<[WHOOPNightSummary], Never>?
        var reader = queries(); reader.healthEnabled = { false }
        reader.whoopEnabled = { true }; reader.whoopConnected = { true }
        reader.whoopHistory = { _, _ in await withCheckedContinuation { continuation = $0; entered.fulfill() } }
        let model = model(access: access, reader: reader), summary = try whoopSummary()
        let task = Task { await model.performRefresh(days: 30) }
        await fulfillment(of: [entered], timeout: 3)
        access.invalidate(.whoop); access.invalidate(.whoop)
        continuation?.resume(returning: [summary]); await task.value
        XCTAssertTrue(model.nights.isEmpty); XCTAssertNil(model.lastRefresh); XCTAssertFalse(model.isLoading)
    }

    func testLateNotificationDoesNotEraseCurrentPublication() async {
        let access = DashboardProviderAccess()
        let model = model(access: access, reader: queries())
        access.invalidate(.health)
        await model.performRefresh(days: 30)
        XCTAssertEqual(model.nights.count, 1)
        model.providerAccessChanged(.health)
        XCTAssertNotNil(model.nights.first?.healthSummary)
        XCTAssertNotNil(model.healthQueryWindow)
    }

    func testBackgroundInvalidationClearsOnMainActorWithoutDeadlock() async {
        let access = DashboardProviderAccess(), changed = expectation(description: "Provider cleared")
        let model = model(access: access, reader: queries()); model.nights = [row(local: false)]
        let token = model.$nights.dropFirst().sink { if $0.isEmpty { changed.fulfill() } }
        DispatchQueue.global().async { access.invalidate(.health) }
        await fulfillment(of: [changed], timeout: 3)
        withExtendedLifetime(token) {}
    }

    func testInvalidationPreservesEveryLocalRecordKindAndOtherProvider() throws {
        let access = DashboardProviderAccess()
        let subject = self.model(access: access, reader: queries())
        var diary = row(local: false); diary.outcome = NightOutcomeDiary()
        var unreadable = row(local: false); unreadable.outcomeReadFailed = true
        var other = row(local: false); other.healthSummary = nil; other.whoopSummary = try whoopSummary()
        let event = DoseTap.StoredSleepEvent(id: "synthetic", eventType: "bathroom",
            timestamp: Date(timeIntervalSince1970: 1_790_000_000), sessionDate: "2026-09-22")
        subject.nights = [diary, unreadable, other, row(local: false, snoozes: 1),
            row(local: false, naps: 1), row(local: false, events: [event]), row(local: false)]
        access.invalidate(.health)
        XCTAssertEqual(subject.nights.count, 6)
        XCTAssertTrue(subject.nights.allSatisfy { $0.healthSummary == nil })
        XCTAssertEqual(subject.nights.filter { $0.snoozeCount == 1 }.count, 1)
        XCTAssertEqual(subject.nights.filter { $0.napSummary.count == 1 }.count, 1)
        XCTAssertEqual(subject.nights.filter { $0.whoopSummary != nil }.count, 1)
    }

    private func queries() -> DashboardProviderQueries {
        DashboardProviderQueries(healthEnabled: { true }, whoopEnabled: { false }, whoopConnected: { false },
            prepareHealth: { true }, healthHistory: { _ in [self.row(local: false).healthSummary!] }, whoopHistory: { _, _ in [] })
    }

    private func model(access: DashboardProviderAccess, reader: DashboardProviderQueries) -> DashboardAnalyticsModel {
        DashboardAnalyticsModel(sessionRepo: SessionRepository(storage: EventStorage.inMemory()),
            providerAccess: access, providerQueries: reader)
    }

    private func whoopSummary() throws -> WHOOPNightSummary {
        let data = Data(#"[{"id":"synthetic","nap":false,"start":"2026-09-21T23:00:00Z","score":{"stage_summary":{"total_light_sleep_time_milli":600000}}}]"#.utf8)
        let sleeps = try WHOOPService.makeAPIDecoder().decode([WHOOPSleep].self, from: data)
        return try XCTUnwrap(WHOOPService.makeNightSummaries(sleeps: sleeps, recoveries: []).first)
    }

    func testDisablingHealthClearsDisplayedProviderWithoutErasingLocalRecord() async {
        let settings = UserSettingsManager.shared
        let original = settings.healthKitEnabled
        settings.healthKitEnabled = true
        defer { settings.healthKitEnabled = original }
        let model = DashboardAnalyticsModel()
        model.nights = [row(local: true), row(local: false)]
        model.healthQueryWindow = model.currentReportWindow
        settings.healthKitEnabled = false
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated {
                model.nights.count == 1 && model.nights.first?.healthSummary == nil && model.healthQueryWindow == nil
            }
        }, object: nil)
        await fulfillment(of: [cleared], timeout: 2)
        XCTAssertEqual(model.nights.first?.dose1Time, Date(timeIntervalSince1970: 1_790_000_000))
    }

    private func row(local: Bool, snoozes: Int = 0, naps: Int = 0, events: [DoseTap.StoredSleepEvent] = []) -> DashboardNightAggregate {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let health = HealthKitService.SleepNightSummary(date: date, bedTime: nil, sleepOnset: nil,
            firstWake: nil, finalWake: nil, ttfwMinutes: nil, totalSleepMinutes: 420, wakeCount: 0, source: "Synthetic")
        return DashboardNightAggregate(sessionDate: local ? "2026-09-21" : "2026-09-22",
            dose1Time: local ? date : nil, dose2Time: nil, dose2Skipped: false,
            snoozeCount: snoozes, extraDoseCount: 0, events: events, morningCheckIn: nil, preSleepLog: nil,
            healthSummary: health, whoopSummary: nil, duplicateClusterCount: 0,
            napSummary: .init(count: naps, totalMinutes: naps * 20))
    }
}
