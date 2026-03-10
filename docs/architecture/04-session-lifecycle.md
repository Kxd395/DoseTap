# 04 — Session Lifecycle

## Session Concept

A "session" = one night of sleep, from Dose 1 through morning check-in.

Sessions are keyed by **evening-anchor date** (not calendar date):

- Before rollover hour (18:00): session belongs to **previous day**
- After rollover hour (18:00): session belongs to **today**

```text
Timeline:
  6 PM Feb 14 ──────── midnight ──────── 6 PM Feb 15
  │                                      │
  │◄──── Session "2026-02-14" ──────────►│
  │ D1 at 10:30 PM ── D2 at 1:15 AM     │
  │ Wake at 6:30 AM ── Check-in 6:32 AM │
```

## Session States

```text
 ┌─────────┐   takeDose1()   ┌──────────┐
 │  empty  │ ───────────────►│  active  │
 └─────────┘                 └────┬─────┘
                                  │
                    ┌─────────────┼─────────────┐
                    │             │             │
              takeDose2()   skipDose2()   auto-expire
                    │             │        (270m)
                    ▼             ▼             ▼
               ┌──────────┐ ┌─────────┐ ┌──────────┐
               │completed │ │ skipped │ │ expired  │
               │(d2 taken)│ │         │ │(sleep-   │
               └────┬─────┘ └────┬────┘ │ through) │
                    │            │      └──────────┘
                    ▼            ▼
               ┌───────────────────┐
               │   wake_final      │  User pressed Wake Up
               │  (finalizing)     │
               └────────┬──────────┘
                        │
                        ▼
               ┌───────────────────┐
               │  check-in done   │  Morning survey completed
               │  (terminal)      │
               └───────────────────┘
```

## SessionRepository (SSOT)

File: `ios/DoseTap/Storage/SessionRepository.swift` (1713 lines)

The **single source of truth** for all session state. UI binds to this, not DoseTapCore directly.

### Published State

```swift
@Published activeSessionDate: String?      // "2026-02-14"
@Published activeSessionId: String?        // UUID
@Published activeSessionStart: Date?       // Session start time
@Published activeSessionEnd: Date?         // Session end time
@Published dose1Time: Date?                // When D1 was taken
@Published dose2Time: Date?                // When D2 was taken
@Published snoozeCount: Int                // Current snooze count
@Published dose2Skipped: Bool              // Whether D2 was skipped
@Published wakeFinalTime: Date?            // When user pressed Wake Up
@Published checkInCompleted: Bool          // Morning check-in done
@Published dose1TimezoneOffsetMinutes: Int? // TZ when D1 taken
@Published awaitingRolloverMessage: String? // Rollover banner text
@Published currentSessionKey: String       // Current session date key
```

### Key Methods

| Method | Purpose |
| ------ | ------- |
| `reload()` | Load session state from SQLite |
| `setDose1Time(_:)` | Record Dose 1 |
| `setDose2Time(_:isEarly:isExtraDose:)` | Record Dose 2 |
| `skipDose2(reason:)` | Mark Dose 2 skipped |
| `incrementSnoozeCount()` | Bump snooze counter |
| `decrementSnoozeCount()` | Undo snooze |
| `clearDose1()` | Undo Dose 1 |
| `clearDose2()` | Undo Dose 2 |
| `clearSkip()` | Undo skip |
| `deleteSession(sessionDate:)` | Wipe a session |
| `fetchRecentSessions(days:)` | History data |
| `fetchTonightSleepEvents()` | Tonight's events |
| `savePreSleepLog(answers:...)` | Pre-sleep survey |
| `saveMorningCheckIn(answers:...)` | Morning survey |
| `currentSessionIdString()` | Get session UUID |
| `currentSessionDateString()` | Get session date key |

### Rollover Logic

```text
Every second (timer) + on scenePhase change:
  │
  ▼
checkRollover()
  ├── currentKey = sessionKey(for: now, rolloverHour: 18)
  ├── if currentKey != storedKey:
  │     ├── Save current session to sleep_sessions
  │     ├── Reset all @Published state
  │     ├── Cancel session-scoped notifications
  │     ├── Start fresh session
  │     └── Emit sessionDidChange
  └── else: no-op
```

### Session Key Computation

```swift
func sessionKey(for date: Date, timeZone: TimeZone, rolloverHour: Int) -> String
// Before rolloverHour → previous day's date string
// After rolloverHour → today's date string
// Format: "YYYY-MM-DD"
```

### Incomplete Session Detection

```text
On app launch:
  ├── Check previous session: has dose1 but no wake_final?
  ├── If yes: show IncompleteSessionBanner on Tonight tab
  └── User can: Complete check-in or Dismiss
```

### Notification Cleanup on Rollover

Cancels these notification IDs on session end:

```text
dosetap_dose2_alarm
dosetap_dose2_pre_alarm
dosetap_followup_1, _2, _3
dosetap_second_dose
dosetap_window_15min
dosetap_window_5min
```

## Dependencies

```text
SessionRepository
  ├── EventStorage (SQLite reads/writes)
  ├── NotificationScheduling (cancel on rollover)
  ├── clock: () -> Date (injectable for tests)
  ├── timeZoneProvider: () -> TimeZone
  └── rolloverHour: Int (default 18)
```

## Testing

- `Tests/DoseCoreTests/SessionRolloverRegressionTests.swift`
- `Tests/DoseCoreTests/SessionIdBackfillTests.swift`
- All SessionRepository tests use in-memory EventStorage + FixedDateProvider
