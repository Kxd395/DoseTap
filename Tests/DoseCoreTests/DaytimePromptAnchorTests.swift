import XCTest
@testable import DoseCore

final class DaytimePromptAnchorTests: XCTestCase {
    func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    let zone = "America/New_York"
    func testThirteenHourMidpointRequiresReviewedEndpoints() throws {
        let start = date("2026-09-30T11:00:00Z"), end = date("2026-10-01T00:00:00Z")
        let source = try DaytimeAnchorSource(id: "shift-1", revision: "r1", at: start, endAt: end)
        let context = DaytimePromptAnchorContext(dayKey: "2026-09-30", timeZone: zone, working: true, shift: source)
        let rule = try DaytimePromptRule(anchor: .shiftMidpoint)
        let resolved = rule.resolve(day: start, clockHour: 14, clockMinute: 0, timeZone: zone, context: context, now: start)
        XCTAssertEqual(resolved.intendedAt, date("2026-09-30T17:30:00Z"))
        XCTAssertEqual(resolved.sourceID, "shift-1")
        XCTAssertEqual(resolved.sourceRevision, "r1")
        let missing = rule.resolve(day: start, clockHour: 14, clockMinute: 0, timeZone: zone,
                                   context: .init(dayKey: "2026-09-30", timeZone: zone, working: true), now: start)
        XCTAssertNil(missing.intendedAt)
        XCTAssertNotNil(missing.unavailableReason)
    }
    func testOffDayClockIsSeparateFromUnknownWorkStatus() throws {
        let day = date("2026-09-30T11:00:00Z")
        let rule = try DaytimePromptRule(anchor: .shiftMidpoint, offDayAnchor: .clock, offDayHour: 15, offDayMinute: 15)
        let off = rule.resolve(day: day, clockHour: 14, clockMinute: 0, timeZone: zone,
                               context: .init(dayKey: "2026-09-30", timeZone: zone, working: false), now: day)
        XCTAssertEqual(off.intendedAt, date("2026-09-30T19:15:00Z"))
        XCTAssertTrue(off.label.contains("Off-day"))
        XCTAssertNil(rule.resolve(day: day, clockHour: 14, clockMinute: 0, timeZone: zone, context: nil, now: day).intendedAt)
    }
    func testMainWakeUsesExplicitSourceAndElapsedOffset() throws {
        let wake = date("2026-09-30T12:00:00Z")
        let source = try DaytimeAnchorSource(id: "night-outcome-1", revision: "wake-r2", at: wake)
        let context = DaytimePromptAnchorContext(dayKey: "2026-09-30", timeZone: zone, mainWake: source)
        let rule = try DaytimePromptRule(anchor: .mainWake, wakeOffsetMinutes: 240)
        let resolved = rule.resolve(day: wake, clockHour: 14, clockMinute: 0, timeZone: zone, context: context, now: wake)
        XCTAssertEqual(resolved.intendedAt, date("2026-09-30T16:00:00Z"))
        XCTAssertEqual(resolved.sourceAt, wake)
        XCTAssertNil(rule.resolve(day: wake, clockHour: 14, clockMinute: 0, timeZone: zone, context: nil, now: wake).intendedAt)
    }
    func testWeekdaysAndTimezoneMismatchStayExplicitlyUnscheduled() throws {
        let day = date("2026-09-30T12:00:00Z") // Wednesday; Gregorian weekday4.
        let rule = try DaytimePromptRule(anchor: .clock, selectedWeekdays: [2])
        XCTAssertNil(rule.resolve(day: day, clockHour: 14, clockMinute: 0, timeZone: zone, context: nil, now: day).intendedAt)
        let wakeRule = try DaytimePromptRule(anchor: .mainWake)
        let foreign = DaytimePromptAnchorContext(dayKey: "2026-09-30", timeZone: "Europe/London", working: true)
        XCTAssertNil(wakeRule.resolve(day: day, clockHour: 14, clockMinute: 0, timeZone: zone, context: foreign, now: day).intendedAt)
        XCTAssertThrowsError(try DaytimePromptRule(anchor: .clock, selectedWeekdays: []))
        XCTAssertThrowsError(try DaytimePromptRule(anchor: .mainWake, wakeOffsetMinutes: -1))
    }
    func testExplicitSavedBreakDoesNotBecomeMidpoint() throws {
        let day = date("2026-09-30T11:00:00Z"), breakAt = date("2026-09-30T16:15:00Z")
        let context = DaytimePromptAnchorContext(dayKey: "2026-09-30", timeZone: zone, working: true,
                        plannedBreak: try DaytimeAnchorSource(id: "break-3", revision: "r3", at: breakAt))
        let rule = try DaytimePromptRule(anchor: .shiftBreak)
        XCTAssertEqual(rule.resolve(day: day, clockHour: 14, clockMinute: 0, timeZone: zone, context: context, now: day).intendedAt, breakAt)
    }
    func testFutureWakeCannotBeUsedAsObservedMainWake() throws {
        let now = date("2026-09-30T11:00:00Z")
        let wake = try DaytimeAnchorSource(id: "future", revision: "r1", at: now.addingTimeInterval(3600))
        let context = DaytimePromptAnchorContext(dayKey: "2026-09-30", timeZone: zone, mainWake: wake)
        let rule = try DaytimePromptRule(anchor: .mainWake)
        XCTAssertNil(rule.resolve(day: now, clockHour: 14, clockMinute: 0, timeZone: zone, context: context, now: now).intendedAt)
    }

    func testRandomWakeWindowsAreStableBoundedAndSeparateByDayType() throws {
        let wake = date("2026-10-05T09:00:00Z")
        let source = try DaytimeAnchorSource(id: "wake", revision: "r1", at: wake)
        let rule = try DaytimePromptRule(anchor: .mainWake, randomizedWake: .init())
        for working in [true, false] {
            let context = DaytimePromptAnchorContext(dayKey: "2026-10-05", timeZone: zone, working: working, mainWake: source)
            var ledger = DaytimePromptLedger()
            try ledger.configure(hour: 14, minute: 0, timeZone: zone, enabled: true, at: wake, rule: rule)
            let first = ledger.prepareHorizon(at: wake, contexts: [context])
            XCTAssertEqual(first.count, working ? 3 : 2)
            XCTAssertEqual(first, ledger.prepareHorizon(at: wake.addingTimeInterval(60), contexts: [context]))
            var restored = try DaytimePromptLedger.decodePayload(ledger.encodedPayload())
            XCTAssertEqual(first, restored.prepareHorizon(at: wake, contexts: [context]))
            for (index, prompt) in first.enumerated() {
                XCTAssertGreaterThanOrEqual(prompt.intendedAt, try XCTUnwrap(prompt.windowStart))
                XCTAssertLessThanOrEqual(prompt.intendedAt, try XCTUnwrap(prompt.windowEnd))
                if index > 0 { XCTAssertGreaterThanOrEqual(prompt.intendedAt.timeIntervalSince(first[index - 1].intendedAt), 7200) }
            }
            try ledger.respond(id: first[0].id, assessmentID: UUID(), assessedAt: first[0].intendedAt, at: first[0].intendedAt)
            XCTAssertEqual(ledger.prepareHorizon(at: first[0].intendedAt, contexts: [context]).count, first.count - 1)
        }
    }
    func testRandomWakeRequiresWorkStatusAndHonorsBedtimeAndCorrection() throws {
        let wake = date("2026-10-05T09:00:00Z")
        let source = try DaytimeAnchorSource(id: "wake", revision: "r1", at: wake)
        var ledger = DaytimePromptLedger()
        try ledger.configure(hour: 14, minute: 0, timeZone: zone, enabled: true, at: wake,
            rule: DaytimePromptRule(anchor: .mainWake, randomizedWake: .init(workBedtimeMinute: 900)))
        XCTAssertTrue(ledger.prepareHorizon(at: wake, contexts: [.init(dayKey: "2026-10-05", timeZone: zone, mainWake: source)]).isEmpty)
        let context = DaytimePromptAnchorContext(dayKey: "2026-10-05", timeZone: zone, working: true, mainWake: source)
        let prompts = ledger.prepareHorizon(at: wake, contexts: [context])
        XCTAssertEqual(prompts.count, 2)
        XCTAssertTrue(prompts.allSatisfy { $0.intendedAt <= date("2026-10-05T17:00:00Z") })
        let corrected = try DaytimeAnchorSource(id: "wake", revision: "r2", at: wake.addingTimeInterval(600))
        XCTAssertTrue(ledger.prepareHorizon(at: wake.addingTimeInterval(600), contexts: [.init(dayKey: "2026-10-05", timeZone: zone, working: true, mainWake: corrected)]).isEmpty)
    }

    func testRandomWakeDSTAndDeferralStayWithinWindows() throws {
        for stamp in ["2026-03-08T05:30:00Z", "2026-11-01T04:30:00Z"] {
            let wake = date(stamp), key = DaytimePromptRule.dayKey(wake, timeZone: zone)
            let context = DaytimePromptAnchorContext(dayKey: key, timeZone: zone, working: true,
                mainWake: try DaytimeAnchorSource(id: key, revision: "r1", at: wake))
            var ledger = DaytimePromptLedger()
            try ledger.configure(hour: 14, minute: 0, timeZone: zone, enabled: true, at: wake,
                rule: DaytimePromptRule(anchor: .mainWake, randomizedWake: .init()))
            let slots = ledger.prepareHorizon(at: wake, contexts: [context])
            XCTAssertEqual(slots.count, 3)
            XCTAssertEqual(slots[0].windowStart!.timeIntervalSince(wake), 7200)
            XCTAssertThrowsError(try ledger.deferPrompt(id: slots[0].id, until: slots[0].windowEnd!.addingTimeInterval(1), now: wake))
            try ledger.satisfyRandomizedWindow(assessmentID: UUID(), assessedAt: slots[0].windowStart!, recordedAt: slots[0].windowStart!)
            XCTAssertEqual(ledger.prompts[0].status, .responded)
            XCTAssertEqual(ledger.prepareHorizon(at: slots[0].windowStart!, contexts: [context]).count, 2)
            try ledger.configure(hour: 14, minute: 0, timeZone: zone, enabled: true, at: slots[0].windowStart!,
                rule: DaytimePromptRule(anchor: .mainWake, randomizedWake: .init()))
            XCTAssertFalse(ledger.prepareHorizon(at: slots[0].windowStart!, contexts: [context]).contains { $0.windowIndex == 0 })
        }
    }
    func testRandomWakeRejectsInvalidRoutineAndKeepsLegacyPayloadReadable() throws {
        XCTAssertThrowsError(try DaytimePromptRule(anchor: .clock, randomizedWake: .init()))
        XCTAssertThrowsError(try DaytimePromptRule(anchor: .mainWake, randomizedWake: .init(offBedtimeMinute: 1440)))
        var ledger = DaytimePromptLedger()
        try ledger.configure(hour: 14, minute: 0, timeZone: zone, enabled: true, at: date("2026-10-05T09:00:00Z"), rule: DaytimePromptRule(anchor: .clock))
        XCTAssertEqual(try DaytimePromptLedger.decodePayload(ledger.encodedPayload()), ledger)
    }

    func testFractionalWakeDoesNotDropWindowWhenRandomChoiceReachesUpperEdge() throws {
        let wake = date("2026-10-05T09:00:00Z").addingTimeInterval(0.123)
        var template = DaytimePromptLedger()
        try template.configure(hour: 14, minute: 0, timeZone: zone, enabled: true, at: wake,
            rule: DaytimePromptRule(anchor: .mainWake, randomizedWake: .init()))
        // Fixed schedule seed selected to exercise the old upper-edge draw deterministically.
        let payload = String(decoding: try template.encodedPayload(), as: UTF8.self)
            .replacingOccurrences(of: template.current!.id.uuidString, with: "00000000-0000-0000-0000-000000000035")
        var ledger = try DaytimePromptLedger.decodePayload(Data(payload.utf8))
        let context = DaytimePromptAnchorContext(dayKey: "2026-10-05", timeZone: zone, working: true,
            mainWake: try DaytimeAnchorSource(id: "wake", revision: "r1", at: wake))
        let slots = ledger.prepareHorizon(at: wake, contexts: [context])
        XCTAssertEqual(slots.count, 3, "Whole-second notification rounding must not discard a valid window")
        XCTAssertEqual(slots.map(\.windowIndex), [0, 1, 2])
        for slot in slots {
            XCTAssertGreaterThanOrEqual(slot.intendedAt, slot.windowStart!)
            XCTAssertLessThanOrEqual(slot.intendedAt, slot.windowEnd!)
            XCTAssertEqual(slot.nextAttemptAt.timeIntervalSince1970.rounded(.down), slot.nextAttemptAt.timeIntervalSince1970)
        }
        XCTAssertEqual(ledger.prepareHorizon(at: wake.addingTimeInterval(1), contexts: [context]), slots)
    }

}
