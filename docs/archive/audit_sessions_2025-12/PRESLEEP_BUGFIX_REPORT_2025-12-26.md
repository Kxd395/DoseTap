# Pre-Sleep Bugfix Report – 2025-12-26

## Findings
- Root cause A: Pre-sleep logs were saved with `sessionId = nil` via `EventStorage.savePreSleepLog(_:)`, so Tonight had no session-scoped data to display until Dose 1 linked the latest log. (`ios/DoseTap/ContentView.swift:392-416`, `ios/DoseTap/Storage/EventStorage.swift:1008-1090`)
- Root cause B: Save errors were only printed and not surfaced to the UI, so failed inserts would dismiss silently. (`ios/DoseTap/Storage/EventStorage.swift:992-1090`, `ios/DoseTap/Views/PreSleepLogView.swift:98-156`)
- Root cause C: Tonight had no UI state for pre-sleep completion, so even successful saves looked like no-op. (`ios/DoseTap/ContentView.swift:312-416`)

## Fix Summary
- Pre-sleep saves now go through `SessionRepository.savePreSleepLog(...)`, which assigns a session key based on the pre-sleep rule and broadcasts `sessionDidChange` on success. (`ios/DoseTap/Storage/SessionRepository.swift:327-359`, `ios/Core/SessionKey.swift:29-43`)
- SQLite inserts now throw on failure; PreSleepLogView handles errors and prevents dismiss. (`ios/DoseTap/Storage/EventStorage.swift:992-1090`, `ios/DoseTap/Views/PreSleepLogView.swift:98-156`)
- Tonight now renders a session-scoped confirmation card (“Pre-sleep logged/skipped at <time>”). (`ios/DoseTap/ContentView.swift:312-416`, `ios/DoseTap/ContentView.swift:653-700`)

## Evidence Table (Claim → File/Lines → Proof)
- Pre-sleep save uses a session key (not nil) and broadcasts change → `ios/DoseTap/Storage/SessionRepository.swift:327-359` → xcodebuild output: `SessionRepositoryTests.test_addPreSleepLog_persistsRowAndIsQueryableBySessionKey()` and `test_preSleepSubmit_broadcastsChangeSignal()` passed.
- Pre-sleep persistence is queryable by sessionId → `ios/DoseTap/Storage/EventStorage.swift:931-989` and `ios/DoseTapTests/SessionRepositoryTests.swift:382-409` → xcodebuild output: `SessionRepositoryTests.test_addPreSleepLog_persistsRowAndIsQueryableBySessionKey()` passed.
- Pre-sleep UI confirmation appears on Tonight → `ios/DoseTap/ContentView.swift:312-416`, `ios/DoseTap/ContentView.swift:653-700` → NOT VERIFIED (requires running UI build).
- Error handling blocks silent dismiss on save failure → `ios/DoseTap/Views/PreSleepLogView.swift:98-156`, `ios/DoseTap/Storage/EventStorage.swift:992-1090` → swift test + xcodebuild completed with new tests passing.

## Test Evidence (command excerpts)
- `swift test --verbose` (2025-12-26T03:40:18Z): `Test Suite 'All tests' passed ... Executed 268 tests, with 0 failures`.
- `xcodebuild test ... OS=17.2` (2025-12-26T03:44:47Z):
  - `SessionRepositoryTests.test_addPreSleepLog_persistsRowAndIsQueryableBySessionKey()` passed
  - `SessionRepositoryTests.test_preSleepSubmit_broadcastsChangeSignal()` passed
  - `SessionRepositoryTests.test_preSleepSessionKey_matchesTonightKey_aroundRollover()` passed

## NOT VERIFIED
- Export-based verification (`pre_sleep_logs.csv`) was not run because the app export flow was not executed in this environment.
- End-to-end UI reproduction (submit pre-sleep and view Tonight banner) was not executed; the code path is present and covered via unit tests.
