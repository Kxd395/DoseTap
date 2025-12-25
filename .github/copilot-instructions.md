# Copilot instructions for DoseTap

Purpose: make AI agents productive fast in this repo. Focus on the current SwiftPM core and SSOT-first workflow.

SSOT update checklist (always first):
- Update `docs/SSOT/README.md` for any behavior change (states, thresholds, errors)
- If navigation or contracts change, also update `docs/SSOT/navigation.md` and `docs/SSOT/contracts/*`
- Link the exact tests you added/updated in your PR description
- Re-run docs check script if applicable (e.g., `tools/ssot_check.sh`)

## Big picture
- App: iOS/watchOS XYWAV-only dose timer. Core invariant: Dose 2 must be 150–240 minutes after Dose 1; default target 165m; Snooze adds 10m; Snooze disabled when <15m remain.
- Architecture split:
  - Core logic (platform-free) in `ios/Core` as SwiftPM target `DoseCore` with unit tests in `Tests/DoseCoreTests`.
  - Legacy SwiftUI app under `ios/DoseTap/` (contains duplicates/old code). Avoid touching unless explicitly modernizing; prefer new work inside `ios/Core` + tests.
  - SSOT docs drive behavior: see `docs/SSOT/` for authoritative specs and contracts.

## Where to work (fast path)
- Add/modify pure logic in `ios/Core/*.swift` (no UIKit/SwiftUI). Keep APIs small, deterministic, and testable.
- Add tests in `Tests/DoseCoreTests/*.swift`. Inject time via closures for determinism (see `DoseWindowCalculator(now:)`).
- Update SSOT when behavior changes: `docs/SSOT/README.md` and/or `docs/SSOT/navigation.md`.

## Build, test, debug
- Build core and run tests from the repo root:
  - `swift build -q`
  - `swift test -q`
- Known good state: `swift build` succeeds; all DoseCoreTests pass (window math, API errors, offline queue, rate limiter). Run `swift test -q` and check CI for current count.
- Xcode app target may fail due to legacy files. If you must run the app, quarantine conflicting legacy files with `#if false` or `#if canImport(...)` as already done in several `ios/DoseTap/*.swift` files.

How to run the iOS app target safely (avoiding legacy conflicts):
- Open `ios/DoseTap/DoseTap.xcodeproj` in Xcode and select the iOS app scheme
- If compile errors appear in legacy files under `ios/DoseTap/`, temporarily wrap them in `#if false ... #endif` (examples: `TimeEngine.swift`, `EventStore.swift`, `UndoManager.swift`, `DoseTapCore.swift`, `ContentView_Old.swift`, `DashboardView.swift`)
- For UIKit/SwiftUI import issues when using SwiftPM-only contexts, guard imports: `#if canImport(SwiftUI) import SwiftUI #endif`
- Prefer validating behavior via `DoseCore` unit tests; only run the app after the build is green

## Key components and patterns
- Dose window model: `ios/Core/DoseWindowState.swift`
  - Config: `DoseWindowConfig(min=150, max=240, nearWindowThresholdMin=15, defaultTargetMin=165, snoozeStepMin=10, maxSnoozes)`
  - Output: `DoseWindowContext` with `phase`, `primary` CTA, `snooze/skip` states, remaining time, errors.
- Networking: `ios/Core/APIClient.swift` with uniform error mapping in `ios/Core/APIErrors.swift`.
  - Endpoints kept: `/doses/take`, `/doses/skip`, `/doses/snooze`, `/events/log`, `/analytics/export`.
  - Errors mapped to `DoseAPIError`: `422_WINDOW_EXCEEDED`, `422_SNOOZE_LIMIT`, `422_DOSE1_REQUIRED`, `409_ALREADY_TAKEN`, `429_RATE_LIMIT`, `401_DEVICE_NOT_REGISTERED`.
- Resilience: `ios/Core/OfflineQueue.swift` (actor) with `enqueue` + `flush`, used by `DosingService`.
- Service façade: `ios/Core/APIClientQueueIntegration.swift` defines `DosingService` actor combining API + queue + limiter.
- Event debounce: `ios/Core/EventRateLimiter.swift` with default cooldowns `{ "bathroom": 60 }`.

## Conventions (project-specific)
- Keep `DoseCore` platform-free: no `import SwiftUI/UIKit`. Use `#if canImport(...)` only in app/UI files.
- Prefer actors for mutable state (`OfflineQueue`, `DosingService`, `EventRateLimiter`).
- Inject time (`now: () -> Date`) for anything time-based; test DST edges explicitly.
- Use discrete actions/strings that match SSOT (e.g., events: `bathroom|lights_out|wake_final`).
- When adding endpoints, route through `APIClient` + map errors via `APIErrorMapper`.

## Typical slice workflow
1. Write a failing unit test in `Tests/DoseCoreTests/*` (add cases like `DoseWindowEdgeTests`, `APIErrorsTests`).
2. Implement logic in `ios/Core/*` (new file if needed). Keep public surface small and value-type heavy.
3. If networking, add a method to `APIClient` and update `DosingService.Action` switch.
4. Add/extend docs in `docs/SSOT/*` reflecting exact UX states, thresholds, and error copy.
5. Run `swift test -q` until green.

## Integration boundaries
- UI (SwiftUI) should consume `DoseWindowContext` and call `DosingService.perform(_:)`. Avoid duplicating window logic in views.
- Rate limits: let `EventRateLimiter` drop spam (e.g., bathroom within 60s) before hitting API.
- Offline: on failure `DosingService` enqueues and later `flushPending()` sends.

## Pitfalls and gotchas
- Legacy duplicates under `ios/DoseTap/` (e.g., `TimeEngine.swift`, `EventStore.swift`, `UndoManager.swift`, `DoseTapCore.swift`) conflict with new core—don’t re-enable them.
- Snooze must be disabled when remaining window < 15m and after `maxSnoozes` reached; tests exist—match them.
- Use UTC ISO8601 for API bodies; server errors are decoded via `APIErrorPayload{ code, message }`.

## Pointers
- Core files: `ios/Core/{DoseWindowState, APIClient, APIErrors, OfflineQueue, APIClientQueueIntegration, EventRateLimiter}.swift`
- Tests: `Tests/DoseCoreTests/{DoseWindowStateTests, DoseWindowEdgeTests, APIErrorsTests, APIClientTests, OfflineQueueTests, EventRateLimiterTests}.swift`
- Specs: `docs/SSOT/README.md`, `docs/SSOT/navigation.md`, `docs/api-documentation.md`

If anything here is unclear or you discover a mismatch with the SSOT or tests, pause and update the SSOT first, then code.

## Examples (repo-specific patterns)

1) Add a new APIClient endpoint (+ minimal test)

Swift (in `ios/Core/APIClient.swift`):

```swift
public struct RegisterBody: Encodable { let device_id: String, platform: String }
public func registerDevice(id: String, platform: String = "iOS") async throws {
  let req = try makeRequest(path: "/auth/device", body: RegisterBody(device_id: id, platform: platform))
  let (data, response) = try await transport.send(req)
  if (400..<600).contains(response.statusCode) { throw APIErrorMapper.map(data: data, status: response.statusCode) }
}
```

Test (in `Tests/DoseCoreTests/APIClientTests.swift`):

```swift
func testRegisterDevicePOST() async throws {
  var captured: URLRequest?
  let transport = StubTransport { req in
    captured = req
    let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    return (Data(), resp)
  }
  let client = APIClient(baseURL: URL(string: "https://example.com")!, transport: transport)
  try await client.registerDevice(id: "dev_123")
  XCTAssertEqual(captured?.httpMethod, "POST")
  XCTAssertEqual(captured?.url?.path, "/auth/device")
}
```

2) Integrate a new action in `DosingService` (façade wiring)

Swift (in `ios/Core/APIClientQueueIntegration.swift`):

```swift
public enum Action: Codable, Sendable, Equatable {
  case takeDose(type: String, at: Date)
  case skipDose(sequence: Int, reason: String?)
  case snooze(minutes: Int)
  case logEvent(name: String, at: Date)
  case registerDevice(id: String) // new
}

private func send(_ action: Action) async throws {
  switch action {
  case .registerDevice(let id): try await client.registerDevice(id: id)
  // …existing cases…
  default: /* existing switch arms */ break
  }
}
```

3) Time-injected test for window math

Swift (in `Tests/DoseCoreTests/DoseWindowEdgeTests.swift`):

```swift
func test_exact_150_enters_active() {
  let d1 = Date(timeIntervalSince1970: 0)
  let calc = DoseWindowCalculator(now: { Date(timeIntervalSince1970: 150*60) })
  let ctx = calc.context(dose1At: d1, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
  XCTAssertEqual(ctx.phase, .active)
}
```
