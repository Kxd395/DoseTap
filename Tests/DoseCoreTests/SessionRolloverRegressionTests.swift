import XCTest
@testable import DoseCore

/// Regression tests for session rollover boundary behavior across
/// timezones, DST transitions, and planner toggle interactions.
///
/// These cover edge cases identified during Phase 1/2 stabilization.
final class SessionRolloverRegressionTests: XCTestCase {

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, tz: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute; comps.second = 0
        return cal.date(from: comps)!
    }

    private let est = TimeZone(identifier: "America/New_York")!
    private let pst = TimeZone(identifier: "America/Los_Angeles")!
    private let utc = TimeZone(identifier: "UTC")!
    private let jst = TimeZone(identifier: "Asia/Tokyo")!  // UTC+9, no DST
    private let aest = TimeZone(identifier: "Australia/Sydney")! // UTC+10/+11 DST

    // MARK: - Session Key Rollover Boundary

    func test_rollover_6pm_boundary_EST() {
        // 5:59 PM EST → previous day
        let before = makeDate(year: 2026, month: 2, day: 14, hour: 17, minute: 59, tz: est)
        XCTAssertEqual(sessionKey(for: before, timeZone: est), "2026-02-13")

        // 6:00 PM EST → current day
        let at = makeDate(year: 2026, month: 2, day: 14, hour: 18, minute: 0, tz: est)
        XCTAssertEqual(sessionKey(for: at, timeZone: est), "2026-02-14")

        // 6:01 PM EST → current day
        let after = makeDate(year: 2026, month: 2, day: 14, hour: 18, minute: 1, tz: est)
        XCTAssertEqual(sessionKey(for: after, timeZone: est), "2026-02-14")
    }

    func test_rollover_midnight_stays_previous_session() {
        // Midnight belongs to previous day's session (hour 0 < rolloverHour 18)
        let midnight = makeDate(year: 2026, month: 2, day: 15, hour: 0, minute: 0, tz: est)
        XCTAssertEqual(sessionKey(for: midnight, timeZone: est), "2026-02-14")

        let twoAM = makeDate(year: 2026, month: 2, day: 15, hour: 2, minute: 0, tz: est)
        XCTAssertEqual(sessionKey(for: twoAM, timeZone: est), "2026-02-14")
    }

    func test_rollover_early_morning_belongs_to_previous_night() {
        // 5:00 AM — still part of last night's session
        let earlyMorning = makeDate(year: 2026, month: 2, day: 15, hour: 5, minute: 0, tz: est)
        XCTAssertEqual(sessionKey(for: earlyMorning, timeZone: est), "2026-02-14")

        // 11:59 AM — still previous session
        let lateMorning = makeDate(year: 2026, month: 2, day: 15, hour: 11, minute: 59, tz: est)
        XCTAssertEqual(sessionKey(for: lateMorning, timeZone: est), "2026-02-14")
    }

    func test_rollover_afternoon_before_cutoff() {
        // 3 PM — still previous session
        let afternoon = makeDate(year: 2026, month: 2, day: 15, hour: 15, minute: 0, tz: est)
        XCTAssertEqual(sessionKey(for: afternoon, timeZone: est), "2026-02-14")
    }

    // MARK: - Custom Rollover Hours

    func test_custom_rollover_hour_20() {
        // Rollover at 8 PM instead of 6 PM
        let at7pm = makeDate(year: 2026, month: 2, day: 14, hour: 19, minute: 59, tz: est)
        XCTAssertEqual(sessionKey(for: at7pm, timeZone: est, rolloverHour: 20), "2026-02-13")

        let at8pm = makeDate(year: 2026, month: 2, day: 14, hour: 20, minute: 0, tz: est)
        XCTAssertEqual(sessionKey(for: at8pm, timeZone: est, rolloverHour: 20), "2026-02-14")
    }

    func test_custom_rollover_hour_16() {
        // Rollover at 4 PM for early sleepers
        let at3pm = makeDate(year: 2026, month: 2, day: 14, hour: 15, minute: 59, tz: est)
        XCTAssertEqual(sessionKey(for: at3pm, timeZone: est, rolloverHour: 16), "2026-02-13")

        let at4pm = makeDate(year: 2026, month: 2, day: 14, hour: 16, minute: 0, tz: est)
        XCTAssertEqual(sessionKey(for: at4pm, timeZone: est, rolloverHour: 16), "2026-02-14")
    }

    // MARK: - Timezone Change Mid-Session

    func test_sessionKey_same_moment_different_timezones() {
        // 11:00 PM UTC on Feb 14 = 6:00 PM EST (Feb 14) = 3:00 PM PST (Feb 14)
        let utcDate = makeDate(year: 2026, month: 2, day: 14, hour: 23, minute: 0, tz: utc)

        // In EST (6 PM), it's exactly rollover → current day
        XCTAssertEqual(sessionKey(for: utcDate, timeZone: est), "2026-02-14")
        
        // In PST (3 PM), it's before rollover → previous day
        XCTAssertEqual(sessionKey(for: utcDate, timeZone: pst), "2026-02-13")
        
        // In UTC (11 PM), it's after rollover → current day
        XCTAssertEqual(sessionKey(for: utcDate, timeZone: utc), "2026-02-14")
    }

    func test_timezone_travel_east_changes_session_key() {
        // User starts in PST, it's 5 PM (before rollover) → session Feb 13
        let pst5pm = makeDate(year: 2026, month: 2, day: 14, hour: 17, minute: 0, tz: pst)
        XCTAssertEqual(sessionKey(for: pst5pm, timeZone: pst), "2026-02-13")
        
        // Same absolute time evaluated in EST (8 PM EST) → session Feb 14
        // This simulates the user traveling east
        XCTAssertEqual(sessionKey(for: pst5pm, timeZone: est), "2026-02-14")
    }

    func test_timezone_travel_west_changes_session_key() {
        // User is in JST at 8 AM Feb 15 → session Feb 14 (before rollover)
        let jst8am = makeDate(year: 2026, month: 2, day: 15, hour: 8, minute: 0, tz: jst)
        XCTAssertEqual(sessionKey(for: jst8am, timeZone: jst), "2026-02-14")
        
        // Same absolute time in PST is Feb 14 3 PM → also session Feb 13
        XCTAssertEqual(sessionKey(for: jst8am, timeZone: pst), "2026-02-13")
    }

    // MARK: - DST Transitions

    func test_dst_spring_forward_rollover_boundary() {
        // US Spring Forward 2026: March 8, 2:00 AM → 3:00 AM
        // At 5:59 PM EST (before DST, this is still EST) → session March 7
        let beforeRollover = makeDate(year: 2026, month: 3, day: 8, hour: 17, minute: 59, tz: est)
        XCTAssertEqual(sessionKey(for: beforeRollover, timeZone: est), "2026-03-07")
        
        // At 6:00 PM EDT (after DST, now EDT) → session March 8
        let atRollover = makeDate(year: 2026, month: 3, day: 8, hour: 18, minute: 0, tz: est)
        XCTAssertEqual(sessionKey(for: atRollover, timeZone: est), "2026-03-08")
    }

    func test_dst_fall_back_rollover_boundary() {
        // US Fall Back 2026: November 1, 2:00 AM → 1:00 AM
        // Rollover at 6 PM still works because DST ends at 2 AM — far from 6 PM
        let beforeRollover = makeDate(year: 2026, month: 11, day: 1, hour: 17, minute: 59, tz: est)
        XCTAssertEqual(sessionKey(for: beforeRollover, timeZone: est), "2026-10-31")
        
        let atRollover = makeDate(year: 2026, month: 11, day: 1, hour: 18, minute: 0, tz: est)
        XCTAssertEqual(sessionKey(for: atRollover, timeZone: est), "2026-11-01")
    }

    func test_dst_fall_back_ambiguous_1am() {
        // At fall-back, 1:00-1:59 AM occurs twice. Both should be the same session.
        let firstOneAM = makeDate(year: 2026, month: 11, day: 1, hour: 1, minute: 30, tz: est)
        // Both interpretations (EDT and EST) of 1:30 AM belong to Oct 31 session
        XCTAssertEqual(sessionKey(for: firstOneAM, timeZone: est), "2026-10-31")
    }

    func test_australia_dst_boundary() {
        // Australia/Sydney: DST starts first Sunday in October, ends first Sunday in April
        // April 5, 2026: 3:00 AM → 2:00 AM (fall back)
        let beforeRollover = makeDate(year: 2026, month: 4, day: 5, hour: 17, minute: 59, tz: aest)
        XCTAssertEqual(sessionKey(for: beforeRollover, timeZone: aest), "2026-04-04")
        
        let atRollover = makeDate(year: 2026, month: 4, day: 5, hour: 18, minute: 0, tz: aest)
        XCTAssertEqual(sessionKey(for: atRollover, timeZone: aest), "2026-04-05")
    }

    // MARK: - nextRollover Function

    func test_nextRollover_before_today_rollover() {
        // 10:00 AM → next rollover is today at 6 PM
        let tenAM = makeDate(year: 2026, month: 2, day: 14, hour: 10, minute: 0, tz: est)
        let next = nextRollover(after: tenAM, timeZone: est)
        
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = est
        XCTAssertEqual(cal.component(.hour, from: next), 18)
        XCTAssertEqual(cal.component(.day, from: next), 14)
    }

    func test_nextRollover_after_today_rollover() {
        // 8:00 PM → next rollover is tomorrow at 6 PM
        let eightPM = makeDate(year: 2026, month: 2, day: 14, hour: 20, minute: 0, tz: est)
        let next = nextRollover(after: eightPM, timeZone: est)
        
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = est
        XCTAssertEqual(cal.component(.hour, from: next), 18)
        XCTAssertEqual(cal.component(.day, from: next), 15)
    }

    func test_nextRollover_at_exact_rollover() {
        // Exactly 6:00 PM → next rollover is tomorrow at 6 PM
        let sixPM = makeDate(year: 2026, month: 2, day: 14, hour: 18, minute: 0, tz: est)
        let next = nextRollover(after: sixPM, timeZone: est)
        
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = est
        XCTAssertEqual(cal.component(.hour, from: next), 18)
        XCTAssertEqual(cal.component(.day, from: next), 15)
    }

    func test_nextRollover_across_month_boundary() {
        // Jan 31, 7 PM → next rollover is Feb 1, 6 PM
        let jan31 = makeDate(year: 2026, month: 1, day: 31, hour: 19, minute: 0, tz: est)
        let next = nextRollover(after: jan31, timeZone: est)
        
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = est
        XCTAssertEqual(cal.component(.month, from: next), 2)
        XCTAssertEqual(cal.component(.day, from: next), 1)
    }

    func test_nextRollover_across_year_boundary() {
        // Dec 31, 7 PM → next rollover is Jan 1, 6 PM
        let dec31 = makeDate(year: 2025, month: 12, day: 31, hour: 19, minute: 0, tz: est)
        let next = nextRollover(after: dec31, timeZone: est)
        
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = est
        XCTAssertEqual(cal.component(.year, from: next), 2026)
        XCTAssertEqual(cal.component(.month, from: next), 1)
        XCTAssertEqual(cal.component(.day, from: next), 1)
    }

    // MARK: - preSleepSessionKey

    func test_preSleepSessionKey_evening_targets_today() {
        // 7 PM on Feb 14 → pre-sleep planning targets Feb 14 session
        let evening = makeDate(year: 2026, month: 2, day: 14, hour: 19, minute: 0, tz: est)
        XCTAssertEqual(preSleepSessionKey(for: evening, timeZone: est), "2026-02-14")
    }

    func test_preSleepSessionKey_afternoon_targets_today() {
        // 3 PM on Feb 14 → planning for tonight targets Feb 14
        let afternoon = makeDate(year: 2026, month: 2, day: 14, hour: 15, minute: 0, tz: est)
        XCTAssertEqual(preSleepSessionKey(for: afternoon, timeZone: est), "2026-02-14")
    }

    func test_preSleepSessionKey_post_midnight_targets_that_calendar_day() {
        // 1 AM Feb 15 → pre-sleep key targets Feb 15 (not Feb 14)
        // This is correct for pre-sleep planning (next upcoming night)
        let postMidnight = makeDate(year: 2026, month: 2, day: 15, hour: 1, minute: 0, tz: est)
        XCTAssertEqual(preSleepSessionKey(for: postMidnight, timeZone: est), "2026-02-15")
    }

    // MARK: - Dose Window + Rollover Interaction

    func test_dose_window_spans_midnight_correctly() {
        // Dose 1 at 10:00 PM → window opens at 12:30 AM (150 min later)
        let dose1 = makeDate(year: 2026, month: 2, day: 14, hour: 22, minute: 0, tz: est)
        let windowOpen = dose1.addingTimeInterval(150 * 60) // 12:30 AM Feb 15
        
        // Session key for dose1 (10 PM) → Feb 14
        XCTAssertEqual(sessionKey(for: dose1, timeZone: est), "2026-02-14")
        // Session key for window open (12:30 AM) → still Feb 14 (before rollover)
        XCTAssertEqual(sessionKey(for: windowOpen, timeZone: est), "2026-02-14")
        
        // Dose window calc should still work across midnight
        let calc = DoseWindowCalculator(now: { windowOpen })
        let ctx = calc.context(dose1At: dose1, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx.phase, .active)
    }

    func test_dose_window_stays_same_session_through_close() {
        // Dose 1 at 11:00 PM → window closes at 3:00 AM (240 min later)
        let dose1 = makeDate(year: 2026, month: 2, day: 14, hour: 23, minute: 0, tz: est)
        let windowClose = dose1.addingTimeInterval(240 * 60) // 3:00 AM Feb 15
        
        // Both belong to Feb 14 session
        XCTAssertEqual(sessionKey(for: dose1, timeZone: est), "2026-02-14")
        XCTAssertEqual(sessionKey(for: windowClose, timeZone: est), "2026-02-14")
    }

    // MARK: - Edge Case: Leap Year / Month Length

    func test_rollover_feb_28_to_march_1_non_leap_year() {
        // Feb 28, 2025 (non-leap) → 7 PM session is Feb 28
        let feb28 = makeDate(year: 2025, month: 2, day: 28, hour: 19, minute: 0, tz: utc)
        XCTAssertEqual(sessionKey(for: feb28, timeZone: utc), "2025-02-28")
        
        // March 1 at 5 AM → still Feb 28 session
        let march1 = makeDate(year: 2025, month: 3, day: 1, hour: 5, minute: 0, tz: utc)
        XCTAssertEqual(sessionKey(for: march1, timeZone: utc), "2025-02-28")
    }

    func test_rollover_feb_29_leap_year() {
        // Feb 29, 2028 (leap year) at 7 PM → session Feb 29
        let feb29 = makeDate(year: 2028, month: 2, day: 29, hour: 19, minute: 0, tz: utc)
        XCTAssertEqual(sessionKey(for: feb29, timeZone: utc), "2028-02-29")
        
        // March 1 at 5 AM → still Feb 29 session
        let march1 = makeDate(year: 2028, month: 3, day: 1, hour: 5, minute: 0, tz: utc)
        XCTAssertEqual(sessionKey(for: march1, timeZone: utc), "2028-02-29")
    }

    // MARK: - No-DST Timezone (JST)

    func test_sessionKey_no_dst_timezone_jst() {
        // JST (UTC+9) has no DST. Session key should be stable.
        let evening = makeDate(year: 2026, month: 3, day: 8, hour: 19, minute: 0, tz: jst)
        XCTAssertEqual(sessionKey(for: evening, timeZone: jst), "2026-03-08")
        
        let nextMorning = makeDate(year: 2026, month: 3, day: 9, hour: 6, minute: 0, tz: jst)
        XCTAssertEqual(sessionKey(for: nextMorning, timeZone: jst), "2026-03-08")
    }
}
