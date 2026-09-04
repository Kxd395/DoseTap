# Copilot instructions for DoseTap

Purpose: make AI agents productive fast in this repo. Focus on the current SwiftPM core and SSOT-first workflow.

## ⛔ Hard Rules (NON-NEGOTIABLE)

These rules override ALL other guidance. Violating any of them creates P0 bugs.

1. **Never leave a broken build.** Every file you save MUST compile. If you delete, rename, or move a type/property/method, use `rg` to find all usages across the repository and update every caller before finishing. Partial refactoring is forbidden.
2. **Preserve the working tree.** Existing changes belong to the user unless proven otherwise. Do not reset, stash, overwrite, or commit unrelated work. Keep each implementation slice scoped and independently testable.
3. **Both targets must build.** Run `swift build -q` for SwiftPM AND verify Xcode compiles if you touched any file under `ios/DoseTap/`. Do NOT wrap broken code in `#if false` without explicit user approval — diagnose and fix it instead.
4. **No `print()` in production code.** Use `os.Logger` with `OSLogPrivacy` annotations. `print()` leaks session/dose data in release builds.
5. **SSOT first, then code.** Update `docs/SSOT/README.md` BEFORE implementing any behavior change. If constants change, update `docs/SSOT/constants.json` too. Run `bash tools/ssot_check.sh` to verify.
6. **Read the constitution.** `.specify/memory/constitution.md` defines authoritative project principles. Consult it before making architectural decisions or adding new patterns.
7. **Test before you ship.** Run `swift test -q` and verify all tests pass before marking any task complete.
8. **Refactoring safety protocol.** For any rename/delete/move operation:
   - `rg "OldName" ios Tests docs` to find all references
   - Update every reference in the same commit
   - Run `swift build -q` to confirm
   - If touching UI files, also run `xcodebuild build -project ios/DoseTap.xcodeproj -scheme DoseTap -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
9. **Plane closeout is mandatory.** Read `.agents/plane-workflow.yml` and `AGENTS.md`. Before implementation, preflight the exact `DOSETAP-N` item with `ruby tools/plane_tracker.rb preflight --issue DOSETAP-N`. Before claiming completion, apply a structured closeout and run the helper's independent `verify` readback. Use `Done` only when acceptance is complete, validation is green, and no human, device, provider, privacy, legal, or release gate remains. If Plane cannot be verified, report the task as locally implemented but not fully closed.

SSOT update checklist (always first):
- Update `docs/SSOT/README.md` for any behavior change (states, thresholds, errors)
- If navigation or contracts change, also update `docs/SSOT/navigation.md` and `docs/SSOT/contracts/*`
- Link the exact tests you added/updated in your PR description
- Re-run docs check script if applicable (e.g., `tools/ssot_check.sh`)

## Big picture
- App: local-first iPhone app for a two-dose nighttime medication workflow. Core invariant: Dose 2 must be 150–240 minutes after Dose 1; default target 165m; Snooze adds 10m; Snooze is disabled when fewer than 15m remain. Watch and widget work is proposal-only.
- Architecture split:
  - Core logic (platform-free) in `ios/Core` as SwiftPM target `DoseCore` with unit tests in `Tests/DoseCoreTests`.
  - Active SwiftUI application code under `ios/DoseTap/`, with domain logic shared through `DoseCore` where platform independence is appropriate.
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
- Xcode app target MUST also build. If you touch any file under `ios/DoseTap/`, verify with: `xcodebuild build -project ios/DoseTap.xcodeproj -scheme DoseTap -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`

How to run the iOS app target safely:
- Open `ios/DoseTap.xcodeproj` in Xcode and select the `DoseTap` scheme
- If compile errors appear under `ios/DoseTap/`, diagnose and fix them. Do not hide failures with `#if false` without explicit user approval.
- The conflicting Core `TimeEngine` and old duplicate app files were retired; do not restore them without a reviewed architecture change.
- For UIKit/SwiftUI import issues when using SwiftPM-only contexts, guard imports: `#if canImport(SwiftUI) import SwiftUI #endif`
- Prefer validating behavior via `DoseCore` unit tests; only run the app after the build is green

## Key components and patterns
- Dose window model: `ios/Core/DoseWindowState.swift`
  - Config: `DoseWindowConfig(min=150, max=240, nearWindowThresholdMin=15, defaultTargetMin=165, snoozeStepMin=10, maxSnoozes)`
  - Output: `DoseWindowContext` with `phase`, `primary` CTA, `snooze/skip` states, remaining time, errors.
- Networking: `ios/Core/APIClient.swift` with uniform error mapping in `ios/Core/APIErrors.swift`.
  - Medication mutation endpoints are forbidden. Only `/events/log` and `/analytics/export` remain, with no shipping runtime call site.
  - Errors mapped to `DoseAPIError`: `422_WINDOW_EXCEEDED`, `422_SNOOZE_LIMIT`, `422_DOSE1_REQUIRED`, `409_ALREADY_TAKEN`, `429_RATE_LIMIT`, `401_DEVICE_NOT_REGISTERED`.
- Resilience utility: `ios/Core/OfflineQueue.swift` (actor) with `enqueue` + `flush`; it is not a medication state owner.
- Event debounce: `ios/Core/EventRateLimiter.swift` with default cooldowns `{ "bathroom": 60 }`.

## Conventions (project-specific)
- Keep `DoseCore` platform-free: no `import SwiftUI/UIKit`. Use `#if canImport(...)` only in app/UI files.
- Prefer actors for mutable state (`OfflineQueue`, `EventRateLimiter`).
- Inject time (`now: () -> Date`) for anything time-based; test DST edges explicitly.
- Use discrete actions/strings that match SSOT (e.g., events: `bathroom|lights_out|wake_final`).
- When adding endpoints, route through `APIClient` + map errors via `APIErrorMapper`.

## Typical slice workflow
1. Write a failing unit test in `Tests/DoseCoreTests/*` (add cases like `DoseWindowEdgeTests`, `APIErrorsTests`).
2. Implement logic in `ios/Core/*` (new file if needed). Keep public surface small and value-type heavy.
3. If networking, update the approved API contract and privacy boundary; medication endpoints require a new architecture decision.
4. Add/extend docs in `docs/SSOT/*` reflecting exact UX states, thresholds, and error copy.
5. Run `swift test -q` until green.

## Integration boundaries
- UI (SwiftUI) should consume `DoseWindowContext` and route medication actions through `DoseActionCoordinator`. Avoid duplicating window logic in views.
- Rate limits: let `EventRateLimiter` enforce the `SleepEventType` cooldown contract before any approved integration call.
- Offline queues must never replay medication mutations outside the coordinator and durable local transaction.

## Pitfalls and gotchas
- Do not restore retired duplicate app files or the retired Core `TimeEngine` without a reviewed architecture change.
- Snooze must be disabled when remaining window < 15m and after `maxSnoozes` reached; tests exist—match them.
- Use UTC ISO8601 for API bodies; server errors are decoded via `APIErrorPayload{ code, message }`.

## Pointers
- Core files: `ios/Core/{DoseWindowState, APIClient, APIErrors, OfflineQueue, EventRateLimiter}.swift`
- Tests: `Tests/DoseCoreTests/{DoseWindowStateTests, DoseWindowEdgeTests, APIErrorsTests, APIClientTests, OfflineQueueTests, EventRateLimiterTests}.swift`
- Specs: `docs/SSOT/README.md`, `docs/SSOT/navigation.md`, `docs/SSOT/contracts/api.openapi.yaml`

If anything here is unclear or you discover a mismatch with the SSOT or tests, pause and update the SSOT first, then code.

## Spec-Driven Development (Spec Kit)

For larger features or architectural changes, use the Spec Kit workflow:

```
/speckit.constitution  → Review project principles (one-time setup)
/speckit.specify       → Write detailed specification for the feature
/speckit.clarify       → Ask clarifying questions (optional)
/speckit.plan          → Create implementation plan
/speckit.tasks         → Break into actionable tasks
/speckit.implement     → Execute implementation
/speckit.checklist     → Verify completion
```

Spec artifacts are stored in `.specify/` and should be committed with the feature.

## Examples (repo-specific patterns)

1) Verify an existing approved APIClient endpoint

Swift (in `ios/Core/APIClient.swift`):

```swift
let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
let response = try await client.logEvent("bathroom", at: timestamp)
XCTAssertEqual(response.event, "bathroom")
```

Test (in `Tests/DoseCoreTests/APIClientTests.swift`):

```swift
func testLogEventUsesApprovedPath() async throws {
  var captured: URLRequest?
  let transport = StubTransport { req in
    captured = req
    let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    return (#"{"event_id":"event-1","event":"bathroom","at":"2023-11-14T22:13:20Z"}"#.data(using: .utf8)!, resp)
  }
  let client = APIClient(baseURL: URL(string: "https://example.com")!, transport: transport)
  _ = try await client.logEvent("bathroom", at: Date(timeIntervalSince1970: 1_700_000_000))
  XCTAssertEqual(captured?.httpMethod, "POST")
  XCTAssertEqual(captured?.url?.path, "/events/log")
}
```

2) Time-injected test for window math

Swift (in `Tests/DoseCoreTests/DoseWindowEdgeTests.swift`):

```swift
func test_exact_150_enters_active() {
  let d1 = Date(timeIntervalSince1970: 0)
  let calc = DoseWindowCalculator(now: { Date(timeIntervalSince1970: 150*60) })
  let ctx = calc.context(dose1At: d1, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
  XCTAssertEqual(ctx.phase, .active)
}
```
