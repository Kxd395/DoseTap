# DoseTap architecture reference

Status: Current architecture index
Last verified: 2026-09-02

This folder contains maintained boundaries and decision records. Hand-written source inventories, screen maps, function lists, line counts, test totals, and broad service snapshots were moved to `docs/archive/architecture/` because they had drifted from the build.

## Current runtime shape

| Component | Current role | Build evidence |
| --- | --- | --- |
| `DoseCore` | Platform-free domain types, policies, time calculations, export helpers, and tests | Root `Package.swift`, `ios/Core/`, `Tests/DoseCoreTests/` |
| `DoseTap` | Shipping local-first iPhone application | `ios/DoseTap.xcodeproj`, `ios/DoseTap/` |
| `DoseTapStaging` | Cloud-enabled validation target, not the shipping sync posture | Xcode project build settings and `DoseTap.Cloud.entitlements` |
| `DoseTapStudio` | Read-only macOS import and insights package | `macos/DoseTapStudio/Package.swift` |
| Companion proposals | Non-shipping watch and widget source retained for design work | `proposals/companions/`, `docs/COMPANION_TARGET_STATUS.md` |

The Xcode project currently exposes `DoseTap`, `DoseTapStaging`, `DoseTapTests`, and `DoseTapUITests`. The repository has no supported watch or widget target.

## Medication mutation path

```text
SwiftUI, Flic, or authorized deep link
  -> DoseActionCoordinator
  -> DoseRegistrationPolicy
  -> SessionRepository
  -> EventStorage transaction
  -> system SQLite
```

No network client, offline queue, watch proposal, widget proposal, or view owns a second medication state machine.

## Data and presentation path

```text
SQLite and external read-only providers
  -> SessionRepository queries and integration services
  -> Dashboard, History, Timeline, and Night Review
  -> explicit export bundle
  -> read-only DoseTapStudio import and analysis
```

Apple Health and WHOOP are external read sources. Source labeling and same-night parity remain acceptance requirements; see `docs/audit/2026-09-01/findings.md`.

## Maintained records

| File | Status | Scope |
| --- | --- | --- |
| `07-api-and-networking.md` | Current reference | Local-first network boundary and inactive API client surface |
| `12-safety-sensitive-legacy-retirement.md` | Implemented; owner review pending | Single medication mutation boundary and retired hazards |
| `13-component-boundaries.md` | Current decision | Responsibility split and migration ratchets |

## Current authority and runbooks

- Behavior and safety: `docs/SSOT/README.md`
- Dose persistence: `docs/SSOT/dose-state-persistence.md`
- Alarm scheduling: `docs/SSOT/alarm-scheduling.md`
- Storage schema: `docs/DATABASE_SCHEMA.md`
- Storage protection: `docs/SSOT/encryption-at-rest.md`
- Companion targets: `docs/COMPANION_TARGET_STATUS.md`
- Testing: `docs/TESTING_GUIDE.md`
- Release findings: `docs/audit/2026-09-01/`

## Maintenance rule

Document stable ownership, invariants, and decisions here. Discover changing counts and target membership from the build instead of copying them into prose. A new architecture claim needs a source path, a check, or a named acceptance gate.
