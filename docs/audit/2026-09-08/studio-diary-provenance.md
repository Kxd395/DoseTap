# Studio diary provenance and timing exports — September 8, 2026

Status: local implementation verified; integration and release HOLD continues.
Tracker: DOSETAP-45 (analytics), DOSETAP-13 (export evidence), both In Progress.
Baseline: `230dbc2` on `fix/locked-dose2-system-alarm` in `DoseTap-main`.

## Corrections

- Studio wake labels, filters, cohorts and wake-dependent score terms now use a supported recorded Dose 2 diary answer with a Dose 2 record. Legacy alarm-time hints cannot supply that answer. Other and Unknown are not counted as Alarm or Natural.
- Natural-wake scoring requires a recorded Natural/Alarm answer. Rich legacy measurements without that answer cannot produce a natural-wake ranking.
- Recorded following-day Workday, Day off and Unknown take precedence over older schedule context in grouping. Raw imported context remains available separately for review.
- Timing Insight text and comparison CSV now include the collected food and next-day diary fields. CSV labels its score basis `legacy_composite`; the native save action passes the selected redaction settings.
- All four legacy score modes disclose that the personal 0–10 sleepiness rating and estimated sleep after Dose 2 are not included in those scores. The diary reports them separately. This is not validation of the legacy model or a dosing/driving recommendation.
- Removed duplicate matched/excluded exports in the no-outcome path.

No dose-write, alarm, hold-to-confirm, questionnaire input, database or iPhone layout behavior changed in this pass. The iPhone candidate remains 0.4.19 (23). Two pre-existing Xcode project/scheme reorder diffs are excluded.

## Validation

- Regression tests reproduced ignored diary answers, inferred wake labels, day-type precedence and absent timing-export fields before correction.
- Studio: 67 tests passed, zero failures/skips, using the synthetic archive produced by the iOS export tests and an enabled view preview. Log: `/tmp/dosetap-wake-provenance-final.log`.
- Core: `swift build -q && swift test -q`; 655 XCTest plus 43 Swift Testing cases passed. Log: `/tmp/dosetap-wake-core.log`.
- Generic iOS Simulator unsigned build passed. Log: `/tmp/dosetap-wake-ios-build.log`.
- Plane workflow, SSOT, Studio export, questionnaire export, version and document guards plus `git diff --check` passed.

Reproduce Studio tests with `swift test --package-path macos/DoseTapStudio --scratch-path /tmp/dosetap-report-studio-build -q`, setting `DOSETAP_STUDIO_PREVIEW` to a temporary PNG path and `DOSETAP_IOS_EXPORT_FIXTURE` to the extracted synthetic archive described in [build-23 acceptance](build23-acceptance.md). These environment variables enable otherwise optional fixture/preview checks.

## Native acceptance (synthetic only)

An isolated QA app built from the tested Studio binary imported the one-night iOS archive through the native folder picker: 2 events, 1 session, 28 inventory doses. The two expected warnings were no wearable summaries and local-only provider data. No real health data or provider fetch was used.

Library showed Off and Recorded Dose 2 wake Natural, while retaining the conflicting raw legacy Work Night context separately. Recommendation showed the `off__natural` cohort and the legacy-score disclosure. Export preview showed one recorded natural wake and zero recorded alarm/Other/Unknown wakes, plus the food and next-day fields.

Native Save Timing Comparison CSV produced `/tmp/dosetap-ios-roundtrip/timing-wake-20260908.csv`. With clinician redaction enabled it produced `/tmp/dosetap-ios-roundtrip/timing-wake-redacted-20260908.csv`. Both displayed Saved confirmation. Ruby CSV readback verified one row, `legacy_composite`, natural wake, dayOff and sleepiness `0`. Normal output preserved Fried food and its exact timestamp; redacted output left those fields empty. The Export screen was visually inspected. Its displayed 0.4.19 (22) is imported archive provenance, not the installed iPhone version.

## Remaining gates

The earlier [integration readiness audit](../2026-09-05/integration-readiness.md) and [build-23 acceptance](build23-acceptance.md) remain in force. No push, main merge or phone installation was performed.

The original owner-reported dose-recording incident still needs signed-device and owner-observed acceptance. Full final-revision UI testing, accessibility/window sizes, real-bundle reconciliation, live providers, background archive delivery, restore, credential rotation/revocation evidence, protected hosted checks and privacy/release-owner approval remain open. Native synthetic saves do not close those gates.

The bounded wake/day provenance and timing-export mismatch is corrected. Broader legacy composite-score validity and clinical/statistical interpretation remain unvalidated; new diary outcomes are not folded into that score. General Studio window sizing also remains open: at the inspected width the long export-action row extends past the visible edge.
