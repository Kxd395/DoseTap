import XCTest
@testable import DoseCore

final class PhysicianVisitTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let zone = TimeZone(identifier: "America/New_York")!
    func testAppointmentsCannotReplaceCompletedVisitAnchor() throws {
        var ledger = PhysicianVisitLedger()
        let visit = try PhysicianVisit(occurredAt: now.addingTimeInterval(-86400), recordedAt: now, note: "Reviewed sleep", now: now)
        try ledger.append(visit, now: now)
        let booking = PhysicianAppointment(id: UUID(), scheduledAt: now.addingTimeInterval(86400), status: .cancelled)
        ledger.appointments = [booking]
        let period = try PhysicianReportPeriod.resolve(.sinceCompletedVisit, ledger: ledger, asOf: now, timeZone: zone)
        XCTAssertEqual(period.start, visit.occurredAt)
        XCTAssertEqual(period.completedVisitID, visit.id)
    }
    func testCorrectionPreservesHistoryAndRejectsStaleRevision() throws {
        var ledger = PhysicianVisitLedger()
        let first = try PhysicianVisit(occurredAt: now.addingTimeInterval(-86400), recordedAt: now, now: now)
        try ledger.append(first, now: now)
        let replacement = try PhysicianVisit(id: first.id, predecessorID: first.revisionID, occurredAt: now.addingTimeInterval(-172800), recordedAt: now, now: now)
        try ledger.append(replacement, now: now)
        XCTAssertEqual(ledger.current.count, 1)
        XCTAssertEqual(ledger.revisions.count, 2)
        XCTAssertThrowsError(try ledger.append(replacement, now: now))
        XCTAssertEqual(ledger.lastCompleted(asOf: now)?.occurredAt, replacement.occurredAt)
    }
    func testMissingVisitAndInvalidBoundsFailClosed() throws {
        XCTAssertThrowsError(try PhysicianReportPeriod.resolve(.sinceCompletedVisit, ledger: .init(), asOf: now, timeZone: zone))
        XCTAssertThrowsError(try PhysicianReportPeriod.resolve(.custom(start: now, endExclusive: now), ledger: .init(), asOf: now, timeZone: zone))
        XCTAssertThrowsError(try PhysicianReportPeriod.resolve(.custom(start: now.addingTimeInterval(-1), endExclusive: now.addingTimeInterval(1)), ledger: .init(), asOf: now, timeZone: zone))
        XCTAssertThrowsError(try PhysicianVisit(occurredAt: now.addingTimeInterval(1), recordedAt: now, now: now))
    }
    func testCalendarMonthsAndDSTKeepExplicitBounds() throws {
        let formatter = ISO8601DateFormatter()
        let cutoff = formatter.date(from: "2026-11-10T17:00:00Z")!
        let period = try PhysicianReportPeriod.resolve(.days28, ledger: .init(), asOf: cutoff, timeZone: zone)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        XCTAssertEqual(period.start, calendar.date(byAdding: .day, value: -27, to: calendar.startOfDay(for: cutoff)))
        XCTAssertEqual(period.endExclusive, cutoff)
        XCTAssertEqual(period.calendarDayCount, 28)
        let months = try PhysicianReportPeriod.resolve(.sixMonths, ledger: .init(), asOf: cutoff, timeZone: zone)
        XCTAssertNotEqual(months.start, cutoff.addingTimeInterval(-180 * 86400))
        XCTAssertFalse(period.contains(cutoff))
        XCTAssertTrue(period.contains(period.start))
    }
    func testSubsecondCustomRangeRemainsNonempty() throws {
        let range = try PhysicianReportPeriod.resolve(.custom(start: now.addingTimeInterval(-0.1), endExclusive: now), ledger: .init(), asOf: now, timeZone: zone)
        XCTAssertEqual(range.calendarDayCount, 1)
    }
    func testMalformedDecodedLedgerIsRejected() throws {
        let visit = try PhysicianVisit(occurredAt: now.addingTimeInterval(-1), recordedAt: now, now: now)
        var ledger = PhysicianVisitLedger(); try ledger.append(visit, now: now)
        var data = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger)) as! [String: Any]
        data["revisions"] = (data["revisions"] as! [[String: Any]]) + (data["revisions"] as! [[String: Any]])
        let malformed = try JSONDecoder().decode(PhysicianVisitLedger.self, from: JSONSerialization.data(withJSONObject: data))
        XCTAssertThrowsError(try malformed.validate(now: now))
    }
}
