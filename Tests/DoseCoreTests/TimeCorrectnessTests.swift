import XCTest
@testable import DoseCore

/// GAP B: Time Correctness Tests
/// Tests for 6 PM session boundary, DST transitions, timezone changes, and backdated edits.
/// These ensure session grouping remains correct across edge cases.
/// All tests explicitly specify timezone to ensure determinism regardless of system TZ.
final class TimeCorrectnessTests: XCTestCase {
    
    // Use a consistent timezone for all tests
    private let testTimeZone = TimeZone(identifier: "America/New_York")!
    
    // MARK: - 6 PM Session Boundary Tests
    
    /// Verify doses at 5:59 PM belong to previous day's session
    func test_6PM_boundary_559PM_belongsToPreviousDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = testTimeZone
        
        // December 26, 2025 at 5:59 PM
        var comps = DateComponents()
        comps.year = 2025; comps.month = 12; comps.day = 26
        comps.hour = 17; comps.minute = 59; comps.second = 0
        guard let fiveFiftyNine = calendar.date(from: comps) else {
            XCTFail("Failed to create date"); return
        }
        
        let calc = DoseWindowCalculator(now: { fiveFiftyNine })
        let sessionDate = calc.sessionDateString(for: fiveFiftyNine, in: testTimeZone)
        
        // 5:59 PM on Dec 26 should belong to Dec 25's sleep session
        // (the session that started at 6 PM on Dec 25)
        XCTAssertEqual(sessionDate, "2025-12-25", 
            "5:59 PM belongs to previous day's session (6 PM cutoff)")
    }
    
    /// Verify doses at 6:00 PM belong to current day's session
    func test_6PM_boundary_600PM_belongsToCurrentDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = testTimeZone
        
        // December 26, 2025 at 6:00 PM exactly
        var comps = DateComponents()
        comps.year = 2025; comps.month = 12; comps.day = 26
        comps.hour = 18; comps.minute = 0; comps.second = 0
        guard let sixPM = calendar.date(from: comps) else {
            XCTFail("Failed to create date"); return
        }
        
        let calc = DoseWindowCalculator(now: { sixPM })
        let sessionDate = calc.sessionDateString(for: sixPM, in: testTimeZone)
        
        // 6:00 PM on Dec 26 should belong to Dec 26's sleep session
        XCTAssertEqual(sessionDate, "2025-12-26",
            "6:00 PM belongs to current day's session (6 PM cutoff)")
    }
    
    /// Verify doses at 6:01 PM belong to current day's session
    func test_6PM_boundary_601PM_belongsToCurrentDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = testTimeZone
        
        var comps = DateComponents()
        comps.year = 2025; comps.month = 12; comps.day = 26
        comps.hour = 18; comps.minute = 1; comps.second = 0
        guard let sixOhOne = calendar.date(from: comps) else {
            XCTFail("Failed to create date"); return
        }
        
        let calc = DoseWindowCalculator(now: { sixOhOne })
        let sessionDate = calc.sessionDateString(for: sixOhOne, in: testTimeZone)
        
        XCTAssertEqual(sessionDate, "2025-12-26",
            "6:01 PM belongs to current day's session")
    }
    
    /// Verify 2 AM dose belongs to previous day's session
    func test_6PM_boundary_2AM_belongsToPreviousDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = testTimeZone
        
        // December 26, 2025 at 2:00 AM
        var comps = DateComponents()
        comps.year = 2025; comps.month = 12; comps.day = 26
        comps.hour = 2; comps.minute = 0; comps.second = 0
        guard let twoAM = calendar.date(from: comps) else {
            XCTFail("Failed to create date"); return
        }
        
        let calc = DoseWindowCalculator(now: { twoAM })
        let sessionDate = calc.sessionDateString(for: twoAM, in: testTimeZone)
        
        // 2 AM on Dec 26 is part of Dec 25's overnight session
        XCTAssertEqual(sessionDate, "2025-12-25",
            "2 AM belongs to previous day's session (overnight)")
    }
    
    /// Verify noon dose belongs to previous day's session
    func test_6PM_boundary_12PM_belongsToPreviousDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = testTimeZone
        
        var comps = DateComponents()
        comps.year = 2025; comps.month = 12; comps.day = 26
        comps.hour = 12; comps.minute = 0; comps.second = 0
        guard let noon = calendar.date(from: comps) else {
            XCTFail("Failed to create date"); return
        }
        
        let calc = DoseWindowCalculator(now: { noon })
        let sessionDate = calc.sessionDateString(for: noon, in: testTimeZone)
        
        // Noon on Dec 26 is still part of Dec 25's session
        XCTAssertEqual(sessionDate, "2025-12-25",
            "Noon belongs to previous day's session")
    }
    
    // MARK: - DST Forward Transition Tests (Spring - lose an hour)
    
    /// Test DST spring forward: 2025-03-09 at 2 AM becomes 3 AM
    /// Window math should use absolute time, not wall clock
    func test_DST_forward_windowStaysCorrect() {
        // PST -> PDT transition: March 9, 2025 at 2:00 AM
        // At 1:30 AM PST, clock jumps to 2:30 AM PDT
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        
        // Dose 1 at 11:00 PM on March 8, 2025
        var dose1Comps = DateComponents()
        dose1Comps.year = 2025; dose1Comps.month = 3; dose1Comps.day = 8
        dose1Comps.hour = 23; dose1Comps.minute = 0
        guard let dose1Time = calendar.date(from: dose1Comps) else {
            XCTFail("Failed to create dose1 date"); return
        }
        
        // After DST: 2:30 AM PDT (which is 165 real minutes later)
        // 11 PM + 165 min = 2:45 AM wall time BUT with DST jump
        // Actually: 11 PM + 165 min in absolute = 1:45 AM PST, then clock jumps to 2:45 AM PDT
        let now = dose1Time.addingTimeInterval(165 * 60) // 165 real minutes
        
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: dose1Time, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        
        // Should still be active because only 165 real minutes passed
        XCTAssertEqual(ctx.phase, .active,
            "DST forward: 165 real minutes should be active phase")
        let remainingMin = ctx.remainingToMax.map { Int($0 / 60) }
        XCTAssertEqual(remainingMin, 75, // 240 - 165 = 75
            "Remaining time should be based on real elapsed time, not wall clock")
    }
    
    /// Verify window expiration uses absolute time during DST forward
    func test_DST_forward_windowExpiresAtRealTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        
        // Dose 1 at 11:30 PM on March 8, 2025 (PST)
        var dose1Comps = DateComponents()
        dose1Comps.year = 2025; dose1Comps.month = 3; dose1Comps.day = 8
        dose1Comps.hour = 23; dose1Comps.minute = 30
        guard let dose1Time = calendar.date(from: dose1Comps) else {
            XCTFail("Failed to create dose1 date"); return
        }
        
        // 240 real minutes later (window should close)
        let now = dose1Time.addingTimeInterval(240 * 60)
        
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: dose1Time, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        
        // Window should be closed after 240 real minutes
        XCTAssertEqual(ctx.phase, .closed,
            "DST forward: window should close after 240 real minutes")
    }
    
    // MARK: - DST Backward Transition Tests (Fall - gain an hour)
    
    /// Test DST fall back: 2025-11-02 at 2 AM becomes 1 AM
    /// User gets an extra hour but window math uses absolute time
    func test_DST_backward_windowStaysCorrect() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        
        // Dose 1 at 11:00 PM on November 1, 2025 (PDT)
        var dose1Comps = DateComponents()
        dose1Comps.year = 2025; dose1Comps.month = 11; dose1Comps.day = 1
        dose1Comps.hour = 23; dose1Comps.minute = 0
        guard let dose1Time = calendar.date(from: dose1Comps) else {
            XCTFail("Failed to create dose1 date"); return
        }
        
        // 165 real minutes later (crosses DST boundary)
        // Wall clock: 11 PM + 2h45m = 1:45 AM, but with fall back it's 12:45 AM PST
        let now = dose1Time.addingTimeInterval(165 * 60)
        
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: dose1Time, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        
        XCTAssertEqual(ctx.phase, .active,
            "DST backward: 165 real minutes should be active phase")
        let remainingMin2 = ctx.remainingToMax.map { Int($0 / 60) }
        XCTAssertEqual(remainingMin2, 75,
            "Remaining time uses real elapsed time")
    }
    
    /// Verify the "extra hour" from fall back doesn't extend window
    func test_DST_backward_noExtraWindowTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        
        // Dose 1 at 10:00 PM on November 1, 2025 (PDT)
        var dose1Comps = DateComponents()
        dose1Comps.year = 2025; dose1Comps.month = 11; dose1Comps.day = 1
        dose1Comps.hour = 22; dose1Comps.minute = 0
        guard let dose1Time = calendar.date(from: dose1Comps) else {
            XCTFail("Failed to create dose1 date"); return
        }
        
        // Exactly 240 real minutes later
        let now = dose1Time.addingTimeInterval(240 * 60)
        
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: dose1Time, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        
        XCTAssertEqual(ctx.phase, .closed,
            "DST backward: window closes after 240 real minutes regardless of wall clock")
    }
    
    // MARK: - Timezone Change Tests
    
    /// Verify session date remains stable if user changes timezone settings
    func test_timezone_change_sessionDateStability() {
        // Create a dose time in Eastern timezone
        let easternTZ = TimeZone(identifier: "America/New_York")!
        var easternCal = Calendar(identifier: .gregorian)
        easternCal.timeZone = easternTZ
        
        var comps = DateComponents()
        comps.year = 2025; comps.month = 12; comps.day = 26
        comps.hour = 23; comps.minute = 0 // 11 PM ET
        guard let doseTime = easternCal.date(from: comps) else {
            XCTFail("Failed to create date"); return
        }
        
        // Get session date in Eastern
        let calcEastern = DoseWindowCalculator(now: { doseTime })
        let sessionDateEastern = calcEastern.sessionDateString(for: doseTime, in: easternTZ)
        
        // Same absolute time, but query with Pacific timezone
        let pacificTZ = TimeZone(identifier: "America/Los_Angeles")!
        let calcPacific = DoseWindowCalculator(now: { doseTime })
        let sessionDatePacific = calcPacific.sessionDateString(for: doseTime, in: pacificTZ)
        
        // Session date in Eastern: 11 PM ET = Dec 26's session (after 6 PM)
        XCTAssertEqual(sessionDateEastern, "2025-12-26",
            "Eastern: 11 PM is current day's session")
        
        // Same absolute time in Pacific is 8 PM PT = Dec 26's session (after 6 PM)
        XCTAssertEqual(sessionDatePacific, "2025-12-26",
            "Pacific: 8 PM is current day's session")
    }
    
    /// Verify window calculations use absolute time regardless of display timezone
    func test_timezone_change_windowMathUnaffected() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        
        // Dose 1 at 11 PM Eastern
        var comps = DateComponents()
        comps.year = 2025; comps.month = 12; comps.day = 26
        comps.hour = 23; comps.minute = 0
        guard let dose1Time = calendar.date(from: comps) else {
            XCTFail("Failed to create date"); return
        }
        
        // 165 real minutes later
        let nowTime = dose1Time.addingTimeInterval(165 * 60)
        
        // Calculate context - should work regardless of system timezone
        let calc = DoseWindowCalculator(now: { nowTime })
        let ctx = calc.context(dose1At: dose1Time, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        
        XCTAssertEqual(ctx.phase, .active,
            "Window phase uses absolute time interval")
        let remainingMin3 = ctx.remainingToMax.map { Int($0 / 60) }
        XCTAssertEqual(remainingMin3, 75,
            "Remaining minutes use absolute time")
    }
    
    // MARK: - Backdated Edit Tests
    
    /// Verify backdated dose 1 edit doesn't create duplicate sessions
    func test_backdatedEdit_noDuplicateSession() {
        let calculator = DoseWindowCalculator(now: { Date() })
        
        // Use fixed timezone for determinism
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = testTimeZone
        
        var originalComps = DateComponents()
        originalComps.year = 2025; originalComps.month = 12; originalComps.day = 26
        originalComps.hour = 23; originalComps.minute = 0
        guard let originalDose = calendar.date(from: originalComps) else {
            XCTFail("Failed to create date"); return
        }
        
        let originalSession = calculator.sessionDateString(for: originalDose, in: testTimeZone)
        
        // Backdated edit to 10:30 PM (same session should be returned)
        var backdatedComps = DateComponents()
        backdatedComps.year = 2025; backdatedComps.month = 12; backdatedComps.day = 26
        backdatedComps.hour = 22; backdatedComps.minute = 30
        guard let backdatedDose = calendar.date(from: backdatedComps) else {
            XCTFail("Failed to create date"); return
        }
        
        let backdatedSession = calculator.sessionDateString(for: backdatedDose, in: testTimeZone)
        
        XCTAssertEqual(originalSession, backdatedSession,
            "Backdated edit within same evening should use same session")
    }
    
    /// Verify forward edit (unusual but possible via undo) stays in same session
    func test_forwardEdit_sameSession() {
        let calculator = DoseWindowCalculator(now: { Date() })
        
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = testTimeZone
        
        // Original at 10 PM
        var originalComps = DateComponents()
        originalComps.year = 2025; originalComps.month = 12; originalComps.day = 26
        originalComps.hour = 22; originalComps.minute = 0
        guard let originalDose = calendar.date(from: originalComps) else {
            XCTFail("Failed to create date"); return
        }
        
        // Edited to 11 PM
        var editedComps = DateComponents()
        editedComps.year = 2025; editedComps.month = 12; editedComps.day = 26
        editedComps.hour = 23; editedComps.minute = 0
        guard let editedDose = calendar.date(from: editedComps) else {
            XCTFail("Failed to create date"); return
        }
        
        let originalSession = calculator.sessionDateString(for: originalDose, in: testTimeZone)
        let editedSession = calculator.sessionDateString(for: editedDose, in: testTimeZone)
        
        XCTAssertEqual(originalSession, editedSession,
            "Forward edit within same evening should use same session")
    }
    
    /// Verify cross-day edit is flagged appropriately
    func test_crossDayEdit_differentSessions() {
        let calculator = DoseWindowCalculator(now: { Date() })
        
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = testTimeZone
        
        // Original at 7 PM Dec 26
        var originalComps = DateComponents()
        originalComps.year = 2025; originalComps.month = 12; originalComps.day = 26
        originalComps.hour = 19; originalComps.minute = 0
        guard let originalDose = calendar.date(from: originalComps) else {
            XCTFail("Failed to create date"); return
        }
        
        // Edit to 5 PM Dec 26 (crosses 6 PM boundary - different session!)
        var editedComps = DateComponents()
        editedComps.year = 2025; editedComps.month = 12; editedComps.day = 26
        editedComps.hour = 17; editedComps.minute = 0
        guard let editedDose = calendar.date(from: editedComps) else {
            XCTFail("Failed to create date"); return
        }
        
        let originalSession = calculator.sessionDateString(for: originalDose, in: testTimeZone)
        let editedSession = calculator.sessionDateString(for: editedDose, in: testTimeZone)
        
        // 7 PM Dec 26 = Dec 26 session
        // 5 PM Dec 26 = Dec 25 session (before 6 PM cutoff)
        XCTAssertEqual(originalSession, "2025-12-26")
        XCTAssertEqual(editedSession, "2025-12-25")
        XCTAssertNotEqual(originalSession, editedSession,
            "Edit crossing 6 PM boundary should change session date")
    }
}
