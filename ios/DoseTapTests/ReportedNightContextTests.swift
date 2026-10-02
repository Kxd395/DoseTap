import XCTest
import SQLite3
import DoseCore
@testable import DoseTap

final class ReportedNightContextTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_791_200)
    func night(type: String = "work_night", session: String = "one", date: String = "2026-09-29",
               timestamp: Date? = nil, firstOff: Bool = false, json: String? = nil) -> DashboardNightAggregate {
        let morning = DoseTap.StoredMorningCheckIn(id: "morning-one", sessionId: session, timestamp: timestamp ?? now,
            sessionDate: date, timingContextJson: json ?? "{\"nightType\":\"\(type)\",\"firstNightOffAfterWorkBlock\":\(firstOff)}")
        var night = DashboardNightAggregate(sessionDate: "2026-09-29", dose1Time: now.addingTimeInterval(-36000),
            dose2Time: now.addingTimeInterval(-25200), dose2Skipped: false, snoozeCount: 0, extraDoseCount: 0,
            events: [], morningCheckIn: morning, preSleepLog: nil, healthSummary: nil, whoopSummary: nil,
            duplicateClusterCount: 0, napSummary: .init(count: 0, totalMinutes: 0))
        night.sessionID = "one"; night.stableID = "session:one"
        return night
    }
    func testEverySavedCategoryKeepsExactSessionAndProvenance() throws {
        for type in NightType.allCases {
            let value = try XCTUnwrap(DashboardReportedNightContext.project(night: night(type: type.rawValue), asOf: now))
            XCTAssertEqual(value.type, type); XCTAssertEqual(value.label, type.displayText)
            XCTAssertEqual(value.recordID, "morning-one"); XCTAssertEqual(value.reportedAt, now)
        }
    }
    func testWrongSessionDateUnresolvedAndFutureCannotSupplyContext() {
        for row in [night(session: "two"), night(date: "2026-09-30"), night(timestamp: now.addingTimeInterval(1)),
                    night(timestamp: Date(timeIntervalSince1970: .infinity)), night(type: "invented")] {
            XCTAssertNil(DashboardReportedNightContext.project(night: row, asOf: now))
        }
        var row = night(); row.identityNeedsReview = true
        XCTAssertNil(DashboardReportedNightContext.project(night: row, asOf: now))
        row = night(); row.sessionID = nil
        XCTAssertNil(DashboardReportedNightContext.project(night: row, asOf: now))
    }
    func testMalformedMissingAndInvalidCutoffStayUnknown() {
        for json in ["not JSON", "{}", "{\"nightType\":false}", "{\"nightType\":\"\"}"] {
            let row = night(json: json)
            XCTAssertNil(DashboardReportedNightContext.project(night: row, asOf: now))
        }
        XCTAssertNil(DashboardReportedNightContext.project(night: night(), asOf: Date(timeIntervalSince1970: .nan)))
    }
    func testFirstOffRemainsIndependentOfUnsureCategory() throws {
        let value = try XCTUnwrap(DashboardReportedNightContext.project(night: night(type: "unsure", firstOff: true), asOf: now))
        XCTAssertEqual(value.type, .unsure); XCTAssertTrue(value.firstOff)
        XCTAssertTrue(value.label.contains("First night off after work block"))
        XCTAssertFalse(try XCTUnwrap(DashboardReportedNightContext.project(night: night(), asOf: now)).firstOff)
    }
    func testCorrectionUpdatesContextWithoutChangingObservationIdentity() throws {
        let old = night(type: "transition_into_work_block"), corrected = night(type: "transition_out_of_work_block")
        XCTAssertEqual(old.id, corrected.id)
        XCTAssertNotEqual(DashboardReportedNightContext.project(night: old, asOf: now)?.type,
                          DashboardReportedNightContext.project(night: corrected, asOf: now)?.type)
    }
}

@MainActor
extension DashboardDosePatternAdapterTests {
    func testMorningWorkContextJoinsPreviousNightPairAndCorrectionByExactIdentity() async throws {
        let storage = EventStorage.inMemory(); seed(storage)
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO dose_events(id,event_type,timestamp,session_date,session_id) VALUES ('d2','dose2','2026-09-30T01:00:00Z','2026-09-29','a')", nil, nil, nil), SQLITE_OK)
        let dashboard = model(storage)
        func save(_ type: NightType) {
            XCTAssertTrue(storage.saveMorningCheckIn(.init(id: "morning-a", sessionId: "a", timestamp: now,
                sessionDate: "2026-09-29", timingContextJson: "{\"nightType\":\"\(type.rawValue)\"}"), forSession: "2026-09-29"))
        }
        func comparison() throws -> ReplayComparisonRow {
            let row = try XCTUnwrap(dashboard.nights.first { $0.sessionID == "a" })
            return try XCTUnwrap(dashboard.replayComparison(for: dashboard.replaySnapshot(for: row), outcome: .mainSleep, preset: .dose1ToDose2))
        }
        save(.transitionIntoWorkBlock)
        await dashboard.performRefresh(days: 30, includeProviders: false)
        let first = try comparison()
        XCTAssertEqual(first.x, 180); XCTAssertEqual(first.reportedNight?.type, .transitionIntoWorkBlock)
        XCTAssertEqual(first.reportedNight?.recordID, "morning-a"); XCTAssertEqual(first.workBeforeSleep, .unknown)
        XCTAssertTrue(first.csv.contains("transition_into_work_block")); XCTAssertTrue(first.csv.contains("morning-a"))
        var presentation = DashboardReplayPresentation(); presentation.reportedNightFilter = .transitionIntoWorkBlock
        XCTAssertTrue(first.matchesTimingContext(presentation))
        presentation.reportedNightFilter = .transitionOutOfWorkBlock
        XCTAssertFalse(first.matchesTimingContext(presentation))
        save(.transitionOutOfWorkBlock)
        await dashboard.performRefresh(days: 30, includeProviders: false)
        let corrected = try comparison()
        XCTAssertEqual(corrected.id, first.id); XCTAssertEqual(corrected.x, 180)
        XCTAssertEqual(corrected.reportedNight?.type, .transitionOutOfWorkBlock)
        XCTAssertTrue(corrected.matchesTimingContext(presentation)); XCTAssertEqual(corrected.workBeforeSleep, .unknown)
        XCTAssertEqual(storage.fetchDoseEvents(sessionKey: "2026-09-29").count, 2)
    }
}
