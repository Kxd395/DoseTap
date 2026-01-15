# Testing Guide Alignment: What Was Fixed

**Date:** 2026-01-04  
**Commit:** bf040a1  
**Severity:** Critical (false alarm prevention)

---

## Executive Summary

The initial `TESTING_GUIDE.md` had **excellent scenario coverage** but was **semantically out of sync** with the actual diagnostic logging system. This created a **dangerous mismatch** where testers following the guide would:

1. Expect logs that do not exist
2. Believe logging was "broken" when it was not
3. Misinterpret the absence of UI tap logs as failures

**Resolution:** All logging expectations now match `DIAGNOSTIC_LOGGING.md`, `DiagnosticEvent.swift`, and `HOW_TO_READ_A_SESSION_TRACE.md` ground truth.

---

## What Was Wrong (Before)

### 1. Tier Definitions Were Incorrect

**Claimed:**
- Tier 1: User actions (button taps, dose events)
- Tier 2: Session context events
- Tier 3: Forensic deep inspection

**Actual (per DIAGNOSTIC_LOGGING.md):**
- Tier 1: Safety-critical diagnostic events (lifecycle, timezone, notifications, undo)
- Tier 2: Session context events (sleep events, pre-sleep, check-in)
- Tier 3: Optional forensic detail (explicitly opt-in)

**Impact:** Testers expected "user action" logs that **never existed**.

---

### 2. Log Format Was Completely Wrong

**Claimed:**
```
[Tier 1] User Action: Take Dose 1 tapped
[Tier 2] Window Transition: noDose1 → beforeWindow
```

**Actual (JSONL):**
```jsonl
{"event":"dose.1.taken","session_id":"2026-01-04","dose1_time":"..."}
{"event":"session.phase.entered","phase":"beforeWindow","previous_phase":"noDose1"}
```

**Impact:** Testers searching Console output for bracketed strings would find nothing and assume failure.

---

### 3. Export Format Was Fabricated

**Claimed:**
```json
{
  "version": "2.15.0",
  "tier": 2,
  "sessionId": "...",
  "logs": [...]
}
```

**Actual:**
```
2026-01-04/
├── meta.json
├── events.jsonl   ← authoritative
└── errors.jsonl   ← incomplete
```

**Impact:** Testers would not know where to look for exported data.

---

### 4. Tested Things That Aren't Logged

**Example scenarios that tested non-existent logs:**
- "User Action: Snooze tapped"
- "User Action: Skip Dose 2 tapped"
- "Offline Queue: enqueued takeDose1"

**Logging philosophy (per DIAGNOSTIC_LOGGING.md):**
> Logs record **state facts**, not UI actions.

**Impact:** Testers would waste time looking for logs of button presses, which are **explicitly not recorded**.

---

## What Was Fixed (After)

### 1. Tier Section: Aligned with Truth

**Before:**
> Tier 1: User actions (button taps, dose events)

**After:**
> Tier 1: Safety-critical diagnostic events (lifecycle, timezone, notifications, undo)

Added explicit warning:
> ⚠️ **Important**: Diagnostic logs record **state facts**, not UI actions. You will not see logs like "button tapped"—instead you'll see the **effects** like `dose.1.taken` or `dose.snooze.activated`.

---

### 2. All "Expected Logs" Sections: Converted to JSONL

**Example - Scenario 1 (Fresh Session):**

**Before:**
```
[Tier 1] User Action: Take Dose 1 tapped
[Tier 2] Session Context: Dose 1 taken at [timestamp]
[Tier 2] Window Transition: noDose1 → beforeWindow
```

**After:**
```jsonl
{"event":"session.started","session_id":"2026-01-04","phase":"noDose1"}
{"event":"dose.1.taken","session_id":"2026-01-04","dose1_time":"2026-01-04T22:00:00-05:00"}
{"event":"session.phase.entered","session_id":"2026-01-04","phase":"beforeWindow","previous_phase":"noDose1"}
```

Now references **actual event names** from `DiagnosticEvent.swift`.

---

### 3. Export Format: Corrected to Folder Structure

**Before:**
```json
{
  "version": "2.15.0",
  "tier": 2,
  "logs": [...]
}
```

**After:**
```
2026-01-04/
├── meta.json      ← Device, app version, timezone
├── events.jsonl   ← Full event stream (authoritative)
└── errors.jsonl   ← Errors only (incomplete)
```

Added explicit warning:
> ⚠️ **Warning**: `errors.jsonl` is a convenience view. **Always use `events.jsonl` for real investigation.**

---

### 4. Scenario Framing: Effects, Not Inputs

**Example - Scenario 9 (Sleep Events):**

**Before:**
```
[Tier 2] Rate Limit Blocked: event=bathroom, cooldown=60s
```

**After:**
```
> ⚠️ **Note**: Rate limiting is handled at the service layer and may not generate diagnostic events. The **absence** of a second bathroom event in the timeline is the test—logs record effects, not blocked actions unless they violate an invariant.
```

**Offline Queue (Scenario 10):**

**Before:**
```
[Tier 2] Offline Queue: enqueued takeDose1
[Tier 2] Offline Queue: flushed 1 actions
```

**After:**
```
> ⚠️ **Important**: Offline queue behavior is validated via **app behavior and unit tests**, not diagnostic logs. Diagnostic logging records session state facts, not infrastructure behavior. Queue mechanics are tested in `OfflineQueueTests.swift`.
```

---

### 5. Added Critical Boundary Warning

**New section header in "Interpreting Logs":**

> ⚠️ **Critical Boundary**: If you are expecting to see a log line and don't, check whether the system logs **effects**, not **inputs**. Diagnostic logs record state facts (e.g., `dose.1.taken`), not UI actions (e.g., "button tapped").

This is the **most important addition** because it prevents the core misunderstanding.

---

### 6. "Interpreting Logs" Section: Rewritten

**Before (wrong):**
| Category | Description | Example |
|----------|-------------|---------|
| `userAction` | Button taps, explicit user input | "Take Dose 1 tapped" |
| `sessionContext` | State transitions | "Window Transition: ..." |

**After (correct):**
| Event Pattern | Description | Example |
|---------------|-------------|---------|
| `session.*` | Session lifecycle | `session.started`, `session.completed` |
| `dose.*` | Dose actions and window boundaries | `dose.1.taken`, `dose.window.opened` |
| `alarm.*` | Notification/alarm events | `alarm.scheduled`, `alarm.suppressed` |

Now references **actual event naming conventions** from `DiagnosticEvent.swift`.

---

## Why This Mattered

### Risk if Not Fixed

1. **Support confusion**: Users report "logging broken" when it's working correctly
2. **False bug reports**: QA files issues for missing logs that were never supposed to exist
3. **Wasted debugging time**: Engineers investigate phantom problems
4. **Loss of trust**: The diagnostic system becomes suspect when it's actually sound

### Benefit Now That It's Fixed

1. **Accurate expectations**: Testers know exactly what to look for
2. **No false alarms**: Absence of "user action" logs is now understood
3. **Efficient triage**: Real issues (missing `dose.1.taken`) vs. non-issues (missing "button tapped")
4. **Trust in evidence**: Diagnostic logs are now a reliable debugging tool

---

## Validation Checklist

If you're reviewing this fix, verify:

- [ ] All "Expected Events" sections use JSONL format
- [ ] All event names match `DiagnosticEvent.swift` enum cases
- [ ] No references to `[Tier N]` bracketed format
- [ ] No references to `userAction`, `sessionContext`, `forensic` categories
- [ ] Export format shows folder structure, not wrapped JSON
- [ ] Offline queue marked as "tested via unit tests, not logs"
- [ ] Boundary warning present: "logs record effects, not inputs"
- [ ] References to `DIAGNOSTIC_LOGGING.md` and `HOW_TO_READ_A_SESSION_TRACE.md` are correct

---

## Files Aligned

This fix ensures consistency across:

1. **`DIAGNOSTIC_LOGGING.md`** - System architecture (authoritative)
2. **`DiagnosticEvent.swift`** - Event enum definition (ground truth)
3. **`HOW_TO_READ_A_SESSION_TRACE.md`** - Example traces
4. **`TESTING_GUIDE.md`** - Testing expectations ← **NOW ALIGNED**

All four documents now tell the same story.

---

## Lessons Learned

### What Went Wrong Initially

The guide was written **before** the diagnostic logging system was fully hardened. When the system evolved to:

- Session-scoped JSONL
- Edge-only logging
- State facts, not UI actions

...the guide was not updated to match.

### How to Prevent This

1. **Write guides AFTER implementation stabilizes** (or update in lockstep)
2. **Reference canonical sources** (e.g., "see DiagnosticEvent.swift for event names")
3. **Add warnings about semantic boundaries** (effects vs. inputs)
4. **Cross-link to authoritative docs** (DIAGNOSTIC_LOGGING.md as SSOT)

---

## Remaining Linting Issues (Non-Critical)

The guide still has markdown linting warnings:
- Missing blank lines around headings/lists
- Missing language tags on code blocks
- Table column spacing

These are **cosmetic** and do not affect correctness. Fix if desired via:

```bash
# Auto-fix safe issues
npx markdownlint-cli2-fix docs/TESTING_GUIDE.md
```

But the **semantic fixes** (this commit) are what mattered for safety.

---

## Conclusion

**Before:** Testing guide was a liability (false alarms, confusion).  
**After:** Testing guide is an asset (accurate expectations, efficient debugging).

The **scenario coverage** was always excellent.  
The **logging expectations** are now aligned with reality.

**Status:** Safe to use for QA, support, and onboarding. ✅
