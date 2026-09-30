import XCTest
@testable import DoseCore
final class DashboardDoseReviewTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    func review(_ count: Int? = 1, at: Date? = nil) -> DashboardDoseReview {
        .init(observationID: "session:s", sourceFingerprint: "evidence", confirmedCount: count,
              historicalPlanCount: nil, secondNotTaken: nil, recordedAt: at ?? now, reason: "Reviewed")
    }
    func testExplicitReviewDoesNotInferCountFromPlan() {
        XCTAssertNil(review(nil).confirmedCount)
        XCTAssertNil(review(nil).validationError(now: now))
        XCTAssertNotNil(review(-1).validationError(now: now))
        XCTAssertNotNil(review(3).validationError(now: now))
        XCTAssertNotNil(review(at: now.addingTimeInterval(1)).validationError(now: now))
    }
    func testFingerprintStableAcrossOrderButChangesWithSourceEvidence() {
        let a = StoredDoseEvent(id:"a",eventType:"dose1",timestamp:now,sessionDate:"2026-09-30",sessionId:"s")
        let b = StoredDoseEvent(id:"b",eventType:"dose2",timestamp:now.addingTimeInterval(9000),sessionDate:"2026-09-30",sessionId:"s")
        XCTAssertEqual(DashboardDoseReview.fingerprint([a,b]),DashboardDoseReview.fingerprint([b,a]))
        XCTAssertNotEqual(DashboardDoseReview.fingerprint([a]),DashboardDoseReview.fingerprint([a,b]))
        XCTAssertNotNil(DashboardDoseReview.fingerprint([a]))
    }
    func testLedgerPreservesRevisionsAndRejectsLostUpdate() throws {
        var ledger=DashboardDoseReviewLedger()
        let first=review(); try ledger.append(first,expectedRevision:nil,now:now)
        try ledger.append(first,expectedRevision:nil,now:now) // idempotent committed retry
        XCTAssertEqual(ledger.revisions.count,1)
        let second=review(2)
        XCTAssertThrowsError(try ledger.append(second,expectedRevision:nil,now:now))
        try ledger.append(second,expectedRevision:first.revisionID,now:now)
        XCTAssertEqual(ledger.revisions.count,2)
        XCTAssertEqual(ledger.current?.confirmedCount,2)
        XCTAssertEqual(ledger.current(matching:"changed"),nil)
        XCTAssertEqual(ledger.current(matching:"evidence"),second)
    }
}
