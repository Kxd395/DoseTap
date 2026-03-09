## Phase 0: Repo Forensics

* [x] Locate Dose button UI entry point (file, view, control)
* [x] Identify action handler and full call path
* [x] Inventory dose related state fields and persistence keys
* [x] Locate morning survey submission entry point and call path
* [x] Locate any "today" or date boundary logic used for night tracking
  Acceptance:
* Call graph produced for Dose 1 and Dose 2 (`ios/DoseTap/ContentView.swift`, `ios/Core/DoseTapCore.swift`, `ios/DoseTap/Storage/SessionRepository.swift`, `ios/DoseTap/Storage/EventStorage.swift`)
* Rollover call graph produced for morning survey submit (`ios/DoseTap/Views/MorningCheckInView.swift`, `ios/DoseTap/Storage/SessionRepository.swift`, `ios/DoseTap/Storage/EventStorage.swift`)

## Phase 1: Dose Flow State Machine and Bug Root Cause

* [x] Write Dose flow state machine table and ASCII diagram
* [x] Identify exact property causing "Complete after Dose 1"
* [x] Propose minimal fix and list affected files
  Acceptance:
* "Complete" only appears when regimen is actually complete by rules
* Clear user guidance exists for dose 2 at all times

## Phase 2: Implement Dose Flow Fix

* [x] Patch state logic so Dose 1 does not mark regimen complete
* [x] Ensure timer expiry leads to "Ready for dose 2" state, not "Complete"
* [x] Add explicit "Skip dose 2" path if needed with clear UI copy
* [x] Add diagnostic log events for key transitions
  Acceptance:
* Manual test: Dose 1 -> countdown -> ready for dose 2 -> dose 2 -> complete
* Manual test: Dose 1 -> countdown -> expired -> still not complete until dose 2 or skip action

## Phase 3: SleepSession Rollover Model

* [x] Introduce or confirm SleepSession id model with start and end timestamps (`sleep_sessions`, `current_session.session_id`)
* [x] Attach dose events and survey events to SleepSession id (`dose_events.session_id`, `sleep_events.session_id`, `morning_checkins.session_id`)
* [x] Define cross midnight assignment rules and implement them (active session id + session_date reporting)
  Acceptance:
* Doses after midnight can still belong to the prior night session until it is closed
* Day shift reporting remains correct without breaking sleep session identity

## Phase 4: Morning Survey Close and Cleanup

* [x] On morning survey submit: close active session, persist, archive, clear night UI state
* [x] Confirm next night starts clean after submit
  Acceptance:
* After submitting morning survey, evening prep shows no stale night data

## Phase 5: Fallback Auto Close and Soft Rollover

* [x] Implement missed survey cutoff auto close (wake + cutoff hours)
* [x] Implement evening prep soft rollover behavior
  Acceptance:
* If morning survey is skipped, the app still starts clean by prep time

## Phase 6: Settings for Sleep Window and Prep Time

* [x] Add settings: sleep start, wake, prep time, cutoff rule (`UserSettingsManager` + `SettingsView`)
* [x] Use settings in rollover calculations (`SessionRepository.evaluateSessionBoundaries`)
  Acceptance:
* Users with 9 PM to 7 AM schedules do not get midnight rollover bugs

## Phase 7: Tests and Regression Checklist

* [ ] Add unit tests for:

  * Dose state machine transitions
  * Cross midnight assignment
  * Rollover on survey submit
  * Fallback cutoff logic
* [ ] Add integration tests where feasible
* [ ] Validate kill and relaunch behavior
  Acceptance:
* All tests pass locally
* Manual checklist passes on simulator and device

## Phase 8: Docs and README Updates

* [x] Document new session model and boundaries
* [x] Document settings and defaults
* [x] Document fallback behavior and edge cases
* [x] Update README with the new rollover logic and how to test it
  Acceptance:
* docs updated and consistent with code behavior
