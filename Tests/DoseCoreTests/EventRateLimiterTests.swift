import XCTest
@testable import DoseCore

final class EventRateLimiterTests: XCTestCase {
    
    // MARK: - Basic shouldAllow Tests
    
    func testBathroomDebounce60s() async {
        let limiter = EventRateLimiter.default
        let first = await limiter.shouldAllow(event: "bathroom", at: Date(timeIntervalSince1970: 0))
        let second = await limiter.shouldAllow(event: "bathroom", at: Date(timeIntervalSince1970: 30))
        let third = await limiter.shouldAllow(event: "bathroom", at: Date(timeIntervalSince1970: 61))
        XCTAssertTrue(first)
        XCTAssertFalse(second) // within 60s
        XCTAssertTrue(third)   // after 60s
    }
    
    func testWaterDebounce300s() async {
        let limiter = EventRateLimiter.default
        let first = await limiter.shouldAllow(event: "water", at: Date(timeIntervalSince1970: 0))
        let atFourMin = await limiter.shouldAllow(event: "water", at: Date(timeIntervalSince1970: 240))
        let atFiveMinPlus = await limiter.shouldAllow(event: "water", at: Date(timeIntervalSince1970: 301))
        XCTAssertTrue(first)
        XCTAssertFalse(atFourMin, "Should block at 4 min (within 5 min cooldown)")
        XCTAssertTrue(atFiveMinPlus, "Should allow after 5 min cooldown")
    }
    
    func testSnackDebounce900s() async {
        let limiter = EventRateLimiter.default
        let first = await limiter.shouldAllow(event: "snack", at: Date(timeIntervalSince1970: 0))
        let at10min = await limiter.shouldAllow(event: "snack", at: Date(timeIntervalSince1970: 600))
        let at15minPlus = await limiter.shouldAllow(event: "snack", at: Date(timeIntervalSince1970: 901))
        XCTAssertTrue(first)
        XCTAssertFalse(at10min, "Should block at 10 min (within 15 min cooldown)")
        XCTAssertTrue(at15minPlus, "Should allow after 15 min cooldown")
    }
    
    func testLightsOutDebounce1Hour() async {
        let limiter = EventRateLimiter.default
        let first = await limiter.shouldAllow(event: "lightsOut", at: Date(timeIntervalSince1970: 0))
        let at30min = await limiter.shouldAllow(event: "lightsOut", at: Date(timeIntervalSince1970: 1800))
        let at1hourPlus = await limiter.shouldAllow(event: "lightsOut", at: Date(timeIntervalSince1970: 3601))
        XCTAssertTrue(first)
        XCTAssertFalse(at30min, "Should block at 30 min (within 1h cooldown)")
        XCTAssertTrue(at1hourPlus, "Should allow after 1h cooldown")
    }
    
    func testUnknownEvent_alwaysAllowed() async {
        let limiter = EventRateLimiter.default
        let first = await limiter.shouldAllow(event: "unknown_event", at: Date(timeIntervalSince1970: 0))
        let second = await limiter.shouldAllow(event: "unknown_event", at: Date(timeIntervalSince1970: 1))
        XCTAssertTrue(first)
        XCTAssertTrue(second, "Unknown events should always be allowed (no cooldown defined)")
    }
    
    // MARK: - canLog Tests (doesn't register)
    
    func testCanLog_doesNotRegister() async {
        let limiter = EventRateLimiter.default
        let canLog1 = await limiter.canLog(event: "bathroom", at: Date(timeIntervalSince1970: 0))
        let canLog2 = await limiter.canLog(event: "bathroom", at: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(canLog1)
        XCTAssertTrue(canLog2, "canLog should not register the event")
    }
    
    func testCanLog_respectsExistingCooldown() async {
        let limiter = EventRateLimiter.default
        _ = await limiter.shouldAllow(event: "bathroom", at: Date(timeIntervalSince1970: 0)) // Register
        let canLogAt30s = await limiter.canLog(event: "bathroom", at: Date(timeIntervalSince1970: 30))
        let canLogAt61s = await limiter.canLog(event: "bathroom", at: Date(timeIntervalSince1970: 61))
        XCTAssertFalse(canLogAt30s, "canLog should respect cooldown")
        XCTAssertTrue(canLogAt61s, "canLog should allow after cooldown")
    }
    
    // MARK: - remainingCooldown Tests
    
    func testRemainingCooldown_returnsCorrectValue() async {
        let limiter = EventRateLimiter.default
        _ = await limiter.shouldAllow(event: "bathroom", at: Date(timeIntervalSince1970: 0))
        let remainingAt30s = await limiter.remainingCooldown(for: "bathroom", at: Date(timeIntervalSince1970: 30))
        let remainingAt60s = await limiter.remainingCooldown(for: "bathroom", at: Date(timeIntervalSince1970: 60))
        let remainingAt70s = await limiter.remainingCooldown(for: "bathroom", at: Date(timeIntervalSince1970: 70))
        XCTAssertEqual(remainingAt30s, 30, accuracy: 0.1, "Should have 30s remaining")
        XCTAssertEqual(remainingAt60s, 0, accuracy: 0.1, "Should have 0s remaining at exact cooldown")
        XCTAssertEqual(remainingAt70s, 0, accuracy: 0.1, "Should have 0s remaining after cooldown")
    }
    
    func testRemainingCooldown_unknownEvent_returnsZero() async {
        let limiter = EventRateLimiter.default
        let remaining = await limiter.remainingCooldown(for: "unknown", at: Date())
        XCTAssertEqual(remaining, 0, "Unknown events should return 0 cooldown")
    }
    
    func testRemainingCooldown_neverRegistered_returnsZero() async {
        let limiter = EventRateLimiter.default
        let remaining = await limiter.remainingCooldown(for: "bathroom", at: Date())
        XCTAssertEqual(remaining, 0, "Never-registered events should return 0 cooldown")
    }
    
    // MARK: - reset Tests
    
    func testReset_clearsSpecificEvent() async {
        let limiter = EventRateLimiter.default
        _ = await limiter.shouldAllow(event: "bathroom", at: Date(timeIntervalSince1970: 0))
        _ = await limiter.shouldAllow(event: "water", at: Date(timeIntervalSince1970: 0))
        
        await limiter.reset(event: "bathroom")
        
        let bathroomAfterReset = await limiter.shouldAllow(event: "bathroom", at: Date(timeIntervalSince1970: 10))
        let waterAfterReset = await limiter.shouldAllow(event: "water", at: Date(timeIntervalSince1970: 10))
        
        XCTAssertTrue(bathroomAfterReset, "Reset event should be allowed immediately")
        XCTAssertFalse(waterAfterReset, "Non-reset event should still be blocked")
    }
    
    func testResetAll_clearsAllEvents() async {
        let limiter = EventRateLimiter.default
        _ = await limiter.shouldAllow(event: "bathroom", at: Date(timeIntervalSince1970: 0))
        _ = await limiter.shouldAllow(event: "water", at: Date(timeIntervalSince1970: 0))
        
        await limiter.resetAll()
        
        let bathroomAfter = await limiter.shouldAllow(event: "bathroom", at: Date(timeIntervalSince1970: 10))
        let waterAfter = await limiter.shouldAllow(event: "water", at: Date(timeIntervalSince1970: 10))
        
        XCTAssertTrue(bathroomAfter, "All events should be allowed after resetAll")
        XCTAssertTrue(waterAfter, "All events should be allowed after resetAll")
    }
    
    // MARK: - register Tests
    
    func testRegister_manuallyRegistersEvent() async {
        let limiter = EventRateLimiter.default
        await limiter.register(event: "bathroom", at: Date(timeIntervalSince1970: 0))
        
        let allowed = await limiter.shouldAllow(event: "bathroom", at: Date(timeIntervalSince1970: 30))
        XCTAssertFalse(allowed, "Manually registered event should start cooldown")
    }
    
    // MARK: - Static Factory Tests
    
    func testDefaultLimiter_hasAllEventCooldowns() async {
        let limiter = EventRateLimiter.default
        
        // Verify key events have cooldowns by checking they start blocked after first call
        _ = await limiter.shouldAllow(event: "bathroom", at: Date(timeIntervalSince1970: 0))
        _ = await limiter.shouldAllow(event: "water", at: Date(timeIntervalSince1970: 0))
        _ = await limiter.shouldAllow(event: "anxiety", at: Date(timeIntervalSince1970: 0))
        
        let bathroomBlocked = await limiter.shouldAllow(event: "bathroom", at: Date(timeIntervalSince1970: 30))
        let waterBlocked = await limiter.shouldAllow(event: "water", at: Date(timeIntervalSince1970: 30))
        let anxietyBlocked = await limiter.shouldAllow(event: "anxiety", at: Date(timeIntervalSince1970: 30))
        
        XCTAssertFalse(bathroomBlocked, "Default should have bathroom cooldown")
        XCTAssertFalse(waterBlocked, "Default should have water cooldown")
        XCTAssertFalse(anxietyBlocked, "Default should have anxiety cooldown")
    }
    
    func testLegacyLimiter_onlyBathroomCooldown() async {
        let limiter = EventRateLimiter.legacy
        
        _ = await limiter.shouldAllow(event: "bathroom", at: Date(timeIntervalSince1970: 0))
        _ = await limiter.shouldAllow(event: "water", at: Date(timeIntervalSince1970: 0))
        
        let bathroomBlocked = await limiter.shouldAllow(event: "bathroom", at: Date(timeIntervalSince1970: 30))
        let waterAllowed = await limiter.shouldAllow(event: "water", at: Date(timeIntervalSince1970: 1))
        
        XCTAssertFalse(bathroomBlocked, "Legacy should have bathroom cooldown")
        XCTAssertTrue(waterAllowed, "Legacy should NOT have water cooldown")
    }
    
    // MARK: - Edge Cases
    
    func testExactCooldownBoundary() async {
        let limiter = EventRateLimiter(cooldowns: ["test": 60])
        _ = await limiter.shouldAllow(event: "test", at: Date(timeIntervalSince1970: 0))
        
        let atExact60 = await limiter.shouldAllow(event: "test", at: Date(timeIntervalSince1970: 60))
        XCTAssertTrue(atExact60, "Should allow at exact cooldown boundary")
    }
    
    func testMultipleEventsIndependent() async {
        let limiter = EventRateLimiter.default
        _ = await limiter.shouldAllow(event: "bathroom", at: Date(timeIntervalSince1970: 0))
        
        let waterAllowed = await limiter.shouldAllow(event: "water", at: Date(timeIntervalSince1970: 30))
        XCTAssertTrue(waterAllowed, "Different events should have independent cooldowns")
    }
}
