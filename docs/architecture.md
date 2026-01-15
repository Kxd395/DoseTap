# DoseTap Architecture

Last updated: 2026-01-14

## Overview

DoseTap is a local-first iOS app built with SwiftUI and a SQLite persistence layer. Domain logic lives in `DoseCore`, while UI and storage orchestration live in the app target.

## Module Layout

- `ios/Core/` (DoseCore): domain logic, time/window calculations, diagnostic logger, shared models.
- `ios/DoseTap/` (App): SwiftUI views, SessionRepository, EventStorage (SQLite), HealthKit integration.
- `ios/DoseTap/FullApp/`: legacy/alternate UI path (not the primary app entry point).

## Storage Boundary (Single Writer)

UI must only talk to `SessionRepository`. `SessionRepository` is the only path to `EventStorage`.

```
SwiftUI Views
  -> SessionRepository (observable facade)
    -> EventStorage (SQLite wrapper)
      -> SQLite database
```

Primary files:
- `ios/DoseTap/Storage/SessionRepository.swift`
- `ios/DoseTap/Storage/EventStorage.swift`
- `docs/DATABASE_SCHEMA.md`

## Session Model

- Session identity: UUID string (`session_id`).
- Grouping key: `session_date` (YYYY-MM-DD, rollover hour 18).
- Session closure: morning check-in, missed check-in cutoff, or prep-time soft rollover.

Key flow:
- `SessionRepository.ensureActiveSession(for:reason:)` creates or reuses the active session.
- `SessionRepository.completeCheckIn()` closes the session and clears in-memory state.
- `SessionRepository.evaluateSessionBoundaries(reason:)` handles fallback rollover.

## HealthKit Integration

HealthKit is read-only and gated by two states:
- Preference: `UserSettingsManager.healthKitEnabled`.
- Authorization: `HealthKitService.isAuthorized`.

The app must reconcile these on launch and on settings view appearance.

## Diagnostics

Diagnostic logs are written to `Documents/diagnostics/sessions/<session-id>/`.
See `docs/DIAGNOSTIC_LOGGING.md` and `docs/HOW_TO_READ_A_SESSION_TRACE.md`.

