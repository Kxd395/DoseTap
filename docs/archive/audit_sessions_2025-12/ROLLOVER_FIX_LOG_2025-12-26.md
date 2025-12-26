# Rollover Bug Fix Log — 2025-12-26

This log records the investigation and fix for the session rollover bug where the Tonight tab remained stuck showing "Complete" from the prior session after 6 PM.

---

## Investigation Timeline

### 08:15 — Initial Bug Report

User report: "At 8:47 PM the Tonight tab is still stuck as Complete (both doses taken) from the prior session. The app only fixes itself after restart."

Core hypothesis: Inconsistent session date rules — one component uses midnight, another uses 6 PM boundary.

### 08:20 — Searched for Session Key Logic

Command:
```bash
grep -rn "sessionKey\|session_id\|sessionDate" --include="*.swift" ios/
```

Found `sessionKey()` in:
- `ios/Core/SessionKey.swift` (canonical)
- `ios/DoseTap/Storage/SessionRepository.swift`
- `ios/DoseTapiOSApp/SQLiteStorage.swift`
- `ios/DoseTapiOSApp/DataStorageService.swift`

### 08:25 — Verified Canonical Session Key

Read `ios/Core/SessionKey.swift` (lines 1-20):
```swift
public func sessionKey(for date: Date, timeZone: TimeZone, rolloverHour: Int = 18) -> String {
    var cal = Calendar.current
    cal.timeZone = timeZone
    let hour = cal.component(.hour, from: date)
    let effectiveDate = hour < rolloverHour ? cal.date(byAdding: .day, value: -1, to: date)! : date
    return cal.startOfDay(for: effectiveDate).formatted(.iso8601.year().month().day())
}
```

Verified: 6 PM rollover is correct in canonical source.

### 08:30 — Examined SessionRepository Rollover

Read `ios/DoseTap/Storage/SessionRepository.swift` (lines 156-193):

SessionRepository already has proper rollover infrastructure:
- `rolloverTimer: Timer?` — Schedules at exact 6 PM
- `setupTimezoneObserver()` — Re-schedules on TZ change
- `handleRollover()` — Publishes new session, resets state

This component is NOT the bug.

### 08:35 — Found Bug #1: SQLiteStorage.fetchTonightSleepEvents()

Read `ios/DoseTapiOSApp/SQLiteStorage.swift` (lines 843-860):

```swift
func fetchTonightSleepEvents() -> [SleepEvent] {
    let now = Date()
    let twelveHoursAgo = Calendar.current.date(byAdding: .hour, value: -12, to: now) ?? now
    let query = sleepEventsTable
        .filter(sleepEventTimestamp >= twelveHoursAgo)
        .order(sleepEventTimestamp.asc)
    // ...
}
```

**BUG IDENTIFIED:** Uses 12-hour sliding window instead of session key!

At 8:47 PM, this window extends back to 8:47 AM — capturing the entire previous session's events.

### 08:40 — Found Bug #2: Events Inserted with nil Session ID

Searched for insert calls:
```bash
grep -n "insertSleepEvent\|sessionId:" ios/DoseTapiOSApp/*.swift
```

Found in `QuickLogPanel.swift` (line 203):
```swift
sessionId: nil  // Always nil!
```

Found in `DoseCoreIntegration.swift` (line 251):
```swift
sessionId: nil  // Always nil!
```

### 08:45 — Applied Fix #1: SQLiteStorage

Changed `fetchTonightSleepEvents()` to use session key:

**Before:**
```swift
let twelveHoursAgo = Calendar.current.date(byAdding: .hour, value: -12, to: now) ?? now
```

**After:**
```swift
let currentSession = currentSessionDate()
return fetchSleepEvents(sessionId: currentSession)
```

### 08:50 — Applied Fix #2: QuickLogPanel

Added session key computation in `addSleepEvent()`:

```swift
let sessionId = sessionKey(for: timestamp, timeZone: TimeZone.current, rolloverHour: 18)
let event = SleepEvent(
    // ...
    sessionId: sessionId
)
```

### 08:55 — Applied Fix #3: DoseCoreIntegration

Added session key computation in `logSleepEvent()`:

```swift
let timestamp = Date()
let sessionId = sessionKey(for: timestamp, timeZone: TimeZone.current, rolloverHour: 18)
storage.insertSleepEvent(
    // ...
    sessionId: sessionId
)
```

### 09:00 — Added Typical Week Schedule UI

Added to `ios/DoseTapiOSApp/SettingsView.swift`:
- `typicalWeekSection` NavigationLink in settings list
- `TypicalWeekScheduleView` struct (~80 lines)
- Uses existing `TypicalWeekSchedule` model from DoseCore

---

## Verification Commands

### Swift Build

```bash
$ swift build -q
# Exit code: 0
```

### Swift Tests (Default TZ)

```bash
$ swift test 2>&1 | tail -5
Executed 268 tests, with 0 failures (0 unexpected) in 2.534 (2.556) seconds
```

### Swift Tests (UTC)

```bash
$ TZ=UTC swift test 2>&1 | tail -5
Executed 268 tests, with 0 failures (0 unexpected) in 2.537 (2.559) seconds
```

### Swift Tests (America/New_York)

```bash
$ TZ=America/New_York swift test 2>&1 | tail -5
Executed 268 tests, with 0 failures (0 unexpected) in 2.539 (2.562) seconds
```

### SSOT Check

```bash
$ bash tools/ssot_check.sh
=== DoseTap SSOT Integrity Check ===
...
✅ SSOT integrity check PASSED! All components, endpoints, and sections verified.
Exit code: 0
```

### Doc Lint

```bash
$ bash tools/doc_lint.sh
=== DoseTap Doc Lint ===
Check 1: No stale hardcoded test counts... ✅ PASS
Check 2: No stale '12 event' or '12 types' references... ✅ PASS
Check 3: Schema version consistency... ✅ PASS: Both at version 6
Check 5: No Core Data as implementation in architecture.md... ✅ PASS
Check 6: constants.json has 13 sleep event types... ✅ PASS
Check 7: DATABASE_SCHEMA sleep_events taxonomy has 13 types... ✅ PASS
Check 8: pre_sleep_logs uses structured columns... ✅ PASS
Check 9: morning_checkins uses session_date UNIQUE... ✅ PASS
=== Summary ===
✅ All checks passed
Exit code: 0
```

---

## Git Status

```bash
$ git rev-parse HEAD
68e74bdccb0bdd09cbae199d2339fb5460aab8a5

$ git status
On branch fix/p0-blocking-issues
Changes not staged for commit:
  modified:   ios/DoseTapiOSApp/DoseCoreIntegration.swift
  modified:   ios/DoseTapiOSApp/QuickLogPanel.swift
  modified:   ios/DoseTapiOSApp/SQLiteStorage.swift
  modified:   ios/DoseTapiOSApp/SettingsView.swift
  modified:   ios/DoseTapiOSApp/TonightView.swift
  ... (other files from prior work)

$ git diff --stat
48 files changed, 3170 insertions(+), 3500 deletions(-)
```

---

## Summary

| Step | Status |
| ---- | ------ |
| Identify root cause | ✅ 12-hour window in SQLiteStorage |
| Fix SQLiteStorage query | ✅ Now uses session key |
| Fix QuickLogPanel insert | ✅ Sets session_id |
| Fix DoseCoreIntegration insert | ✅ Sets session_id |
| Add Typical Week Schedule UI | ✅ In SettingsView |
| Verify build | ✅ Success |
| Verify tests | ✅ 268 pass (all TZ) |
| Verify SSOT | ✅ Passed |
| Verify doc lint | ✅ Passed |

---

*Log completed: 2025-12-26 09:10*
*Branch: fix/p0-blocking-issues*
