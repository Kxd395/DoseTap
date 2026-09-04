# DoseTap SSOT Navigation

Status: Current SSOT index
Last verified: 2026-09-02

This file is a pointer map for the SSOT. The canonical spec lives in `docs/SSOT/README.md`.

## Quick Links

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
