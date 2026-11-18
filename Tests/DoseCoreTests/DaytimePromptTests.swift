import XCTest
@testable import DoseCore

final class DaytimePromptTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_769_600)
    func testDefaultOffAndInvalidClockRejected() throws {
        XCTAssertFalse(DaytimePromptLedger().enabled)
        XCTAssertThrowsError(try DaytimePromptSchedule(hour: 24, minute: 0, timeZone: "UTC", createdAt: now))
    }
    func testRetryKeepsIdentityAndRevisionPreservesHistory() throws {
        var ledger = DaytimePromptLedger()
        try ledger.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true, at: now)
        let first = try XCTUnwrap(ledger.prepare(at: now))
        XCTAssertEqual(ledger.prepare(at: now)?.id, first.id)
        try ledger.configure(hour: 15, minute: 0, timeZone: "UTC", enabled: true, at: now)
        XCTAssertEqual(ledger.prompts.first?.status, .suppressed)
        XCTAssertEqual(ledger.schedules.count, 2)
        XCTAssertNotEqual(ledger.prepare(at: now)?.id, first.id)
    }
    func testLateResponseRetainsIntendedTimeAndNoInventedDelivery() throws {
        var ledger = DaytimePromptLedger()
        try ledger.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true, at: now)
        let prompt = try XCTUnwrap(ledger.prepare(at: now))
        let actual = prompt.intendedAt.addingTimeInterval(7200), assessment = UUID()
        try ledger.respond(id: prompt.id, assessmentID: assessment, assessedAt: actual, at: actual)
        XCTAssertEqual(ledger.prompts[0].intendedAt, prompt.intendedAt)
        XCTAssertEqual(ledger.prompts[0].assessedAt, actual)
        XCTAssertEqual(ledger.prompts[0].status, .responded)
        XCTAssertThrowsError(try ledger.respond(id: prompt.id, assessmentID: UUID(), assessedAt: actual, at: actual))
    }
    func testQuietWindowAndDSTGapUseNextValidTime() throws {
        let zone = "America/New_York"
        var ledger = DaytimePromptLedger()
        let before = ISO8601DateFormatter().date(from: "2026-03-08T05:00:00Z")!
        try ledger.configure(hour: 2, minute: 30, timeZone: zone, enabled: true, at: before)
        XCTAssertEqual(ledger.prepare(at: before)?.intendedAt, ISO8601DateFormatter().date(from: "2026-03-08T07:00:00Z"))
        XCTAssertTrue(DaytimePromptSchedule.isQuiet(minute: 60, start: 1320, end: 420))
        XCTAssertFalse(DaytimePromptSchedule.isQuiet(minute: 840, start: 1320, end: 420))
    }
    func testSevenDayHorizonDeduplicatesAndRenewsOnlyMissingDates() throws {
        var ledger = DaytimePromptLedger()
        try ledger.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true, at: now)
        let first = ledger.prepareHorizon(at: now)
        XCTAssertEqual(first.count, 7)
        XCTAssertEqual(ledger.prepareHorizon(at: now).map(\.id), first.map(\.id))
        XCTAssertEqual(Set(first.map(\.id)).count, 7)
        let later = ledger.prepareHorizon(at: now.addingTimeInterval(86400))
        XCTAssertEqual(later.count, 7)
        XCTAssertEqual(Set(first.map(\.id)).intersection(Set(later.map(\.id))).count, 6)
        XCTAssertNoThrow(try ledger.validate())
    }
    func testSpringForwardDoesNotRejectTwoRecentUnansweredSlots() throws {
        var ledger = DaytimePromptLedger()
        let before = ISO8601DateFormatter().date(from: "2026-03-07T05:00:00Z")!
        try ledger.configure(hour: 2, minute: 30, timeZone: "America/New_York", enabled: true, at: before)
        _ = ledger.prepareHorizon(at: before)
        _ = ledger.prepareHorizon(at: ISO8601DateFormatter().date(from: "2026-03-08T07:15:00Z")!)
        XCTAssertNoThrow(try ledger.validate())
    }
    func testResponseRetryCannotRewriteEvidenceAndFirstOpenIsPreserved() throws {
        var ledger = DaytimePromptLedger()
        try ledger.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true, at: now)
        let prompt = try XCTUnwrap(ledger.prepare(at: now)), id = UUID(), actual = prompt.intendedAt.addingTimeInterval(7200)
        try ledger.open(id: prompt.id, at: actual)
        try ledger.open(id: prompt.id, at: actual.addingTimeInterval(60))
        XCTAssertEqual(ledger.prompts[0].openedAt, actual)
        try ledger.respond(id: prompt.id, assessmentID: id, assessedAt: actual, at: actual)
        XCTAssertThrowsError(try ledger.respond(id: prompt.id, assessmentID: id, assessedAt: actual, at: actual.addingTimeInterval(60)))
    }
    func testSleepNowDoesNotInventSuppressionOfPastPrompt() throws {
        var ledger = DaytimePromptLedger()
        try ledger.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true, at: now)
        let prompt = try XCTUnwrap(ledger.prepare(at: now))
        ledger.suppressDue(at: prompt.intendedAt.addingTimeInterval(3600), reason: "Sleep active now")
        XCTAssertEqual(ledger.prompts[0].status, .expired)
        XCTAssertEqual(ledger.prompts[0].reason, "No response recorded; earlier delivery unknown")
    }
    func testFutureEligibilityRecoveryKeepsIDsAndDoesNotUndoSkip() throws {
        for reason in ["Notification permission unavailable", "Inside configured quiet hours"] {
            var ledger = DaytimePromptLedger()
            try ledger.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true, at: now)
            let first = ledger.prepareHorizon(at: now)
            try ledger.skip(id: first[0].id)
            ledger.suppress(id: first[1].id, reason: reason)
            let recovered = ledger.prepareHorizon(at: now)
            XCTAssertEqual(recovered.count, 6)
            XCTAssertTrue(recovered.contains { $0.id == first[1].id })
            XCTAssertEqual(ledger.prompts[0].status, .skipped)
            XCTAssertEqual(ledger.prompts.count, 7)
        }
    }
    func testExpiredIsNonresponseAndCannotBecomeZero() throws {
        var ledger = DaytimePromptLedger()
        try ledger.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true, at: now)
        let prompt = try XCTUnwrap(ledger.prepare(at: now))
        _ = ledger.prepare(at: prompt.intendedAt.addingTimeInterval(86400))
        XCTAssertEqual(ledger.prompts[0].status, .expired)
        XCTAssertNil(ledger.prompts[0].assessmentID)
    }
    func testISOMillisecondPayloadRoundTripKeepsRetryAndMinuteBoundary() throws {
        var ledger = DaytimePromptLedger()
        let precise = now.addingTimeInterval(0.123456), responseID = UUID()
        try ledger.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true, at: precise)
        let prompt = try XCTUnwrap(ledger.prepare(at: precise))
        let assessed = prompt.intendedAt.addingTimeInterval(0.123456)
        try ledger.respond(id: prompt.id, assessmentID: responseID, assessedAt: assessed, at: assessed)
        let payload = try ledger.encodedPayload()
        XCTAssertTrue(try XCTUnwrap(String(data: payload, encoding: .utf8)).contains(".123Z"))
        var restored = try DaytimePromptLedger.decodePayload(payload)
        XCTAssertEqual(try restored.encodedPayload(), payload)
        XCTAssertEqual(restored.prompts[0].intendedAt, prompt.intendedAt)
        XCTAssertNoThrow(try restored.respond(id: prompt.id, assessmentID: responseID, assessedAt: assessed, at: assessed))
        XCTAssertEqual(try restored.encodedPayload(), payload)
        var invalid = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        var schedules = try XCTUnwrap(invalid["schedules"] as? [[String: Any]])
        schedules[0]["createdAt"] = 123.456; invalid["schedules"] = schedules
        XCTAssertThrowsError(try DaytimePromptLedger.decodePayload(JSONSerialization.data(withJSONObject: invalid)))
        XCTAssertThrowsError(try restored.respond(id: prompt.id, assessmentID: responseID,
                            assessedAt: assessed, at: assessed.addingTimeInterval(0.002)))
    }

}
