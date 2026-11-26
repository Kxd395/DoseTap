# DoseTap SSOT Navigation

Status: Current SSOT index
Last verified: 2026-09-11

This file is a pointer map for the SSOT. The canonical spec lives in `docs/SSOT/README.md`.

On iPhone, Tonight places the Pre-Sleep Check entry immediately before the primary dose action, including its logged/edit state. Preparation precedes taking a dose; quick logs and statistics follow the nightly actions. Log Medication and Daytime check-in are not nightly dose actions; they appear last, under Other records, after the quick log and summaries (DOSETAP-90). When the Dose 2 alarm cannot be confirmed, Tonight shows a full-width warning with Retry Alarm instead of a caption. Optional bottle-opening recording remains available in Pre-Sleep Check. Tonight's Bottle & supply card exposes amount and unopened-stock status plus direct quantity setup/review; it does not record an opening or dose merely by being opened. All five tabs share a native toolbar with theme at the leading edge and current-page capture at the trailing edge. Timeline exposes capture in both Live and Review, even without records. Its separate review-summary capture stays within Review content. Global floating controls must not cover screen content or back navigation. The work-warning sheet separates its dated schedule summary, explicit recording action, and date-only adjustments.

Take Dose 1 presents a native review sheet with occurrence, reminder presets and
an exact alarm preview. Confirmation stays in the bottom safe area while content
scrolls. The saved result separates medication from alarm verification and permits
alarm-only retry/change. An active/unlocked Dose 1 deep link opens this review;
Flic directs the user to review in the app. Neither external action records a dose.

## Quick Links

The nightly alarm indicator is labeled “Dose 2 alarm” to distinguish it from the morning “Wake by” time. Scheduling errors and retry remain visible; internal reconciliation metadata does not occupy the main nightly flow.

Weekly Schedule in Settings owns one draft and explicit Save for recurring wake times, workdays and warning preferences. Fill selected days is optional. Days refer to wake dates; disabled means no wake requirement. Tonight shows a compact effective “Wake by” summary above Pre-Sleep Check. The first Pre-Sleep Check card shows the plan and editable “Just for tonight” override after bottle recording. The nightly override does not change Typical Week. The override and displayed plan use the same pre-sleep display session key. After explicit consolidation, recurring wake preferences are owned by the SQLite work/wake document; SleepPlanStore reads this schedule and retains separate one-night planner overrides; the large planning and override cards are not duplicated on Tonight.

Nightly wake overrides persist in the existing local UserDefaults store under `sleepPlan.tonightOverrides.v1`, keyed by dosing-night date. They survive relaunch; obsolete entries are removed when the displayed dosing night changes. Clearing an override restores the Typical Week wake time, not the overridden time. These planning preferences never record a dose.

- Domain entities and invariants: `docs/SSOT/README.md` (Domain Entities and Invariants)
- Dose flow state machine: `docs/SSOT/README.md` (Dose Flow State Machine)
- Session rollover state machine: `docs/SSOT/README.md` (Session Rollover State Machine)
- Event flow diagram: `docs/SSOT/README.md` (Event Flow)
- Time boundary model: `docs/SSOT/README.md` (Time Boundary Model)
- Storage and persistence: `docs/SSOT/README.md` (Storage and Persistence Truth)
- HealthKit model: `docs/SSOT/README.md` (HealthKit Interaction Diagram)

## Key Source Files

- Dose button actions: `ios/DoseTap/Views/CompactDoseButton.swift`
- Tonight tab: `ios/DoseTap/Views/TonightView.swift`
- Quick log grid: `ios/DoseTap/Views/QuickEventViews.swift`
- Event logger: `ios/DoseTap/EventLogger.swift`
- Session repository: `ios/DoseTap/Storage/SessionRepository.swift`
- Storage core: `ios/DoseTap/Storage/EventStorage.swift` and `ios/DoseTap/Storage/EventStorage+*.swift`
- Dose storage: `ios/DoseTap/Storage/EventStorage+Dose.swift`
- Morning check-in storage: `ios/DoseTap/Storage/EventStorage+MorningCheckIn.swift`
- Check-in submissions: `ios/DoseTap/Storage/EventStorage+CheckInSubmissions.swift`
- Domain core: `ios/Core/DoseTapCore.swift`
- Window calculator: `ios/Core/DoseWindowState.swift`

## Related Canonical Docs

- Database schema: `docs/DATABASE_SCHEMA.md`
- Data dictionary: `docs/SSOT/contracts/DataDictionary.md`
- Diagnostic logging: `docs/DIAGNOSTIC_LOGGING.md`
- Session trace reading: `docs/HOW_TO_READ_A_SESSION_TRACE.md`

## Repository Index

- Project README: `README.md`
- Documentation lifecycle index: `docs/README.md`
- Architecture overview: `docs/architecture/README.md`
- Testing guide: `docs/TESTING_GUIDE.md`
- Feature triage: `docs/FEATURE_TRIAGE.md`
- Work tracking: `docs/PLANNING.md`
- Production readiness: `docs/PRODUCTION_READINESS_CHECKLIST.md`
- Archived point-in-time plans/results: `docs/archive/`

Dashboard opens with All selected: Overview (recorded timing, sleep and WHOOP), Trends (explicit sleep source, comparisons, lifestyle/mood/stress), and Data (coverage, integrations, recent 14 nights, captured metric reference) appear in one scroll. Overview, Trends and Data remain optional filters and preserve the date range. Missing WHOOP, prior-period or timing-group data has an explanatory card rather than silently removing the section. Empty ranges retain Data cards and the metric reference without showing fabricated outcome statistics. Pull-to-refresh awaits data loading; provider errors stay visible.

All, Overview, Trends and Data share the same card implementations and metric definitions. Each exposes the Dashboard colors & missing data explanation. Overview restores build-14 summary coverage/streak/status, Trends restores neutral interval change and paired comparisons, and Data includes each recent night’s coverage.

## Saved medication setup (build 70)

Settings → Saved medication presets → Add medication preset or Revise preset.
Revision history is read-only. Save preset only writes label setup, never a taken
administration. Existing My Medications picker settings remain a separate route.

## Daytime check-in (DOSETAP-58)

Tonight opens the manual Daytime check-in form directly. History → Diary records
→ Daytime check-ins also offers entry. Opening the latest revision exposes
Correct response. Older revisions remain available in the same list.

## Dose controls and alarm screen (DOSETAP-90, DOSETAP-91, DOSETAP-93)

- The dose button's spoken label always contains its visible text; status is its accessibility value. Before the window opens, the button reads "Waiting for Dose 2 window" with "Tap to review an early Dose 2"; a tap starts the existing early-dose warning and records nothing without confirmation.
- Snooze controls name the configured snooze length (1–30 minutes), not a fixed 10 minutes.
- The open-window status shows the alarm target and the window closing time. In the last 15 minutes, one countdown shows the closing time and minutes left in plain wording.
- The in-app alarm screen offers Record Dose 2…, Snooze and Stop Alarm. Record Dose 2… stops the sound and starts the same Record Dose 2 review as the Tonight button; nothing is recorded until the user confirms. Snooze uses the notification snooze policy. Stop Alarm leaves Dose 2 unrecorded. The alarm screen is presented from an observer of the alarm service, so it appears as soon as ringing starts. A Record Dose 2 request from the alarm screen is used once and expires after 10 seconds.
- Tonight shows every Quick Log button Settings allows (16). Labels use scalable text styles; accessibility text sizes use at most three columns.
- First-run setup shows only choices the app applies. Notification sound, auto-snooze and data-retention pickers were removed; setup states that records stay on the device until deleted in Settings.
- The Dashboard WHOOP card says WHOOP is not connected when there is no WHOOP connection, instead of asking for a wider date range.
