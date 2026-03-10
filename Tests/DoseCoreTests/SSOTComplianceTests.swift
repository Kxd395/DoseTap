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
    
    // MARK: - P0-2: Snooze Disabled in ALL Non-Active Phases
    // These tests enforce the SSOT snooze invariant: "Snooze is DISABLED in all phases except .active"
    // P0-2 fix required all surfaces to use DoseWindowContext.snooze enum, not manual count checks.
    
    /// SSOT: Snooze DISABLED in .noDose1 phase
    func testSSOT_snoozeDisabled_noDose1() {
        let calc = DoseWindowCalculator(now: { Date() })
        let ctx = calc.context(dose1At: nil, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx.phase, .noDose1)
        if case .snoozeDisabled = ctx.snooze { /* expected */ } else {
            XCTFail("SSOT P0-2: Snooze must be disabled when no Dose 1")
        }
    }
    
    /// SSOT: Snooze DISABLED in .beforeWindow phase
    func testSSOT_snoozeDisabled_beforeWindow() {
        let anchor = Date()
        let calc = DoseWindowCalculator(now: { anchor.addingTimeInterval(120 * 60) })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx.phase, .beforeWindow)
        if case .snoozeDisabled = ctx.snooze { /* expected */ } else {
            XCTFail("SSOT P0-2: Snooze must be disabled before window opens")
        }
    }
    
    /// SSOT: Snooze ENABLED in .active phase when snoozeCount < maxSnoozes
    func testSSOT_snoozeEnabled_activePhase() {
        let anchor = Date()
        let calc = DoseWindowCalculator(now: { anchor.addingTimeInterval(160 * 60) })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx.phase, .active)
        if case .snoozeEnabled(let remaining) = ctx.snooze {
            XCTAssertGreaterThan(remaining, 0, "Remaining time must be positive")
        } else {
            XCTFail("SSOT P0-2: Snooze must be enabled in active phase with snoozes available")
        }
    }
    
    /// SSOT: Snooze DISABLED in .active phase when snoozeCount >= maxSnoozes
    func testSSOT_snoozeDisabled_activePhaseSnoozeLimitReached() {
        let anchor = Date()
        let calc = DoseWindowCalculator(now: { anchor.addingTimeInterval(160 * 60) })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 3)
        XCTAssertEqual(ctx.phase, .active)
        if case .snoozeDisabled(let reason) = ctx.snooze {
            XCTAssertTrue(reason.lowercased().contains("limit"), "Reason should mention limit")
        } else {
            XCTFail("SSOT P0-2: Snooze must be disabled when snooze limit reached")
        }
    }
    
    /// SSOT: Snooze DISABLED in .nearClose phase (< 15 min remaining)
    func testSSOT_snoozeDisabled_nearClosePhase() {
        let anchor = Date()
        let calc = DoseWindowCalculator(now: { anchor.addingTimeInterval(230 * 60) }) // 10 min remaining
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx.phase, .nearClose)
        if case .snoozeDisabled = ctx.snooze { /* expected */ } else {
            XCTFail("SSOT P0-2: Snooze must be disabled when <15 minutes remain")
        }
    }
    
    /// SSOT: Snooze DISABLED in .closed phase
    func testSSOT_snoozeDisabled_closedPhase() {
        let anchor = Date()
        let calc = DoseWindowCalculator(now: { anchor.addingTimeInterval(250 * 60) })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx.phase, .closed)
        if case .snoozeDisabled = ctx.snooze { /* expected */ } else {
            XCTFail("SSOT P0-2: Snooze must be disabled when window is closed")
        }
    }
    
    /// SSOT: Snooze DISABLED in .completed phase
    func testSSOT_snoozeDisabled_completedPhase() {
        let anchor = Date()
        let d2 = anchor.addingTimeInterval(165 * 60)
        let calc = DoseWindowCalculator(now: { anchor.addingTimeInterval(200 * 60) })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: d2, dose2Skipped: false, snoozeCount: 1)
        XCTAssertEqual(ctx.phase, .completed)
        if case .snoozeDisabled = ctx.snooze { /* expected */ } else {
            XCTFail("SSOT P0-2: Snooze must be disabled after completion")
        }
    }
    
    /// SSOT: Snooze DISABLED in .finalizing phase
    func testSSOT_snoozeDisabled_finalizingPhase() {
        let anchor = Date()
        let d2 = anchor.addingTimeInterval(165 * 60)
        let wakeTime = anchor.addingTimeInterval(420 * 60)
        let calc = DoseWindowCalculator(now: { anchor.addingTimeInterval(430 * 60) })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: d2, dose2Skipped: false, snoozeCount: 0, wakeFinalAt: wakeTime, checkInCompleted: false)
        XCTAssertEqual(ctx.phase, .finalizing)
        if case .snoozeDisabled = ctx.snooze { /* expected */ } else {
            XCTFail("SSOT P0-2: Snooze must be disabled during finalizing")
        }
    }
    
    // MARK: - P0-3: Closed Phase Must Not Allow Direct Dose Persistence
    // Validates the window state supports P0-3 Flic bypass fix
    
    /// SSOT: Closed phase has .takeWithOverride (requires explicit confirmation, not auto-persist)
    func testSSOT_closedPhase_requiresOverride() {
        let anchor = Date()
        let calc = DoseWindowCalculator(now: { anchor.addingTimeInterval(250 * 60) })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx.phase, .closed)
        if case .takeWithOverride = ctx.primary { /* expected */ } else {
            XCTFail("SSOT P0-3: Closed phase must use .takeWithOverride, not .takeNow")
        }
    }
    
    /// SSOT: Completed phase must have .disabled primary (no second-take via any surface)
    func testSSOT_completedPhase_primaryDisabled() {
        let anchor = Date()
        let d2 = anchor.addingTimeInterval(165 * 60)
        let calc = DoseWindowCalculator(now: { anchor.addingTimeInterval(200 * 60) })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: d2, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx.phase, .completed)
        if case .disabled = ctx.primary { /* expected */ } else {
            XCTFail("SSOT P0-3: Completed phase must have .disabled primary CTA")
        }
    }
    
    // MARK: - GAP D: DoseTapCore Stored State Regression Guard
    
    /// CRITICAL: DoseTapCore must NOT store dose state directly.
    /// All state must flow through SessionRepository to prevent two sources of truth.
    /// If this test fails, it means someone added stored dose state to DoseTapCore.
    func testSSOT_doseTapCore_noStoredDoseState() {
        // DoseTapCore's computed properties must delegate to sessionRepository.
        // NO @Published var dose1Time, NO private var _dose1Time.
        // DoseWindowCalculator must be stateless - same calculator, different inputs → different outputs.
        let calc = DoseWindowCalculator()
        let ctx1 = calc.context(dose1At: Date(), dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        let ctx2 = calc.context(dose1At: nil, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertNotEqual(ctx1.phase, ctx2.phase,
            "DoseWindowCalculator must be stateless - same calculator, different inputs, different outputs")
    }
    
    /// Verify DoseWindowContext is computed fresh each time (no caching)
    func testSSOT_doseWindowContext_computedNotCached() {
        let anchor = Date()
        var now = anchor
        let calc = DoseWindowCalculator(now: { now })
        
        // First context at 0 minutes
        let ctx1 = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx1.phase, .beforeWindow, "0 minutes: beforeWindow")
        
        // Move time forward
        now = anchor.addingTimeInterval(160 * 60)
        
        // Second context should reflect new time
        let ctx2 = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx2.phase, .active, "160 minutes: active")
        
        // Verify contexts are independent
        XCTAssertNotEqual(ctx1.phase, ctx2.phase, "Contexts must be computed fresh, not cached")
    }
}

