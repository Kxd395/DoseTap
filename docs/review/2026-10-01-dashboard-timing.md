# Dashboard timing recovery — 2026-10-01

Tracked by DOSETAP-45, In Progress. Active checkout: `DoseTap-dashboard-recovery`, branch `fix/dashboard-recovery`. The preserved legacy checkout and paused iPad implementation are untouched.

## Requested experience

Restore the full-period interval scatter to the phone landing view. Keep timing-window colors and add a separate work-before-sleep shape dimension. A second view compares recorded main-sleep minutes against dose spacing and explicitly includes confirmed single-dose nights at a labeled category position of zero.

## Data behavior

- By date: every eligible selected-period interval, with the existing inclusive 150–240 minute reference shaded. Shared inspection filters apply; the view is no longer a 14-pair sample.
- Sleep vs spacing: X is actual dose interval, or the separately labeled Single dose category; Y is the selected provider's recorded main sleep. A synthetic category coordinate never becomes a stored zero-minute interval.
- Morning reconciliation's explicit Dose 2 skip plus a recorded first dose on a finished session counts as a confirmed single. Correcting it with an actual Dose 2 time replaces the skip and moves the same observation to the actual interval. Missing Dose 2 alone remains unresolved.
- Work before sleep uses confirmed exact-session work context. Between/after phases imply preceding work; entering/off imply preceding off; missing, stale or ambiguous context remains unknown. Planned rosters alone never establish attendance.
- Blue/purple/orange encode within/below/above reference. Square/circle/diamond encode work/off/unknown. Selection changes marker size. Night Mode uses the existing warm palette, with text labels retaining category identity.
- Selected records show readable date, occurrence times, interval/category, work status and sleep source. Raw IDs, definitions and timestamps remain available under source details.
- Comparison exports preserve interval state/value, add dose pattern/work/single-category fields, and use the same work and bin filters as the detailed chart.

## Verification record

Evidence lives in `.build/dashboard-timing-evidence/`.

- Test-first work mapping failed before its implementation; targeted native work/dose adapter suite subsequently passed.
- The morning-skip integration test exercises real repository reconciliation, refresh and comparison mapping, then corrects the same observation to a 180-minute pair. Missing provider sleep remains missing.
- SwiftPM: 1,191 XCTest and 43 Swift Testing cases passed.
- First UI run: normal landing, return/scroll navigation and single-dose selection passed. Maximum-text landscape caught a count below the initial viewport; moving the count above the controls corrected it in the subsequent run.
- Final native suite: 54 tests passed across dose-pattern, inspection, replay adapters and provider snapshots (`native-final.xcresult`).
- Corrected UI run: four journeys passed, including normal/max-text layout, exact point/table/bin/export identity and single-dose/work filtering (`ui-corrected.xcresult`); screenshots were inspected.
- Build 92 delivery checks and Plane receipts are recorded below when verified. Owner acceptance remains open.

## Recommendation and gates

Continue with the bounded recovery branch rather than rebasing or reverting the entire app to build 88. Keep unrelated feature work preserved. Review the delivered candidate against actual phone records before broader integration.

Simulator fixtures establish rendering and interaction behavior, not real provider data or owner acceptance. Actual-phone usefulness, responsiveness, work associations, accessibility/VoiceOver, provider permissions/coverage, privacy, release approval and inherited feature gates remain open. Physical iPad launch remains deferred.
