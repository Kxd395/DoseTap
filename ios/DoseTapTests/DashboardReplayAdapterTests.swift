import XCTest
import DoseCore
@testable import DoseTap

@MainActor
final class DashboardReplayAdapterTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    func night(metadata: String? = nil) -> DashboardNightAggregate {
        var row = DashboardNightAggregate(sessionDate: "2026-09-21", dose1Time: start,
            dose2Time: start.addingTimeInterval(10_800), dose2Skipped: false, snoozeCount: 0, extraDoseCount: 0,
            events: [], morningCheckIn: nil, preSleepLog: nil, healthSummary: nil, whoopSummary: nil,
            duplicateClusterCount: 0, napSummary: .init(count: 0, totalMinutes: 0))
        row.sessionID = "durable-session"
        row.doseEvents = [.init(id: "d1", eventType: "dose1", timestamp: start, sessionDate: row.sessionDate,
                               metadata: metadata, sessionId: row.sessionID),
                          .init(id: "d2", eventType: "dose2", timestamp: start.addingTimeInterval(10_800),
                                sessionDate: row.sessionDate, sessionId: row.sessionID)]
        return row
    }
    func testReplayUsesDurableIdentityAndNeverCurrentReminderPreference() {
        let model = DashboardAnalyticsModel(now: { self.start.addingTimeInterval(50_000) })
        let snapshot = model.replaySnapshot(for: night())
        XCTAssertEqual(snapshot.sessionID, "durable-session")
        XCTAssertEqual(snapshot.interval(.dose1ToDose2).minutes, 180)
        XCTAssertEqual(snapshot.interval(.reminderDeviation).state, .unavailable)
    }
    func testSavedReminderAndExplicitNoAlarmRemainSeparateFromDelivery() {
        let model = DashboardAnalyticsModel(now: { self.start.addingTimeInterval(50_000) })
        let saved = model.replaySnapshot(for: night(metadata: "{\"reminder_interval_minutes\":165}"))
        XCTAssertEqual(saved.interval(.reminderDeviation).minutes, 15)
        XCTAssertNil(saved.interval(.deliveredAlarmToDose).minutes)
        let disabled = model.replaySnapshot(for: night(metadata: "{\"reminder_interval_minutes\":165,\"dose2_reminder_enabled\":false}"))
        XCTAssertNil(disabled.interval(.reminderDeviation).minutes)
    }
    func testAmbiguousRowsNeverSupplyUsableIntervals() {
        let model = DashboardAnalyticsModel(now: { self.start.addingTimeInterval(50_000) })
        var row = night(); row.identityNeedsReview = true
        XCTAssertEqual(model.replaySnapshot(for: row).interval(.dose1ToDose2).state, .needsReview)
    }
    func testDateScopedCoverageCannotSelectBetweenTwoSessions() async {
        let model = DashboardAnalyticsModel(now: { self.start.addingTimeInterval(50_000) })
        var other = night(); other.sessionID = "second-session"
        model.nights = [night(), other]
        let result = await model.replayCoverage(sessionID: "durable-session")
        XCTAssertEqual(result.status, .needsReview)
    }
}
