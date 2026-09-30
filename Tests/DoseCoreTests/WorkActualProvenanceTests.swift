import XCTest
@testable import DoseCore

final class WorkActualProvenanceTests: XCTestCase {
    func testExactZeroGapAndClassifierProvenanceSurviveCSV() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let evidence = WorkCycleMetricEvidence(metricID: "gap", source: "actual_shift_events", definitionVersion: "v1",
            metric: .init(value: 0, state: .available, reason: "touching endpoints", unit: "minutes"), start: now, end: now)
        var row = WorkCycleObservation(sleepID: "session:a", sleepDate: "2026-09-21", phase: .after,
            position: "First post-block main sleep", blockID: "block:stable", value: nil)
        row.classificationVersion = 2; row.firstShiftDate = "2026-09-18"; row.metricSourceRecordIDs = ["shift-revision"]
        row = row.applying(evidence, includePartial: false, asOf: now)
        XCTAssertEqual(row.value, 0)
        let csv = WorkCycleSummary.csv([row], metric: "Gap", basis: .confirmed, range: "Selected",
            revision: nil, asOf: now)
        let records = try ReportCSV.rows(csv), headers = try XCTUnwrap(records.first)
        let values = try XCTUnwrap(records.dropFirst().first)
        XCTAssertEqual(values[try XCTUnwrap(headers.firstIndex(of: "classification_version"))], "2")
        XCTAssertEqual(values[try XCTUnwrap(headers.firstIndex(of: "first_shift_date"))], "2026-09-18")
        XCTAssertEqual(values[try XCTUnwrap(headers.firstIndex(of: "metric_source_record_ids"))], "shift-revision")
    }
    func testLaterOffBlockReferenceRetainsExactBlockWithoutClaimingAdjacentWork() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var shift = WorkShiftEvent(timeZoneIdentifier: "UTC", recordedAt: now)
        shift.status = .worked; shift.attendanceConfirmed = true; shift.blockID = "block:one"
        shift.position = 3; shift.blockShiftCount = 3; shift.firstShiftDate = "2026-09-17"
        shift.actualEnd = now.addingTimeInterval(-86400)
        var association = WorkSleepAssociation(sleepID: "session:a", precedingDate: "2026-09-20", followingDate: "2026-09-21",
            timeZoneIdentifier: "UTC", plannedAt: now, recordedAt: now)
        var context = WorkSleepEventContext(mainSleepStart: now.addingTimeInterval(-7200), mainSleepEnd: now.addingTimeInterval(-3600),
            precedingStatus: .off, followingStatus: .off, wakingPeriodsReviewed: true)
        context.postBlockReferenceShiftID = shift.shiftID; context.postBlockMainSleepIndex = 2
        association.eventContext = context
        var doc = WorkContextDocument(); doc.schemaVersion = 3; doc.shiftEvents = [shift]; doc.associations = [association]
        let result = doc.classify(association, basis: .confirmed, asOf: now)
        XCTAssertEqual(result.phase, .off); XCTAssertEqual(result.blockID, "block:one")
        XCTAssertEqual(result.postBlockMainSleepIndex, 2); XCTAssertNil(result.precedingPosition)
    }
}
