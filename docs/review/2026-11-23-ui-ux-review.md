# UI/UX review and first fixes — 23 November 2026

Status: evidence record. Plane owns work state.
Source: static review of the iPhone app at `eb5ab14`, then fixes on branch `feat/ui-ux-review-fixes`.

## Findings and owners

| # | Finding | Plane | Result in this branch |
|---|---------|-------|-----------------------|
| 1 | Log Medication and Daytime check-in appeared above the nightly dose action | DOSETAP-90 | Moved to "Other records" after the nightly actions |
| 2 | Pre-Sleep Check inserts Lights Out at the current time, also on Skip; `lightsOut` and `lights_out` names disagree | DOSETAP-94 | Not changed; needs a product decision |
| 3 | Alarm screen offered only Stop Alarm | DOSETAP-90 | Added Record Dose 2… (opens the normal review) and Snooze |
| 4 | Snooze buttons always said +10m | DOSETAP-91 | Labels use the configured length |
| 5 | Setup offered retention, sound and auto-snooze choices that nothing read | DOSETAP-91 | Removed; setup states what the app does |
| 6 | Tonight showed 15 of 16 allowed Quick Log buttons | DOSETAP-91 | Shared limit of 16; 4x4 grid |
| 7 | Check-in forms closed on swipe-down or Close without asking | DOSETAP-92 | Guarded; "Close check-in" renamed "Cancel" |
| 8 | "Waiting..." looked disabled but started the early-dose flow | DOSETAP-91 | Says "Tap to review an early Dose 2" |
| 9 | Spoken dose labels did not contain the visible text | DOSETAP-91 | Label equals visible text; status is the value |
| 10 | Skip, Skipped, Mark missed and D1 Only for related outcomes | DOSETAP-97 | Not changed; terminology decision |
| 11 | Near-close view showed two countdowns, HARD STOP and TAKE DOSE NOW! | DOSETAP-93 | One countdown with closing time, plain wording |
| 12 | Open-window card showed no times | DOSETAP-90 | Shows target and closing time |
| 13 | An unconfirmed alarm was a red caption | DOSETAP-90 | Full-width warning with Retry Alarm |
| 14, 15 | Theme tap cycles on every screen; tab paging and overlapping tabs | DOSETAP-96 | Not changed; SSOT specifies current behavior |
| 16 | WHOOP card asked unconnected users to widen the range | DOSETAP-91 | Says WHOOP is not connected; card kept per Dashboard contract |
| 17 | Morning check-in is long with Submit at the end | DOSETAP-81 | Existing owner; not changed here |
| 19 | Night Mode did not reach sheets or the alarm screen (confirmed on simulator) | DOSETAP-93 | Applied to Tonight sheets and the alarm screen |
| 20 | Reduce Motion and high-contrast helpers had no callers | DOSETAP-93 | Reduce Motion helper now used by 19 animations; `HighContrastColors.swift` still unused |
| 21 | Quick Log text fixed at 8–9 pt; dose button fixed at 50 pt | DOSETAP-93 | Scalable text styles; button grows with text |
| 22 | White on green and colored status text on light cards | DOSETAP-93 | Black on green; status titles use the primary label color |
| — | No Live Activity, widget or Control Center control | DOSETAP-95 | Not started; needs a new target |
| — | Locked-phone alarm test only in Settings | DOSETAP-98 | Not started |
| — | No string catalog | DOSETAP-99 | Not started |

## Evidence

- Simulator observation (iPhone 17, iOS 26.5): before the change, Pre-Sleep Check opened at full brightness in Night Mode. After the change, it uses the Night Mode tint once. With one changed answer, swipe-down kept the sheet open and Skip asked "Skip and discard your answers?". An unchanged form still closed. Morning check-in Cancel asked "Discard your check-in answers?".
- The first attempt placed `interactiveDismissDisabled` inside the NavigationView, and iOS ignored it. It now sits on the outer navigation container.
- Defect found while testing, already present on main: `ContentView` read `AlarmService` through the app container without observing it. Setting `isAlarmRinging` therefore did not redraw the root view, so the in-app alarm screen appeared only after an unrelated redraw. The full-screen cover now sits in a modifier that observes `AlarmService`. After the fix, the alarm screen appeared on every simulator launch with the ringing fixture.
- Two defects in the new Record Dose 2 path were found and fixed on the simulator. A sheet presented while the alarm cover was still dismissing was dropped, so the review now starts from the cover's `onDismiss`. `onReceive` replayed the `@Published` request after each redraw, which reopened the sheet in a loop, so requests are now taken once and expire after 10 seconds.
- Unit tests: `DoseControlCopyTests`, `QuickLogLayoutTests` and `StatusCardCopyTests` and `Dose2ReviewRequestTests`, together with the existing `UIStateTests`, `UISmokeTests` and `HomeStateResolverTests`.
- UI tests: `testDose2ConfirmationFromAlarmScreen` (new, uses the simulator-only `--uitesting-alarm-ringing` fixture), plus the existing journeys that touch moved or renamed controls.

## Open gates

- Signed-device check of the alarm screen with a real scheduled alarm, including that follow-up reminders still fire after Stop Alarm.
- Physical VoiceOver and Voice Control check of the dose button labels.
- Owner design acceptance of the Tonight order, countdown wording and Night Mode sheets.
