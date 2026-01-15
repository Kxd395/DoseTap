# DoseTap Testing Guide

Last updated: 2026-01-14

## Build and Test

```bash
# From repo root
swift build
swift test

# Xcode app build
open ios/DoseTap.xcodeproj
```

## Manual Regression Checklist

1. Dose 1 -> window -> Dose 2 -> complete.
2. Dose 2 late (after window close) logs as Dose 2 with `is_late` metadata, not extra.
3. Extra dose only at dose index 3+.
4. Dose 1 before midnight, Dose 2 after midnight, session remains open until morning check-in.
5. Morning check-in closes session and Tonight view resets.
6. Missed check-in cutoff auto-closes session and allows a clean next night.
7. Nap Start -> Nap End paired in History; missing end shows "Nap in progress".
8. HealthKit: toggle ON, authorize, force quit, reopen; preference persists and authorization is rechecked.

## Diagnostics

- Logs are written to `Documents/diagnostics/sessions/<session-id>/`.
- See `docs/DIAGNOSTIC_LOGGING.md` for event formats and `docs/HOW_TO_READ_A_SESSION_TRACE.md` for triage.

## State Machines

- Dose flow and session rollover diagrams live in `docs/SSOT/README.md`.

