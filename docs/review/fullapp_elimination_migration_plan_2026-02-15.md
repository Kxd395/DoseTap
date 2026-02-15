# FullApp Elimination Migration Plan (Start)

Date: 2026-02-15
Scope: Remove `ios/DoseTap/FullApp/` by extracting active symbols into non-legacy app modules without behavior changes.

## Current State Verification

Compiled and referenced `FullApp` files (must migrate before delete):
1. `FullApp/SetupWizardService.swift`
2. `FullApp/SetupWizardView.swift`
3. `FullApp/KeychainHelper.swift`
4. `FullApp/DoseModels.swift`

`legacy/` status:
- No `legacy/` directory present in repository.

## Active External Dependencies

- `DoseTapApp.swift` depends on `SetupWizardService.setupCompletedKey` and `SetupWizardView`.
- `SecureConfig.swift` depends on `KeychainHelper.shared`.
- `MorningCheckInView.swift`, `SessionRepository.swift`, and `StorageModels.swift` depend on `SQLiteStoredMorningCheckIn` / `SQLiteStoredMedicationEntry` from `DoseModels.swift`.
- `MedicationPickerView.swift` and `MedicationSettingsView.swift` depend on medication model types that are currently sourced via `DoseModels.swift`.

## Migration Strategy (Atomic Phases)

### Phase 1: Move Setup Wizard module
Destination:
- `ios/DoseTap/Onboarding/SetupWizardService.swift`
- `ios/DoseTap/Onboarding/SetupWizardView.swift`

Rules:
- Keep public/visible API unchanged in first move.
- No behavior changes in onboarding flow.
- Update project references; remove `FullApp` refs for these files only.

Acceptance criteria:
- `DoseTapApp` compiles unchanged behavior.
- `AlarmAndSetupRegressionTests` pass.

### Phase 2: Move Keychain helper into Security
Destination:
- `ios/DoseTap/Security/KeychainHelper.swift`

Rules:
- Keep `KeychainHelper.shared` singleton contract unchanged.
- No key names/service string changes.

Acceptance criteria:
- `SecureConfig` builds and WHOOP token paths compile.
- `HealthKitAndAPITests` and full test bundle pass.

### Phase 3: Split and relocate FullApp models
Destination split:
- `ios/DoseTap/Models/Compatibility/SQLiteEventRecord.swift`
- `ios/DoseTap/Models/Compatibility/SQLiteStoredMorningCheckIn.swift`
- `ios/DoseTap/Models/Compatibility/SQLiteStoredMedicationEntry.swift`
- `ios/DoseTap/Models/Domain/DoseEventType.swift` (only if still needed after conflict check)

Rules:
- Preserve existing symbol names first; refactor names only after all references are stable.
- Avoid introducing duplicate `DoseEvent` symbol ambiguity with Core Data entity classes.
- Keep `StoredMedicationEntry` typealias behavior unchanged.

Acceptance criteria:
- `MorningCheckInView`, `SessionRepository`, and storage models compile.
- `DataIntegrityTests`, `SessionRepositoryTests`, `EventStorageIntegrationTests` pass.

### Phase 4: Remove FullApp group and directory
Actions:
- Remove remaining `PBXBuildFile` / `PBXFileReference` entries for `FullApp/*` in project.
- Delete `ios/DoseTap/FullApp/` directory.

Acceptance criteria:
- No `FullApp/` references in `project.pbxproj`.
- Full `DoseTapTests` suite passes.
- `xcodebuild` app build succeeds.

## Rollout Plan

1. Phase 1 in isolated commit.
2. Phase 2 in isolated commit.
3. Phase 3 in isolated commit.
4. Phase 4 cleanup + full test run + final prune commit.

## Risks to Watch

- `DoseEvent` naming collision between compatibility model and Core Data model class.
- `SetupWizardView` previews/imports after folder move.
- Missed hidden reference in `project.pbxproj` causing compile-source drift.

## Immediate Next Action

- Execute Phase 1 extraction (`SetupWizard*`) in-place with no logic changes and re-run targeted setup regression tests before Phase 2.
