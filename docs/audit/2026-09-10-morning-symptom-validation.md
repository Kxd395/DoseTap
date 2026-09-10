# Morning symptom selection and save repair

Date: 2026-09-10
Owner: DOSETAP-67; related symptom scope DOSETAP-61
Baseline: `bb3208e45456452c94c0ea87a7d65158081f3f43`, build 40.
Candidate: 0.4.19 (41). Local implementation; integration status belongs in Plane and the PR.

## Changes

- Renamed the physical branch from Physical Pain to Physical Symptoms, matching its existing headache, reflux, stiffness, soreness, restlessness and urgency questions.
- Removed the whole-form requirement for a localized pain entry. The separate pain editor still validates its own entries; an unfilled or cancelled editor does not add one.
- Gated current derived pain burden by physical-section and headache selection. Deselecting Headache excludes its hidden severity/location/migraine-like fields from new or explicitly edited payloads, including the dictionary copied from an existing answer.
- Empty localized-pain lists omit default pain type/intensity. Existing selected pain entries and other symptoms remain intact.
- Kept the same questionnaire storage transaction, retry behavior, History correction path and medication boundary. No old rows are automatically repaired; no schema migration or clinical scale was added.

The legacy normalized `pain.any` key still represents the physical-section flag, not a localized pain count. The existing derived burden and default-origin ambiguity are not a validated clinical measure. Broader fresh-answer and scale/provenance changes remain planned.

## Validation record

Records are synthetic. This run did not read or change personal medication or Apple Health data.

| Command or case | Result |
| --- | --- |
| New repository regressions on baseline | Two test methods failed with 10 assertions: hidden headache data remained in burden, source payload and normalized responses. The six non-localized symptom save/reopen cases were positive storage controls; the blocker was in the UI |
| Baseline `testMorningPhysicalSymptomsWithoutPain` | Reproduced the disabled Complete Check-In button with Headache on and no localized pain entry |
| `DT_SIMULATOR_NAME='iPhone 17 Pro' tools/dt-test all -only-testing:DoseTapTests -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO` | 417 app tests passed on iOS 26.5. Includes six symptom-only round trips, inactive-headache correction, normalized answers and Studio bundle raw-payload/burden checks |
| `swift build -q`; `swift test -q` | Build passed; 682 XCTest plus 43 Swift Testing cases passed |
| `xcodebuild test -scheme DoseTapUITests -only-testing:DoseTapUITests/DoseTapUITests/testMorningPhysicalSymptomsWithoutPain -only-testing:DoseTapUITests/DoseTapUITests/testMorningDefaultDoseIntent -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO` | Two UI tests passed on build 41 in 76.7 seconds. Exported screenshots inspected: Headache selected with no localized entry, enabled Complete Check-In, and unchanged missing-dose behavior |
| `xcodebuild build -quiet -project ios/DoseTap.xcodeproj -scheme DoseTap -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`; `bash tools/check_app_version.sh` | Simulator build passed; DoseTap and Staging Debug/Release all report 0.4.19 (41) |
| Plane workflow, docs, SSOT, architecture, dose-write, legacy-safety and diff checks | Passed locally |

During test authoring, the first two attempts did not compile because the test used the Core record where the app record was required, then attempted a private conversion helper. Tests were corrected to use the existing public repository fetch and distinct synthetic identities before reproducing the baseline assertion failures. Those compiler failures are not product defect evidence.

Local logs use `/tmp/dosetap-symptom-*`. Exported screenshots/manifest are in `/tmp/dosetap-symptom-ui-proof/`; the UI result is `Test-DoseTapUITests-2026.09.10_07-59-45--0400.xcresult` in local DoseTap DerivedData test logs. Hosted checks and merge readback are recorded separately in Plane and the PR.

## Open gates

- Signed-phone and owner confirmation that headache-only and other symptom-only mornings save/reopen correctly and do not trigger repeated check-in prompts.
- Full VoiceOver, largest Dynamic Type and device acceptance.
- Shared recurring patterns in morning, same-area multiple-problem identity, fresh morning outcomes, independent medication actions and durable draft/skip states remain planned. This slice does not close those scopes or the earlier unexpected-dose investigation.

No phone build was installed. Existing unrelated Xcode project/scheme edits are preserved and excluded; only the app build settings are changed in the project file.
