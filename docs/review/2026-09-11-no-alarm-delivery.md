# No alarm in the Dose 1 review

Status: DOSETAP-71 follow-up; phone and release acceptance remain open
Version: 0.4.19 (50)
Baseline: main 78e4e74, PR #35, build 49

The sixth reminder pill is No alarm, following 3h 45m. Ordinary text places it
beside the last interval; accessibility text retains the existing one-column
layout. Selecting the pill or cancelling the sheet records no medication.
Confirmation explicitly says No alarm. A successful dose save precedes cancelling
and verifying this session's app-controlled Dose 2 wake and window reminders.
The morning wake and unrelated notifications are outside that cancellation set.

No alarm can be tonight-only or saved as the usual reminder choice. It does not
change the global notification preference, usual interval, dosing window or dose
outcome. A failed write retains the choice without changing the preference.
The dose metadata records an explicit false reminder-enabled value and omits an
interval for No alarm. Existing records are not backfilled.

Alarm-only changes can turn reminders off or explicitly back on without another
dose record. Local session-scoped opt-out persists across restart and is honored
by History corrections and alarm reconstruction. Failed cancellation stays visible
and may be retried; reconciliation retries cancellation instead of rearming.
Tonight shows No alarm selected instead of an invented red target time.

Validation evidence is recorded in PR and the exact DOSETAP-71 workpad. Local app
suite: 455 tests passed, including denied permission, write rollback, restart,
explicit re-enable/disable, cancellation races, unrelated reminder preservation,
and failed-cancellation reconciliation. Core tests: 710 XCTest + 43 Swift Testing.
Native normal/largest-text journeys and final signed-build evidence are separate
from phone/owner, VoiceOver, privacy and release acceptance.
