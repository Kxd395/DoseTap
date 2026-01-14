# Specification: Manual Dose Time Entry & Adjustment

**Feature ID**: 003-manual-dose-entry
**Status**: Draft
**Created**: 2026-01-10
**Priority**: P1 (User-requested, medication safety)

---

## Problem Statement

When a user **takes Dose 2 but forgets to log it**, the app currently:

1. Shows "Window Expired" after 240 minutes
2. Auto-skips the session after 270 minutes (slept-through detection)
3. Records the session as incomplete with no way to correct it

**User need**: "I took Dose 2 at 2:30 AM but fell asleep before logging. When I woke up, the app said I missed it. I need to add the correct time."

---

## User Stories

### US-001: Add Missed Dose 2 Time

**As a** XYWAV patient who forgot to log Dose 2,
**I want to** manually enter the time I actually took it,
**So that** my session record is accurate and my adherence metrics reflect reality.

**Acceptance Criteria**:

- [ ] Can enter Dose 2 time after window expired (up to 6 hours after Dose 1)
- [ ] Time picker defaults to current time but allows past selection
- [ ] Entry requires confirmation ("I took this dose at [time]")
- [ ] Session updates from "skipped" to "completed" with corrected time
- [ ] Interval calculation uses the manually entered time
- [ ] Diagnostic log captures the manual entry with `source: "manual"`

### US-002: Correct Dose 1 Time

**As a** XYWAV patient who logged Dose 1 at the wrong time,
**I want to** adjust the recorded time,
**So that** my Dose 2 window calculations are accurate.

**Acceptance Criteria**:

- [ ] Can edit Dose 1 time within current session only
- [ ] Adjustment limited to ±30 minutes from original entry
- [ ] Window countdown recalculates based on corrected time
- [ ] Original time preserved in audit log
- [ ] Requires confirmation before saving

### US-003: Correct Dose 2 Time

**As a** XYWAV patient who logged Dose 2 at the wrong time,
**I want to** adjust the recorded time,
**So that** my interval tracking is accurate.

**Acceptance Criteria**:

- [ ] Can edit Dose 2 time within current session only
- [ ] Adjustment limited to ±30 minutes from original entry
- [ ] Interval recalculates based on corrected time
- [ ] Original time preserved in audit log
- [ ] Requires confirmation before saving

### US-004: Recover Auto-Skipped Session

**As a** XYWAV patient whose session was auto-skipped,
**I want to** convert the skip to a completed dose with actual time,
**So that** my records reflect that I did take the medication.

**Acceptance Criteria**:

- [ ] Can convert within 12 hours of session date
- [ ] Must enter the actual time taken
- [ ] Session terminal state changes from `incomplete_slept_through` to `completed_manual`
- [ ] Clear warning: "This will change your recorded adherence"
- [ ] Diagnostic log captures the recovery action

---

## Functional Requirements

### FR-001: Manual Entry Access Points

| Location | Trigger | Action |
|----------|---------|--------|
| Tonight Tab (Expired) | "I already took it" button | Opens manual time entry |
| Tonight Tab (Timeline) | Tap on dose row | Opens time editor |
| History Tab (Date View) | Tap on dose row | Opens time editor |
| History Tab (Session) | Tap on any event | Opens time editor |
| Session Detail | "Edit" icon on dose row | Opens time correction |
| History Tab | "Fix" badge on incomplete session | Opens recovery flow |
| Incomplete Banner | "I took Dose 2" link | Opens manual time entry |

### FR-002: Time Picker Constraints

| Constraint | Value | Rationale |
|------------|-------|-----------|
| Earliest allowed | Dose 1 time + 90 min | Safety: No dose before 1.5h |
| Latest allowed | Dose 1 time + 360 min | Reasonableness: 6 hours max |
| Default selection | Current time OR 165 min after Dose 1 | Optimal interval |
| Adjustment range | ±30 minutes from original | Prevent major falsification |
| Recovery window | 12 hours from session date | Practical limit |

### FR-003: Confirmation Requirements

All manual entries require explicit confirmation:

```
┌─────────────────────────────────────────┐
│  ⚠️ Confirm Manual Entry                │
│                                         │
│  You are recording Dose 2 at 2:35 AM    │
│  (175 minutes after Dose 1)             │
│                                         │
│  ☑️ I confirm I took this dose at       │
│     this time                           │
│                                         │
│  [Cancel]              [Confirm & Save] │
└─────────────────────────────────────────┘
```

### FR-004: Audit Trail

All manual entries logged with metadata:

```json
{
  "event": "dose.2.manual_entry",
  "dose2_time": "2026-01-10T02:35:00-05:00",
  "source": "manual",
  "original_state": "skipped",
  "entry_time": "2026-01-10T08:15:00-05:00",
  "hours_after_session": 5.5,
  "user_confirmed": true
}
```

---

## UI/UX Design

### Screen: Manual Dose 2 Entry

```
┌─────────────────────────────────────────┐
│ ← Back          Add Dose 2              │
├─────────────────────────────────────────┤
│                                         │
│  Session: Tonight (Jan 10)              │
│  Dose 1 taken at: 10:45 PM              │
│                                         │
│  ─────────────────────────────────────  │
│                                         │
│  When did you take Dose 2?              │
│                                         │
│       ┌─────────────────────┐           │
│       │    ⏰ 2:35 AM       │           │
│       │   [Time Picker]     │           │
│       └─────────────────────┘           │
│                                         │
│  Interval: 2h 50m (170 min) ✅          │
│  Status: Within window                  │
│                                         │
│  ─────────────────────────────────────  │
│                                         │
│  ☑️ I confirm I took Dose 2 at this     │
│     time                                │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │         Save Entry              │    │
│  └─────────────────────────────────┘    │
│                                         │
└─────────────────────────────────────────┘
```

### Screen: Edit Existing Dose Time

```
┌─────────────────────────────────────────┐
│ ← Back         Edit Dose Time           │
├─────────────────────────────────────────┤
│                                         │
│  Original time: 2:30 AM                 │
│  Recorded: 15 minutes ago               │
│                                         │
│  ─────────────────────────────────────  │
│                                         │
│  Correct time:                          │
│                                         │
│       ┌─────────────────────────┐       │
│       │    ⏰ 2:35 AM           │       │
│       │   [Time Picker]         │       │
│       └─────────────────────────┘       │
│                                         │
│  Adjustment: +5 minutes                 │
│  (max ±30 min allowed)                  │
│                                         │
│  ─────────────────────────────────────  │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │         Save Correction         │    │
│  └─────────────────────────────────┘    │
│                                         │
└─────────────────────────────────────────┘
```

### "I Already Took It" Button (Expired Window State)

When window is expired but not yet auto-skipped:

```
┌─────────────────────────────────────────┐
│  ⛔️ Window Expired                      │
│                                         │
│  The Dose 2 window closed 45 min ago.   │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │  🕐 I Already Took It           │    │  ← NEW
│  └─────────────────────────────────┘    │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │     Take Now (Late)             │    │
│  └─────────────────────────────────┘    │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │     Skip Dose 2                 │    │
│  └─────────────────────────────────┘    │
└─────────────────────────────────────────┘
```

---

## Data Model Changes

### New Fields in `dose_events`

```sql
ALTER TABLE dose_events ADD COLUMN source TEXT DEFAULT 'app';
-- Values: 'app' (real-time), 'manual' (retroactive), 'adjusted' (time corrected)

ALTER TABLE dose_events ADD COLUMN original_timestamp TEXT;
-- Stores original value when time is adjusted

ALTER TABLE dose_events ADD COLUMN entry_timestamp TEXT;
-- When the manual entry was recorded (for audit)
```

### Session Repository Methods

```swift
protocol SessionRepository {
    // Existing
    func setDose2Time(_ time: Date, isEarly: Bool, isExtraDose: Bool)
    
    // New
    func setDose2TimeManual(_ time: Date, confirmed: Bool) async throws
    func adjustDose1Time(_ newTime: Date) async throws
    func adjustDose2Time(_ newTime: Date) async throws
    func recoverSkippedSession(dose2Time: Date) async throws
}
```

### Validation Errors

```swift
enum ManualEntryError: Error {
    case tooEarlyAfterDose1(minMinutes: Int)      // < 90 min
    case tooLateAfterDose1(maxMinutes: Int)       // > 360 min
    case adjustmentTooLarge(maxMinutes: Int)      // > ±30 min
    case sessionTooOld(maxHours: Int)             // > 12 hours
    case confirmationRequired
    case sessionAlreadyComplete
}
```

---

## Safety Guards

### Guard 1: Minimum Interval

Prevents logging Dose 2 too close to Dose 1:

```swift
func validateManualDose2Time(_ time: Date, dose1At: Date) throws {
    let interval = time.timeIntervalSince(dose1At)
    let minMinutes = 90  // Safety floor
    
    if interval < Double(minMinutes) * 60 {
        throw ManualEntryError.tooEarlyAfterDose1(minMinutes: minMinutes)
    }
}
```

### Guard 2: Maximum Interval

Prevents unreasonable entries:

```swift
let maxMinutes = 360  // 6 hours
if interval > Double(maxMinutes) * 60 {
    throw ManualEntryError.tooLateAfterDose1(maxMinutes: maxMinutes)
}
```

### Guard 3: Adjustment Limit

Prevents large time changes to existing entries:

```swift
let maxAdjustmentMinutes = 30
let adjustment = abs(newTime.timeIntervalSince(originalTime))

if adjustment > Double(maxAdjustmentMinutes) * 60 {
    throw ManualEntryError.adjustmentTooLarge(maxMinutes: maxAdjustmentMinutes)
}
```

### Guard 4: Recovery Window

Prevents editing ancient sessions:

```swift
let maxRecoveryHours = 12
let sessionAge = Date().timeIntervalSince(sessionDate)

if sessionAge > Double(maxRecoveryHours) * 3600 {
    throw ManualEntryError.sessionTooOld(maxHours: maxRecoveryHours)
}
```

---

## Constants (for `constants.json`)

```json
{
  "manualEntry": {
    "minIntervalMinutes": 90,
    "maxIntervalMinutes": 360,
    "maxAdjustmentMinutes": 30,
    "recoveryWindowHours": 12,
    "requiresConfirmation": true
  }
}
```

---

## Test Scenarios

### T001: Manual Entry After Auto-Skip

```gherkin
Given session was auto-skipped (slept through)
And session is less than 12 hours old
When user taps "I took Dose 2"
And enters time 170 min after Dose 1
And confirms the entry
Then session terminal_state changes to "completed_manual"
And dose2_time is recorded with source "manual"
And interval shows 170 min
```

### T002: Manual Entry Too Early

```gherkin
Given user is on manual entry screen
When user selects time 60 min after Dose 1
Then "Save" button is disabled
And error shows "Dose 2 must be at least 90 min after Dose 1"
```

### T003: Adjustment Within Limit

```gherkin
Given Dose 2 was logged at 2:30 AM
When user adjusts time to 2:50 AM (+20 min)
And confirms the change
Then original_timestamp stores "2:30 AM"
And timestamp updates to "2:50 AM"
And source changes to "adjusted"
```

### T004: Adjustment Exceeds Limit

```gherkin
Given Dose 2 was logged at 2:30 AM
When user tries to adjust to 3:30 AM (+60 min)
Then error shows "Adjustments limited to ±30 minutes"
And change is blocked
```

### T005: Recovery Too Late

```gherkin
Given session from 2 days ago was skipped
When user tries to recover
Then error shows "Sessions can only be corrected within 12 hours"
```

---

## Out of Scope

- Editing sessions older than 12 hours
- Changing Dose 1 after Dose 2 is logged
- Bulk editing multiple sessions
- Deleting dose entries entirely
- Adjusting times by more than ±30 minutes

---

## Success Metrics

| Metric | Target |
|--------|--------|
| Manual entries per user/month | < 2 (indicates good real-time logging) |
| Recovery success rate | > 95% of attempts complete |
| False entry rate | < 1% (abuse detection) |
| User satisfaction | Resolves "forgot to log" complaints |

---

## Related Documents

- `docs/SSOT/README.md` - Core timing rules
- `docs/DATABASE_SCHEMA.md` - Storage schema
- `specs/002-cloudkit-sync/` - Sync considerations for manual entries
