# Pre-sleep zero-intensity entry preservation

Date: 2026-09-15
Owner: DOSETAP-61
Build: 0.4.19 (58) candidate

## Failure and repair contract

The pre-sleep card projects the highest detailed intensity into the legacy overall pain level. A zero maximum produces None. The same change observer also handled an explicit None selection, so saving a zero-level entry could clear its location, sensations, pattern and notes from the draft. The detail section then disappeared. This is separate from build 57's first-opening editor repair.

The repair retains explicitly reviewed zero-level entries and keeps them visible and editable. Only the overall selector's user action may clear the draft's pain details. Selecting None explicitly keeps the existing clearing behavior and never deletes saved preferences. The UI explains this distinction beside zero-level entries. Existing-night pencil Edit uses the same editor and supports changing a nonzero level back to zero.

The existing source questionnaire, normalized response, derived symptom and Studio export paths already support zero. No SQL migration, medication action, automatic preference update or historical rewrite is needed. A previously erased draft cannot be reconstructed from this repair.

## Validation record

Fresh build-57 post-merge readback: Documentation CI 34913866853, Swift CI 34913867024 and CI 34913866813 all passed on `5d21c3dc24d8898c2f5aa35a3877753eef81ee87`.

The zero-entry native regression saves, edits, completes and reopens the entry, then explicitly clears the nightly observation without deleting the saved preference. The synthetic storage regression checks source, normalized fields, source-derived symptom identity/zero severity and exported raw answers after repository recreation. Final measured results are recorded below and in the exact Plane workpad; planned tests are not passing evidence.

The first attempt on the existing simulator did not launch the test runner, and a screenshot command also stalled. Those task-owned commands were stopped; the existing simulator/data were preserved. A separate iOS 26.5 simulator also stalled before launch. The installed iOS 27 runtime launched the runner and app under Xcode 27, but the test did not reach its interaction assertions. Device Hub displayed Tonight while accessibility interaction failed with AXError.cannotComplete. A temporary no-debugger scheme also stalled before app tests executed. Task-owned attempts were stopped; the cause is not established. These startup attempts are neither product regression evidence nor passing tests.

## Remaining acceptance

Phone installation and owner interaction are separate evidence. Verify a zero-level entry with sensations remains visible after completing and reopening the exact night; check the pencil Edit path and unchanged saved preference. VoiceOver, broader accessibility, privacy and release gates remain open. Largest-text label truncation and broader pain-pattern identity/presence work remain separate DOSETAP-61 follow-ups.

## Candidate status

Build 58 is a draft candidate, not a delivered phone update. The UI repair passed independent source review. Local SwiftPM validation passed 710 XCTest and 43 Swift Testing cases. The signed device build and signature verification passed; all four app/staging configurations agree on 0.4.19 (58).

The new app storage/export test compiles after qualifying the app model as `DoseTap.PreSleepLogAnswers`. Local simulator test execution remains blocked before assertions, so the new storage test and native save/edit/reopen journey are not recorded as passing. Temporary diagnostic schemes are excluded from the change. Hosted checks and exact PR state are recorded in the Plane workpad.

Merge remains gated on simulator interaction proof for the zero-entry path. Build 57 remains the last integrated and installed version; its three post-merge workflows are now verified successful. No phone records were changed during this follow-up.
