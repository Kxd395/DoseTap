# DoseTap Diagnostic Logging System

> **Version**: 2.14.0  
> **Status**: Production  
> **Last Updated**: 2026-01-04

## Overview

DoseTap's diagnostic logging system records **session lifecycle events** as machine-readable JSONL files. This is not observability infrastructure—it's the "black box recorder" for each medication session.

### Key Principles

1. **Session-scoped**: Every log entry has a `session_id`. If it can't be tied to a session, it doesn't belong.
2. **Edges only**: Log transitions and invariants, not ticks.
3. **State facts, not UI actions**: Logs record what the state machine did, not what buttons were pressed.
4. **Authoritative and complete**: Unlike analytics (lossy), diagnostic logs are the definitive record.

### What This Is NOT

- ❌ Interaction telemetry (that's `AnalyticsService`)
- ❌ Performance monitoring
- ❌ Crash reporting
- ❌ User behavior tracking
- ❌ Cloud-based observability

## Architecture

```
SessionRepository ──────────────────┐
                                    │
DoseWindowCalculator (via repo) ────┼──▶ DiagnosticLogger ──▶ Documents/diagnostics/
                                    │         │                   └── sessions/
NotificationScheduler ──────────────┤         │                        └── 2026-01-03/
                                    │         │                             ├── meta.json
CheckInFlow ────────────────────────┘         │                             ├── events.jsonl
                                              │                             └── errors.jsonl
                                              ▼
                                         DiagnosticExportView (Settings)
```

### Boundary Rules (CI-Enforced)

| Rule | Enforcement |
|------|-------------|
| Views MAY NOT call DiagnosticLogger | CI grep guard |
| DiagnosticLogger MAY NOT access SQLite | Code review |
| Every log MUST have session_id | Logger rejects events without it |
| Only 4 integration points | Architecture review |

## Integration Points

Logging is allowed in exactly **four places**:

### 1. SessionRepository (80% of value)

Events logged:
- `session.started` - When Dose 1 is taken
- `session.phase.entered` - Phase transitions (beforeWindow → active → nearClose → closed)
- `session.completed` - Dose 2 taken
- `session.skipped` - User skipped Dose 2
- `session.autoExpired` - Slept through window + grace period
- `session.rollover` - Day boundary crossed
- `dose.1.taken` - Dose 1 recorded
- `dose.2.taken` - Dose 2 recorded
- `dose.2.skipped` - Explicit skip
- `dose.snooze.activated` - Snooze pressed

### 2. DoseWindowCalculator (via SessionRepository)

Boundary events (edges only):
- `dose.window.opened` - 150 minutes elapsed (beforeWindow → active)
- `dose.window.nearClose` - <15 minutes remaining (active → nearClose)
- `dose.window.expired` - 240 minutes elapsed (nearClose → closed)

### 3. Notification/Alarm Service

- `alarm.scheduled` - Notification scheduled
- `alarm.cancelled` - Notification cancelled
- `alarm.suppressed` - Not scheduled due to rules (e.g., <15m remaining)
- `alarm.autoCancelled` - Cancelled on session completion

### 4. Morning Check-In

- `checkin.started` - Check-in flow opened
- `checkin.completed` - Check-in submitted
- `checkin.skipped` - User dismissed without completing

## Event Format

All events are JSON objects with consistent structure:

```json
{
  "ts": "2026-01-04T03:45:00-05:00",
  "level": "info",
  "event": "dose.window.opened",
  "session_id": "2026-01-03",
  "phase": "active",
  "previous_phase": "beforeWindow",
  "elapsed_minutes": 150,
  "remaining_minutes": 90,
  "snooze_count": 0,
  "app_version": "2.14.0",
  "build": "release"
}
```

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `ts` | ISO8601 | Event timestamp with timezone offset |
| `level` | string | `debug`, `info`, `warning`, `error` |
| `event` | string | Dot-notation event name |
| `session_id` | string | Session date (YYYY-MM-DD) |
| `app_version` | string | Bundle version |
| `build` | string | `debug` or `release` |

### Context Fields (Event-Specific)

| Field | Type | When Present |
|-------|------|--------------|
| `phase` | string | Phase changes |
| `previous_phase` | string | Phase transitions |
| `dose1_time` | ISO8601 | Dose-related events |
| `dose2_time` | ISO8601 | Dose 2 events |
| `elapsed_minutes` | int | Window calculations |
| `remaining_minutes` | int | Window state |
| `snooze_count` | int | Snooze events |
| `terminal_state` | string | Session completion |
| `reason` | string | Blocked/suppressed events |
| `alarm_id` | string | Alarm events |

## File Layout

```
Documents/
  diagnostics/
    sessions/
      2026-01-03/
        meta.json       # Static context for session
        events.jsonl    # Event stream (append-only)
        errors.jsonl    # Errors/warnings subset
      2026-01-04/
        ...
```

### meta.json

Created once per session with environment context:

```json
{
  "session_id": "2026-01-03",
  "created_at": "2026-01-03T22:15:00-05:00",
  "app_version": "2.14.0",
  "build_number": "42",
  "build_type": "release",
  "device_model": "iPhone15,3",
  "os_version": "17.2",
  "timezone": "America/New_York",
  "timezone_offset_minutes": -300,
  "constants_hash": "a1b2c3d4"
}
```

The `constants_hash` enables detecting config drift ("this bug only happened before config X changed").

### events.jsonl

One JSON object per line, append-only:

```jsonl
{"ts":"2026-01-03T22:15:00-05:00","level":"info","event":"session.started","session_id":"2026-01-03",...}
{"ts":"2026-01-04T01:20:00-05:00","level":"info","event":"dose.1.taken","session_id":"2026-01-03",...}
{"ts":"2026-01-04T03:50:00-05:00","level":"info","event":"dose.window.opened","session_id":"2026-01-03",...}
```

### errors.jsonl

Subset containing only `warning` and `error` level events for quick triage.

## API Reference

### DiagnosticLogger

```swift
public actor DiagnosticLogger {
    public static let shared = DiagnosticLogger()
    
    /// Log an event with optional context
    public func log(
        _ event: DiagnosticEvent,
        level: DiagnosticLevel = .info,
        sessionId: String,
        context: ((inout DiagnosticLogEntry) -> Void)? = nil
    )
    
    /// Ensure session metadata is written (call once per session)
    public func ensureSessionMetadata(sessionId: String)
    
    /// Export session folder URL
    public func exportSession(_ sessionId: String) -> URL?
    
    /// List available sessions
    public func availableSessions() -> [String]
    
    /// Remove old sessions
    public func pruneOldSessions(keepDays: Int = 14)
}
```

### Convenience Methods

```swift
// Session lifecycle
await logger.logSessionStarted(sessionId: key)
await logger.logPhaseEntered(sessionId: key, phase: "active", previousPhase: "beforeWindow")
await logger.logSessionCompleted(sessionId: key, terminalState: "completed")

// Doses
await logger.logDoseTaken(sessionId: key, dose: 1, at: timestamp)
await logger.logDoseTaken(sessionId: key, dose: 2, at: timestamp, elapsedMinutes: 165)

// Windows
await logger.logWindowBoundary(.doseWindowOpened, sessionId: key, phase: "active", elapsedMinutes: 150)

// Alarms
await logger.logAlarm(.alarmScheduled, sessionId: key, alarmId: "dose_reminder")

// Errors
await logger.logError(.errorStorage, sessionId: key, reason: "SQLite write failed")
```

## Session Trace Export

**Location**: Settings → Data Management → Export Session Diagnostics

### What's Exported

- `meta.json` - Device/app context
- `events.jsonl` - Complete event stream
- `errors.jsonl` - Errors subset

### Privacy

- Local export only (no cloud upload)
- No personal health data (timing/state only)
- User controls sharing destination

### Use Cases

1. Debug your own edge cases
2. Share with clinician (narcolepsy timing anomalies)
3. Validate timezone behavior
4. Investigate missed doses

## Questions This System Answers

With diagnostic logs, you can determine:

1. **Did the window really expire, or was the app backgrounded?**
   - Check `dose.window.expired` event timestamp vs app lifecycle

2. **Was Dose 2 blocked by rules or user action?**
   - Look for `dose.window.blocked` events with `reason` field

3. **Did timezone change mid-session?**
   - Compare `timezone_offset_minutes` in meta.json vs event timestamps

4. **Did Night Mode suppress a reminder visually but not functionally?**
   - Check `alarm.scheduled` / `alarm.cancelled` events

5. **Did narcolepsy-related wake events cluster before missed doses?**
   - Correlate sleep event timestamps with session outcomes

6. **Why didn't the alarm fire?**
   - Look for `alarm.suppressed` with reason

## Implementation Files

| File | Purpose |
|------|---------|
| `ios/Core/DiagnosticEvent.swift` | Event enum, log entry struct, session metadata |
| `ios/Core/DiagnosticLogger.swift` | Logger actor, file I/O, convenience methods |
| `ios/DoseTap/Views/DiagnosticExportView.swift` | Settings UI for export |
| `ios/DoseTap/Storage/SessionRepository.swift` | Integration point (80% of events) |

## What NOT to Add

- ❌ OpenTelemetry
- ❌ Tracing SDKs
- ❌ Dashboards
- ❌ Sampling
- ❌ Live tail UI
- ❌ Cloud upload

DoseTap is a medical-adjacent tool. **Calm beats clever.**

## Retention

Sessions are retained for 14 days by default. Older sessions are pruned automatically on app launch.

```swift
// Customize retention
DiagnosticLogger.shared.retentionDays = 30
```

## Disabling Logging

Logging can be disabled if needed:

```swift
DiagnosticLogger.shared.isEnabled = false
```

This does not delete existing logs—use `pruneOldSessions()` for that.

---

## Changelog

### v2.14.0 (2026-01-04)
- Initial implementation
- Session lifecycle events
- Phase transition logging at edges
- JSONL file format
- Session trace export in Settings
