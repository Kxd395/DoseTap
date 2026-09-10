# Pain reuse and morning check-in repair

Date: September 9, 2026
Baseline: `36b54be`, shipping checkout `/Volumes/Developer/projects/DoseTap-main`
Candidate: 0.4.19 (39)
Plane: DOSETAP-61 and DOSETAP-67, In Progress

## Owner report and scope

Recurring back and foot pain should be reusable with a nightly intensity adjustment. Morning check-ins were reportedly still requested after saving. The supplied phone screenshot shows a prior-night reminder and a separately saved pre-sleep entry for tonight. It is not a storage-error dialog and does not establish whether the earlier night has a saved morning record. The installed build and exact phone failure remain unverified; no personal database was edited or copied into this audit.

## Changes

- The live pre-sleep pain editor now offers Remember for future nights before Save. Each saved pattern retains its separate area, side and sensations. Reuse opens with tonight's intensity at the top. Remembering is a preference write, not a symptom log for another night; finish the pre-sleep questionnaire to persist tonight's draft. History and morning editors cannot use the new preference-write control.
- Morning storage now returns the questionnaire transaction's success or failure. A failed source, normalized-submission or symptom write cannot dismiss the form, save preferences, or close its session. The draft and retry guidance remain visible. An explicit medication correction that already committed is not claimed to roll back with a later questionnaire failure.
- New-form retries retain one questionnaire ID. The form's date and identity do not get reassigned to a newly active session. Successful historical writes notify the UI, and Tonight rechecks its older-night reminder when records change.
- Incomplete-night selection recognizes legacy date-keyed morning records only when the date is unambiguous among saved sessions. One date-keyed answer cannot hide two distinct saved session identities. Selection is read-only; no historical rows are rewritten.
- The nonblocking banner says Earlier check-in and names the date whose morning answers were not found. Its accessibility hint distinguishes that morning from tonight's pre-sleep log.
- PR review caught a questionnaire retry repeating medication reconciliation that had already committed. A new regression reproduced changed dose UUIDs/metadata and overwriting a newer correction. The retained form now records successful reconciliation, retries only questionnaire persistence, and replaces medication controls with a saved-status explanation directing further corrections to History. This does not make the two persistence stages atomic.

## Validation evidence

- Test-first morning runs failed to compile against the absent durable result and injectable submit API. The first green storage/pain run passed 93 tests. Expanded app regression passed 409 tests, including injected transaction failure, retained form/error, successful retry with one ID, identity/legacy-reminder checks and standard/largest-text rendering. Result: `/tmp/dosetap-checkin-build39-all.xcresult`.
- Core build passed. UTC and America/New_York each passed 682 XCTest and 43 Swift Testing cases. No core medication policy changed.
- An initial UI command found a pre-existing result bundle and did not run; it was retried with a unique path without deleting the old bundle. The first pain UI attempt failed after restart. A diagnostic rerun showed the automated center tap left the native switch off. Screenshot inspection confirmed its position; the test now taps the visible switch control and asserts its value before Save. The production control was not auto-enabled to satisfy the test.
- The final pain restart UI test passed (1 test, 85.6 seconds; `/tmp/dosetap-pain-reuse-final-ui.xcresult`). Screenshot inspection confirmed separate saved back/foot patterns, tonight's back level at 6/10, and the Update saved pattern action. The test also verifies cancellation, reuse without auto-logging, identity preservation and forgetting a preference without deleting tonight's answer.
- Standard and largest-text reminder/error renderings were inspected. Largest-text controls wrap substantially; these component captures are not a full-screen accessibility or VoiceOver acceptance pass. Workflow, SSOT, documentation, architecture, dose-write-path, version and whitespace checks passed. Hosted and merge readbacks are recorded in Plane and the PR.
- Review follow-up: the medication-identity regression failed before the retry guard (`/tmp/dosetap-medication-retry-red.xcresult`). With the guard, all 410 app tests passed (`/tmp/dosetap-medication-retry-green.xcresult`), including repeated failure and successful retry after a newer medication correction. Workflow, SSOT, documentation, architecture and dose-write guards passed again. PR checks must rerun on the follow-up commit before merge.

## Remaining gates

Exact installed-phone reproduction, owner confirmation, signed-device restart/persistence and VoiceOver remain open. A real earlier night with no morning record should still be offered for review; the repair must not hide all old reminders. Broader morning carry-forward and medication-reconciliation policy remain outside this slice. Saved pain preferences are not a clinical event export or complete backup, and one entry per area/side remains the existing identity contract.

The preserved original checkout and two unrelated shipping Xcode ordering/scheme edits are excluded. Only four build-number changes are included from the project file. No schema migration is required; revert the scoped commit to revert these changes.
