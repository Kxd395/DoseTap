# Morning reuse of saved pain patterns

Date: 2026-09-10. Work item: DOSETAP-61, In Progress.
Implementation baseline: `d059bba9e7eef3b6c6051d1ff588ff80c547c08c` in `/Volumes/Developer/projects/DoseTap-main`.
Candidate app: 0.4.19 (45).

## Scope and choice

Live DOSETAP-67/61 workpads confirmed that the prior questionnaire transaction, reminder and bedtime reuse repairs were merged. The owner reported that everything works so far and authorized the next step; no new save failure was reported. IR-08 still had a concrete gap: morning Physical Symptoms could add/edit entries but could not use the bedtime saved-pattern library. This slice adds that explicit access before starting new sleep metrics. DOSETAP-57 remains Todo; DOSETAP-56's projection does not establish full marker acceptance.

## What changes

Open morning Physical Symptoms to see Saved pain patterns. Each card shows the saved area, side and sensations without presenting the saved intensity as a morning answer. Use this morning opens one review. Its intensity starts Not recorded; choose an explicit 0–10 value, review the other details and Save to add the entry to the questionnaire draft. Daily notes start blank. Complete Check-In writes the morning questionnaire through the existing repository transaction.

Cancelling review adds nothing. Using the foot pattern does not add back pain. An already-added area/side directs the user to Edit rather than reapplying that preference. Ordinary editing preserves that morning's existing intensity/notes. Morning and History cannot update or forget preferences, and History does not offer current patterns as historical evidence. Existing bedtime behavior stays intact.

Confirmed entries use the existing source JSON, normalized `pain.entries`, derived symptom and Studio raw-payload paths. No schema, medication, alarm, HealthKit or quick-log ownership changes. Failure retains the confirmed draft for retry; source, normalized submission and symptoms retain their existing atomic write boundary.

This is the existing one-entry-per-area/side library. Stable UUID pattern identity, same-area coexistence, automatic prompts, recurrence phase/scope and independent present/absent/unsure states remain planned. Explicit pain zero with sensations retains the existing field meanings; this is not the full sensory-symptom redesign or a new clinical scale. Preferences remain outside clinical-event exports and the complete-backup claim.

## Verification

- Baseline native UI reproduction failed at the absent morning reuse action after saving bedtime patterns and restarting: `/tmp/dosetap-morning-pain-red.xcresult` (one expected failing test). That confirms the access gap, not a new phone save defect.
- `swift build -q` and `swift test -q`: 699 XCTest plus 43 Swift Testing cases passed. Log: `/tmp/dosetap-morning-pain-core.log`.
- Targeted simulator repository, saved-pattern and export suites: 92 passed, no failures/skips, iPhone 17 Pro / iOS 26.5. Result: `/tmp/dosetap-morning-pain-app-verified.xcresult`. The new integration test covers an explicit zero-intensity foot entry, failed normalized-write rollback, retained retry identity, save/reopen, source/normalized/Studio export parity, unchanged bedtime answers/preferences and medication, and removal of the morning observation and its derived symptom. Initial test-only fixes qualified the app's questionnaire model and compared canonicalized bedtime ordering; these were not product regressions.
- Initial combined UI run: the existing medication-default, symptom-only and bedtime-reuse regressions passed. The new tests identified a missing accessibility value on the intensity picker and premature lookup of lazy Form controls. The picker now supplies its unanswered/selected accessibility value. An intermediate rerun was deliberately interrupted after it reached explicit zero selection but used the wrong notes-control type; it is not passing evidence. The subsequent two journeys passed, but native screenshot review exposed an additional first-open state defect: the saved foot summary could appear above the default back selection. The editor now resets identity when the selected entry or review mode changes. Tests assert selected foot area and numbness on the first review, and the normal-text journey saves directly on that first opening; the largest-text journey also checks cancellation. After the fix, the normal-text journey passed with a direct first-open save (122.888 seconds, `/tmp/dosetap-morning-pain-ui-state.xcresult`). Its native screenshot shows Ankle / Foot selected beneath the matching saved summary. That bundle also contains a largest-text test-gesture failure: swiping downward from the newly opened sheet dismissed it. The corrected largest-text result is recorded separately; the combined bundle is not an overall pass.
- Final largest-text journey passed after the gesture correction: 1 test, zero failures, 241.680 seconds; `/tmp/dosetap-morning-pain-ui-state-large.xcresult`. It verifies first-open area/sensation selection, unanswered intensity, cancellation/reopen, explicit zero, fresh notes, one independent morning entry and successful submission. Teardown restores the normal app text category. Together with the separately passing normal-text journey, this validates the final app source; it does not close VoiceOver acceptance.
- Local Plane, SSOT, documentation, architecture, dose-write, legacy-safety and whitespace guards passed.
- `check_app_version.sh`: DoseTap and DoseTapStaging, Debug and Release, all report 0.4.19 (45). Signed iOS build succeeded in isolated `/tmp/dosetap-morning-pain-device`; signature verification passed. The final signed artifact was refreshed after the editor-state fix and verified with `codesign --verify --deep --strict`: `/tmp/dosetap-morning-pain-device/Build/Products/Debug-iphoneos/DoseTap.app`. A signed local artifact is not an installed-phone or release acceptance result.

Commands use `tools/dt-test` with isolated DerivedData `/tmp/dosetap-morning-pain-build`, serial execution and `CODE_SIGNING_ALLOWED=NO`. No concurrent build uses this directory. Screenshots come from native simulator interaction, not off-screen rendering.

Protected Xcode edits were compared with their original patch after removing only the four intentional 44-to-45 build increments. Original patch SHA-256: `4a7607f2b7124ea4e2ad83927b8d6783f1ee76bbe3a09a6e2add80f6edf6c4e1`. The scheme, unrelated project edits, `docs/review/icon/` and preserved legacy checkout are excluded from this delivery.

## Build 44 phone checkpoint

All three post-merge workflows for `d059bba` passed, including previously pending CI run `34555205230`. A read-only device-app query confirmed `com.dosetap.ios` version 0.4.19, bundle version 44 installed on the paired iPhone. The owner said, “I think everything works so far.” This is general feedback and installed-build identity, not a performed exact-night questionnaire checklist. No phone app was installed, launched or modified by this run.

## Open acceptance

Build 45 signed-phone installation and owner-observed morning/bedtime reuse, save/reopen/restart remain open. Native largest-text results do not close VoiceOver or full accessibility acceptance. Privacy/release acceptance for symptom and sleeping-context data remains separate. DOSETAP-70 retains exact-night sleeping-setup acceptance despite verified build-44 installation. Existing medication/alarm/background/provider and complete-backup gates are unaffected.

Next owner check: on build 45, use only the foot pattern in morning, choose a fresh level, complete the check-in and reopen that night. Verify the back entry was not added and bedtime/saved patterns stayed unchanged. If no further reproducible integrity defect appears, the next engineering slice can begin DOSETAP-57 read-only metrics on the reviewed-night projection with explicit missingness and conflicts.
