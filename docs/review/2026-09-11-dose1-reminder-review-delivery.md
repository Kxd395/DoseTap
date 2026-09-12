# Dose 1 confirmation and tonight's reminder

Status: DOSETAP-71 bounded delivery; acceptance remains open
Version: 0.4.19 (49)
Baseline: main 7d402ff, PR #34, build 48

Take Dose 1 opens review before recording. The user chooses Now or an earlier
occurrence in the current treatment night, one of the existing reminder intervals,
and optionally makes it the usual interval. A clock-time preview follows the
reported occurrence. Choosing an interval or closing the sheet records nothing.
An eligible active/unlocked Dose 1 deep link opens the review directly; Flic directs
the user to review in the app. Neither external action writes a dose.

The confirmation is single-use and bound to the session and treatment date.
Backgrounding invalidates uncommitted consent. A failed write retains the confirmed
occurrence and selections for explicit retry; it does not update the preference.
Successful medication persistence precedes alarm scheduling. Recording time and
the initial selected interval are additive metadata, independent of occurrence.
A past target may fail alarm scheduling while preserving the reported taken dose.

The persistent bottom confirmation control remains reachable while scrolling.
After saving, the sheet shows the recorded dose separately from verified alarm
status, retains an unverified target, and supports alarm-only retry/change for that
still-active dose. Changing
an alarm does not rewrite medication metadata or the usual interval. Alarm options
link to the existing separate test alarm; existing snooze preferences are shown
with a Settings reference. The app does not promise that an alarm will wake someone.

No interval/window changes, dosing recommendations, SQL migration or inferred
medication outcomes are introduced. Existing dose cancellation, manual correction,
provider data, questionnaires and quick logs retain their ownership boundaries.

Local validation on 2026-09-11:

- `swift build -q` and `swift test -q`: 710 XCTest plus 43 Swift Testing cases passed.
- Full `DoseTap` Xcode suite: 447 tests passed. This includes write-failure rollback,
  occurrence/recording separation, all five command surfaces, deep-link review,
  duplicate/stale consent and alarm-only retry after notification permission recovery.
- Six distinct native journeys passed: Dose 1 cancel/background/restart, usual
  preference/save-failure retry, largest text, Dose 2 correction/morning review,
  automatic night-mode wake restoration, and manual appearance override/restart.
  The final three Dose 1 journeys passed together after review corrections.
- Native screenshots were inspected at ordinary and accessibility XXXL text sizes.
  Accessibility intervals use one column; successful save returns the result to the
  top. The simulator was restored to ordinary text afterward.
- Unsigned simulator and signed-device builds passed. Signature verification and
  all four version configurations report 0.4.19 (49).
- Plane workflow, SSOT, documentation, architecture, dose-write, legacy-safety,
  companion-target, repository-hygiene and whitespace checks passed.

Review corrections: eligible deep links now present the review; unverified targets
remain visible; an invalid earlier date stays editable; taken and recorded times
have separate labels. Hosted storage enforcement caught the initial test-fixture
placement; injection now belongs to SessionRepository. Fixed-time transaction tests
set and restore their schedule, and the Dose 2 native review selects its exact
treatment date across the 18:00 boundary. Product rollover behavior is unchanged.

The final review also verifies reminder-only failure/recovery while the wake alarm
remains scheduled, retains the originating surface on write retry, and uses the
confirmed session target for work advisories after reload and in History. Later
snoozes/alarm-only changes do not rewrite the confirmed treatment target.

PR #35 and the DOSETAP-71 workpad retain exact integration/hosted-check readbacks.
Signed-phone install, locking/ringing/retry, owner acceptance, VoiceOver/full
accessibility, privacy and release acceptance remain separate open gates.
