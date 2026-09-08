# Dose 2 recording incident — 2026-09-07

Status: In Progress; merge and release remain HOLD
Plane: DOSETAP-46, related to DOSETAP-4, DOSETAP-34, DOSETAP-38, and DOSETAP-42
Checkout: `DoseTap-main`, `fix/locked-dose2-system-alarm`

## Verified evidence and limits

The owner reported that Dose 1 recorded normally, but Dose 2 already appeared recorded when they returned to enter an occurrence roughly two hours later. The connected signed-device installation was version 0.4.17 (19).

Read-only inspection of the app's SQLite database and WAL confirmed a durable prospective `dose2` event, not an alarm target displayed as a dose. The active-session projection agreed with the event. `PRAGMA quick_check` returned `ok`. Matching `dose.action.attempted` and `dose.action.committed` diagnostics identify the `tonight_button` route, shortly after app launch/foregrounding. The later foreground events are consistent with the owner's reported later interaction.

This evidence identifies the recorded entry path. It does **not** establish an intentional gesture or when medication was actually taken. The earlier activation's cause remains unresolved. No medication event was corrected, deleted, inferred, or added on the device. Raw timestamps, device identifiers, database files, and diagnostics are retained only in an owner-accessible local temporary directory, outside Git and the public source audit.

Source tracing found no dose write in AlarmKit's Open DoseTap intent, notification delivery/open/stop, or app foregrounding. Simulator fixtures are excluded from physical-device builds. An initial ordinary in-window Dose 2 action did, however, immediately commit without a separate record confirmation. A regression test reproduced that behavior before remediation.

## Implemented safeguard

Local commit `2f29ff7` contains the safeguard in version 0.4.18 (20). It has not been pushed, merged, or installed on the owner's phone.

- An ordinary Dose 2 request cannot commit. It returns a separate record-confirmation challenge on every entry surface.
- Confirmation is single-use and tied to the active session and its persisted Dose 1 instant. Cancel, dismissal, or inactive/background transitions invalidate it.
- Confirmation rechecks current state, timing, and work-warning policy. It captures a fresh clock instant rather than reusing the earlier request or alarm time.
- Concurrent confirmations cannot create an unconfirmed extra dose, and old consent cannot be replayed after undo or a session change.
- The existing early-dose warning and explicit hold remain a separate confirmation path. Retrospective, work-warning, and extra-dose paths retain their existing checks. A closed window cannot be bypassed using an older in-window prompt.
- The alarm screen identifies itself as a Dose 2 reminder and states that stopping it does not record a dose; its old morning-check-in wording was incorrect.

## Validation

- Before the change: the new no-unconfirmed-write regression failed against the single-tap behavior.
- SwiftPM build and test passed on 2026-09-07: 637 XCTest cases plus 43 Swift Testing cases.
- Full `DoseTap` app-scheme verification passed on 2026-09-07: 325 tests, zero failures, serial execution on the iPhone 17 Pro simulator.
- All three targeted simulator journeys passed on the final code: ordinary Dose 2 cancel/background/explicit-save/restart, work-warning Continue followed by explicit confirmation, and the nonworking-night exception without a dose write.
- Regressions also exposed and fixed canonical millisecond precision after repository reload, and preserved the existing early-dose warning/hold flow. Confirmation identity uses persisted state, not an unpersisted higher-precision clock value.
- SSOT, architecture, dose-write, Plane-workflow, documentation, version, legacy-safety, companion, hygiene, and whitespace guards passed. The app pre-commit hook's unsigned simulator build passed.
- Simulator tests explicitly pin portrait orientation instead of inheriting the previous launch-performance run's landscape state. Portrait is a fixture condition, not evidence of landscape acceptance.
- The broader integration UI suite is not green. Rechecking its two prior failures on 2026-09-07 passed tab-switching stress but reproduced the supply test failure: after the test's `Mark handled` tap, the status still read `Scheduled:` rather than `Handled`. That result does not establish whether the remaining cause is UI interaction or application behavior.

## Open gates

1. Resolve the remaining supply UI failure and rerun the broader UI suite; a passing isolated tab-switching recheck does not close full-suite stability.
2. Verify the changed build on a signed device: alarm open/stop/snooze must not record medication, explicit confirmation must persist exactly once, and the recorded timestamp must survive restart/export.
3. Owner review of the original record and any correction. This change must not silently rewrite historical medication data.
4. Explain the original unexpected activation if further evidence becomes available; the safeguard is not proof of its cause.
5. Finish the prior integration audit's credential incident, canonical security review, protected CI, and exact-item tracker closeouts before merge. All provider, privacy, accessibility, and release-owner gates remain separate.

The new code has not been installed on the owner's phone by this investigation. Passing local tests does not resolve the reported incident or grant release approval.
