# Component Boundaries and Incremental Extraction

Last updated: 2026-09-01
Status: Current architecture decision; migration remains in progress
Plane: DOSETAP-22 / audit finding DT-AUD-022

## Decision

DoseTap uses responsibility boundaries, characterization tests, and small extraction steps instead of treating a line-count target as an architecture. Large files are migration signals: they may remain temporarily large only when they have one named responsibility, a growth ceiling, and a documented next seam.

The executable contract is `tools/check_architecture_boundaries.sh`. Its ceilings are migration ratchets, not a general rule that a file is well-designed merely because it is shorter.

## Current ownership

| Component | Owns | Must not own |
|---|---|---|
| `ios/Core/TimeIntervalMath.swift` | Absolute timestamp interval calculation and minute formatting for every Apple target | App-specific copies or UI policy |
| `InsightBundleModels.swift` | Studio import/export transport DTOs and backward-compatible decoding | Session scoring, cohort classification, or presentation filters |
| `InsightModels.swift` | An imported Studio session, derived facts, classification, and filtering | Bundle transport schema declarations |
| `SettingsActions.swift` | Notification authorization, opening system settings, and the explicit local-data reset action | Export schema or Studio bundle construction |
| `SettingsStudioExport.swift` | Studio archive orchestration, enrichment, provenance, quality flags, and export DTOs | General settings controls |
| `SessionRepository.swift` | Active-session lifecycle, committed medication-state mutation, finalization, rollover, and destructive reset | View construction or export formatting |
| `SessionRepositoryPresentation.swift` | Read-only dose-window context, phase-edge diagnostics, and quick sleep-event commands | Medication-state persistence implementation |
| `SessionRepositoryDoseEventMetadata.swift` | Deterministic dose-event metadata merge/encoding | Session lifecycle |
| `MorningCheckInDoseAndFunctioningSections.swift` | Quick mode, sleep quality, dose reconciliation, and morning functioning UI | Clinical symptom/environment sections or submission orchestration |
| `MorningCheckInClinicalSections.swift` | Night, work-safety, clinical, symptom, environment, therapy, and narcolepsy UI | Submission controls and shared leaf components |
| `MorningCheckInSections.swift` | Notes, remember-settings, submit controls, and shared section primitives | Domain-specific clinical/dose sections |
| `EventStorage+CheckInSubmissions.swift` | Normalized questionnaire submission transaction and CRUD | Normalized symptom graph persistence |
| `EventStorage+SymptomEvents.swift` | Symptom commands, events, locations, body-map points, summaries, and legacy pain decoding | Questionnaire submission storage |

SwiftPM automatically discovers both Studio model files. The iOS Xcode project explicitly compiles every extracted iPhone source listed by the boundary guard.

## Characterization before extraction

The extraction intentionally keeps behavior in place and moves declarations or extensions across file boundaries. The focused evidence is:

- `TimeIntervalMathCharacterizationTests` fixes the canonical interval and formatting behavior at the shared utility boundary.
- `SessionRepositoryTests` and `MedicationMutationTransactionTests` exercise lifecycle, committed medication mutations, queries, and failure behavior across repository extensions.
- `UIStateTests` and morning-check-in tests exercise section bindings, conditional sections, and submission state.
- `EventStorageIntegrationTests` covers check-in submissions, symptom replacement, idempotency, summary rebuilds, and rollback behavior.
- DoseTap Studio importer, builder, correlation, recommendation, report, and coverage suites compile and exercise the separated transport/session model declarations.

The boundary script adds structural assertions so a later edit cannot silently recreate the duplicate utility or collapse these responsibilities into the former concentration files.

## Independent review and rollback order

Review and, if necessary, revert the slices independently in this order:

1. canonical `TimeIntervalMath` removal plus its focused tests;
2. Studio transport/session model split;
3. settings actions/Studio export split;
4. repository presentation and metadata extensions;
5. morning-check-in UI split;
6. check-in submission/symptom persistence split;
7. structural guard, CI wiring, and this decision record.

No database schema, export schema, public user behavior, or medication policy is intentionally changed by these moves. A rollback should restore both a source file and its matching Xcode project entry; it must not restore the app-local `TimeIntervalMath` implementation.

## Owner-observed architecture review

Before DOSETAP-22 is marked Done, the owner should inspect the slices above and confirm:

- the names and ownership boundaries match how future features will be reviewed;
- internal visibility widened only where a cross-file extension requires it (`lastLoggedPhase` remains module-internal);
- each extraction is understandable and revertible without mixing in a behavior change;
- the remaining large single-purpose files are acceptable migration points rather than a request for a one-shot rewrite.

That review is a human acceptance gate. Passing builds and tests does not substitute for it.
