import XCTest
@testable import DoseCore

/// Tests for Dose 2 edge cases:
/// - Early Dose 2 (before window opens)
/// - Extra Dose attempts (second Dose 2)
/// - Interval calculations
final class Dose2EdgeCaseTests: XCTestCase {
    
    func makeDate(_ base: Date, addMinutes: Int) -> Date {
        base.addingTimeInterval(Double(addMinutes) * 60)
    }
    
    // MARK: - Early Dose 2 Tests
    
    func test_earlyDose2_showsBeforeWindowPhase() {
        // Dose 1 taken at T=0, now is T=120min (window opens at T=150)
        let anchor = Date()
        let now = makeDate(anchor, addMinutes: 120)
        let calc = DoseWindowCalculator(now: { now })
        
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        
        XCTAssertEqual(ctx.phase, .beforeWindow, "Should be beforeWindow when 30 minutes remain")
        // User can still attempt early dose via override
    }
    
    func test_earlyDose2_takenAt120Minutes_isRecordedAndCompletes() {
        // Dose 1 at T=0, Dose 2 taken early at T=120 (30 min before window)
        let anchor = Date()
        let earlyDose2Time = makeDate(anchor, addMinutes: 120)
        let now = makeDate(anchor, addMinutes: 125) // 5 minutes after early dose
        
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: earlyDose2Time, dose2Skipped: false, snoozeCount: 0)
        
        // Even though dose2 was early, state should be completed
        XCTAssertEqual(ctx.phase, .completed, "Early dose 2 should still mark session as completed")
    }
    
    func test_earlyDose2_intervalCalculation() {
        // Dose 1 at T=0, Dose 2 at T=120 (early)
        let anchor = Date()
        let earlyDose2Time = makeDate(anchor, addMinutes: 120)
        
    let minutes = TimeIntervalMath.minutesBetween(start: anchor, end: earlyDose2Time)
    XCTAssertEqual(minutes, 120, "Interval should be 120 minutes")
    XCTAssertLessThan(minutes, 150, "Early dose interval is less than minimum window (150)")
    }
    
    func test_earlyDose2_exact150Minutes_isNotEarly() {
        // Exactly at window open is NOT early
        let anchor = Date()
        let dose2Time = makeDate(anchor, addMinutes: 150)
        let now = makeDate(anchor, addMinutes: 151)
        
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: dose2Time, dose2Skipped: false, snoozeCount: 0)
        
        XCTAssertEqual(ctx.phase, .completed)
        
        // Verify it's exactly at window boundary
    let minutes = TimeIntervalMath.minutesBetween(start: anchor, end: dose2Time)
    XCTAssertEqual(minutes, 150, "Interval should be exactly 150 minutes (not early)")
    }
    
    // MARK: - Extra Dose (Second Dose 2 Attempt) Tests
    
    func test_afterDose2Taken_phaseIsCompleted() {
        let anchor = Date()
        let dose2Time = makeDate(anchor, addMinutes: 165)
        let now = makeDate(anchor, addMinutes: 180)
        
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: dose2Time, dose2Skipped: false, snoozeCount: 0)
        
        XCTAssertEqual(ctx.phase, .completed, "Phase should be completed after Dose 2 taken")
    }
    
    func test_completedPhase_primaryActionIsDisabled() {
        let anchor = Date()
        let dose2Time = makeDate(anchor, addMinutes: 165)
        let now = makeDate(anchor, addMinutes: 180)
        
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: dose2Time, dose2Skipped: false, snoozeCount: 0)
        
        if case .disabled(let reason) = ctx.primary {
            XCTAssertEqual(reason, "Completed", "Primary action should be disabled with 'Completed' reason")
        } else {
            XCTFail("Primary action should be .disabled when completed, got: \(ctx.primary)")
        }
    }
    
    // MARK: - Interval Calculation Tests

    func test_intervalCalculation_midnightRollover_isPositiveAndCorrect() {
        // Real-world case: Dose 1 at 8:53 PM, Dose 2 at 12:51 AM next day.
        // Interval should be 238 minutes.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)! // stable + deterministic

        let dose1 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 20, minute: 53))!
        let dose2 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 0, minute: 51))!

        let calc = DoseWindowCalculator(now: { dose2 })
        let ctx = calc.context(dose1At: dose1, dose2TakenAt: dose2, dose2Skipped: false, snoozeCount: 0)

        XCTAssertEqual(ctx.phase, .completed)
        XCTAssertEqual(TimeIntervalMath.minutesBetween(start: dose1, end: dose2), 238)
    }

    func test_minutesBetween_nonsensicalNegative_keepsNegativeValue() {
    // If the negative delta isn't plausibly a midnight rollover, we should NOT coerce it.
    // NOTE: `assertionFailure` can be configured to trap in this test environment, so we
    // keep the delta small enough to be non-rollover but non-fatal.
    let start = Date(timeIntervalSince1970: 0)
    let end = Date(timeIntervalSince1970: -60) // -1 minute (not a plausible rollover)
    XCTAssertEqual(TimeIntervalMath.minutesBetween(start: start, end: end), -1)
    }
    
    func test_intervalCalculation_normalCase() {
        // Dose 1 at T=0, Dose 2 at T=165 (optimal)
        let anchor = Date()
        let dose2Time = makeDate(anchor, addMinutes: 165)
        
    let minutes = TimeIntervalMath.minutesBetween(start: anchor, end: dose2Time)
    XCTAssertEqual(minutes, 165, "Normal interval should be 165 minutes")
    XCTAssertGreaterThanOrEqual(minutes, 150, "Should be >= min window")
    XCTAssertLessThanOrEqual(minutes, 240, "Should be <= max window")
    }
    
    func test_intervalCalculation_nearClose() {
        // Dose 1 at T=0, Dose 2 at T=235 (near window close)
        let anchor = Date()
        let dose2Time = makeDate(anchor, addMinutes: 235)
        
    let minutes = TimeIntervalMath.minutesBetween(start: anchor, end: dose2Time)
    XCTAssertEqual(minutes, 235, "Near-close interval should be 235 minutes")
    XCTAssertLessThan(minutes, 240, "Should still be within window")
    }
    
    func test_intervalCalculation_exactMaxWindow() {
        // Dose 1 at T=0, Dose 2 at T=240 (exactly at window close)
        let anchor = Date()
        let dose2Time = makeDate(anchor, addMinutes: 240)
        
    let minutes = TimeIntervalMath.minutesBetween(start: anchor, end: dose2Time)
    XCTAssertEqual(minutes, 240, "Exact max interval should be 240 minutes")
    }
    
    // MARK: - Window Boundary Tests
    
    func test_windowBoundary_149Minutes_isBeforeWindow() {
        let anchor = Date()
        let now = makeDate(anchor, addMinutes: 149)
        
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        
        XCTAssertEqual(ctx.phase, .beforeWindow, "149 minutes should be before window")
    }
    
    func test_windowBoundary_150Minutes_isActive() {
        let anchor = Date()
        let now = makeDate(anchor, addMinutes: 150)
        
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        
        XCTAssertEqual(ctx.phase, .active, "Exactly 150 minutes should be active window")
    }
    
    func test_windowBoundary_240Minutes_isClosed() {
        // At exactly 240 minutes, window is closed (exclusive boundary)
        let anchor = Date()
        let now = makeDate(anchor, addMinutes: 240)
        
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        
        // Window is [150, 240) - 240 is closed
        XCTAssertEqual(ctx.phase, .closed, "At exactly 240 minutes, window is closed (boundary exclusive)")
    }
    
    func test_windowBoundary_239Minutes_isNearClose() {
        // At 239 minutes (1 min before close), should be nearClose
        let anchor = Date()
        let now = makeDate(anchor, addMinutes: 239)
        
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        
        XCTAssertEqual(ctx.phase, .nearClose, "239 minutes should be nearClose")
    }
    
    func test_windowBoundary_241Minutes_isClosed() {
        let anchor = Date()
        let now = makeDate(anchor, addMinutes: 241)
        
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        
        XCTAssertEqual(ctx.phase, .closed, "241 minutes should be window closed")
    }
    
    // MARK: - Skip Tests
    
    func test_skippedDose2_showsCompletedPhase() {
        let anchor = Date()
        let now = makeDate(anchor, addMinutes: 180)
        
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: true, snoozeCount: 0)
        
        // When skipped, should show completed (not error state)
        XCTAssertEqual(ctx.phase, .completed, "Skipped dose 2 should show completed phase")
    }
}
