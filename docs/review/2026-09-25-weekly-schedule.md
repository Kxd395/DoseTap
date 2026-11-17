# Weekly schedule repair — build 71

Status: Local automated validation passed; phone and owner acceptance open.
Plane: DOSETAP-41. Version: 0.4.19 (71).

## Confirmed defects and correction

The prior screen combined an independently saved work advisory, a temporary
Mon/Wed/Fri template, and immediately saved per-day wake rows. The template did
not retain selected workdays and seeded its summary times from Monday/Sunday.
Disabling a day still produced a hidden 07:30 deadline.

The new screen has one seven-day draft and Save Schedule. Days mean the date of
waking. Work status and required wake are separate; Fill selected days starts
empty and modifies the draft only. No required wake produces no planner deadline.
Back navigation without Save leaves the stored schedule unchanged.

An explicit save adds the weekly planner to the existing SQLite work/wake JSON
in the same revision-checked transaction as working days, timezone, advisory mode
and dated exceptions. Existing preference times remain the initial review input;
legacy warning configuration requires an acknowledgment before consolidation.
Opening alone does not migrate data. Failed/stale saves retain the draft. A
failed read disables saving. The old preference remains preserved but is ignored
by the live projection after a canonical weekly schedule exists.

One-night planner overrides remain independent of dated work-advisory exceptions.
The disabled-day picker uses the treatment night's following wake date without
creating a deadline until enabled. Exports retain effective override time and
local clock minutes, tagged one_night_override instead of inferred work/off.
Current schedule projections do not establish historical work attendance.

No medication, alarm, questionnaire or sleep-evidence record is created by
editing or saving this screen. No SQL column migration or historical rewrite.

## Validation and remaining gates

Validation on September 25, 2026, for the scoped build-71 patch:

- Core: 789 XCTest plus 43 Swift Testing cases passed in both UTC and
  America/New_York. DST gaps/folds, disabled dates and legacy decoding covered.
- Studio: 92 tests executed, 4 skipped, no failures; a one-night override is not
  classified as a recurring work/off/uniform schedule estimate.
- Native iOS: all 527 tests passed, including revision/write failure, canonical
  save/reopen, date anchoring, timezone publication and effective override export.
- Native UI: all 3 journeys passed: normal-size save/reopen, largest accessibility
  text save/reopen, and all 3 work-warning target choices. Both schedule journeys
  include app restart and unsaved edit discard. Screenshots inspected at both
  sizes. Destination: iPhone 17 Pro, iOS 26.5.
- Unsigned iOS Simulator build passed. All four app/staging Debug/Release
  configurations report 0.4.19 (71).
- Plane workflow, SSOT, architecture and dose-write guards, documentation lint,
  and whitespace checks passed.
- Independent code review found date-anchor, effective-export-time and
  timezone-only publication gaps; these were corrected and regression cases added.

Final native evidence:

- App result: `/tmp/dosetap-weekly71/Logs/Test/Test-DoseTap-2026.09.25_17-41-34--0400.xcresult`.
- UI result: `/tmp/dosetap-weekly71-ui-clean/Logs/Test/Test-DoseTapUITests-2026.09.25_17-34-13--0400.xcresult`.
- [Normal text native capture](weekly-schedule-build71/normal.png).
- [Largest text native capture](weekly-schedule-build71/largest-text.png).

The captures contain synthetic simulator settings, not the owner's phone data.
The UI run ends at normal text size; large text is a test configuration.

The initial UI trials exposed partial-row switch taps and stale test-runner
execution. The results above come from the fresh isolated UI build directory.
A missing Combine import in a new test was corrected before the final app run.
Signed-phone review, VoiceOver, timezone travel and the original DOSETAP-41
retrospective/advisory acceptance gates remain open. Build/CI success does not
close them. No phone installation is claimed by this record.
