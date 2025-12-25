import XCTest
@testable import DoseCore

final class DoseWindowEdgeTests: XCTestCase {
    private func makeDate(_ base: Date, addMinutes: Int) -> Date { base.addingTimeInterval(Double(addMinutes) * 60) }

    func test_exact_150_enters_active() {
        let anchor = Date()
        let now = makeDate(anchor, addMinutes: 150)
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        // At EXACT 150 we consider window open
        XCTAssertEqual(ctx.phase, .active)
    }

    func test_exact_165_mid_window() {
        let anchor = Date()
        let now = makeDate(anchor, addMinutes: 165)
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx.phase, .active)
        XCTAssertEqual(ctx.primary, .takeNow)
    }

    func test_exact_225_is_near_close_threshold() {
        let anchor = Date()
        let now = makeDate(anchor, addMinutes: 225) // 15 minutes before 240 => nearClose threshold is 15 so 225 should be active
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        // At exactly remaining == threshold we classify as nearClose
        XCTAssertEqual(ctx.phase, .nearClose)
    }

    func test_239_near_close() {
        let anchor = Date()
        let now = makeDate(anchor, addMinutes: 239)
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx.phase, .nearClose)
    }

    func test_exact_240_closed() {
        let anchor = Date()
        let now = makeDate(anchor, addMinutes: 240)
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx.phase, .closed)
    }

    func test_dst_forward_skip() {
        // Simulate DST jump (e.g. 2 AM -> 3 AM) by adding 60m gap in timeline
        // We'll emulate Dose1 at 01:30, then 'now' 3.5h later in wall clock but with a 1h shift.
        let calendar = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = 2025; comps.month = 3; comps.day = 9; comps.hour = 1; comps.minute = 30
        let tz = TimeZone(abbreviation: "PST") ?? .current
        var cal = calendar
        cal.timeZone = tz
        guard let anchor = cal.date(from: comps) else { return XCTFail("Failed build anchor") }
        // Add 3.5h real time (210m). In a forward DST shift night, wall clock might show 4.5h difference.
        let now = anchor.addingTimeInterval(210 * 60)
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        // Should still be active (since 210 < 225 threshold for nearClose)
        XCTAssertEqual(ctx.phase, .active)
    }
    
    // MARK: - Finalizing State Tests
    
    func test_wakeFinal_without_checkin_shows_finalizing() {
        let anchor = Date()
        let calc = DoseWindowCalculator(now: { anchor.addingTimeInterval(300 * 60) })
        let wakeFinal = anchor.addingTimeInterval(420 * 60) // Wake up 7 hours after dose 1
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: anchor.addingTimeInterval(165 * 60), dose2Skipped: false, snoozeCount: 0, wakeFinalAt: wakeFinal, checkInCompleted: false)
        XCTAssertEqual(ctx.phase, .finalizing)
    }
    
    func test_checkin_complete_shows_completed() {
        let anchor = Date()
        let calc = DoseWindowCalculator(now: { anchor.addingTimeInterval(300 * 60) })
        let wakeFinal = anchor.addingTimeInterval(420 * 60)
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: anchor.addingTimeInterval(165 * 60), dose2Skipped: false, snoozeCount: 0, wakeFinalAt: wakeFinal, checkInCompleted: true)
        XCTAssertEqual(ctx.phase, .completed)
    }
    
    func test_session_without_wakeFinal_still_shows_normal_phases() {
        let anchor = Date()
        let calc = DoseWindowCalculator(now: { anchor.addingTimeInterval(180 * 60) })
        // No wakeFinal - should show active (180 min after dose 1)
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0, wakeFinalAt: nil, checkInCompleted: false)
        XCTAssertEqual(ctx.phase, .active)
    }
    
    // MARK: - Sleep-Through Detection Tests
    
    func test_shouldAutoExpire_false_when_no_dose1() {
        let calc = DoseWindowCalculator(now: { Date() })
        XCTAssertFalse(calc.shouldAutoExpireSession(dose1At: nil, dose2TakenAt: nil, dose2Skipped: false))
    }
    
    func test_shouldAutoExpire_false_when_dose2_taken() {
        let anchor = Date().addingTimeInterval(-300 * 60) // 5 hours ago
        let dose2Time = anchor.addingTimeInterval(165 * 60)
        let calc = DoseWindowCalculator(now: { Date() })
        XCTAssertFalse(calc.shouldAutoExpireSession(dose1At: anchor, dose2TakenAt: dose2Time, dose2Skipped: false))
    }
    
    func test_shouldAutoExpire_false_when_dose2_skipped() {
        let anchor = Date().addingTimeInterval(-300 * 60) // 5 hours ago
        let calc = DoseWindowCalculator(now: { Date() })
        XCTAssertFalse(calc.shouldAutoExpireSession(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: true))
    }
    
    func test_shouldAutoExpire_false_within_window_and_grace() {
        let anchor = Date()
        // At 260 min: window closed (240) + only 20 min grace (need 30)
        let now = anchor.addingTimeInterval(260 * 60)
        let calc = DoseWindowCalculator(now: { now })
        XCTAssertFalse(calc.shouldAutoExpireSession(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false))
    }
    
    func test_shouldAutoExpire_true_after_window_plus_grace() {
        let anchor = Date()
        // At 270 min: window (240) + grace (30) = 270 - should expire
        let now = anchor.addingTimeInterval(270 * 60)
        let calc = DoseWindowCalculator(now: { now })
        XCTAssertTrue(calc.shouldAutoExpireSession(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false))
    }
    
    func test_shouldAutoExpire_true_well_past_grace() {
        let anchor = Date()
        // 6 hours after dose 1 (360 min) - definitely slept through
        let now = anchor.addingTimeInterval(360 * 60)
        let calc = DoseWindowCalculator(now: { now })
        XCTAssertTrue(calc.shouldAutoExpireSession(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false))
    }
}
