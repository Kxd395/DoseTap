# Dose 2 wake selection and outcomes — 2026-09-07

## Scope and authority

Implementation checkout: `/Volumes/Developer/projects/DoseTap-main`, branch `fix/locked-dose2-system-alarm`. The preserved `/Volumes/Developer/projects/DoseTap` checkout is not a second shipping authority. Its private drafts and dirty worktree were not transferred. The two existing project/scheme reorder diffs in the implementation checkout remain excluded from commits.

Plane work: DOSETAP-49, High, In Progress; timing reconciliation: DOSETAP-15, High, In Progress. Both were read before implementation. This evidence does not close the existing integration HOLD.

## Delivered behavior

- The ordinary Dose 2 confirmation presents checkbox-style **Woke naturally** / **Woke to an alarm** choices. They are mutually exclusive and initially unanswered. Cancelling or backgrounding does not save the choice or record a dose. Selecting a box never records medication.
- An explicit confirmation commits Dose 2 and its selected answer in one SQLite transaction. Early confirmation retains the three-second hold; cancellation, dismissal and backgrounding stop the hold timer. Late/retrospective entry also offers the choice and retains the actual occurrence time independently of the assessment/entry time. Historical entry uses stable session identity.
- The morning questionnaire and History review the same `night_outcome.v1` answer. The final morning awakening question remains separate. The old morning-only Dose 2 wake field is no longer the visible editor and is not used to infer the new comparison groups. Historical legacy answers are retained, not rewritten.
- The full diary supports Natural, Alarm, Other and Unknown, plus independent backup-alarm status and following-day Workday / Day off / Unknown. Natural waking before a backup alarm stays Natural.
- Next-day sleepiness is a personal 0–10 diary rating with an assessment timestamp and final awakening. It is not a validated clinical score. The older 1–5 question is not converted. New unanswered fields can be added later; corrections to answered fields require a visible reason and retain prior values. Save failures leave the form open with an explicit alert.
- Estimated sleep after Dose 2 sums recorded asleep intervals between actual Dose 2 and final awakening. Intervals are clipped and unioned; recorded awake intervals override asleep intervals. Missing coverage is not invented. Valid all-awake coverage can produce zero. WHOOP aggregate totals are not substituted for missing sleep-stage segments.
- Dashboard comparison uses explicit Natural / Alarm groups, medians, a usable observation count beside every outcome, optional middle-50% ranges, day-type filtering, visible Other / Unknown counts and data notes. Timing/status counts remain independent of the narrower outcome filter. Taken, explicitly skipped and unrecorded are distinct.
- History's Natural Wake percentage no longer treats zero snoozes as proof of natural waking. Unknown answers are excluded from its denominator; no explicit answers displays “No data yet.”
- Existing Quick Log events and automatic Night Mode remain available. This work does not change the owner's medication history, install a phone build, or assert that the earlier unexpected Dose 2 activation has been explained.

## Timing contract reconciliation

The owner explicitly requested the inclusive four-hour endpoint. This supersedes the earlier exclusive-240 contract recorded on DOSETAP-15. The [current XYWAV prescribing information](https://pp.jazzpharma.com/pi/xywav.en.USPI.pdf), sections 2.2/2.3, describes a 2.5-to-4-hour second-dose interval. The shared implementation now classifies actual elapsed time as early below 150 minutes, within-window from 150 through 240 inclusive, and late above 240. Exactly 240 is not late; 240 minutes plus a fraction of a second is late. Invalid/reversed timestamps remain invalid, not a wrapped interval. Tests and SSOT conditions were reconciled together; no new “better before 165 minutes” claim is made.

## Validation

- `swift build -q && swift test -q`: 652 XCTest cases plus 43 Swift Testing cases, passed. `/tmp/dosetap-checkbox-core.log`.
- `TZ=UTC swift test -q` and `TZ=America/New_York swift test -q`: 652 + 43 each, passed. `/tmp/dosetap-checkbox-core-utc.log`, `/tmp/dosetap-checkbox-core-ny.log`.
- `swift test -q --package-path macos/DoseTapStudio`: 55 XCTest cases, passed. `/tmp/dosetap-checkbox-studio.log`.
- Full unsigned `DoseTap` app scheme on iPhone 17 Pro, iOS 26.5: 347 tests, passed. `/tmp/dosetap-checkbox-full-app.log`. Includes persistence, rollback, stale correction, actual occurrence and per-outcome analytics tests. The final early-hold dismissal guard is additionally compiled by the subsequent UI build.
- `DoseTapUITests/testDose2ConfirmationCancelBackgroundAndExplicitSave`: 1 end-to-end test passed, including mutually exclusive checkbox choices, cancel/background non-recording, committed answer after restart, correction reason, later timestamped sleepiness, and the same answer reviewed from the morning questionnaire. `/tmp/dosetap-checkbox-ui-v6.log`. Earlier failed automation attempts are retained and are not counted as passes.
- Final `DoseTapUITests/testDashboardWakeComparison`: 1 test passed. `/tmp/dosetap-checkbox-dashboard-ui.log`. Visually inspected final grid and independent sample counts: `/tmp/dosetap-checkbox-dashboard-proof/712B2E0A-C574-4462-9992-17BA51E80F07.png`.
- Visual inspection of the final simulator attachments confirmed checkbox layout and the separate morning/second-dose wake questions: `/tmp/dosetap-checkbox-final-proof/7CDA2AC1-0C44-4F03-A907-140C9B7F70A6.png` and `/tmp/dosetap-checkbox-final-proof/4C6848EA-FC9F-472B-8F77-11C7E181E1B0.png`. Earlier comparison-card visual proof: `/tmp/dosetap-wake-dashboard-proof-v2/9C2B9C87-1395-47D3-AE5A-3A7CD908CEFC.png`.
- Plane workflow (10 tests/64 assertions), SSOT, architecture, dose-write boundaries, version 0.4.19 (21), documentation, legacy safety, repository hygiene and companion-target guards passed. `git diff --check` passed. Git's dangling objects were informational and were not removed.

## Failed attempts and limits

The initial new SwiftPM test file was not in the explicit package sources, producing a zero-test run; membership was corrected before counting evidence. UI correction validation initially appeared below the visible area; the required reason now appears near the top with an explicit failure alert. A full app run exposed fixed-clock tests consuming persisted prep/wake settings; fixtures now pin and restore them. The storage extension exceeded its 300-line architecture ceiling and was split into its own target member.

A new atomic-write test caught the wake write before the Dose 2 insert; moving it after the insert inside the same transaction restored the full 347-test pass. Earlier batched UI attempts could not launch after the built simulator app disappeared; those attempts are not counted as functional passes. Subsequent tests use an isolated derived-data folder and retain individual-case results.

Morning-review automation also encountered the identical History button behind the questionnaire and gestures that could open the editor while revealing the card. The morning control now has a distinct accessibility identifier, and the test recognizes an already-open editor instead of scrolling over its hidden parent. A separately attempted new test selector executed zero cases and is not counted; the verified journey uses the established Dose 2 test entry point. Live simulator inspection confirmed the saved Alarm answer in the editor presented from the morning questionnaire.

## Open gates and follow-up scope

- Signed-phone and owner acceptance: ordinary, early-hold and late-entry wake choices; restart, overnight suspension and alarm interactions; actual morning/History corrections. The original unexpected Dose 2 activation remains unresolved under DOSETAP-46.
- Actual HealthKit stage/final-awakening and WHOOP source parity across real nights; partial coverage interpretation; export/Studio readback; daylight-saving travel and clinical/provider review.
- VoiceOver, maximum accessibility text, smaller phones, iPad/landscape and complete Night Mode contrast/readability.
- Full broader UI-suite closure (including the separately tracked supply-reminder failure), sealed final security review, credential rotation and old-key/provider-revocation readback, protected hosted checks, privacy/legal/release-owner acceptance. No push or main merge.
- Not implemented in this slice: optional separate morning grogginess 0–10, dated Epworth assessment, matching dose-amount / similar-interval filters, or the independent last-dose-to-planned-driving/hazardous-work readout. No “safe to drive” claim or derived safety score was added.

The dashboard skill informed source grain, missingness, usable sample counts, filtering and visual QA; the destination remains the existing native app. No website or external analytics publication was created.
