# Encryption at Rest — Active Boundary and Future Proposal

Status: Current decision; system SQLite is active and SQLCipher is proposal-only
Last verified: 2026-09-02

## Active implementation

DoseTap stores medication, sleep, check-in, and diagnostic records in the app sandbox using the system SQLite library. `EventStorage` opens `dosetap_events.sqlite`; the shipping target has no SQLCipher dependency, no database-encryption key lifecycle, and no alternate encrypted-storage wrapper.

The active boundary is therefore:

- application sandbox isolation and the device's operating-system Data Protection behavior;
- plain SQLite pages managed by `EventStorage`;
- Keychain storage for integration tokens, separate from the database;
- local transactional mutation through `SessionRepository` and `EventStorage`.

The source tree does not claim a specific effective file-protection class for the database. That attribute must be verified on a signed device, including before-first-unlock and locked-device behavior, before a stronger protection claim is made.

## Medication mutation boundary

Database protection and medication safety are separate concerns. Dose 1, Dose 2, extra dose, skip, and snooze actions must enter through `DoseActionCoordinator`, then commit through `SessionRepository` and `EventStorage`. The shipping API client exposes no remote medication mutation endpoints. A network retry queue must never become an alternative medication state owner.

`tools/check_legacy_safety_paths.sh` and `tools/check_dose_state_writes.sh` enforce these source boundaries in CI.

## Retired scaffolding

The former `DatabaseSecurity.swift` and `EncryptedEventStorage.swift` files were inactive scaffolding. They could generate an unused Keychain key and expose SQLCipher-shaped APIs while silently operating without SQLCipher. They were removed from the target and source tree on 2026-09-01 so documentation and compiled behavior no longer imply database-level encryption that is not active.

## Reconsidering SQLCipher

SQLCipher or another database-level encryption design requires a separate, reviewed proposal. At minimum it must define:

1. the threat model and the protection gained beyond the signed-device Data Protection baseline;
2. dependency provenance, version pinning, and release packaging;
3. key creation, accessibility, rotation, recovery, deletion, and lost-key behavior;
4. an atomic, restart-safe migration from every supported plain-SQLite schema;
5. rollback and recovery without data loss or false medication-state success;
6. performance and storage measurements on supported devices;
7. automated corruption, wrong-key, interruption, and restore tests;
8. owner-observed locked-device and before-first-unlock evidence.

Until that proposal is approved and its migration is proven, SQLCipher is not a shipping capability and no production code or documentation should describe it as one.

## Related authorities

- `docs/SSOT/dose-state-persistence.md`
- `docs/architecture/12-safety-sensitive-legacy-retirement.md`
- `docs/archive/architecture/2026-02-16-numbered-reference/05-storage-layer.md` (historical context only)
- `ios/DoseTap/Storage/EventStorage.swift`
- `ios/DoseTap/Storage/EventStorage+Schema.swift`
