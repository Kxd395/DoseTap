# Dose 1 confirmation and tonight's reminder

Status: DOSETAP-71 bounded delivery; acceptance remains open
Version: 0.4.19 (49)
Baseline: main 7d402ff, PR #34, build 48

Take Dose 1 opens review before recording. The user chooses Now or an earlier
occurrence in the current treatment night, one of the existing reminder intervals,
and optionally makes it the usual interval. A clock-time preview follows the
reported occurrence. Choosing an interval or closing the sheet records nothing.
External Dose 1 actions direct the user to in-app review without writing a dose.

The confirmation is single-use and bound to the session and treatment date.
Backgrounding invalidates uncommitted consent. A failed write retains the confirmed
occurrence and selections for explicit retry; it does not update the preference.
Successful medication persistence precedes alarm scheduling. Recording time and
the initial selected interval are additive metadata, independent of occurrence.
A past target may fail alarm scheduling while preserving the reported taken dose.

The persistent bottom confirmation control remains reachable while scrolling.
After saving, the sheet shows the recorded dose separately from verified alarm
status and supports alarm-only retry/change for that still-active dose. Changing
an alarm does not rewrite medication metadata or the usual interval. Alarm options
link to the existing separate test alarm; existing snooze preferences are shown
with a Settings reference. The app does not promise that an alarm will wake someone.

No interval/window changes, dosing recommendations, SQL migration or inferred
medication outcomes are introduced. Existing dose cancellation, manual correction,
provider data, questionnaires and quick logs retain their ownership boundaries.

Exact validation and integration evidence is in the DOSETAP-71 workpad. The first
native run exposed a confirmation control below optional settings and lazy-form
locator assumptions; final evidence must be from the corrected footer and scroll
journeys. Signed-phone locking/ringing/retry, owner acceptance, VoiceOver/full
accessibility, privacy and release acceptance remain separate open gates.
