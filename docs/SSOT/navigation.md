# DoseTap SSOT Navigation

Status: Current SSOT index
Last verified: 2026-09-30

This file is a pointer map for the SSOT. The canonical spec lives in `docs/SSOT/README.md`.

On iPhone, Tonight places the Pre-Sleep Check entry immediately before the primary dose action, including its logged/edit state. Preparation precedes taking a dose; quick logs and statistics follow the nightly actions. Optional bottle-opening recording remains available in Pre-Sleep Check. Tonight's Bottle & supply card exposes amount and unopened-stock status plus direct quantity setup/review; it does not record an opening or dose merely by being opened. All five tabs share a native toolbar with theme at the leading edge and current-page capture at the trailing edge. Timeline exposes capture in both Live and Review, even without records. Its separate review-summary capture stays within Review content. Global floating controls must not cover screen content or back navigation. The work-warning sheet separates its dated schedule summary, explicit recording action, and date-only adjustments.

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

## Focused dashboard views

Dashboard opens on Session Replay. One view menu selects Session Replay, Interval Explorer, Sleep Opportunity, Medication Explorer, Reviewed Sleep Coverage, Sleep & Naps, Sleep & Dose Pattern, Work Block & Sleep, Context & Morning Outcomes, Daytime Diary, Physician Review, Review Data or Other Recorded Measures. The reporting-period controls remain visible above the selected page. Accessibility text sizes stack the controls vertically without clamping the selected text size.

Replay-related pages and the internal replay mode menu share one model-owned mode. Changing a page only changes presentation: it does not reload sources, reset the reporting period, clear a stable observation selection or invalidate checked sleep coverage. Actual source, selection, cutoff, timezone or provider changes still invalidate checked evidence. A refresh retains stable identifiers while marking filtered or unavailable selections explicitly.

The shared-filter sheet owns sleep source, dose pattern, work phase and planned/confirmed basis, documented context and partial-value inclusion. Resetting filters retains the selected night/provider ID; clearing that ID is a separate action and does not clear an independent nap or daytime selection. Each independent-record view states its own period and filter scope. Night-empty guidance cannot hide daytime, nap, medication or physician records.

Review Data retains source coverage, integrations, provider matching, duplicate review, the metric inventory, local/iPad storage explanation and the color/missing-data legend. Other Recorded Measures retains the trustworthy dose/provider panels and the selected panel when leaving and returning; these panels explicitly describe their whole-period scope. Original morning and pre-sleep questionnaire values remain inspectable with stable source identity and needs-review labels, without inferred confirmation, absence, percentages, averages or paired outcomes from legacy defaults. Provider errors and unavailable states remain visible, and refresh awaits completion.

## Saved medication setup (build 70)

Settings → Saved medication presets → Add medication preset or Revise preset.
Revision history is read-only. Save preset only writes label setup, never a taken
administration. Existing My Medications picker settings remain a separate route.

### Independent daytime diary

History → Daytime check-in opens independent observations, current custom 0–10 entry, explicit remembered entries and correction history. Opening does not create a nighttime session. No score is selected initially; save failure retains the exact pending revision for retry.

## Dashboard reporting period

The phone dashboard's reporting-period menu offers 7/28/90 days, 6/12 calendar months and legacy preset ranges. Custom dates opens one cancellable review sheet with inclusive start, exclusive end and captured timezone; Apply validates before changing the selection. Since last completed visit reads confirmed visit history and directs an empty-history user to Physician review without substituting a booking or a guessed date. The period explanation identifies whole treatment-night membership at the 18:00 rollover, including boundary-night overlap.

## Physician review

The physician-review screen opens a completed-visit history and explicit report-period selection, followed by unscored activity notes and questions. Save and preview persists one immutable snapshot. Saved previews reopen the captured values; corrections generate another preview. The preview contains a separate Share button. Opening or saving never invokes the activity sheet or sends health records.

### Optional daytime reminder

Settings → Daytime reminder provides one explicit Save for the master opt-in, selected weekdays, anchor, saved timezone, quiet hours and independent off-day rule. Clock anchors use a chosen clock time; main-wake anchors use an elapsed-minute offset; work anchors require reviewed shift endpoints or a saved break. “Use current timezone” is an explicit action; travel does not silently replace the saved zone. Enabling requires at least one weekday. Pausing remains available with an empty draft selection and retains the previous valid day selection. Status shows scheduled-through and expandable reasons for unscheduled dates. History keeps original intended time, anchor label and actual assessment time separate. Notification taps open an unanswered current check-in with immutable schedule protocol identity and label.
