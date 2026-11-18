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

    func randomLedger(seed: Int = 1) throws -> DaytimePromptLedger {
        var value = DaytimePromptLedger()
        try value.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true,
            at: date("2035-10-04T23:00:00Z"), rule: DaytimePromptRule(anchor: .mainWake,
            randomizedWake: .init(workBedtimeMinute: 1380)))
        let fixed = String(format: "00000000-0000-0000-0000-%012d", seed)
        let text = String(decoding: try value.encodedPayload(), as: UTF8.self)
            .replacingOccurrences(of: value.current!.id.uuidString, with: fixed)
        return try DaytimePromptLedger.decodePayload(Data(text.utf8))
    }
    func wakeContext(_ stamp: String, revision: String = "r1", workID: String = "work-A") throws -> DaytimePromptAnchorContext {
        let wake = date(stamp)
        return .init(dayKey: DaytimePromptRule.dayKey(wake, timeZone: "UTC"), timeZone: "UTC",
            working: true, mainWake: try DaytimeAnchorSource(id: stamp, revision: revision, at: wake),
            workSourceID: workID, workRevision: "w1")
    }
    func testRandomizedSpacingIncludesRetainedPreviousWakeDay() throws {
        let prior = try wakeContext("2035-10-04T23:00:00Z"), today = try wakeContext("2035-10-05T09:00:00Z")
        for seed in 1...24 {
            var ledger = try randomLedger(seed: seed)
            _ = ledger.prepareHorizon(at: prior.mainWake!.at, contexts: [prior])
            let retained = ledger.prompts
            _ = ledger.prepareHorizon(at: today.mainWake!.at, contexts: [prior, today])
            XCTAssertEqual(Array(ledger.prompts.prefix(retained.count)), retained)
            let attempts = ledger.prompts.map(\.nextAttemptAt).sorted()
            for pair in zip(attempts, attempts.dropFirst()) {
                XCTAssertGreaterThanOrEqual(pair.1.timeIntervalSince(pair.0), 7200, "seed \(seed)")
            }
        }
    }
    func testCorrectionPreservesPastAttemptAndIncludesWorkSourceIdentity() throws {
        let context = try wakeContext("2035-10-05T09:00:00Z")
        var ledger = try randomLedger()
        let slots = ledger.prepareHorizon(at: context.mainWake!.at, contexts: [context])
        let first = try XCTUnwrap(slots.first)
        let attempted = first.nextAttemptAt.addingTimeInterval(1)
        let corrected = try wakeContext("2035-10-05T09:00:00Z", revision: "r2")
        _ = ledger.prepareHorizon(at: attempted, contexts: [corrected])
        XCTAssertEqual(ledger.prompts[0], first)
        XCTAssertTrue(ledger.prompts.dropFirst().allSatisfy { $0.status == .suppressed })
        var sourceLedger = try randomLedger()
        _ = sourceLedger.prepareHorizon(at: context.mainWake!.at, contexts: [context])
        _ = sourceLedger.prepareHorizon(at: context.mainWake!.at, contexts: [try wakeContext("2035-10-05T09:00:00Z", workID: "work-B")])
        XCTAssertTrue(sourceLedger.prompts.allSatisfy { $0.status == .suppressed })
        var deferred = try randomLedger()
        let original = try XCTUnwrap(deferred.prepareHorizon(at: context.mainWake!.at, contexts: [context]).first)
        let later = min(original.nextAttemptAt.addingTimeInterval(60), original.windowEnd!)
        try deferred.deferPrompt(id: original.id, until: later, now: context.mainWake!.at)
        _ = deferred.prepareHorizon(at: later.addingTimeInterval(1), contexts: [corrected])
        XCTAssertEqual(deferred.prompts[0].status, .deferred)
    }
    func testManualCompletionRecoversOnlyEnvironmentalSuppression() throws {
        let context = try wakeContext("2035-10-05T09:00:00Z")
        for reason in ["Notification permission unavailable", "Inside configured quiet hours", "Known sleep or nap active", "Wake or work evidence changed; review the routine", "Schedule changed"] {
            for offset in [0.0, 3600.0, 7200.0] {
                var ledger = try randomLedger()
                let slot = try XCTUnwrap(ledger.prepareHorizon(at: context.mainWake!.at, contexts: [context]).first)
                ledger.suppress(id: slot.id, reason: reason)
                let assessed = min(slot.windowStart!.addingTimeInterval(offset), slot.windowEnd!)
                let id = UUID()
                try ledger.satisfyRandomizedWindow(assessmentID: id, assessedAt: assessed, recordedAt: assessed)
                let recoverable = ["Notification permission unavailable", "Inside configured quiet hours", "Known sleep or nap active"].contains(reason)
                XCTAssertEqual(ledger.prompts[0].assessmentID, recoverable ? id : nil, reason)
            }
        }
        var skipped = try randomLedger()
        let slot = try XCTUnwrap(skipped.prepareHorizon(at: context.mainWake!.at, contexts: [context]).first)
        try skipped.skip(id: slot.id)
        try skipped.satisfyRandomizedWindow(assessmentID: UUID(), assessedAt: slot.windowStart!, recordedAt: slot.windowStart!)
        XCTAssertEqual(skipped.prompts[0].status, .skipped)
    }
    func testBedtimeBetweenFallbackFoldsUsesNextActualBedtime() throws {
        let routine = RandomizedWakeRoutine(workBedtimeMinute: 90)
        let wake = date("2035-11-04T05:45:00Z") // 01:45 first fold; next 01:30 is second fold.
        XCTAssertEqual(routine.cutoff(wake: wake, working: true, timeZone: zone), date("2035-11-04T04:30:00Z"))
    }

    func testPreFixTwoPromptPayloadIsStableWithoutBackfill() throws {
        // Literal payload generated by c5446a5 with the fractional upper-edge seed.
        let payload = #"{"enabled":true,"prompts":[{"anchor":{"intendedAt":"2026-10-05T15:54:01.000Z","kind":"mainWake","label":"Workday check-in 2 · after main wake","sourceAt":"2026-10-05T09:00:00.123Z","sourceID":"wake","sourceRevision":"r1","working":true},"anchorDayKey":"2026-10-05","id":"00000000-0000-0000-0000-D639DA929C9A","intendedAt":"2026-10-05T15:54:01.000Z","nextAttemptAt":"2026-10-05T15:54:01.000Z","scheduleID":"00000000-0000-0000-0000-000000000035","status":"pending","windowEnd":"2026-10-05T18:00:00.123Z","windowIndex":1,"windowStart":"2026-10-05T15:00:00.123Z"},{"anchor":{"intendedAt":"2026-10-05T20:18:01.000Z","kind":"mainWake","label":"Workday check-in 3 · after main wake","sourceAt":"2026-10-05T09:00:00.123Z","sourceID":"wake","sourceRevision":"r1","working":true},"anchorDayKey":"2026-10-05","id":"00000000-0000-0000-0000-D539DA929AE7","intendedAt":"2026-10-05T20:18:01.000Z","nextAttemptAt":"2026-10-05T20:18:01.000Z","scheduleID":"00000000-0000-0000-0000-000000000035","status":"pending","windowEnd":"2026-10-05T22:00:00.123Z","windowIndex":2,"windowStart":"2026-10-05T20:00:00.123Z"}],"quietEnd":420,"quietStart":1320,"schedules":[{"createdAt":"2026-10-05T09:00:00.123Z","hour":14,"id":"00000000-0000-0000-0000-000000000035","minute":0,"rule":{"anchor":"mainWake","offDayAnchor":"clock","offDayHour":14,"offDayMinute":0,"randomizedWake":{"offBedtimeMinute":1320,"workBedtimeMinute":1320},"selectedWeekdays":[1,2,3,4,5,6,7],"wakeOffsetMinutes":240},"timeZone":"America\/New_York"}]}"#
        var ledger = try DaytimePromptLedger.decodePayload(Data(payload.utf8))
        let saved = ledger.prompts
        XCTAssertEqual(saved.map(\.windowIndex), [1, 2])
        let wake = date("2026-10-05T09:00:00Z").addingTimeInterval(0.123)
        let context = DaytimePromptAnchorContext(dayKey: "2026-10-05", timeZone: zone, working: true,
            mainWake: try DaytimeAnchorSource(id: "wake", revision: "r1", at: wake))
        for clock in [wake, wake.addingTimeInterval(1), wake.addingTimeInterval(3600)] {
            _ = ledger.prepareHorizon(at: clock, contexts: [context])
            XCTAssertEqual(ledger.prompts, saved)
            ledger = try DaytimePromptLedger.decodePayload(ledger.encodedPayload())
        }
    }
    func testLaterCannotCollideWithAnotherWakeDay() throws {
        let prior = try wakeContext("2035-10-04T23:00:00Z"), today = try wakeContext("2035-10-05T09:00:00Z")
        var ledger = try randomLedger(), separate = try randomLedger()
        _ = ledger.prepareHorizon(at: prior.mainWake!.at, contexts: [prior])
        let other = try XCTUnwrap(separate.prepareHorizon(at: today.mainWake!.at, contexts: [today]).first)
        let target = date("2035-10-05T12:00:00Z")
        // Persist two legitimate adjacent-day windows, then place the other attempt at the boundary.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: ledger.encodedPayload()) as? [String: Any])
        var prompts = try XCTUnwrap(json["prompts"] as? [[String: Any]])
        let otherJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: separate.encodedPayload()) as? [String: Any])
        var next = try XCTUnwrap((otherJSON["prompts"] as? [[String: Any]])?.first)
        next["nextAttemptAt"] = "2035-10-05T12:00:00.000Z"
        prompts.append(next); json["prompts"] = prompts
        ledger = try DaytimePromptLedger.decodePayload(JSONSerialization.data(withJSONObject: json))
        let priorSlot = try XCTUnwrap(ledger.prompts.first { $0.anchorDayKey == prior.dayKey && $0.windowIndex == 2 })
        XCTAssertNotEqual(priorSlot.anchorDayKey, other.anchorDayKey)
        XCTAssertThrowsError(try ledger.deferPrompt(id: priorSlot.id, until: target, now: today.mainWake!.at))
    }

    func testRetainedPreFixCrossDayCollisionIsSuppressedWithoutRedrawing() throws {
        let payload = #"{"enabled":true,"prompts":[{"anchor":{"intendedAt":"2035-10-05T02:17:00.000Z","kind":"mainWake","label":"Workday check-in 1 · after main wake","sourceAt":"2035-10-04T23:00:00.000Z","sourceID":"2035-10-04T23:00:00Z","sourceRevision":"r1","workRevision":"w1","workSourceID":"work-A","working":true},"anchorDayKey":"2035-10-04","id":"00000000-0000-0000-0000-295B83AB8D1B","intendedAt":"2035-10-05T02:17:00.000Z","nextAttemptAt":"2035-10-05T02:17:00.000Z","scheduleID":"00000000-0000-0000-0000-000000000001","status":"pending","windowEnd":"2035-10-05T03:00:00.000Z","windowIndex":0,"windowStart":"2035-10-05T01:00:00.000Z"},{"anchor":{"intendedAt":"2035-10-05T07:17:00.000Z","kind":"mainWake","label":"Workday check-in 2 · after main wake","sourceAt":"2035-10-04T23:00:00.000Z","sourceID":"2035-10-04T23:00:00Z","sourceRevision":"r1","workRevision":"w1","workSourceID":"work-A","working":true},"anchorDayKey":"2035-10-04","id":"00000000-0000-0000-0000-285B83AB8B68","intendedAt":"2035-10-05T07:17:00.000Z","nextAttemptAt":"2035-10-05T07:17:00.000Z","scheduleID":"00000000-0000-0000-0000-000000000001","status":"pending","windowEnd":"2035-10-05T08:00:00.000Z","windowIndex":1,"windowStart":"2035-10-05T05:00:00.000Z"},{"anchor":{"intendedAt":"2035-10-05T10:58:00.000Z","kind":"mainWake","label":"Workday check-in 3 · after main wake","sourceAt":"2035-10-04T23:00:00.000Z","sourceID":"2035-10-04T23:00:00Z","sourceRevision":"r1","workRevision":"w1","workSourceID":"work-A","working":true},"anchorDayKey":"2035-10-04","id":"00000000-0000-0000-0000-2B5B83AB9081","intendedAt":"2035-10-05T10:58:00.000Z","nextAttemptAt":"2035-10-05T10:58:00.000Z","scheduleID":"00000000-0000-0000-0000-000000000001","status":"pending","windowEnd":"2035-10-05T12:00:00.000Z","windowIndex":2,"windowStart":"2035-10-05T10:00:00.000Z"},{"anchor":{"intendedAt":"2035-10-05T11:14:00.000Z","kind":"mainWake","label":"Workday check-in 1 · after main wake","sourceAt":"2035-10-05T09:00:00.000Z","sourceID":"2035-10-05T09:00:00Z","sourceRevision":"r1","workRevision":"w1","workSourceID":"work-A","working":true},"anchorDayKey":"2035-10-05","id":"00000000-0000-0000-0000-405B888238D0","intendedAt":"2035-10-05T11:14:00.000Z","nextAttemptAt":"2035-10-05T11:14:00.000Z","scheduleID":"00000000-0000-0000-0000-000000000001","status":"pending","windowEnd":"2035-10-05T13:00:00.000Z","windowIndex":0,"windowStart":"2035-10-05T11:00:00.000Z"},{"anchor":{"intendedAt":"2035-10-05T16:43:00.000Z","kind":"mainWake","label":"Workday check-in 2 · after main wake","sourceAt":"2035-10-05T09:00:00.000Z","sourceID":"2035-10-05T09:00:00Z","sourceRevision":"r1","workRevision":"w1","workSourceID":"work-A","working":true},"anchorDayKey":"2035-10-05","id":"00000000-0000-0000-0000-415B88823A83","intendedAt":"2035-10-05T16:43:00.000Z","nextAttemptAt":"2035-10-05T16:43:00.000Z","scheduleID":"00000000-0000-0000-0000-000000000001","status":"pending","windowEnd":"2035-10-05T18:00:00.000Z","windowIndex":1,"windowStart":"2035-10-05T15:00:00.000Z"},{"anchor":{"intendedAt":"2035-10-05T20:21:00.000Z","kind":"mainWake","label":"Workday check-in 3 · after main wake","sourceAt":"2035-10-05T09:00:00.000Z","sourceID":"2035-10-05T09:00:00Z","sourceRevision":"r1","workRevision":"w1","workSourceID":"work-A","working":true},"anchorDayKey":"2035-10-05","id":"00000000-0000-0000-0000-425B88823C36","intendedAt":"2035-10-05T20:21:00.000Z","nextAttemptAt":"2035-10-05T20:21:00.000Z","scheduleID":"00000000-0000-0000-0000-000000000001","status":"pending","windowEnd":"2035-10-05T21:00:00.000Z","windowIndex":2,"windowStart":"2035-10-05T20:00:00.000Z"}],"quietEnd":420,"quietStart":1320,"schedules":[{"createdAt":"2035-10-04T23:00:00.000Z","hour":14,"id":"00000000-0000-0000-0000-000000000001","minute":0,"rule":{"anchor":"mainWake","offDayAnchor":"clock","offDayHour":14,"offDayMinute":0,"randomizedWake":{"offBedtimeMinute":1320,"workBedtimeMinute":1380},"selectedWeekdays":[1,2,3,4,5,6,7],"wakeOffsetMinutes":240},"timeZone":"UTC"}]}"#
        let original = try DaytimePromptLedger.decodePayload(Data(payload.utf8))
        let prior = try wakeContext("2035-10-04T23:00:00Z"), today = try wakeContext("2035-10-05T09:00:00Z")
        for clock in [today.mainWake!.at, date("2035-10-05T10:58:01Z")] {
            var ledger = original
            let eligible = ledger.prepareHorizon(at: clock, contexts: [prior, today]).sorted { $0.nextAttemptAt < $1.nextAttemptAt }
            for pair in zip(eligible, eligible.dropFirst()) {
                XCTAssertGreaterThanOrEqual(pair.1.nextAttemptAt.timeIntervalSince(pair.0.nextAttemptAt), 7200)
            }
            XCTAssertEqual(ledger.prompts.map(\.id), original.prompts.map(\.id))
            XCTAssertEqual(ledger.prompts.map(\.intendedAt), original.prompts.map(\.intendedAt))
            XCTAssertEqual(ledger.prompts.map(\.nextAttemptAt), original.prompts.map(\.nextAttemptAt))
            for old in original.prompts where old.nextAttemptAt <= clock {
                XCTAssertEqual(ledger.prompts.first { $0.id == old.id }, old)
            }
            XCTAssertTrue(ledger.prompts.contains { $0.reason == "Spacing conflict; review the routine" })
            let retained = ledger.prompts
            _ = ledger.prepareHorizon(at: clock, contexts: [prior, today])
            XCTAssertEqual(ledger.prompts, retained)
        }
    }

}
