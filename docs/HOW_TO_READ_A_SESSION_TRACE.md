# How to Read a Session Trace

This guide helps diagnose a single session from its diagnostic log folder.

## Quick Start

1. Open `events.jsonl` (authoritative stream).
2. Find the terminal event (`session.completed`, `session.expired`, `session.skipped`, or `session.autoExpired`).
3. Read the prior 5-10 events to reconstruct what happened.

## File Structure

```
<session-id>/
  meta.json
  events.jsonl
  errors.jsonl
```

`<session-id>` is the UUID string assigned by `SessionRepository` when the session starts.

## Event Anatomy

```json
{
  "ts": "2026-01-14T03:45:00-05:00",
  "seq": 12,
  "level": "info",
  "event": "dose.window.opened",
  "sessionId": "7E4E6A9E-1F2B-4B52-9E9C-0B5F9B8C91D1",
  "phase": "active",
  "elapsedMinutes": 150,
  "appVersion": "2.14.0",
  "build": "release"
}
```

Key fields:
- `ts`: event timestamp
- `seq`: order within session
- `event`: what happened
- `sessionId`: session UUID

## Common Patterns

Normal night:
```
session.started

dose.1.taken

dose.window.opened

dose.2.taken

session.completed

checkin.completed
```

Missed Dose 2:
```
session.started

dose.1.taken

dose.window.opened

dose.window.expired

session.autoExpired
```

## Red Flags

- `invariant.violation`
- `timezone.changed` mid-session
- long gaps between events with `app.backgrounded`
- `alarm.suppressed` without a clear reason

## Tools

Count events by type:
```bash
cat events.jsonl | jq -r '.event' | sort | uniq -c | sort -rn
```

Extract a timeline:
```bash
cat events.jsonl | jq -r '[.ts, .event] | @tsv'
```

