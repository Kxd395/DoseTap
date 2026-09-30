import XCTest
@testable import DoseCore

final class DaytimePromptHorizonTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-09-30T10:00:00Z")!
    func context(_ hour: Double, revision: String) throws -> DaytimePromptAnchorContext {
        .init(dayKey: "2026-09-30", timeZone: "UTC", mainWake:
            try DaytimeAnchorSource(id: "main-night", revision: revision, at: now.addingTimeInterval((hour - 10) * 3600)))
    }
    func configured(_ rule: DaytimePromptRule) throws -> DaytimePromptLedger {
        var ledger = DaytimePromptLedger()
        try ledger.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true, at: now, rule: rule)
        return ledger
    }
    func testSelectedWeekdaysDoNotExtendBeyondSevenCivilDays() throws {
        var ledger = try configured(DaytimePromptRule(anchor: .clock, selectedWeekdays: [2]))
        let slots = ledger.prepareHorizon(at: now)
        XCTAssertEqual(slots.count, 1)
        XCTAssertEqual(slots.first?.intendedAt, ISO8601DateFormatter().date(from: "2026-10-05T14:00:00Z"))
        XCTAssertEqual(slots.first?.anchorDayKey, "2026-10-05")
    }
    func testChangedFutureWakeRetainsOriginalSourceAndRetryIdentity() throws {
        var ledger = try configured(DaytimePromptRule(anchor: .mainWake, wakeOffsetMinutes: 240))
        let original = try XCTUnwrap(ledger.prepareHorizon(at: now, contexts: [context(9, revision: "r1")]).first)
        let revised = try XCTUnwrap(ledger.prepareHorizon(at: now, contexts: [context(9.5, revision: "r2")]).first)
        XCTAssertNotEqual(original.id, revised.id)
        XCTAssertEqual(ledger.prompts.first?.intendedAt, original.intendedAt)
        XCTAssertEqual(ledger.prompts.first?.anchor?.sourceRevision, "r1")
        XCTAssertEqual(ledger.prompts.first?.status, .suppressed)
        XCTAssertEqual(revised.anchor?.sourceRevision, "r2")
        XCTAssertEqual(try ledger.prepareHorizon(at: now, contexts: [context(9.5, revision: "r2")]).first?.id, revised.id)
        XCTAssertEqual(ledger.prompts.count, 2)
    }
    func testMissingOrConflictingAnchorCancelsOnlyFutureSlot() throws {
        var ledger = try configured(DaytimePromptRule(anchor: .mainWake))
        _ = try ledger.prepareHorizon(at: now, contexts: [context(9, revision: "r1")])
        XCTAssertTrue(ledger.prepareHorizon(at: now, contexts: []).isEmpty)
        XCTAssertEqual(ledger.prompts.first?.status, .suppressed)
        XCTAssertTrue(try ledger.prepareHorizon(at: now, contexts: [context(9, revision: "r1"), context(9.5, revision: "r2")]).isEmpty)
        XCTAssertNil(ledger.prompts.first?.assessmentID)
    }
    func testPastOrExplicitlySkippedSlotDoesNotCreateSecondSameDayPrompt() throws {
        for skip in [false, true] {
            var ledger = try configured(DaytimePromptRule(anchor: .mainWake))
            let original = try XCTUnwrap(ledger.prepareHorizon(at: now, contexts: [context(9, revision: "r1")]).first)
            if skip { try ledger.skip(id: original.id) }
            let later = skip ? now : now.addingTimeInterval(4 * 3600)
            XCTAssertTrue(try ledger.prepareHorizon(at: later, contexts: [context(skip ? 9.5 : 11, revision: "r2")]).isEmpty)
            XCTAssertEqual(ledger.prompts.count, 1)
            XCTAssertEqual(ledger.prompts.first?.id, original.id)
        }
    }
    func testExistingMainWakeIdentityCannotBeReplacedByAnotherNight() throws {
        var ledger = try configured(DaytimePromptRule(anchor: .mainWake))
        _ = try ledger.prepareHorizon(at: now, contexts: [context(9, revision: "r1")])
        let other = DaytimePromptAnchorContext(dayKey: "2026-09-30", timeZone: "UTC", mainWake:
            try DaytimeAnchorSource(id: "different-night", revision: "r2", at: now.addingTimeInterval(-1800)))
        XCTAssertTrue(ledger.prepareHorizon(at: now, contexts: [other]).isEmpty)
        XCTAssertEqual(ledger.prompts.count, 1)
        XCTAssertEqual(ledger.prompts.first?.anchor?.sourceID, "main-night")
    }
    func testFractionalWakeKeepsIntendedPrecisionAndDeclaresWholeSecondAttempt() throws {
        var ledger = try configured(DaytimePromptRule(anchor: .mainWake))
        let wake = try DaytimeAnchorSource(id: "main-night", revision: "r1", at: now.addingTimeInterval(-3599.876544))
        let context = DaytimePromptAnchorContext(dayKey: "2026-09-30", timeZone: "UTC", mainWake: wake)
        let prompt = try XCTUnwrap(ledger.prepareHorizon(at: now, contexts: [context]).first)
        XCTAssertEqual(prompt.intendedAt, wake.at.addingTimeInterval(14400))
        XCTAssertEqual(prompt.nextAttemptAt, Date(timeIntervalSince1970: ceil(prompt.intendedAt.timeIntervalSince1970)))
    }

    func testAnchoredPayloadCannotLoseItsRequiredSourceContext() throws {
        var ledger = try configured(DaytimePromptRule(anchor: .clock))
        _ = ledger.prepareHorizon(at: now)
        let payload = try ledger.encodedPayload()
        XCTAssertEqual(try DaytimePromptLedger.decodePayload(payload).encodedPayload(), payload)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        var prompts = try XCTUnwrap(object["prompts"] as? [[String: Any]])
        prompts[0].removeValue(forKey: "anchor"); object["prompts"] = prompts
        XCTAssertThrowsError(try DaytimePromptLedger.decodePayload(JSONSerialization.data(withJSONObject: object)))
    }

    func testWeeklyTimeAlreadyPassedStillQueuesNextOccurrenceWithinRollingWeek() throws {
        var ledger = try configured(DaytimePromptRule(anchor: .clock, selectedWeekdays: [4]))
        let afternoon = now.addingTimeInterval(5 * 3600)
        let slots = ledger.prepareHorizon(at: afternoon)
        XCTAssertEqual(slots.count, 1)
        XCTAssertEqual(slots.first?.intendedAt, ISO8601DateFormatter().date(from: "2026-10-07T14:00:00Z"))
    }
    func testRollingWeekUsesCivilDaysAcrossFallBack() throws {
        let afternoon = ISO8601DateFormatter().date(from: "2026-10-31T19:00:00Z")!
        var ledger = DaytimePromptLedger()
        try ledger.configure(hour: 14, minute: 0, timeZone: "America/New_York", enabled: true,
                             at: afternoon, rule: DaytimePromptRule(anchor: .clock))
        let slots = ledger.prepareHorizon(at: afternoon)
        XCTAssertEqual(slots.count, 7)
        XCTAssertEqual(slots.last?.intendedAt, ISO8601DateFormatter().date(from: "2026-11-07T19:00:00Z"))
    }

    func testPreviousDayExplicitAnchorCanScheduleAfterMidnight() throws {
        let clock = ISO8601DateFormatter().date(from: "2026-09-30T00:15:00Z")!
        let start = ISO8601DateFormatter().date(from: "2026-09-29T20:00:00Z")!
        let end = ISO8601DateFormatter().date(from: "2026-09-30T09:00:00Z")!
        for anchor in [DaytimePromptRule.Anchor.mainWake, .shiftMidpoint] {
            var ledger = DaytimePromptLedger()
            try ledger.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true, at: clock,
                                 rule: DaytimePromptRule(anchor: anchor, selectedWeekdays: [3], wakeOffsetMinutes: 390))
            let source = try DaytimeAnchorSource(id: "prior-day-source", revision: "r1", at: start, endAt: end)
            let context = DaytimePromptAnchorContext(dayKey: "2026-09-29", timeZone: "UTC", working: true,
                                                    mainWake: source, shift: source)
            let slots = ledger.prepareHorizon(at: clock, contexts: [context])
            XCTAssertEqual(slots.count, 1)
            XCTAssertEqual(slots.first?.intendedAt, ISO8601DateFormatter().date(from: "2026-09-30T02:30:00Z"))
            XCTAssertEqual(slots.first?.anchorDayKey, "2026-09-29")
            var otherDay = DaytimePromptLedger()
            try otherDay.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true, at: clock,
                                   rule: DaytimePromptRule(anchor: anchor, selectedWeekdays: [4], wakeOffsetMinutes: 390))
            XCTAssertTrue(otherDay.prepareHorizon(at: clock, contexts: [context]).isEmpty)
        }
    }

}
