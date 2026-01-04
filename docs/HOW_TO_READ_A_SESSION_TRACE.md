# How to Read a Session Trace

> **For when you're tired and trying to understand what went wrong.**

This guide assumes you exported a session's diagnostics and have the folder open.

---

## Quick Start (30 seconds)

1. **Open `events.jsonl`** - this is the event stream
2. **Find the terminal event** - search for `session.completed`, `session.expired`, or `session.skipped`
3. **Read backward from there** - the last 5-10 events usually tell the story

---

## File Structure

```
2026-01-03/
├── meta.json      ← Device, app version, timezone at session start
├── events.jsonl   ← The full story (authoritative)
└── errors.jsonl   ← Errors only (triage, not evidence)
```

**⚠️ Warning**: `errors.jsonl` is incomplete. Always use `events.jsonl` for real investigation.

---

## The Three Questions

When something goes wrong, you're usually asking one of:

### 1. "Did my phone fail me?"

Look for:
- `app.backgrounded` → long gap → `app.foregrounded`
- `notification.delivered` without `notification.tapped`
- `alarm.suppressed` with reason

### 2. "Did time move underneath me?"

Look for:
- `timezone.changed` - shows old/new timezone
- `time.significantChange` - clock jumped
- `constants_hash` changes between events

### 3. "Did I miss my window?"

Look for:
- `dose.window.opened` (150 min mark)
- `dose.window.nearClose` (<15 min remaining)
- `dose.window.expired` (240 min mark)
- `session.autoExpired` (slept through)

---

## Event Anatomy

Every event looks like this:

```json
{
  "ts": "2026-01-04T03:45:00-05:00",
  "seq": 12,
  "level": "info",
  "event": "dose.window.opened",
  "session_id": "2026-01-03",
  "phase": "active",
  "elapsed_minutes": 150,
  "app_version": "2.14.0",
  "build": "release"
}
```

Key fields:
- **`ts`** - When it happened (with timezone)
- **`seq`** - Order within session (survives timestamp collisions)
- **`event`** - What happened (dot-notation name)
- **`phase`** - Current state machine phase
- **`elapsed_minutes`** - Time since Dose 1

---

## Common Patterns

### Normal night (7 events)
```
session.started
dose.1.taken
dose.window.opened      ← 150 min
dose.2.taken            ← In window
session.completed
checkin.started
checkin.completed
```

### Missed Dose 2 (5 events)
```
session.started
dose.1.taken
dose.window.opened
dose.window.nearClose   ← <15 min left
dose.window.expired     ← 240 min
session.autoExpired
```

### App killed during window
```
session.started
dose.1.taken
dose.window.opened
app.backgrounded        ← Gap starts here
... (long silence) ...
app.foregrounded        ← background_duration_seconds shows gap
session.autoExpired
```

---

## Red Flags

These warrant investigation:

| Event | Meaning |
|-------|---------|
| `invariant.violation` | Something impossible happened |
| `alarm.suppressed` | Notification wasn't scheduled (check reason) |
| `timezone.changed` | Clock moved during session |
| `error.*` | System error occurred |

---

## Reconstruction Checklist

When investigating a bad night:

- [ ] Check `meta.json` timezone matches your expectation
- [ ] Count events with `wc -l events.jsonl`
- [ ] Find the terminal event (completed/expired/skipped)
- [ ] Look for `app.backgrounded` with long gaps
- [ ] Check for `timezone.changed` or `time.significantChange`
- [ ] Verify `seq` numbers are contiguous (no missing events)
- [ ] Compare `constants_hash` at start vs end

---

## Tools

### Count events by type
```bash
cat events.jsonl | jq -r '.event' | sort | uniq -c | sort -rn
```

### Find all phase transitions
```bash
grep "phase" events.jsonl | jq '{ts, event, phase, previous_phase}'
```

### Extract timeline
```bash
cat events.jsonl | jq -r '[.ts, .event] | @tsv'
```

### Check for gaps > 30 minutes
```bash
# Manual: compare timestamps between consecutive events
```

---

## When to Escalate

Contact support with the session folder if:

1. `invariant.violation` appears
2. `seq` numbers have gaps
3. `constants_hash` changed unexpectedly
4. Events contradict each other
5. Terminal state doesn't match your memory

The session folder is self-contained evidence. Share it intact.

---

## One More Thing

This system exists because sleep medication timing matters.

If you're reading this at 3 AM after a confusing night, the data is there. Take your time. The sequence numbers don't lie.
