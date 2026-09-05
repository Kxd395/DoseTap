# Supply reminder implementation evidence

## Status

- Scope: user-authorized improvement of the missing local order reminder.
- Baseline: clean `DoseTap-main`, main `5d1fa4b48bec00007a0b6f8327a8edee7b096569`.
- Branch: `feat/local-order-reminder`; preserved `/Volumes/Developer/projects/DoseTap` is untouched.
- Plane: DOSETAP-30 preflight confirmed Backlog. State mismatch reported; user explicitly requested implementation. Closeout will retain physical/owner gates.
- Completed: source review, actual UI/storage/notification call-path review, current remote main readback, feature contract.
- Remaining: core fixtures, SQLite persistence, verified isolated notification reconciliation, UI and lifecycle wiring, checks and simulator evidence, Plane readback.
- Next step: implement and test the deterministic manual-date record, then persistence.

## Findings and decisions

- SUP-A01 (confirmed): the existing Next Refill snapshot date saves to SQLite only; it schedules no notification. Fix with a separately labeled order-reminder workflow.
- SUP-A02 (confirmed): the old inventory forecast is pure/disconnected, and the referenced proposal is explicitly superseded. Do not wire unconfirmed quantities into an alert.
- Decision: no dependency upgrade or rewrite is needed. Use existing SQLite, SwiftUI and notification boundary.
- Decision: preserve snapshot dates as historical notes, never auto-convert them into reminder intent.
- Owner clarification: manually enter last received date; remind 21 calendar days later. Add optional Started a new bottle action on Tonight. Bottle starts do not move reminder dates.
- Open gates: signed-device notification delivery, owner copy/privacy acceptance, assistive-technology review. No production/user database migration or deployment is authorized by this work.

## Action log

- Added this evidence record and `docs/SSOT/supply-reminder.md` before behavior changes.
