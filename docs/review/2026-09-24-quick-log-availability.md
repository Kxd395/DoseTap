# Quick-log availability and cooldown feedback

Date: September 24, 2026
Plane: DOSETAP-72, In Progress
App: 0.4.19 (65)
Baseline: main `b015297`, build 64

## Owner report and findings

The owner reported recurring untappable Bathroom and other quick-log controls,
possibly before the dosing window, without a known exact night or screen.
Read-only phone metadata confirmed build 64. Its saved Bathroom and Water waits
were both 30 seconds; no phone preference or clinical record was edited.
Only the relevant cooldown values were retained from the temporary preference
inspection, outside Git and Plane.

Source review found no Dose 2 window gate on Tonight's or Timeline Live's
quick-log buttons. They used separate 0.1-second progress timers while evaluating
disabled state directly from Date. A saved event disables only its own type
for the configured duplicate-tap wait. A pending failed write has separate
retry/discard guidance. Medication writes have a different owner.

The baseline native test successfully logged Bathroom while Dose 2 was waiting,
then failed the new assertion requiring readable cooldown feedback. This proves
missing feedback, not the exact cause of the owner's intermittent lockout.
Do not describe the report as a confirmed medication-window bug or a resolved
phone failure.

## Bounded change

Both quick-log grids now share a date-driven TimelineView button. Its enabled
state, progress ring, visible Wait Ns label and accessibility value use the same
cooldown deadline. Foreground return recalculates against the current time.
The full label column has a rectangular tap target. The logger still rechecks
its own cooldown and acknowledges success only after persistence.

Native screenshot review found that using the event's blue/green color made the
new wait label too dim under automatic Night Mode. Wait text now uses the primary
text color; the existing time-since badge retains its color. The screen's other
Night Mode contrast and full accessibility review remain separate.

This changes neither event cooldown settings nor medication timing, alarms,
SQLite schema, history or exports. It creates no doses and does not allow a
failed write to publish success. The fixture that seeds an early-session Dose 1
is restricted to DEBUG simulator builds.

## Validation and acceptance

- Core: 748 XCTest and 43 Swift Testing cases passed; swift build passed.
- Baseline native test: expected failure at the missing wait-value assertion,
  after Bathroom logging succeeded before the Dose 2 window.
- Three native UI journeys passed again on the final wait-color adjustment:
  before Dose 1; before Dose 2's window; largest-text save-failure/retry.
  They cover independent Water availability, background/foreground cooldown
  expiry, another Bathroom log and Timeline Live's equivalent control.
- All 80 repository tests passed, including five persisted quick logs before
  Dose 1 and before the Dose 2 window, an independent Water cooldown, duplicate
  rejection, and only the explicitly seeded Dose 1 medication row.
- Simulator and signed-device builds passed; strict signature verification passed.
  All four app/staging configurations identify build 65. Native final screenshots
  confirm primary-color wait text on Tonight and Timeline Live in Night Mode.
- Plane workflow (15 tests, 80 assertions), SSOT, architecture, documentation and
  whitespace checks passed. USB update without uninstall/reset succeeded, and
  independent installed-app metadata confirmed 0.4.19 (65). This is installation
  evidence; real-night owner recurrence acceptance remains open.
- Independent source review found no blocking issue and retained the exact-cause
  caveat. Personal phone records were not used as test fixtures.

DOSETAP-72 remains In Progress until owner recurrence acceptance is available.
The next real-night check should establish whether an untappable control shows
Wait Ns, whether it becomes available after that wait, which screen is affected,
and whether the rest of the app responds. Do not create a fake clinical event
just to exercise the control. VoiceOver, broader accessibility, signed-phone
behavior and release acceptance are separate from simulator proof. Integration
and hosted CI are recorded in the exact Plane workpad.
