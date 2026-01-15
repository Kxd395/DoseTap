# Feature Triage

Last updated: 2026-01-14

This is a reality-based feature inventory. Status is based on current code paths, not plans.

| Feature | Status | Value | Risk/Complexity | Decision | Notes / Evidence |
| --- | --- | --- | --- | --- | --- |
| Dose window + Dose 1/2 flow | Implemented | Core | Medium | Ship | `DoseWindowCalculator`, `DoseTapCore.takeDose` |
| Dose index + extra dose (3+) | Implemented | Core | Medium | Ship | `SessionRepository.setDose2Time` |
| Late Dose 2 flag | Implemented | Core | Medium | Ship | `EventStorage.saveDose2(isLate:)` |
| Morning check-in | Implemented | Core | Medium | Ship | `MorningCheckInView`, `SessionRepository.saveMorningCheckIn` |
| Session rollover (prep + cutoff) | Implemented | Core | Medium | Ship | `SessionRepository.evaluateSessionBoundaries` |
| Sleep event logging | Implemented | Core | Low | Ship | `EventLogger`, `SessionRepository.insertSleepEvent` |
| Nap tracking | Partial | Medium | Low | Defer | Paired in History only; no overlap guard |
| Medication logging | Implemented | Medium | Medium | Ship | `MedicationPickerView`, `SessionRepository.logMedicationEntry` |
| HealthKit sleep import | Partial | Medium | Medium | Defer | `HealthKitService` reads sleep analysis only |
| WHOOP integration | Planned | Low | High | Defer | `ios/DoseTap/WHOOP.swift` not wired to UI |
| Cloud sync | Planned | Medium | High | Defer | Specs exist in `specs/002-cloudkit-sync` |
| Export CSV | Implemented | Medium | Low | Ship | Settings -> Export Data |
| Diagnostic logging | Implemented | High | Medium | Ship | `DiagnosticLogger` + docs |
| watchOS companion | Planned | Low | High | Defer | Placeholder target only |
| Flic button integration | Partial | Low | Medium | Defer | `FlicButtonService` exists; verify UX |

