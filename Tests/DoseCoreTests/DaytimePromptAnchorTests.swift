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

}
