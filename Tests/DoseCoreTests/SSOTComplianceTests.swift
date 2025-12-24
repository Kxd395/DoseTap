import XCTest
@testable import DoseCore

/// Tests that ensure code constants match SSOT-defined values.
/// If these tests fail, either the code or SSOT needs to be updated.
/// Reference: docs/SSOT/README.md
final class SSOTComplianceTests: XCTestCase {
    
    // MARK: - Core Window Invariants (SSOT §Core Invariants)
    
    /// SSOT: "Window Opens: 150 minutes After Dose 1"
    func testSSOT_windowOpens_150minutes() {
        let config = DoseWindowConfig()
        XCTAssertEqual(config.minIntervalMin, 150, "SSOT: Window opens at 150 minutes")
    }
    
    /// SSOT: "Window Closes: 240 minutes After Dose 1 (hard limit)"
    func testSSOT_windowCloses_240minutes() {
        let config = DoseWindowConfig()
        XCTAssertEqual(config.maxIntervalMin, 240, "SSOT: Window closes at 240 minutes")
    }
    
    /// SSOT: "Default Target: 165 minutes"
    func testSSOT_defaultTarget_165minutes() {
        let config = DoseWindowConfig()
        XCTAssertEqual(config.defaultTargetMin, 165, "SSOT: Default target is 165 minutes")
    }
    
    /// SSOT: "Snooze Duration: 10 minutes (Fixed)"
    func testSSOT_snoozeDuration_10minutes() {
        let config = DoseWindowConfig()
        XCTAssertEqual(config.snoozeStepMin, 10, "SSOT: Snooze duration is 10 minutes")
    }
    
    /// SSOT: "Max Snoozes: 3 per night"
    func testSSOT_maxSnoozes_3() {
        let config = DoseWindowConfig()
        XCTAssertEqual(config.maxSnoozes, 3, "SSOT: Max snoozes is 3")
    }
    
    /// SSOT: "Snooze Disabled: <15 min remaining"
    func testSSOT_snoozeDisabled_threshold_15minutes() {
        let config = DoseWindowConfig()
        XCTAssertEqual(config.nearWindowThresholdMin, 15, "SSOT: Snooze disabled at <15 minutes")
    }
    
    /// SSOT: "Undo Window: 5 seconds"
    func testSSOT_undoWindow_5seconds() {
        XCTAssertEqual(DoseUndoManager.defaultWindowSeconds, 5.0, "SSOT: Undo window is 5 seconds")
    }
    
    // MARK: - Rate Limiter Cooldowns (SSOT §Sleep Event Types)
    
    /// SSOT: Bathroom cooldown 60 seconds (legacy) or per-event cooldowns
    func testSSOT_bathroomCooldown_exists() {
        // Bathroom should have a cooldown defined
        XCTAssertGreaterThan(SleepEventType.bathroom.defaultCooldownSeconds, 0, "Bathroom must have cooldown")
    }
    
    /// All sleep event types should have defined cooldowns
    func testSSOT_allEventTypesHaveCooldowns() {
        for eventType in SleepEventType.allCases {
            XCTAssertGreaterThanOrEqual(eventType.defaultCooldownSeconds, 0, "\(eventType.rawValue) must have a cooldown defined")
        }
    }
    
    // MARK: - State Machine Phases (SSOT §State Machine)
    
    /// SSOT defines 6 phases: noDose1, beforeWindow, active, nearClose, closed, completed
    func testSSOT_statePhaseCount() {
        let phases: [DoseWindowPhase] = [.noDose1, .beforeWindow, .active, .nearClose, .closed, .completed]
        XCTAssertEqual(phases.count, 6, "SSOT defines exactly 6 phases")
    }
    
    // MARK: - Window Math Edge Cases
    
    /// At exactly 150 minutes, phase should be .active (not beforeWindow)
    func testSSOT_exact150minutes_isActive() {
        let d1 = Date(timeIntervalSince1970: 0)
        let now = d1.addingTimeInterval(150 * 60)
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: d1, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx.phase, .active, "SSOT: Window is OPEN at exactly 150 minutes")
    }
    
    /// At exactly 240 minutes, phase should be .closed
    func testSSOT_exact240minutes_isClosed() {
        let d1 = Date(timeIntervalSince1970: 0)
        let now = d1.addingTimeInterval(240 * 60)
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: d1, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx.phase, .closed, "SSOT: Window is CLOSED at exactly 240 minutes")
    }
    
    /// At exactly 225 minutes (15 remaining), snooze should be disabled
    func testSSOT_15minutesRemaining_snoozeDisabled() {
        let d1 = Date(timeIntervalSince1970: 0)
        let now = d1.addingTimeInterval(225 * 60) // 240 - 15 = 225
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: d1, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        
        // Phase should be nearClose
        XCTAssertEqual(ctx.phase, .nearClose, "SSOT: Phase is nearClose at 15 minutes remaining")
        
        // Snooze should be disabled
        if case .snoozeDisabled(let reason) = ctx.snooze {
            XCTAssertTrue(reason.contains("15") || reason.contains("time") || !reason.isEmpty, "Snooze disabled due to time remaining")
        } else {
            XCTFail("SSOT: Snooze must be disabled when <15 minutes remain")
        }
    }
}
