# DoseTap SSOT Navigation

Status: Current SSOT index
Last verified: 2026-09-02

This file is a pointer map for the SSOT. The canonical spec lives in `docs/SSOT/README.md`.

On iPhone, Tonight places the Pre-Sleep Check entry immediately before the primary dose action, including its logged/edit state. Preparation precedes taking a dose; quick logs and statistics follow the nightly actions. Optional bottle recording is the first item inside Pre-Sleep Check, with no duplicate standalone bottle button on Tonight. Theme and page capture controls occupy separate header positions. History, Dashboard, and Settings expose page capture in their native navigation toolbar; global floating controls must not cover screen content or back navigation. The work-warning sheet separates its dated schedule summary, explicit recording action, and date-only adjustments.

## Quick Links

The nightly alarm indicator is labeled “Dose 2 alarm” to distinguish it from the morning “Wake by” time. Scheduling errors and retry remain visible; internal reconciliation metadata does not occupy the main nightly flow.

Typical Week in Settings owns the recurring wake schedule. Tonight shows a compact effective “Wake by” summary above Pre-Sleep Check. The first Pre-Sleep Check card shows the plan and editable “Just for tonight” override after bottle recording. The nightly override does not change Typical Week. The override and displayed plan use the same pre-sleep display session key. Saved wake preferences and overrides remain owned by SleepPlanStore; the large planning and override cards are not duplicated on Tonight.

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
