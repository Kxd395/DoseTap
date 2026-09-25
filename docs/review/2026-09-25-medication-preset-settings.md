# Saved medication setup delivery

Date: 2026-09-25
Plane: DOSETAP-74, B3a
Candidate: 0.4.19 (70)
Baseline: merged main `48ca2d1` / PR #59 / build 69; all three post-merge workflows passed.

## Scope

Settings → Saved medication presets supports oral-solid label setup, exact decimal
components, explicit IR/XR/Other/Unknown release and scheduled/as-needed choices,
reviewed effective dates, and immutable revision history. Save preset only creates
setup, never an administration or night/session/reminder/inventory change. Existing
My Medications picker configuration remains separate. These are patient-entered
label details, not clinician verification.

The latest editable record is the chain leaf, not the largest timestamp. A failed
save freezes its complete command for retry. Return to editing clears that command
and requires fresh review. A stale predecessor gives conflict/reopen guidance rather
than misleading field-validation advice. Read failures block creation/revision.
The retention notice explains independent local history, Clear All/app removal and
separate exported copies. No individual purge or administration Undo is implied.

## Validation and evidence

Core draft tests cover exact decimals, locale separators, invalid/partial/lossy
values, localized decimal digits, unanswered choices, review requirements, effective dates and equal-time
revision ordering. Repository-backed setup tests cover rollback/retry, stable IDs,
fresh review after editing, no-write preview, competing revisions and active-night isolation.
Core: 785 XCTest plus 43 Swift Testing passed. Full native app suite: 523 tests
passed with zero failures. Independent final code review found no remaining blocker.

Native journeys exercise create/save/restart/revise/history at normal and largest
text. Initial runs exposed numeric-keyboard navigation and test hit-target issues;
Done/scroll dismissal and a full-row review checkbox were added. Tests explicitly
verify its Reviewed accessibility value. A dismissible bottom confirmation remains
visible after saving even when the preset list is scrolled. Strength and unit-count
labels remain visible after entry. Tests use short scroll gestures to avoid passing
large-text controls. One retry was stopped while an earlier Xcode run finalized;
final evidence uses serial runs only. Exact final counts and PR/main state are recorded in Plane.

## Open gates and next slice

Signed-phone setup/reopen/export, VoiceOver, privacy and release acceptance remain
open. No phone installation occurred in this run. Preset-based administration
capture, duplicate review, receipts, audited corrections/reversals, retention
controls, liquids/other units and named groups remain separate follow-on work.
DOSETAP-58 daytime observations and licensed ESS remain separate. Existing exports
already retain these preset revisions; setup adds no new schema or report metric.
