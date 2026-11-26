import XCTest
@testable import DoseCore

final class WorkShiftDateResolutionDraftTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private func shift(_ hour: Double = 0) -> WorkShiftEvent {
        var event = WorkShiftEvent(timeZoneIdentifier: "UTC", recordedAt: now)
        event.workDate = "2026-09-21"; event.status = .scheduled
        event.scheduledStart = now.addingTimeInterval(hour * 3600)
        event.scheduledEnd = now.addingTimeInterval((hour + 8) * 3600)
        return event
    }
    func testExplicitShiftDateWithUnknownTimesPreservesPlanWithoutAnchors() throws {
        var event = shift(); event.scheduledStart = nil; event.scheduledEnd = nil
        var doc = WorkContextDocument(); doc.schemaVersion = 3; doc.shiftEvents = [event]
        let row = try XCTUnwrap(doc.resolvedWorkDate("2026-09-21", timeZoneIdentifier: "UTC", asOf: now))
        XCTAssertEqual(row.plannedWorking, true); XCTAssertEqual(row.plannedSourceID, event.id)
        XCTAssertNil(row.scheduledStart); XCTAssertNil(row.scheduledEnd); XCTAssertNil(row.actualStart)
    }
    func testUniqueScheduledShiftPublishesItsRevisionAndMultipleShiftsRemainAmbiguous() throws {
        let event = shift()
        var doc = WorkContextDocument(); doc.schemaVersion = 3; doc.shiftEvents = [event]
        let row = try XCTUnwrap(doc.resolvedWorkDate("2026-09-21", timeZoneIdentifier: "UTC", asOf: now))
        XCTAssertEqual(row.scheduledStart, event.scheduledStart); XCTAssertEqual(row.shiftSourceID, event.id)
        doc.shiftEvents?.append(shift(1))
        let ambiguous = try XCTUnwrap(doc.resolvedWorkDate("2026-09-21", timeZoneIdentifier: "UTC", asOf: now))
        XCTAssertNil(ambiguous.scheduledStart); XCTAssertNil(ambiguous.scheduledEnd)
    }
    func testLaterCancellationClearsScheduledAnchorsButNotRecordedHistory() throws {
        let original = shift(); var cancellation = original
        cancellation.id = UUID(); cancellation.status = .cancelled; cancellation.recordedAt = now.addingTimeInterval(1)
        var doc = WorkContextDocument(); doc.schemaVersion = 3; doc.shiftEvents = [original, cancellation]
        XCTAssertEqual(doc.resolvedWorkDate("2026-09-21", timeZoneIdentifier: "UTC", asOf: now)?.plannedWorking, true)
        let current = try XCTUnwrap(doc.resolvedWorkDate("2026-09-21", timeZoneIdentifier: "UTC", asOf: cancellation.recordedAt))
        XCTAssertEqual(current.plannedWorking, false); XCTAssertNil(current.scheduledStart)
        XCTAssertEqual(doc.shiftEvents?.count, 2)
    }
    func testCapturingNewPlanNeverDowngradesEventContextSchema() throws {
        var doc = WorkContextDocument(); doc.schemaVersion = 3; doc.shiftEvents = [shift()]
        XCTAssertNotNil(doc.capturePlan(preSleepLogID: "pre", sessionID: "session:exact", at: now))
        XCTAssertEqual(doc.schemaVersion, 3)
        let decoded = try JSONDecoder().decode(WorkContextDocument.self, from: JSONEncoder().encode(doc))
        XCTAssertTrue(decoded.isValid); XCTAssertEqual(decoded.shiftEvents?.first?.workDate, "2026-09-21")
    }

    func testWorkedWithoutRecordedPlanDoesNotCreateScheduledAnchors() throws {
        var event = shift(); event.status = .worked; event.attendanceConfirmed = true
        event.scheduledStart = nil; event.scheduledEnd = nil
        var doc = WorkContextDocument(); doc.schemaVersion = 3; doc.shiftEvents = [event]
        let row = try XCTUnwrap(doc.resolvedWorkDate("2026-09-21", timeZoneIdentifier: "UTC", asOf: now))
        XCTAssertNil(row.plannedWorking); XCTAssertEqual(row.attendance, .worked)
        XCTAssertNil(row.scheduledStart); XCTAssertNil(row.scheduledEnd)
    }

}
