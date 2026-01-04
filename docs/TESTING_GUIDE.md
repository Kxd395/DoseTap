# DoseTap Testing Guide

## Overview
This guide walks you through thoroughly testing DoseTap's core functionality and reviewing diagnostic logs to ensure everything works correctly.

## Pre-Testing Setup

### 1. Build Verification

```bash
# From repo root
swift build -q
swift test -q
```

✅ **Expected:** Build succeeds, all 277 tests pass

### 2. Xcode Build (Optional - for running on device/simulator)

```bash
cd ios/DoseTap
open DoseTap.xcodeproj
```

- Select the iOS scheme and device/simulator
- Build the project (⌘B)
- If legacy file conflicts occur, they're already quarantined with `#if false`

### 3. Enable Diagnostic Logging

The app has **session-scoped diagnostic logging** that records state transitions and invariants (see `docs/DIAGNOSTIC_LOGGING.md`):

- **Tier 1:** Safety-critical diagnostic events (lifecycle, timezone, notifications, undo) - always on
- **Tier 2:** Session context events (sleep events, pre-sleep, check-in) - enabled by default
- **Tier 3:** Forensic deep inspection (optional snapshots, state deltas) - explicitly opt-in

> ⚠️ **Important**: Diagnostic logs record **state facts**, not UI actions. You will not see logs like "button tapped"—instead you'll see the **effects** like `dose.1.taken` or `dose.snooze.activated`.

**To enable full logging:**

- Go to Settings > Diagnostic Logging
- Toggle "Enable Diagnostic Logging" ON
- Toggle "Enable Tier 2 Logging" ON (if available)
- Toggle "Enable Tier 3 Forensic Logging" ON (if you want maximum detail)

---

## Core Testing Scenarios

### Scenario 1: Fresh Session (No Doses)

**Goal:** Verify the app starts in the correct state and shows proper prompts.

**Steps:**

1. Launch app (fresh install or reset data)
2. Verify UI shows:
   - Phase: `noDose1` or "No Dose 1"
   - Primary CTA: "Take Dose 1"
   - No window timer visible
3. Check logs for session initialization

**Expected Events:**

```jsonl
{"event":"session.started","session_id":"2026-01-04","phase":"noDose1"}
{"event":"dose.1.taken","session_id":"2026-01-04","dose1_time":"2026-01-04T22:00:00-05:00"}
{"event":"session.phase.entered","session_id":"2026-01-04","phase":"beforeWindow","previous_phase":"noDose1"}
```

---

### Scenario 2: Take Dose 1 → Before Window

**Goal:** Verify window calculations start correctly.

**Steps:**

1. Tap "Take Dose 1"
2. Note the timestamp (e.g., 10:00 PM)
3. Verify UI shows:
   - Phase: `beforeWindow`
   - Window opens at: Dose 1 + 150 min (12:30 AM)
   - Primary CTA: disabled or shows countdown
   - Skip: disabled ("Window hasn't opened yet")
   - Snooze: disabled

**Expected Events:**

```jsonl
{"event":"dose.1.taken","session_id":"2026-01-04","dose1_time":"2026-01-04T22:00:00-05:00"}
{"event":"session.phase.entered","phase":"beforeWindow","elapsed_minutes":0}
```

**Edge Case:** Fast-forward time (or use Xcode's time debug):

- At exactly +150 min, verify phase changes to `active`

```jsonl
{"event":"dose.window.opened","phase":"active","previous_phase":"beforeWindow","elapsed_minutes":150}
```

---

### Scenario 3: Active Window → Take Dose 2

**Goal:** Verify dose 2 can be taken within the window.

**Steps:**

1. Wait until window opens (150 min after Dose 1)
2. Verify UI shows:
   - Phase: `active`
   - Primary CTA: "Take Dose 2"
   - Target time: Dose 1 + 165 min (default)
   - Skip: enabled
   - Snooze: enabled (if >15 min remaining)
3. Tap "Take Dose 2"
4. Verify phase changes to `completed`

**Expected Events:**

```jsonl
{"event":"dose.window.opened","phase":"active","elapsed_minutes":150,"remaining_minutes":90}
{"event":"dose.2.taken","dose2_time":"2026-01-05T00:45:00-05:00"}
{"event":"session.completed","terminal_state":"completed"}
```

---

### Scenario 4: Snooze (+10 min)

**Goal:** Verify snooze increments target time correctly.

**Steps:**

1. Take Dose 1 at 10:00 PM
2. Wait until window opens (12:30 AM)
3. Verify target time shows 12:45 AM (default 165 min)
4. Tap "Snooze"
5. Verify target time updates to 12:55 AM (+10 min)
6. Snooze again → 1:05 AM
7. Verify snooze counter increments (shown in UI if configured)

**Expected Events:**

```jsonl
{"event":"dose.snooze.activated","snooze_count":1,"new_target_minutes":175}
{"event":"dose.snooze.activated","snooze_count":2,"new_target_minutes":185}
```

**Edge Cases:**

- Snooze disabled when `remaining < 15 min`
- Snooze disabled after `maxSnoozes` reached (default: 3)

**Expected Events for Edge Case:**

```jsonl
{"event":"dose.window.blocked","reason":"snooze_limit_reached","snooze_count":3}
```

---

### Scenario 5: Skip Dose 2

**Goal:** Verify skip works and logs correctly.

**Steps:**

1. Take Dose 1
2. Wait for window to open
3. Tap "Skip Dose 2"
4. Verify phase changes to `completed` (or `finalizing`)
5. Verify dose 2 is NOT recorded (check history/session data)

**Expected Events:**

```jsonl
{"event":"dose.2.skipped","session_id":"2026-01-04","reason":"user_skipped"}
{"event":"session.skipped","terminal_state":"skipped"}
```

---

### Scenario 6: Undo (5-second window)

**Goal:** Verify undo works within 5 seconds.

**Steps:**

1. Take Dose 1 at 10:00 PM
2. Immediately tap "Undo" (within 5 seconds)
3. Verify:
   - Dose 1 is removed
   - Phase returns to `noDose1`
   - Snackbar disappears
4. Verify no undo button after 5 seconds

**Expected Events:**

```jsonl
{"event":"dose.1.taken","dose1_time":"2026-01-04T22:00:00-05:00"}
{"event":"dose.undone","action":"takeDose1","elapsed_seconds":2.1}
{"event":"session.phase.entered","phase":"noDose1","previous_phase":"beforeWindow"}
```

**Edge Case:** Wait >5 seconds, then try to undo

```jsonl
{"event":"undo.expired","action":"takeDose1","elapsed_seconds":6.2}
```

---

### Scenario 7: Window Exceeded (Closed)

**Goal:** Verify behavior when dose 2 is taken after the 240-minute window.

**Steps:**

1. Take Dose 1 at 10:00 PM
2. Fast-forward past 2:00 AM (+240 min)
3. Verify UI shows:
   - Phase: `closed` or "Window Exceeded"
   - Warning message: "Outside recommended window"
   - Primary CTA: still allows taking dose (with warning)
4. Take Dose 2 anyway
5. Verify it logs with a warning flag

**Expected Events:**

```jsonl
{"event":"dose.window.expired","phase":"closed","elapsed_minutes":240}
{"event":"dose.window.override.required","reason":"window_exceeded"}
{"event":"dose.2.taken","dose2_time":"2026-01-05T02:05:00-05:00","window_exceeded":true}
{"event":"session.completed","terminal_state":"completed","late_dose":true}
```

---

### Scenario 8: Near-Window Threshold (15 min warning)

**Goal:** Verify UI shows urgency when <15 min remain.

**Steps:**

1. Take Dose 1 at 10:00 PM
2. Fast-forward to 1:45 AM (10 min before close)
3. Verify UI shows:
   - Phase: `nearClose` or visual warning
   - Snooze: disabled
   - "Less than 15 minutes remaining" message

**Expected Events:**

```jsonl
{"event":"dose.window.nearClose","phase":"nearClose","remaining_minutes":10}
{"event":"dose.window.blocked","reason":"near_close_threshold","remaining_minutes":10}
```

---

### Scenario 9: Sleep Events (Bathroom, Lights Out, Wake)

**Goal:** Verify event logging works.

**Steps:**

1. From dashboard, tap "Quick Log" (if available)
2. Log events:
   - "Bathroom" event
   - "Lights Out" event
   - "Wake Final" event
3. Verify events appear in timeline/history
4. Check rate limiting: tap "Bathroom" twice within 60 seconds

**Expected Events:**

```jsonl
{"event":"sleep.event.logged","event_type":"bathroom","timestamp":"2026-01-05T01:30:00-05:00"}
{"event":"sleep.event.logged","event_type":"lights_out","timestamp":"2026-01-04T22:15:00-05:00"}
{"event":"sleep.event.logged","event_type":"wake_final","timestamp":"2026-01-05T07:00:00-05:00"}
```

> ⚠️ **Note**: Rate limiting is handled at the service layer and may not generate diagnostic events. The **absence** of a second bathroom event in the timeline is the test—logs record effects, not blocked actions unless they violate an invariant.

---

### Scenario 10: Offline Queue (Network Resilience)

**Goal:** Verify offline actions are queued and retried.

> ⚠️ **Important**: Offline queue behavior is validated via **app behavior and unit tests**, not diagnostic logs. Diagnostic logging records session state facts, not infrastructure behavior. Queue mechanics are tested in `OfflineQueueTests.swift`.

**Steps:**

1. Turn on Airplane Mode
2. Take Dose 1
3. Verify action completes in UI (queued locally)
4. Turn off Airplane Mode
5. Verify dose syncs automatically (check history/server)

**What to verify:**

- UI responds immediately (optimistic update)
- Dose appears in local session storage
- After network restore, server reflects the dose
- No user-visible errors

**Diagnostic events (if any):**

Offline queue operations are **not** part of the diagnostic event contract unless a sync failure violates a session invariant (e.g., server rejects a dose as duplicate).

---

## Reviewing Diagnostic Logs

### Method 1: In-App Export

1. Go to Settings > Diagnostic Logging
2. Tap "Export Logs"
3. Choose destination (Files, AirDrop, email)
4. Open exported folder

**Folder Structure:**

```
2026-01-04/
├── meta.json      ← Device, app version, timezone at session start
├── events.jsonl   ← Full event stream (authoritative)
└── errors.jsonl   ← Errors only (incomplete, use events.jsonl for investigation)
```

**⚠️ Warning**: `errors.jsonl` is a convenience view. **Always use `events.jsonl` for real investigation.**

**Example `events.jsonl` entry:**

```jsonl
{"ts":"2026-01-04T22:00:00-05:00","seq":1,"level":"info","event":"dose.1.taken","session_id":"2026-01-04","dose1_time":"2026-01-04T22:00:00-05:00","app_version":"2.15.0"}
{"ts":"2026-01-05T00:30:00-05:00","seq":2,"level":"info","event":"dose.window.opened","session_id":"2026-01-04","phase":"active","previous_phase":"beforeWindow","elapsed_minutes":150}
```

### Method 2: Xcode Console
1. Run app from Xcode
2. Open Console (View > Debug Area > Show Debug Area)
3. Filter by `[DiagnosticLogger]` or `[DoseTap]`
4. Logs appear in real-time

### Method 3: macOS Console App
1. Open Console.app (Applications > Utilities)
2. Select your device (if physical) or simulator
3. Filter by process: `DoseTap`
4. Search for specific events: `Dose 1 Taken`, `Window Transition`, etc.

---

## Interpreting Logs

> ⚠️ **Critical Boundary**: If you are expecting to see a log line and don't, check whether the system logs **effects**, not **inputs**. Diagnostic logs record state facts (e.g., `dose.1.taken`), not UI actions (e.g., "button tapped").

### Key Event Types

| Event Pattern | Description | Example |
|---------------|-------------|---------|
| `session.*` | Session lifecycle | `session.started`, `session.completed` |
| `dose.*` | Dose actions and window boundaries | `dose.1.taken`, `dose.window.opened` |
| `alarm.*` | Notification/alarm events | `alarm.scheduled`, `alarm.suppressed` |
| `checkin.*` | Morning check-in flow | `checkin.started`, `checkin.completed` |
| `app.*` | App lifecycle (foreground/background) | `app.foregrounded` |
| `*.error` | Error conditions | `sync.error`, `storage.error` |

### Common Patterns to Look For

#### ✅ Healthy Session

```jsonl
{"event":"session.started","session_id":"2026-01-04"}
{"event":"dose.1.taken","dose1_time":"2026-01-04T22:00:00-05:00"}
{"event":"dose.window.opened","phase":"active","elapsed_minutes":150}
{"event":"dose.2.taken","dose2_time":"2026-01-05T00:45:00-05:00"}
{"event":"session.completed","terminal_state":"completed"}
{"event":"checkin.completed"}
```

#### ⚠️ Warning Signs

**Late dose:**

```jsonl
{"event":"dose.window.expired","phase":"closed","elapsed_minutes":240}
{"event":"dose.window.override.required","reason":"window_exceeded"}
{"event":"dose.2.taken","window_exceeded":true}
```

→ User took dose late; expected if confirmed via UI.

**Snooze limit reached:**

```jsonl
{"event":"dose.window.blocked","reason":"snooze_limit_reached","snooze_count":3}
```

→ User hit snooze limit; expected behavior per SSOT.

**Session expired:**

```jsonl
{"event":"session.autoExpired","terminal_state":"expired","elapsed_minutes":360}
```

→ User slept through window + grace period; requires check-in.

---

## Testing Checklist

### Core Dose Flow
- [ ] Take Dose 1 → verify phase = `beforeWindow`
- [ ] Wait 150 min → verify phase = `active`
- [ ] Take Dose 2 → verify phase = `completed`
- [ ] Undo Dose 1 (within 5s) → verify phase returns to `noDose1`
- [ ] Undo Dose 2 (within 5s) → verify phase returns to `active`

### Snooze Logic
- [ ] Snooze 1x → verify target +10 min
- [ ] Snooze 3x → verify snooze disabled
- [ ] Snooze with <15 min remaining → verify snooze disabled

### Skip Logic
- [ ] Skip Dose 2 (before window) → verify skip disabled
- [ ] Skip Dose 2 (during window) → verify success
- [ ] Skip Dose 2 (after taken) → verify skip disabled

### Window Edge Cases
- [ ] Exact 150 min → verify enters `active` phase
- [ ] Exact 240 min → verify enters `closed` phase
- [ ] <15 min remaining → verify enters `nearClose` phase
- [ ] Dose 2 after 240 min → verify logs warning

### Event Logging
- [ ] Log "bathroom" event → verify appears in timeline
- [ ] Log "lights_out" event → verify appears in timeline
- [ ] Log "wake_final" event → verify appears in timeline
- [ ] Spam "bathroom" within 60s → verify rate limited

### Offline Resilience

> ⚠️ **Note**: Offline queue behavior is tested via unit tests (`OfflineQueueTests.swift`), not diagnostic logs.

- [ ] Airplane mode + Take Dose 1 → verify UI responds (optimistic update)
- [ ] Re-enable network → verify dose syncs to server
- [ ] Verify dose appears in history after network restore

### DST & Time Zones
- [ ] Test during DST transition (if applicable)
- [ ] Change time zone → verify session date stability
- [ ] Verify window math unaffected by time zone change

---

## Automated Testing

### Unit Tests (DoseCore)
```bash
swift test -q
```
- **277 tests** covering window math, API errors, offline queue, rate limiter
- Tests include DST edge cases, time zone changes, and exact boundary conditions

### Key Test Files
- `Tests/DoseCoreTests/DoseWindowStateTests.swift` - Core window logic
- `Tests/DoseCoreTests/DoseWindowEdgeTests.swift` - Boundary conditions
- `Tests/DoseCoreTests/APIErrorsTests.swift` - Error handling
- `Tests/DoseCoreTests/OfflineQueueTests.swift` - Resilience
- `Tests/DoseCoreTests/EventRateLimiterTests.swift` - Spam prevention

---

## Troubleshooting

### Build Fails
**Check:** Legacy file conflicts
**Fix:** Quarantine conflicting files with `#if false` (already done for known files)

### Logs Not Appearing
**Check:** Diagnostic logging enabled in Settings
**Fix:** Toggle "Enable Diagnostic Logging" ON

### Offline Queue Not Flushing
**Check:** Network connectivity
**Fix:** Verify `DosingService.flushPending()` is called on app foreground

### Undo Not Working
**Check:** Elapsed time (must be <5s)
**Check:** Undo window configured in Settings
**Fix:** Verify `UserSettingsManager.shared.undoWindowSeconds` is set correctly

---

## How to Read a Session Trace

See `docs/HOW_TO_READ_A_SESSION_TRACE.md` for detailed examples of full session traces and how to interpret them.

**Quick Reference:**

1. **Find session start:** Look for `{"event":"session.started","session_id":"YYYY-MM-DD"}`
2. **Track transitions:** Follow `session.phase.entered` events and `dose.window.*` boundaries
3. **Verify timing:** Check `elapsed_minutes` fields match expected intervals (150-240 min)
4. **Check for errors:** Search for `"level":"error"` or `"reason":` fields indicating blocked actions
5. **Validate undo:** Look for `dose.undone` or `undo.expired` events

---

## Performance Benchmarks

### Expected Timing
| Action | Expected Duration |
|--------|-------------------|
| App launch | <2s |
| Take Dose 1 | <100ms (UI response) |
| Window calculation | <50ms |
| Log export | <1s for 1000 entries |
| Offline queue flush | <500ms per action |

### Memory Usage
- Baseline: ~50-80 MB
- With HealthKit data: +10-20 MB
- With 1000 log entries: +5-10 MB

---

## Next Steps

1. **Run through all scenarios** in this guide
2. **Export logs** after each test
3. **Review logs** for unexpected errors or warnings
4. **Compare logs** against expected patterns above
5. **File issues** for any deviations from expected behavior

For questions or issues, see:
- `docs/SSOT/README.md` - Authoritative behavior spec
- `docs/DIAGNOSTIC_LOGGING.md` - Logging architecture
- `docs/HOW_TO_READ_A_SESSION_TRACE.md` - Example traces
- `.github/copilot-instructions.md` - Development workflow

---

**Happy Testing! 🚀**
