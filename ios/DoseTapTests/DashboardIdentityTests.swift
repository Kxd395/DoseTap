import XCTest
import SQLite3
import DoseCore
@testable import DoseTap

@MainActor
final class DashboardIdentityTests: XCTestCase {
    let date = "2026-09-29"
    func insert(_ sql: String, into storage: EventStorage) {
        XCTAssertEqual(sqlite3_exec(storage.db, sql, nil, nil, nil), SQLITE_OK)
    }
    func seed(_ storage: EventStorage) {
        insert("INSERT INTO sleep_sessions(session_id,session_date,start_utc) VALUES ('a','2026-09-29','2026-09-29T22:00:00Z'),('b','2026-09-29','2026-09-30T02:00:00Z')", into: storage)
        insert("INSERT INTO dose_events(id,event_type,timestamp,session_date,session_id) VALUES ('d1','dose1','2026-09-29T22:00:00Z','2026-09-29','a'),('d2','dose2','2026-09-30T02:00:00Z','2026-09-29','b')", into: storage)
    }
    func testSameDateSessionsNeverCollapseOrPair() async {
        let storage = EventStorage(dbPath: ":memory:")
        seed(storage)
        let model = DashboardAnalyticsModel(sessionRepo: SessionRepository(storage: storage))
        await model.performRefresh(days: 30, includeProviders: false)
        XCTAssertEqual(model.nights.count, 2)
        XCTAssertEqual(Set(model.nights.map(\.id)).count, 2)
        XCTAssertTrue(model.nights.allSatisfy { $0.exactIntervalMinutes == nil })
    }
    func testAmbiguousProviderRemainsSeparateAndStable() throws {
        let storage = EventStorage.inMemory(); seed(storage)
        let model = DashboardAnalyticsModel(sessionRepo: SessionRepository(storage: storage))
        let time = Date(timeIntervalSince1970: 1_790_721_600)
        let summary = HealthKitService.SleepNightSummary(date: time, bedTime: time, sleepOnset: time,
            firstWake: nil, finalWake: time.addingTimeInterval(3600), ttfwMinutes: nil,
            totalSleepMinutes: 60, wakeCount: 0, source: "Synthetic watch")
        let local = try storage.dashboardLocalSessions()
        let rows = model.identityAggregates(local: local, health: [date: summary], whoop: [:])
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows.filter { $0.sessionID != nil }.allSatisfy { $0.healthSummary == nil })
        XCTAssertNil(rows.first { $0.healthSummary != nil }?.sessionID)
        XCTAssertEqual(rows.map(\.id), model.identityAggregates(local: local, health: [date: summary], whoop: [:]).map(\.id))
    }
    func testFailedLocalReadRetainsPublishedRows() async {
        let storage = EventStorage.inMemory(); seed(storage)
        let model = DashboardAnalyticsModel(sessionRepo: SessionRepository(storage: storage))
        await model.performRefresh(days: 30, includeProviders: false)
        let ids = model.nights.map(\.id), refresh = model.lastRefresh
        insert("DROP TABLE morning_checkins", into: storage)
        await model.performRefresh(days: 30, includeProviders: false)
        XCTAssertEqual(model.nights.map(\.id), ids)
        XCTAssertEqual(model.lastRefresh, refresh)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
    }
}
