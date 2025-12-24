import XCTest
@testable import DoseCore

/// Comprehensive CRUD and action tests for DoseTap
/// Verifies all state transitions and API actions work correctly
final class CRUDActionTests: XCTestCase {
    
    // MARK: - Test Helper
    
    private struct StubTransport: APITransport {
        var handler: (URLRequest) async throws -> (Data, HTTPURLResponse)
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            try await handler(request)
        }
    }
    
    // MARK: - CREATE Tests - Initial States
    
    func testCREATE_newContext_noDose1() {
        // CREATE: New context with no doses - should show noDose1 phase
        let calc = DoseWindowCalculator()
        let ctx = calc.context(dose1At: nil, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        
        XCTAssertEqual(ctx.phase, .noDose1)
        XCTAssertNil(ctx.elapsedSinceDose1)
        XCTAssertTrue(ctx.errors.contains(.dose1Required))
    }
    
    func testCREATE_contextWithDose1() {
        // CREATE: Context with Dose 1 recorded - should be beforeWindow
        let dose1 = Date()
        let calc = DoseWindowCalculator(now: { dose1.addingTimeInterval(60 * 60) }) // 1 hour later
        let ctx = calc.context(dose1At: dose1, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        
        XCTAssertEqual(ctx.phase, .beforeWindow)
        XCTAssertNotNil(ctx.elapsedSinceDose1)
        XCTAssertNotNil(ctx.remainingToMax)
    }
    
    // MARK: - READ Tests - Query Current State
    
    func testREAD_phaseActive() {
        // READ: Query phase when in active window
        let dose1 = Date()
        let calc = DoseWindowCalculator(now: { dose1.addingTimeInterval(160 * 60) }) // In window
        let ctx = calc.context(dose1At: dose1, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        
        XCTAssertEqual(ctx.phase, .active)
        XCTAssertEqual(ctx.primary, .takeNow)
    }
    
    func testREAD_snoozeState_enabled() {
        // READ: Snooze should be enabled in active window
        let dose1 = Date()
        let calc = DoseWindowCalculator(now: { dose1.addingTimeInterval(160 * 60) })
        let ctx = calc.context(dose1At: dose1, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        
        if case .snoozeEnabled = ctx.snooze {
            // Success
        } else {
            XCTFail("Expected snooze to be enabled")
        }
    }
    
    func testREAD_snoozeState_disabled_nearClose() {
        // READ: Snooze should be disabled near close
        let dose1 = Date()
        let calc = DoseWindowCalculator(now: { dose1.addingTimeInterval(230 * 60) }) // 10 min left
        let ctx = calc.context(dose1At: dose1, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        
        XCTAssertEqual(ctx.phase, .nearClose)
        if case .snoozeDisabled = ctx.snooze {
            // Success - snooze disabled near close
        } else {
            XCTFail("Expected snooze to be disabled near close")
        }
    }
    
    // MARK: - UPDATE Tests - Modify State
    
    func testUPDATE_snoozeCount_increment() {
        // UPDATE: Increment snooze count
        let dose1 = Date()
        let calc = DoseWindowCalculator(now: { dose1.addingTimeInterval(170 * 60) })
        
        let ctx0 = calc.context(dose1At: dose1, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx0.snoozeCount, 0)
        
        let ctx1 = calc.context(dose1At: dose1, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 1)
        XCTAssertEqual(ctx1.snoozeCount, 1)
        
        let ctx2 = calc.context(dose1At: dose1, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 2)
        XCTAssertEqual(ctx2.snoozeCount, 2)
    }
    
    func testUPDATE_snoozeCount_limitReached() {
        // UPDATE: Max snoozes reached - snooze should be disabled
        let dose1 = Date()
        let calc = DoseWindowCalculator(now: { dose1.addingTimeInterval(170 * 60) })
        
        let ctx3 = calc.context(dose1At: dose1, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 3)
        XCTAssertEqual(ctx3.snoozeCount, 3)
        
        if case .snoozeDisabled(let reason) = ctx3.snooze {
            XCTAssertTrue(reason.contains("limit") || reason.contains("Limit"))
        } else {
            XCTFail("Expected snooze to be disabled at max count")
        }
    }
    
    func testUPDATE_dose2Taken_completed() {
        // UPDATE: Mark Dose 2 as taken - should be completed
        let dose1 = Date()
        let dose2 = dose1.addingTimeInterval(170 * 60)
        let calc = DoseWindowCalculator(now: { dose2.addingTimeInterval(60) })
        
        let ctx = calc.context(dose1At: dose1, dose2TakenAt: dose2, dose2Skipped: false, snoozeCount: 0)
        
        XCTAssertEqual(ctx.phase, .completed)
    }
    
    func testUPDATE_dose2Skipped_completed() {
        // UPDATE: Mark Dose 2 as skipped - should be completed
        let dose1 = Date()
        let calc = DoseWindowCalculator(now: { dose1.addingTimeInterval(250 * 60) })
        
        let ctx = calc.context(dose1At: dose1, dose2TakenAt: nil, dose2Skipped: true, snoozeCount: 0)
        
        XCTAssertEqual(ctx.phase, .completed)
    }
    
    // MARK: - DELETE Tests - Reset State
    
    func testDELETE_resetSession() {
        // DELETE: Reset to fresh state
        let calc = DoseWindowCalculator()
        let ctx = calc.context(dose1At: nil, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        
        XCTAssertEqual(ctx.phase, .noDose1)
        XCTAssertNil(ctx.elapsedSinceDose1)
        XCTAssertNil(ctx.remainingToMax)
    }
    
    // MARK: - API Action Tests
    
    func testACTION_takeDose_POST() async throws {
        var capturedRequest: URLRequest?
        let transport = StubTransport { req in
            capturedRequest = req
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = """
            {"event_id":"123","type":"dose1","at":"2025-01-01T00:00:00Z"}
            """
            return (json.data(using: .utf8)!, resp)
        }
        
        let client = APIClient(baseURL: URL(string: "https://api.test.com")!, transport: transport)
        try await client.takeDose(type: "dose1", at: Date())
        
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertTrue(capturedRequest?.url?.path.contains("/doses/take") ?? false)
    }
    
    func testACTION_skipDose_POST() async throws {
        var capturedRequest: URLRequest?
        let transport = StubTransport { req in
            capturedRequest = req
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = """
            {"event_id":"456","reason":"testing"}
            """
            return (json.data(using: .utf8)!, resp)
        }
        
        let client = APIClient(baseURL: URL(string: "https://api.test.com")!, transport: transport)
        try await client.skipDose(sequence: 2, reason: "testing")
        
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertTrue(capturedRequest?.url?.path.contains("/doses/skip") ?? false)
    }
    
    func testACTION_snooze_POST() async throws {
        var capturedRequest: URLRequest?
        let transport = StubTransport { req in
            capturedRequest = req
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = """
            {"event_id":"789","minutes":10,"new_target_at":"2025-01-01T00:10:00Z"}
            """
            return (json.data(using: .utf8)!, resp)
        }
        
        let client = APIClient(baseURL: URL(string: "https://api.test.com")!, transport: transport)
        try await client.snooze(minutes: 10)
        
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertTrue(capturedRequest?.url?.path.contains("/doses/snooze") ?? false)
    }
    
    func testACTION_logEvent_POST() async throws {
        var capturedRequest: URLRequest?
        let transport = StubTransport { req in
            capturedRequest = req
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = """
            {"event_id":"abc","event":"bathroom","at":"2025-01-01T00:00:00Z"}
            """
            return (json.data(using: .utf8)!, resp)
        }
        
        let client = APIClient(baseURL: URL(string: "https://api.test.com")!, transport: transport)
        try await client.logEvent("bathroom", at: Date())
        
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertTrue(capturedRequest?.url?.path.contains("/events/log") ?? false)
    }
    
    func testACTION_exportAnalytics_GET() async throws {
        var capturedRequest: URLRequest?
        let transport = StubTransport { req in
            capturedRequest = req
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = "{\"events\":[]}"
            return (json.data(using: .utf8)!, resp)
        }
        
        let client = APIClient(baseURL: URL(string: "https://api.test.com")!, transport: transport)
        let _ = try await client.exportAnalytics()
        
        XCTAssertEqual(capturedRequest?.httpMethod, "GET")
        XCTAssertTrue(capturedRequest?.url?.path.contains("/analytics/export") ?? false)
    }
    
    // MARK: - Rate Limiter Tests
    
    func testRateLimiter_allowsFirst() async {
        let limiter = EventRateLimiter(cooldowns: ["bathroom": 60])
        let allowed = await limiter.shouldAllow(event: "bathroom")
        XCTAssertTrue(allowed)
    }
    
    func testRateLimiter_blocksRapid() async {
        let limiter = EventRateLimiter(cooldowns: ["bathroom": 60])
        
        _ = await limiter.shouldAllow(event: "bathroom") // First - allowed
        let second = await limiter.shouldAllow(event: "bathroom") // Second - blocked
        
        XCTAssertFalse(second)
    }
    
    func testRateLimiter_allowsDifferentEvents() async {
        let limiter = EventRateLimiter(cooldowns: ["bathroom": 60, "lights_out": 300])
        
        let bathroom = await limiter.shouldAllow(event: "bathroom")
        let lights = await limiter.shouldAllow(event: "lights_out")
        
        XCTAssertTrue(bathroom)
        XCTAssertTrue(lights)
    }
    
    // MARK: - Phase Transition Tests
    
    func testTransition_noDose1_to_beforeWindow() {
        let calc = DoseWindowCalculator()
        
        // Before Dose 1
        let ctx1 = calc.context(dose1At: nil, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx1.phase, .noDose1)
        
        // After Dose 1 (immediately)
        let dose1 = Date()
        let calcAfter = DoseWindowCalculator(now: { dose1.addingTimeInterval(1) })
        let ctx2 = calcAfter.context(dose1At: dose1, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx2.phase, .beforeWindow)
    }
    
    func testTransition_beforeWindow_to_active() {
        let dose1 = Date()
        
        // At 149 minutes - still beforeWindow
        let calc149 = DoseWindowCalculator(now: { dose1.addingTimeInterval(149 * 60) })
        let ctx149 = calc149.context(dose1At: dose1, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx149.phase, .beforeWindow)
        
        // At 150 minutes - active
        let calc150 = DoseWindowCalculator(now: { dose1.addingTimeInterval(150 * 60) })
        let ctx150 = calc150.context(dose1At: dose1, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx150.phase, .active)
    }
    
    func testTransition_active_to_nearClose() {
        let dose1 = Date()
        
        // At 224 minutes - still active
        let calc224 = DoseWindowCalculator(now: { dose1.addingTimeInterval(224 * 60) })
        let ctx224 = calc224.context(dose1At: dose1, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx224.phase, .active)
        
        // At 225 minutes - near close (15m threshold)
        let calc225 = DoseWindowCalculator(now: { dose1.addingTimeInterval(225 * 60) })
        let ctx225 = calc225.context(dose1At: dose1, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx225.phase, .nearClose)
    }
    
    func testTransition_nearClose_to_closed() {
        let dose1 = Date()
        
        // At 239 minutes - still nearClose
        let calc239 = DoseWindowCalculator(now: { dose1.addingTimeInterval(239 * 60) })
        let ctx239 = calc239.context(dose1At: dose1, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx239.phase, .nearClose)
        
        // At 240 minutes - closed
        let calc240 = DoseWindowCalculator(now: { dose1.addingTimeInterval(240 * 60) })
        let ctx240 = calc240.context(dose1At: dose1, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx240.phase, .closed)
    }
    
    func testTransition_active_to_completed() {
        let dose1 = Date()
        let dose2 = dose1.addingTimeInterval(170 * 60) // Dose 2 at 170 minutes
        
        let calc = DoseWindowCalculator(now: { dose2.addingTimeInterval(60) })
        let ctx = calc.context(dose1At: dose1, dose2TakenAt: dose2, dose2Skipped: false, snoozeCount: 0)
        
        XCTAssertEqual(ctx.phase, .completed)
    }
    
    // MARK: - Error State Tests
    
    func testError_windowExceeded() {
        let dose1 = Date()
        let calc = DoseWindowCalculator(now: { dose1.addingTimeInterval(250 * 60) }) // Past window
        let ctx = calc.context(dose1At: dose1, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        
        XCTAssertEqual(ctx.phase, .closed)
        XCTAssertTrue(ctx.errors.contains(.windowExceeded))
    }
    
    func testError_dose1Required() {
        let calc = DoseWindowCalculator()
        let ctx = calc.context(dose1At: nil, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        
        XCTAssertTrue(ctx.errors.contains(.dose1Required))
    }
}
