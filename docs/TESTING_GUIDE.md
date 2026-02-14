# DoseTap Testing Guide

Last updated: 2026-02-13

## Test Inventory

| Suite | Location | Count | Runner |
|-------|----------|-------|--------|
| **DoseCoreTests** (SwiftPM) | `Tests/DoseCoreTests/` (29 files) | 497 tests | `swift test` |
| **DoseTapTests** (Xcode) | `ios/DoseTapTests/` (11 files) | ~134 tests | Xcode / `xcodebuild test` |
| **DoseTapUITests** (XCUITest) | `ios/DoseTapUITests/` (2 files) | 12 tests | Xcode / `xcodebuild test` |
| **Total** | | **643+** | |

## Build and Test

```bash
# From repo root — core library + unit tests
swift build -q
swift test -q

# To avoid SIGTSTP in some terminals:
script -q /tmp/test.txt swift test -q 2>&1

# Xcode app build (verify no compile errors)
xcodebuild build -project ios/DoseTap.xcodeproj -scheme DoseTap \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5

# Xcode unit tests
xcodebuild test -project ios/DoseTap.xcodeproj -scheme DoseTap \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20

# XCUITests
xcodebuild test -project ios/DoseTap.xcodeproj -scheme DoseTapUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

## SwiftPM Test Files (DoseCoreTests — 29 files)

Core domain tests (time-injected, deterministic):

- `DoseWindowStateTests.swift` — window phase transitions
- `DoseWindowEdgeTests.swift` — boundary/edge cases (exact 150m, 240m, DST)
- `DoseWindowConfigTests.swift` — config validation
- `DosingModelsTests.swift` — dosing model encoding/decoding
- `DoseTapCoreTests.swift` — core orchestration
- `TimeEngineTests.swift` — time calculations
- `SessionKeyTests.swift` — session key derivation
- `TimeIntervalMathTests.swift` — interval math helpers
- `DiagnosticLoggerTests.swift` — log output format
- `DiagnosticSessionRolloverTests.swift` — rollover diagnostics

Networking & resilience tests:

- `APIClientTests.swift` — request construction, transport
- `APIErrorsTests.swift` — error mapping from status codes
- `OfflineQueueTests.swift` — enqueue, flush, retry
- `EventRateLimiterTests.swift` — cooldown enforcement
- `APIClientQueueIntegrationTests.swift` — DosingService façade

Additional coverage:

- `InputValidatorTests.swift` — input validation rules
- `DoseScheduleTests.swift` — schedule logic
- `UserSettingsManagerTests.swift` — settings persistence
- `HealthKitServiceTests.swift` — HK authorization states
- `EventStorageTests.swift` — storage CRUD
- Plus 9 more specialized test files

## XCUITest Coverage (DoseTapUITests — 12 tests)

Smoke tests for critical user paths:

- App launch and tab bar presence
- Tonight tab default state
- Dose 1 button tap flow
- Quick log button grid display
- Settings navigation
- History tab presence
- Tab switching (Tonight ↔ History ↔ Settings)
- Launch performance benchmark
- Screenshot capture for App Store

## CI Pipeline

Three workflows guard the `main` branch:

1. **ci.yml**: SSOT lint → SwiftPM tests (US/Eastern, UTC, Asia/Tokyo) → Xcode sim tests → release pinning
2. **ci-swift.yml**: Storage enforcement guards (no direct EventStorage access from views)
3. **ci-docs.yml**: Documentation validation

Branch protection requires PR + all 3 status checks to merge.

## Manual Regression Checklist

1. Dose 1 → window → Dose 2 → complete.
2. Dose 2 late (after window close) logs as Dose 2 with `is_late` metadata, not extra.
3. Extra dose only at dose index 3+.
4. Dose 1 before midnight, Dose 2 after midnight, session remains open until morning check-in.
5. Morning check-in closes session and Tonight view resets.
6. Missed check-in cutoff auto-closes session and allows a clean next night.
7. Nap Start → Nap End paired in History; missing end shows "Nap in progress".
8. HealthKit: toggle ON, authorize, force quit, reopen; preference persists and authorization is rechecked.

## Diagnostics

- Logs are written to `Documents/diagnostics/sessions/<session-id>/`.
- See `docs/DIAGNOSTIC_LOGGING.md` for event formats and `docs/HOW_TO_READ_A_SESSION_TRACE.md` for triage.

## State Machines

- Dose flow and session rollover diagrams live in `docs/SSOT/README.md`.

