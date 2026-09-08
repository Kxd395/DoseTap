# Manual history entry and questionnaire corrections

Date: 2026-09-07
Tracker: DOSETAP-47, In Progress
Candidate: 0.4.19 (21), local implementation only
Integration recommendation: HOLD

## What changed

History now has an Add / Correct entry point for the selected treatment night, including an empty date. Existing dose and sleep-event edit buttons use the same editor.

- Add missing Dose 1, Dose 2, explicit missed/not-taken outcomes, extra doses, and sleep/quick-log events.
- Correct actual occurrence times, change a recorded Dose 2 to an explicit not-taken outcome, or remove an erroneous record. Missing and skipped remain different states.
- Require a reason and confirmation for medication changes. Retain previous medication contents and correction chains, including after removal. Export the medication ledger rather than only primary-dose projections.
- Add or edit the full pre-sleep and morning questionnaires for the selected night. Keep occurrence time separate from submission time, retain previous questionnaire rows and normalized submissions, and require a final confirmation.
- Keep questionnaire editing separate from medication reconciliation, wake-plan changes, remembered settings, alarms, and active-session completion. Historical forms cannot log or delete other medication entries.
- Reject stale reviews, ambiguous identities, future occurrence times, conflicting primary doses, and a Dose 2 without an actual Dose 1. A failed transaction does not report success.

Questionnaire correction evidence is visible in History and retained in normalized submissions used by Studio export. Standard medication CSV is not a whole-project backup or restore format.

## Validation record

The implementation followed failing regression tests with fixes. Coverage includes missing-night creation without replacing an active session, rollback, stale review/replay rejection, preserved metadata, skipped-dose amount cleanup, questionnaire conflicts, and invalid times.

- Core: 646 XCTest tests and 43 Swift Testing checks passed in the local timezone and UTC.
- Studio: 55 tests passed.
- App: 334 tests passed after questionnaire storage and form integration, including stable-ID morning readback and rejection of cross-night record-ID reuse.
- Dose/sleep History simulator journey passed after correcting keyboard focus handling and test navigation. It covers cancellation, Dose 1 and Dose 2 creation, extra-dose addition/removal, Dose 2 outcome correction, bathroom notes, and fresh-process persistence. The final records-only run passed on 2026-09-07 at 10:29 EDT (`/tmp/dosetap-history-records-ui-verified.log`).
- The earlier ordinary Dose 2 confirmation journey passed cancellation, backgrounding, explicit save, and restart checks.
- The full-questionnaire simulator journey passed add, cancel, edit, and restart checks. Test navigation uses stable field identifiers rather than a disappearing placeholder, and brings record rows below the translucent navigation bar before tapping. The final questionnaire/Dose 2 run passed 2/2 on 2026-09-07 at 10:32 EDT (`/tmp/dosetap-history-questionnaires-ui-verified.log`), including the keyboard-presentation fix. Together with the records-only pass, all three targeted UI journeys are verified; this is not a full-suite UI pass.

Only synthetic simulator records were used. No phone installation, modification of the owner's medication history, push, PR, or merge was performed.

## Remaining gates

- Signed-device and owner acceptance of medication corrections, both questionnaires, and the Dose 2 confirmation safeguard.
- VoiceOver, largest Dynamic Type, landscape/iPad, and timezone/DST interaction checks for the new forms.
- Ambiguous multiple-session nights require review; this editor does not guess which identity is correct. Removing a Dose 1 with dependent doses or snoozes requires resolving those records first.
- The unrelated supply-reminder UI journey still has a failed Handled-status assertion. Its cause and signed-device acceptance remain open under DOSETAP-30.
- Final security review, credential replacement/old-token rejection evidence, provider revocation, protected hosted CI, and release-candidate preflight remain open. The prior integration decision record still applies.

The branch was current with origin/main at the start of this work, but had 28 unmerged commits. New History commits add to that branch. A clean local test run does not meet the existing conditional merge requirement while integration gates remain open. Plane remains the status authority; this document does not mark DOSETAP-47 Done.
