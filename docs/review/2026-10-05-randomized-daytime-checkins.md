# Randomized wake check-ins and quick entry

Status: Implementation evidence; physical and owner acceptance remain open
Date: 2026-10-05, America/New_York
Plane: DOSETAP-58
Checkout: DoseTap-chart-inspection, feat/sleep-chart-inspection
Version: 0.4.19 (101)

## Behavior

An optional Vary check-ins after waking setting preserves existing routines.
Workdays use 2–4, 6–9 and 11–13 elapsed-hour windows; off days use 3–5 and 8–10.
One stable pseudorandom time is selected per window. Main wake must be explicitly
reported; work status comes from the reviewed work document, never weekday guesses.
Separate editable work/off bedtime choices stop reminders two hours before bed.
Quiet hours, known sleep, permissions and other notification owners are preserved.
Unknown evidence stays unscheduled; changing source evidence suppresses remaining
old windows and calls for routine review. Future wakes are never predicted.

A current manual check-in satisfies its window without changing its sampling
origin. Later windows remain independent. An invalid Later action preserves the
queue and explains the unavailable deferral. There are no automatic repeat nudges.

The questionnaire opens with direct 0–10 buttons, an explicit unanswered state,
and toolbar Save. Add details reveals optional context, earlier observations,
source links and event review. Large text changes the grid column count. No answer
is filled automatically. Corrections and exact failed-save retries are retained.

## Validation

- Test-first missing-member compilation: /tmp/dosetap-random-red.log.
- Default-zone and UTC SwiftPM: 1195 XCTest and 43 Swift Testing cases each passed.
- Final service/storage: 44 passed, including invalid-deferral queue preservation;
  /tmp/dosetap-random-service-release.xcresult.
- Normal/largest-text diary save/reopen, source links and failed-write retry passed
  in /tmp/dosetap-random-ui.xcresult. Its initial largest-text reminder assertion
  checked an offscreen row without revealing it; the test was corrected to scroll.
- Final reminder UI: 2 passed, normal15.275s/largest42.712s;
  /tmp/dosetap-random-ui-verified.xcresult. Signed delivery is recorded in Plane.
- Generic simulator and signed builds passed; repository guards passed.

## Acceptance boundaries

Simulator results do not establish actual notification receipt, Focus behavior,
lock-screen privacy, background renewal, VoiceOver or owner usability. No existing
owner routine is silently converted, enabled or assigned guessed wake/work data.
The off-day bedtime is an editable draft default requiring review before Save.
Hosted CI, merge, provider/privacy review and release approval remain separate.
