# Dose completion and morning timing repair

Status: Bounded DOSETAP-67 delivery; phone and release acceptance remain open
Version: 0.4.19 (47)
Baseline: main `da45253` (PR #32, build 46)

## Confirmed defects and changes

The morning exception question was enabled whenever Dose 2 was taken, without
classifying its interval. It now uses shared `MedicationTiming` on actual dose
timestamps. A synthetic 170-minute pair shows its interval and an in-window label,
without exception questions. The early/late reason is optional and starts absent;
explicit Unsure is retained. Existing stored reasons are not bulk rewritten.

The coordinator already attempted cancellation after saving a dose. It now shares
verified cleanup with morning reconciliation, including when the subsequent
questionnaire write fails. Cleanup checks active session identity, invalidates
pending scheduling, stops in-app ringing, removes only Dose 2 identifiers, and
reads back the system alarm and pending/delivered notifications. Failed or absent
verification returns a separate warning; it never erases the committed dose.
Morning retry does not repeat the committed medication action. A successfully
saved questionnaire displays any cancellation warning before dismissal.

Close check-in replaces the ambiguous Skip label. It remains dismissal, not a
durable partial save. The form does not claim that drafts survive intentional close.

## Validation

Local validation: 710 core XCTest cases plus 43 Swift Testing cases passed;
241 focused iOS tests passed together after the final live-session ownership guard
review. All three final native UI journeys passed. Simulator and signed
device builds, signature verification, all four app/staging version configurations,
SSOT/docs checks, Plane workflow (15 tests/80 assertions) and whitespace checks passed.
Final hosted integration evidence is recorded in the DOSETAP-67 workpad.
Focused tests cover before-target completion, current/historical session isolation,
failed/ignored AlarmKit cancellation, retained pending/delivered reminders,
questionnaire failure after medication success, successful questionnaire with alarm
failure, unchanged medication on retry, interval endpoints and explicit uncertainty.
Native UI journeys cover normal and largest text plus missing-dose intent.
An initial UI runner failed to launch before testing; an explicit simulator boot
was used for the rerun. Off-screen rendering is not visual acceptance evidence.
The signed app and native screenshots are retained locally under
`DoseTap-main/.build/deliveries/0.4.19-47/`. This is a development-signed artifact,
not a claim that it is installed on the owner's phone. Larger-text legacy option
grids still need layout review; the passing journey does not close that gate.

## Remaining work and acceptance

- Signed-phone build-47 install, in-window logging before the target, sounding and
  snoozed alarm cancellation, background/restart behavior, and exact-night reopen.
- VoiceOver, privacy and release acceptance; source/tests/CI do not close these.
- General morning context defaults, distinct unknown-time outcomes, approximate
  timing bounds, consistent original-entry provenance and session window snapshots.
- Durable partial drafts and explicit skipped-questionnaire semantics.
- Dashboard outcome/interval wording, snooze coverage denominator, eligible Dose 2
  wake-comparison population and hours/minutes presentation.
- Confirmed work-before/work-after schedule cohorts and historical provenance.

The [collected-data inventory and dashboard plan](2026-09-11-dashboard-and-collected-data-review.md)
remains the review catalog. Preserve all Apple Health, WHOOP, questionnaire,
medication and quick-log data. No personal screenshot, private export, historical
skip reclassification, SQL migration or medication-window change is included.

Prior DOSETAP-67 evidence remains in the build-39 save audit, build-40 dose-intent
audit and build-41 symptom validation. Owner reports that build-45 morning edits
persist after restart are user-observed evidence, not build-47 alarm acceptance.
