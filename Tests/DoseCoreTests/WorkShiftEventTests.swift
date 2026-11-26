import XCTest
@testable import DoseCore

final class WorkShiftEventTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    func event() -> WorkShiftEvent {
        var value = WorkShiftEvent(timeZoneIdentifier: "UTC", recordedAt: start.addingTimeInterval(7200))
        value.scheduledStart = start; value.scheduledEnd = start.addingTimeInterval(3600)
        return value
    }
    func testScheduledDoesNotEstablishAttendanceAndIntervalIsHalfOpen() {
        var doc = WorkContextDocument(); doc.schemaVersion = 2; doc.shiftEvents = [event()]
        XCTAssertEqual(doc.shiftContexts(at: start, basis: .planned, asOf: start.addingTimeInterval(7200)).count, 1)
        XCTAssertTrue(doc.shiftContexts(at: start.addingTimeInterval(3600), basis: .planned, asOf: start.addingTimeInterval(7200)).isEmpty)
        XCTAssertTrue(doc.shiftContexts(at: start, basis: .confirmed, asOf: start.addingTimeInterval(7200)).isEmpty)
        var future = event(); future.scheduledStart = future.recordedAt.addingTimeInterval(3600); future.scheduledEnd = future.recordedAt.addingTimeInterval(7200)
        XCTAssertTrue(future.isValid)
    }
    func testExplicitActualPrecisionFutureEvidenceAndAmbiguousCandidates() {
        var value = event(); value.status = .worked; value.attendanceConfirmed = true
        value.actualStart = start; value.actualEnd = start.addingTimeInterval(3600)
        XCTAssertNil(value.actualMinutes)
        value.actualTimePrecision = .reportedMinute; XCTAssertEqual(value.actualMinutes, 60)
        var doc = WorkContextDocument(); doc.schemaVersion = 2; var other = value; other.id = UUID(); other.shiftID = UUID(); doc.shiftEvents = [value, other]
        XCTAssertEqual(doc.shiftContexts(at: start, basis: .confirmed, asOf: value.recordedAt).count, 2)
        value.actualEnd = value.recordedAt.addingTimeInterval(1); XCTAssertFalse(value.isValid)
        var occurrence = WorkOccurrence(workDate: "2026-09-22", timeZoneIdentifier: "UTC", attendance: .worked, recordedAt: start)
        occurrence.actualStart = start.addingTimeInterval(1); XCTAssertFalse(occurrence.isValid)
    }
    func testRevisionCancellationAndCardinalityRemainExplicit() {
        var first = event(); first.position = 2; XCTAssertEqual(first.positionLabel, "Shift 2")
        var cancel = first; cancel.id = UUID(); cancel.status = .cancelled; cancel.recordedAt = first.recordedAt.addingTimeInterval(1)
        var doc = WorkContextDocument(); doc.schemaVersion = 2; doc.shiftEvents = [first]
        let snapshot = doc.capturePlan(preSleepLogID: "pre", sessionID: nil, at: first.recordedAt)
        doc.shiftEvents?.append(cancel)
        XCTAssertEqual(doc.latestShiftEvents(asOf: cancel.recordedAt, snapshotID: snapshot?.id).first?.id, first.id)
        XCTAssertEqual(doc.shiftContexts(at: start, basis: .planned, asOf: first.recordedAt).first?.id, first.id)
        XCTAssertTrue(doc.shiftContexts(at: start, basis: .planned, asOf: cancel.recordedAt).isEmpty)
    }
}
