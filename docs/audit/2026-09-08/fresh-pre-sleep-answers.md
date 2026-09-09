# Fresh pre-sleep answers: first implementation slice

Date: 2026-09-08
Plane: DOSETAP-51, In Progress
Branch: fix/fresh-night-observations
Candidate: 0.4.19 (26)

## Implemented

New-night carry-forward uses an explicit allowlist: room temperature, noise setup and non-medication sleep aids. It does not copy daily observations, occurrence timestamps, notes or questionnaire dose-plan amounts. "Use room setup" fills unanswered setup fields without overwriting answers already entered. Existing and historical logs retain their stored data; there is no migration or owner-record rewrite.

The UI now says "Remember room setup" and explains which information carries. The current SSOT and supply-reminder contract agree. The remembered preference key is preserved; it now controls only the narrower setup behavior.

Apple Health imports/charts, dose confirmation, alarm policy, session lifecycle and quick logs were not changed.

## Verification

Destination: iPhone 17 Pro simulator, iOS 26.5, unsigned Debug. Tests ran with the two pre-existing Xcode project/scheme edits preserved. Only four app build-number substitutions from the project file are included in this implementation commit.

| Check | Result | Evidence |
| --- | --- | --- |
| New carry-forward regression before implementation | Expected failure: 4 tests, 3 assertion failures | red.log and red.xcresult |
| CheckInCarryForwardTests, SessionRepositoryTests, MedicationMutationTransactionTests | 98 tests passed | green.log and green.xcresult |
| swift build -q and swift test -q | 655 XCTest plus 43 Swift Testing checks passed | core.log |
| Pre-sleep bottle/setup UI journey | Passed; explicit room-setup action, navigation and restart | ui.log and ui.xcresult |
| Full History questionnaire save/edit/restart journey | Passed | ui.log and ui.xcresult |
| Screenshot inspection | New setup copy and reopened History last-food fields inspected | screens/ attachments |
| Plane workflow, SSOT, architecture, dose-write, legacy-path and doc guards | Passed | local tool results |
| App version and compiled Info.plist | DoseTap/Staging Debug/Release and compiled app 0.4.19 (26) | check_app_version and PlistBuddy readback |
| git diff --check | Passed | local tool result |

Temporary run artifacts: `/tmp/dosetap-fresh-night.kbRCDW/`. No full app or full UI-suite run is claimed. The 98 focused app tests preceded the metadata-only build bump; both UI journeys ran on compiled build 26.

## Remaining gates

- DOSETAP-51 still includes substance quantity/time bootstrap, optional unknown-value entry and legacy adapter defaults. These are not fixed by narrowing carry-forward.
- DOSETAP-52 owns the caffeine volume/mass migration. No historical quantities were converted.
- Morning-questionnaire remembered observations need their own scoped audit; this patch does not change them.
- Signed-phone and owner acceptance, VoiceOver/largest text, and broader regression/release/security gates remain open. No phone installation or hosted CI/merge was performed.
- DOSETAP-56..60 are planned, not implemented. Sleep markers, counts, source corrections, daytime observations and clinician reporting remain future work.

## Preservation and rollback

Planning is committed separately. The two existing Xcode project ordering and UI-test scheme edits remain unstaged. A code rollback can revert the implementation commit without touching those user changes; it would restore the old cross-night copying behavior, so it should be reviewed before any phone deployment.
