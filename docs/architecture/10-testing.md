# 10 — Testing

## Test Pyramid

```text
         ┌───────────┐
         │  XCUITest  │  12 tests
         │  (E2E)     │  Full app UI flows
         ├───────────┤
         │  Xcode    │  134 tests
         │  Unit     │  App-layer with SwiftUI deps
         ├───────────┤
         │  SwiftPM  │  559 tests
         │  Unit     │  Platform-free DoseCore logic
         └───────────┘
         Total: 705 tests
```

## SwiftPM Tests (559)

Directory: `Tests/DoseCoreTests/` (31 files)

All run with `swift test -q` from repo root. No simulator needed.

### Test File Inventory

| File | Tests | Coverage |
| ---- | ----- | -------- |
| `DoseWindowStateTests.swift` | Window phase computation, all 7 phases |
| `DoseWindowEdgeTests.swift` | Boundary conditions (exact 150m, 240m, DST) |
| `Dose2EdgeCaseTests.swift` | Dose 2 edge cases, extra dose |
| `DosingModelsTests.swift` | Amount units, regimen, adherence |
| `DosingAmountTests.swift` | Dosing amount schema |
| `APIClientTests.swift` | All endpoints with StubTransport |
| `APIErrorsTests.swift` | Error mapping for all codes |
| `DosingServiceTests.swift` | Façade integration |
| `OfflineQueueTests.swift` | Queue/flush/retry |
| `EventRateLimiterTests.swift` | Cooldown logic |
| `CertificatePinningTests.swift` | Pin matching, domain scoping |
| `DataRedactorTests.swift` | Email/UUID/IP redaction |
| `DiagnosticEventTests.swift` | Event serialization |
| `DiagnosticLoggerTests.swift` | Tier filtering |
| `DoseUndoManagerTests.swift` | Undo/commit lifecycle |
| `EventStoreModelsTests.swift` | Event type normalization |
| `MedicationLoggerTests.swift` | Medication CRUD |
| `MorningCheckInTests.swift` | Check-in validation |
| `NightScoreCalculatorTests.swift` | Score computation (24 tests) |
| `RecommendationEngineTests.swift` | Sleep recommendations |
| `SessionRolloverRegressionTests.swift` | Rollover boundary |
| `SessionIdBackfillTests.swift` | Session ID migration |
| `SleepEventTests.swift` | Sleep event types |
| `SleepPlanCalculatorTests.swift` | Plan computation |
| `SleepEnvironmentTests.swift` | Environment factors |
| `SSOTComplianceTests.swift` | Constants match SSOT |
| `TimeCorrectnessTests.swift` | Time computation accuracy |
| `TimeEngineTests.swift` | Time engine logic |
| `UnifiedSleepSessionTests.swift` | Cross-source session merge |
| `CSVExporterTests.swift` | CSV output format |
| `CRUDActionTests.swift` | CRUD operation types |

## Testing Patterns

### Time Injection

```swift
// Production: real clock
let calc = DoseWindowCalculator()

// Test: fixed time
let calc = DoseWindowCalculator(now: {
    Date(timeIntervalSince1970: 150 * 60)
})
```

### In-Memory Storage

```swift
#if DEBUG
let storage = EventStorage.inMemory()
let repo = SessionRepository(storage: storage)
#endif
```

### Stub Transport (API)

```swift
let transport = StubTransport { request in
    let response = HTTPURLResponse(
        url: request.url!, statusCode: 200,
        httpVersion: nil, headerFields: nil
    )!
    return (responseData, response)
}
let client = APIClient(baseURL: url, transport: transport)
```

### DST Edge Testing

```swift
func test_DST_spring_forward_150m_boundary() {
    // 2:00 AM → 3:00 AM (spring forward)
    // Elapsed: 150 real minutes, but wall clock shows 210m
    // Window calculator uses TimeInterval, not wall clock
}
```

## Xcode Unit Tests (134)

Directory: `ios/DoseTapTests/`

Tests that require SwiftUI or UIKit imports. Run via Xcode scheme.

## XCUITest (12)

Directory: `ios/DoseTapTests/` (UI target)

End-to-end flows:

- App launch
- Take Dose 1 flow
- Take Dose 2 flow
- Snooze flow
- Settings navigation
- Deep link handling

## Running Tests

```bash
# SwiftPM (fast, no simulator)
swift test -q

# Xcode unit tests
xcodebuild test -project ios/DoseTap.xcodeproj \
  -scheme DoseTap \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  CODE_SIGNING_ALLOWED=NO

# Just build check (no tests)
swift build -q
```

## Test Coverage Goals

- DoseCore: >90% line coverage (window math, API errors)
- Session lifecycle: all state transitions tested
- Security: all validation paths tested
- Undo: all action types tested
- Edge cases: DST, timezone change, midnight rollover
