# DoseTap Rollover Fix Report – 2025-12-25

## Scope
- Centralized session key computation and rollover timing.
- Fixed timezone change detection used by Wake Up & End Session flows.
- Added Sleep Plan (Typical Week) planner surface to Tonight and Settings.

## Modified Logic (file:path#line)
- Session key canonicalization: `ios/Core/SessionKey.swift:10-46`
- Repository rollover + timezone detection: `ios/DoseTap/Storage/SessionRepository.swift:263-402`
- Tonight UI (awaiting rollover banner + planner cards): `ios/DoseTap/ContentView.swift:270-505`
- Sleep planner storage (UserDefaults + per-session override): `ios/DoseTap/UserSettingsManager.swift:315-412`
- Planner math (wake-by/in-bed/wind-down): `ios/Core/SleepPlan.swift:54-89`
- Settings UI for Typical Week + Sleep Plan knobs: `ios/DoseTap/SettingsView.swift:34-80`
- Tests for planner math and session key rollover: `Tests/DoseCoreTests/SleepPlanCalculatorTests.swift:6-73`, `ios/DoseTapTests/SessionRepositoryTests.swift:289-343`

## Before vs After
- Before: SessionRepository cached `TimeZone.current` and never recalculated offsets when `NSTimeZone.default` changed, causing `SessionRepositoryTests.test_timezoneChange_detectedAfterDose1` to fail and Tonight to remain on the prior session after Wake Up until app restart.
- After: `sessionKey(for:timeZone:rolloverHour:)` is the single source of session identity; SessionRepository recomputes `currentSessionKey` on timers/app/timezone changes and records dose1 offsets via the injected time zone provider. Timezone deltas now consider both the autoupdating zone and `NSTimeZone.default`, unblocking rollover and timezone-shift detection. Tonight renders an “Ended, waiting for rollover” banner before 6 PM and clears state after rollover without restart.

## Evidence (command output)
- `swift test --verbose` (2025-12-26T03:18:07Z)  
  `Test Suite 'SleepPlanCalculatorTests' passed... Executed 3 tests, with 0 failures` (verifies planner math for next-morning wake-by and latency).
- `TZ=UTC swift test --verbose` (2025-12-26T03:18:24Z)  
  Same suite count (268) passes under UTC, showing deterministic session key math.
- `TZ=America/New_York swift test --verbose` (2025-12-26T03:18:42Z)  
  Same suite count (268) passes under New York, no timezone-only passes.
- `xcodebuild test -project ios/DoseTap.xcodeproj -scheme DoseTap -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.2' CODE_SIGNING_ALLOWED=NO` (2025-12-26T03:21:34Z)  
  `Test case 'SessionRepositoryTests.test_timezoneChange_detectedAfterDose1()' passed...` and `Test case 'SessionRepositoryTests.test_tonight_empty_after_rollover()' passed...` (shows rollover + timezone change now detectable in UI-facing repository).

## Tests Added/Updated
- `Tests/DoseCoreTests/SleepPlanCalculatorTests.swift:6-73` – deterministic planner math for wake-by (next-morning), latency-adjusted in-bed time, and decreasing “if in bed now” sleep minutes.
- `ios/DoseTapTests/SessionRepositoryTests.swift:289-343` – verifies rollover rebroadcast with injectable clock and Tonight empties after crossing 6 PM boundary.

## Outstanding Risks
- Rollover hour remains hard-coded at 18; changing this requires regenerating planner copy and timers. No UI yet for custom rollover.
- Tonight banner/timezone handling depends on main-actor timers; background termination could still delay refresh until next launch (NOT VERIFIED).
