# DoseTap Diagnostic Logging

Last updated: 2026-01-14
Source of truth: `ios/Core/DiagnosticLogger.swift`, `ios/Core/DiagnosticEvent.swift`.

## Purpose

Diagnostic logs are the session "black box". They record state transitions and invariants, not UI taps.

Core rules:
- Every event includes `sessionId` (UUID string for the session).
- Log edges and state transitions only.
- Views do not call `DiagnosticLogger` directly.

## Integration Points

Logs are emitted from four areas:
- `SessionRepository` (session lifecycle + dose actions)
- `DoseWindowCalculator` (phase edges)
- `AlarmService` / notification scheduler
- Morning check-in flow

## Event Types (selected)

From `DiagnosticEvent`:
- `session.started`, `session.phase.entered`, `session.completed`, `session.expired`, `session.skipped`, `session.autoExpired`, `session.rollover`
- `dose.1.taken`, `dose.2.taken`, `dose.extra.taken`, `dose.2.skipped`, `dose.snooze.activated`
- `dose.window.opened`, `dose.window.nearClose`, `dose.window.expired`, `dose.window.blocked`, `dose.window.override.required`
- `checkin.started`, `checkin.completed`, `checkin.skipped`
- `sleepEvent.logged`, `sleepEvent.deleted`, `sleepEvent.edited`
- `app.*`, `timezone.changed`, `time.significantChange`, `notification.*`, `undo.*`
- `invariant.violation`

## Log Entry Fields

Required:
- `ts` (ISO8601)
- `seq` (monotonic per session, when available)
- `level`
- `event`
- `sessionId` (UUID string)
- `appVersion`, `build`

Optional (context):
- `phase`, `previousPhase`
- `dose1Time`, `dose2Time`
- `doseIndex`, `elapsedMinutes`, `elapsedSincePrevDoseMinutes`, `isLate`
- `remainingMinutes`, `snoozeCount`
- `terminalState`, `reason`, `alarmId`
- `sleepEventType`, `sleepEventId`
- `previousTimezone`, `newTimezone`, offsets, `timeDeltaSeconds`
- `constantsHash`, `invariantName`

## Storage Location

Logs are stored on device under:

```
Documents/diagnostics/sessions/<session-id>/
  meta.json
  events.jsonl
  errors.jsonl
```

`errors.jsonl` is a filtered view (warning/error). Use `events.jsonl` for the authoritative sequence.

## How to Read a Session Trace

See `docs/HOW_TO_READ_A_SESSION_TRACE.md` for step-by-step triage guidance.

