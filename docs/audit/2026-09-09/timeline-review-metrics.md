# Timeline Review metric correction

Status: Implementation and local validation; integration and phone acceptance tracked in DOSETAP-64
Date: 2026-09-09, America/New_York
Baseline: main `1927dbd`; candidate 0.4.19 (31)

## Scope

Review, Full Review and the review-summary capture share the corrected metric card. It classifies actual dose timestamps with `MedicationTiming`, separates pending, unrecorded, skipped, orphan and conflicting records, and reports bathroom/disruption logs as counts. No awake duration is inferred from event counts. Logged lights-out to final wake remains elapsed time, not measured sleep; missing or reversed markers are unavailable.

The adjacent summary now describes the record instead of suggesting dose or lights-out changes. Accessibility text sizes use one column, with explicit spoken labels for metric values. Apple Health import, stored sleep intervals, medication writes, alarms, questionnaires and exports are unchanged. The simulator fixture is display-only and does not seed the dose ledger.

## Local evidence

- Test-first check failed to compile while the new presentation type was absent. The eight-test suite covers calculations, rendered standard/accessibility cards and full-report raster pixels. An initial broad test import caused a type-name collision; the import is now scoped to DoseTapCore.
- `swift build -q` and `swift test -q`: passed, 655 XCTest cases plus 43 Swift Testing cases.
- `xcodebuild test -project ios/DoseTap.xcodeproj -scheme DoseTap -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath /tmp/dosetap64-fresh -parallel-testing-enabled NO -only-testing:DoseTapTests/TimelineReviewMetricsTests CODE_SIGNING_ALLOWED=NO`: eight passed, zero failed/skipped, iOS 26.5. Bundle: `/tmp/dosetap64-verified.xcresult`.
- Coverage includes 149m59s, 150m, 240m, 240m1s, pending at the inclusive endpoint, unrecorded after it, explicit skip, missing Dose 1, reversed pairs, conflicting outcomes, event counts, ordered rest markers and the repeated DST hour.
- Visual inspection caught truncated accessibility labels and a blank capture preview. The revised card stacks large text and wraps its explanation. Capture now draws into a bitmap graphics context, rejects invalid dimensions and tests the actual render helper. An early clipboard diagnostic required simulator paste permission and is not retained as an unattended test. A stale runner and later simulator installation error are excluded from acceptance; validation moved to a fresh build directory and iPhone 17 Pro Max.
- The focused `DoseTapUITests/testTimelineReviewMetricsAndCapture` test passed on iPhone 17 Pro Max, iOS 26.5. It verifies exact Late status, the displayed interval, accessible log counts, capture preview and Copy feedback. `/tmp/dosetap64-clipped-preview.xcresult` contains the final inspected screenshot: an upright report contained below the preview header. The direct render test retains the full raster image. The first graphics-context render exposed a vertical flip; the corrected transform and preview clipping were rerun and visually checked.
- Generic iOS Simulator build passed with signing disabled. Existing compiler warnings remain; this is not a warning-free or signed-device build claim.
- Plane workflow, SSOT, documentation, architecture, dose-write and repository-hygiene guards passed. The version guard reports 0.4.19 (31) for both app targets and configurations. Whitespace checks passed.

## PR review follow-up

Two review comments arrived before merge: Pending could remain stale on an open screen, and a valid-sized bitmap could still be transparent. Both review screens now supply their cards from one updating clock; saved summaries freeze one generation timestamp. Cards require an explicit timestamp so a caller cannot silently use a construction-time default. Capture checks rendered alpha pixels, preserving black or sparsely painted images while rejecting transparent output. The expanded nine-test suite passed, including these pixel cases, in `/tmp/dosetap64-review-fixed.xcresult`.

Both focused UI tests passed in `/tmp/dosetap64-clock-ui.xcresult`: the original capture/Copy path and the new Pending-to-Not-recorded transition without interaction. Repository guards passed again after these changes. An initial alpha-only graphics-context attempt did not compile with this SDK; the tested implementation uses an explicit RGBA buffer and inspects alpha bytes.

## Preservation and acceptance

Only the four build-number values are staged from `project.pbxproj`. After excluding those intended changes, the original project/scheme diff retains SHA256 `12b4189a22bdd27e51a6185bd5432664d1d686c5e11bb1dc09aa829c4a1f073d`. The scheme changes are not part of this implementation.

Hosted PR checks, merge state and final capture readback belong in the verified Plane workpad. A signed-phone check of Review, Full Review, capture and VoiceOver remains open. DOSETAP-65 separately tracks the legacy `InsightsCalculator` bathroom-count-to-minutes estimate still used by History and the 14-night trend card; this per-night correction does not claim that legacy aggregate is fixed. Existing provider, medication-reliability, privacy and release gates are not closed by this reporting fix.
