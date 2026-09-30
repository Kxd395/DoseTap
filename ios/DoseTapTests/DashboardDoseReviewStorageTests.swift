import XCTest
import SQLite3
import DoseCore
@testable import DoseTap

@MainActor
final class DashboardDoseReviewStorageTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    func review(_ count: Int = 1) -> DashboardDoseReview {
        .init(observationID: "session:s", sourceFingerprint: "evidence", confirmedCount: count,
              historicalPlanCount: nil, secondNotTaken: nil, recordedAt: now, reason: "Reviewed")
    }
    func testIndependentReviewKeepsRevisionsAndDoesNotCreateSession() throws {
        let storage = EventStorage.inMemory(), first = review()
        try storage.saveDashboardDoseReview(first, sessionDate:"2026-09-30", expectedRevision:nil, now:now)
        try storage.saveDashboardDoseReview(first, sessionDate:"2026-09-30", expectedRevision:nil, now:now)
        XCTAssertEqual(try storage.dashboardDoseReviews(now:now)[first.observationID]?.revisions.count,1)
        XCTAssertThrowsError(try storage.saveDashboardDoseReview(first, sessionDate:"2026-09-29", expectedRevision:nil, now:now))
        XCTAssertNil(storage.fetchSessionId(forSessionDate:"2026-09-30"))
        XCTAssertTrue(storage.fetchDoseEvents(sessionKey:"2026-09-30").isEmpty)
        let next=review(2)
        XCTAssertThrowsError(try storage.saveDashboardDoseReview(next, sessionDate:"2026-09-30", expectedRevision:nil, now:now))
        try storage.saveDashboardDoseReview(next, sessionDate:"2026-09-30", expectedRevision:first.revisionID, now:now)
        XCTAssertEqual(try storage.dashboardDoseReviews(now:now)[first.observationID]?.revisions.count,2)
        storage.clearAllData()
        XCTAssertTrue(try storage.dashboardDoseReviews(now:now).isEmpty)
    }
    func testReadFailureNeverBecomesEmptyAndFailedWriteRetainsOriginal() throws {
        let storage=EventStorage.inMemory(), first=review()
        try storage.saveDashboardDoseReview(first,sessionDate:"2026-09-30",expectedRevision:nil,now:now)
        XCTAssertEqual(sqlite3_exec(storage.db,"CREATE TRIGGER reject_review BEFORE UPDATE ON dashboard_dose_reviews BEGIN SELECT RAISE(ABORT, 'synthetic'); END",nil,nil,nil),SQLITE_OK)
        XCTAssertThrowsError(try storage.saveDashboardDoseReview(review(2),sessionDate:"2026-09-30",expectedRevision:first.revisionID,now:now))
        XCTAssertEqual(try storage.dashboardDoseReviews(now:now)[first.observationID]?.current,first)
        XCTAssertEqual(sqlite3_exec(storage.db,"DROP TABLE dashboard_dose_reviews",nil,nil,nil),SQLITE_OK)
        XCTAssertThrowsError(try storage.dashboardDoseReviews(now:now))
    }
}
