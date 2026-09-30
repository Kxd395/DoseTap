import XCTest
@testable import DoseCore

final class DashboardDosePatternTests: XCTestCase {
    let t = Date(timeIntervalSince1970: 1_790_000_000)
    func dose(_ id: String, _ slot: Int, _ offset: Double? = 0, session: String = "s") -> DashboardDosePattern.Administration {
        .init(id: id, sessionID: session, slot: slot, occurredAt: offset.map { t.addingTimeInterval($0) })
    }
    func result(_ doses: [DashboardDosePattern.Administration], count: Int? = nil,
                plan: Int? = nil, omitted: Bool = false, open: Bool = false) -> DashboardDosePattern {
        .derive(sessionID: "s", administrations: doses, confirmedCount: count,
                historicalPlanCount: plan, secondNotTaken: omitted, sessionOpen: open)
    }
    func testSinglePatternsHaveNoIntervalAndDistinctReasons() {
        XCTAssertEqual(result([dose("a",1)], count: 1, plan: 1).pattern, .singlePlanned)
        XCTAssertEqual(result([dose("a",1)], omitted: true).pattern, .singleOmitted)
        let one = result([dose("a",1)], count: 1)
        XCTAssertEqual(one.pattern, .singleUnknownPlan)
        XCTAssertEqual(one.interval.state, .notApplicable)
        XCTAssertNil(one.interval.value)
        XCTAssertEqual(result([dose("a",1)]).pattern, .incomplete)
        XCTAssertEqual(result([dose("a",1)]).interval.reason, "dose_outcome_unknown")
    }
    func testUnknownTimeDoesNotChangeReportedCount() {
        let r = result([dose("a",1),dose("b",2,nil)], count: 2)
        XCTAssertEqual(r.reportedCount, 2)
        XCTAssertEqual(r.pattern, .twoReported)
        XCTAssertEqual(r.interval.state, .unavailable)
        XCTAssertEqual(r.interval.reason, "occurrence_time_missing")
        XCTAssertEqual(result([dose("a",1)], count: 2).reportedCount, 2)
        XCTAssertNil(result([dose("a",1)], count: 2).interval.value)
    }
    func testNoDoseRequiresExplicitCompletedReport() {
        XCTAssertEqual(result([], count: 0).pattern, .noneReported)
        XCTAssertEqual(result([]).pattern, .incomplete)
        XCTAssertEqual(result([], count: 0).postDose2State, .notApplicable)
    }
    func testOpenUnresolvedAndClosedCountRemainDifferent() {
        XCTAssertEqual(result([dose("a",1)], open: true).pattern, .inProgress)
        XCTAssertEqual(result([dose("a",1)]).pattern, .incomplete)
        XCTAssertFalse(result([dose("a",1),dose("b",2,9000)]).countComplete)
        XCTAssertTrue(result([dose("a",1),dose("b",2,9000)], count: 2).countComplete)
    }
    func testValidPairUsesExactUTCDurationAndLineage() {
        let r = result([dose("b",2,9000.5),dose("a",1)])
        XCTAssertEqual(r.interval.value!,9000.5/60,accuracy:0.00001)
        XCTAssertEqual(r.interval.state,.available)
        XCTAssertEqual(r.pairIDs,["a","b"])
    }
    func testCrossSessionExtraDuplicateSlotsAndContradictionRequireReview() {
        for ds in [[dose("a",1),dose("b",2,9000,session:"other")],
                   [dose("a",1),dose("b",2,9000),dose("c",3,18000)],
                   [dose("a",1),dose("b",1,9000)], [dose("b",2)]] {
            XCTAssertEqual(result(ds).pattern,.needsReview)
            XCTAssertNil(result(ds).interval.value)
        }
        XCTAssertEqual(result([dose("a",1),dose("b",2,9000)], omitted:true).pattern,.needsReview)
        XCTAssertEqual(result([dose("a",1)],count:0).pattern,.needsReview)
    }
    func testCanonicalDuplicateDoesNotDoubleCountButConflictingDuplicateDoes() {
        let a=dose("a",1)
        XCTAssertEqual(result([a,a],count:1).reportedCount,1)
        XCTAssertEqual(result([a,dose("a",2,9000)]).pattern,.needsReview)
    }
    func testIdenticalOrReversedTimesStayReviewableNotSingle() {
        for offset in [0.0,-1] {
            let r=result([dose("a",1),dose("b",2,offset)],count:2)
            XCTAssertEqual(r.reportedCount,2)
            XCTAssertEqual(r.pattern,.needsReview)
            XCTAssertEqual(r.interval.reason,"nonpositive_pair")
        }
    }
    func testNonfiniteAndInvalidCountNeverProduceValues() {
        XCTAssertEqual(result([dose("a",1,.infinity)]).pattern,.needsReview)
        XCTAssertEqual(result([],count:-1).pattern,.needsReview)
        XCTAssertEqual(result([],count:3).pattern,.needsReview)
    }
    func testMetricMissingnessDoesNotInventZero() {
        XCTAssertNil(DashboardMetricValue(value:.nan,state:.available,reason:"bad",unit:"minutes").value)
        XCTAssertEqual(DashboardMetricValue(value:.nan,state:.available,reason:"bad",unit:"minutes").state,.needsReview)
        XCTAssertEqual(DashboardMetricValue(value:0,state:.available,reason:"observed",unit:"minutes").value,0)
    }
}
