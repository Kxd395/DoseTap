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
The app has **3 tiers of diagnostic logging** (see `docs/DIAGNOSTIC_LOGGING.md`):
- **Tier 1:** User actions (button taps, dose events) - always on
- **Tier 2:** Session context events (window transitions, snooze state changes) - enabled by default
- **Tier 3:** Forensic deep inspection (state deltas, full context snapshots) - opt-in

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

**Expected Logs:**
```
[Tier 1] User Action: Take Dose 1 tapped
[Tier 2] Session Context: Dose 1 taken at [timestamp]
[Tier 2] Window Transition: noDose1 → beforeWindow
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

**Expected Logs:**
```
[Tier 1] Dose 1 Taken: [timestamp]
[Tier 2] Window Transition: noDose1 → beforeWindow
[Tier 2] Window State: opens in 150 minutes
[Tier 3] DoseWindowContext: {phase: beforeWindow, remaining: 9000s, ...}
```

**Edge Case:** Fast-forward time (or use Xcode's time debug):
- At exactly +150 min, verify phase changes to `active`

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

**Expected Logs:**
```
[Tier 2] Window Transition: beforeWindow → active
[Tier 1] User Action: Take Dose 2 tapped
[Tier 1] Dose 2 Taken: [timestamp]
[Tier 2] Window Transition: active → completed
[Tier 2] Undo Window Started: 5 seconds
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

**Expected Logs:**
```
[Tier 1] User Action: Snooze tapped
[Tier 2] Snooze Applied: count=1, newTarget=[timestamp]
[Tier 1] User Action: Snooze tapped
[Tier 2] Snooze Applied: count=2, newTarget=[timestamp]
```

**Edge Cases:**
- Snooze disabled when `remaining < 15 min`
- Snooze disabled after `maxSnoozes` reached (default: 3)

**Expected Logs for Edge Case:**
```
[Tier 2] Snooze Disabled: reason="Less than 15 minutes remaining"
[Tier 1] User Action: Snooze blocked (not enabled)
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

**Expected Logs:**
```
[Tier 1] User Action: Skip Dose 2 tapped
[Tier 1] Dose 2 Skipped: reason="user_skipped"
[Tier 2] Window Transition: active → completed
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

**Expected Logs:**
```
[Tier 1] Dose 1 Taken: [timestamp]
[Tier 2] Undo Window Started: 5 seconds, action=takeDose1
[Tier 1] User Action: Undo tapped
[Tier 1] Undo Success: action=takeDose1
[Tier 2] Window Transition: beforeWindow → noDose1
```

**Edge Case:** Wait >5 seconds, then try to undo
```
[Tier 2] Undo Expired: action=takeDose1, elapsed=6.2s
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

**Expected Logs:**
```
[Tier 2] Window Transition: active → closed
[Tier 1] User Action: Take Dose 2 tapped (outside window)
[Tier 1] Dose 2 Taken: [timestamp], windowExceeded=true
[Tier 2] Window Exceeded: elapsed=245 minutes
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

**Expected Logs:**
```
[Tier 2] Window Transition: active → nearClose
[Tier 2] Snooze Disabled: reason="nearWindowThresholdMin=15"
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

**Expected Logs:**
```
[Tier 1] Sleep Event Logged: type=bathroom, timestamp=[timestamp]
[Tier 1] Sleep Event Logged: type=lights_out, timestamp=[timestamp]
[Tier 1] Sleep Event Logged: type=wake_final, timestamp=[timestamp]
[Tier 2] Rate Limit Blocked: event=bathroom, cooldown=60s
```

---

### Scenario 10: Offline Queue (Network Resilience)
**Goal:** Verify offline actions are queued and retried.

**Steps:**
1. Turn on Airplane Mode
2. Take Dose 1
3. Verify action is queued (check logs)
4. Turn off Airplane Mode
5. Verify queue flushes automatically

**Expected Logs:**
```
[Tier 1] Dose 1 Taken: [timestamp]
[Tier 2] Network Error: action queued (offline)
[Tier 2] Offline Queue: enqueued takeDose1
[Tier 2] Network Restored: flushing queue
[Tier 2] Offline Queue: flushed 1 actions
```

---

## Reviewing Diagnostic Logs

### Method 1: In-App Export
1. Go to Settings > Diagnostic Logging
2. Tap "Export Logs"
3. Choose destination (Files, AirDrop, email)
4. Open exported JSON file

**Log Structure:**
```json
{
  "version": "2.15.0",
  "tier": 2,
  "sessionId": "2026-01-04",
  "logs": [
    {
      "timestamp": "2026-01-04T22:00:00Z",
      "level": "info",
      "category": "userAction",
      "message": "Dose 1 Taken",
      "metadata": {
        "timestamp": "2026-01-04T22:00:00Z",
        "source": "dashboard"
      }
    }
  ]
}
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

### Key Log Categories
| Category | Description | Example |
|----------|-------------|---------|
| `userAction` | Button taps, explicit user input | "Take Dose 1 tapped" |
| `sessionContext` | State transitions, window changes | "Window Transition: beforeWindow → active" |
| `forensic` | Deep state inspection (Tier 3 only) | Full `DoseWindowContext` snapshot |
| `error` | Failures, edge cases | "Network error: 500" |

### Common Patterns to Look For

#### ✅ Healthy Session
```
[userAction] Dose 1 Taken: 22:00:00
[sessionContext] Window Transition: noDose1 → beforeWindow
[sessionContext] Window Opens: 00:30:00 (150 min)
[sessionContext] Window Transition: beforeWindow → active
[userAction] Dose 2 Taken: 00:45:00
[sessionContext] Window Transition: active → completed
```

#### ⚠️ Warning Signs
```
[error] Network error: Failed to sync dose
[sessionContext] Offline Queue: enqueued takeDose1
```
→ Action was queued; verify it syncs later.

```
[sessionContext] Snooze Disabled: reason="maxSnoozes=3"
[userAction] Snooze blocked (not enabled)
```
→ User hit snooze limit; expected behavior.

```
[error] Window Exceeded: elapsed=245 minutes
[userAction] Dose 2 Taken (outside window)
```
→ User took dose late; flag for review in insights.

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
- [ ] Airplane mode + Take Dose 1 → verify queued
- [ ] Re-enable network → verify queue flushes
- [ ] Check logs for `Offline Queue: flushed X actions`

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
1. **Find session start:** Look for `Session Initialized: sessionId=YYYY-MM-DD`
2. **Track transitions:** Follow `Window Transition: X → Y` logs
3. **Verify timing:** Check `elapsed` fields match expected intervals (150-240 min)
4. **Check for errors:** Search for `[error]` or `blocked` keywords
5. **Validate undo:** Look for `Undo Window Started` → `Undo Success` or `Undo Expired`

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
