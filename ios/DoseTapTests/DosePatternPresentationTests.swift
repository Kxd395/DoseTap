import XCTest
import DoseCore
@testable import DoseTap

@MainActor
final class DosePatternPresentationTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_790_720_000)
    func night(hasDose2: Bool = true, hasOmission: Bool = true, intervals: [RecordedSleepInterval]) -> DashboardNightAggregate {
        let second = start.addingTimeInterval(180 * 60), end = second.addingTimeInterval(60 * 60)
        let health = HealthKitService.SleepNightSummary(date: start, bedTime: start, sleepOnset: start,
            firstWake: nil, finalWake: end, ttfwMinutes: nil, totalSleepMinutes: 0, wakeCount: 0,
            source: "Synthetic", recordedIntervals: intervals)
        var row = DashboardNightAggregate(sessionDate: "2026-09-29", dose1Time: start,
            dose2Time: hasDose2 ? second : nil, dose2Skipped: !hasDose2 && hasOmission, snoozeCount: 0,
            extraDoseCount: 0, events: [], morningCheckIn: nil, preSleepLog: nil,
            healthSummary: health, whoopSummary: nil, duplicateClusterCount: 0,
            napSummary: .init(count: 0, totalMinutes: 0))
        row.sessionID = "s"; row.stableID = "session:s"; row.sessionClosed = true
        row.doseEvents = [.init(id: "d1", eventType: "dose1", timestamp: start,
                               sessionDate: row.sessionDate, sessionId: "s")]
        if hasDose2 || hasOmission { row.doseEvents.append(.init(id: "d2", eventType: hasDose2 ? "dose2" : "dose2_skipped",
            timestamp: second, sessionDate: row.sessionDate, sessionId: "s")) }
        return row
    }
    func testPartialSleepPreservesMeasuredValueAndLabelsCoverage() {
        let second = start.addingTimeInterval(180 * 60)
        let row = night(intervals: [.init(start: second, end: second.addingTimeInterval(30 * 60), asleep: true)])
        let metric = DosePatternPresentation.sleepMetric(row, source: .appleHealth, outcome: .postDose2)
        XCTAssertEqual(metric.state, .partial); XCTAssertEqual(metric.value, 30)
        XCTAssertTrue(DosePatternPresentation.coverage(row, outcome: .postDose2).contains("30 min"))
        let projection = DosePatternPresentation.sleepProjection(row, source: .appleHealth, outcome: .postDose2)
        XCTAssertNil(projection.summaryValue()); XCTAssertEqual(projection.summaryValue(includePartial: true), 30)
    }
    func testAllAwakeIsObservedZero() {
        let second = start.addingTimeInterval(180 * 60)
        let row = night(intervals: [.init(start: second, end: second.addingTimeInterval(60 * 60), asleep: false)])
        let metric = DosePatternPresentation.sleepMetric(row, source: .appleHealth, outcome: .postDose2)
        XCTAssertEqual(metric.state, .available); XCTAssertEqual(metric.value, 0)
    }
    func testNoDose2IsNotApplicableRatherThanZero() {
        let metric = DosePatternPresentation.sleepMetric(night(hasDose2: false, intervals: []), source: .appleHealth, outcome: .postDose2)
        XCTAssertEqual(metric.state, .notApplicable); XCTAssertNil(metric.value)
    }
    func testNoMeasurementsAreUnavailable() {
        let metric = DosePatternPresentation.sleepMetric(night(intervals: []), source: .appleHealth, outcome: .postDose2)
        XCTAssertEqual(metric.state, .unavailable); XCTAssertNil(metric.value)
    }
    func testMorningDoesNotReofferKnownOmissionOrUnchangedCompleteReport() throws {
        XCTAssertFalse(MorningDoseHistoryReviewSection.offersUnresolvedReview(night(hasDose2: false, intervals: [])))
        var row = night(hasDose2: false, hasOmission: false, intervals: [])
        XCTAssertTrue(MorningDoseHistoryReviewSection.offersUnresolvedReview(row))
        let review = DashboardDoseReview(observationID: row.id, sourceFingerprint: try XCTUnwrap(row.reviewFingerprint),
            confirmedCount: 1, historicalPlanCount: 1, secondNotTaken: nil, recordedAt: start, reason: "Synthetic report")
        var ledger = DashboardDoseReviewLedger(); try ledger.append(review, expectedRevision: nil, now: start)
        row.doseReviewLedger = ledger
        XCTAssertFalse(MorningDoseHistoryReviewSection.offersUnresolvedReview(row))
        XCTAssertEqual(row.dosePattern.pattern, .singlePlanned); XCTAssertEqual(row.doseEvents.count, 1)
        row.doseEvents.append(.init(id: "correction", eventType: "history_correction", timestamp: start,
            sessionDate: row.sessionDate, sessionId: "s"))
        XCTAssertTrue(MorningDoseHistoryReviewSection.offersUnresolvedReview(row))
        XCTAssertEqual(row.doseReviewLedger?.current?.revisionID, review.revisionID)
    }
    func testAmountIsOnlyRecordedAdministrationMetadata() {
        for (metadata, expected) in [("{\"amount_mg\":4500}", 4500.0 as Double?), ("{\"amount_mg\":true}", nil),
                                     ("{\"amount_mg\":-1}", nil), ("not JSON", nil)] {
            let event = StoredDoseEvent(id: "amount", eventType: "dose1", timestamp: start, sessionDate: "2026-09-29", metadata: metadata)
            XCTAssertEqual(DosePatternPresentation.recordedAmountMg(event), expected)
        }
    }
}
