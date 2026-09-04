# 12 — Safety-Sensitive Legacy Retirement

Status: **Implemented; owner architecture review pending**
Decision date: 2026-09-01
Last verified: 2026-09-02
Plane: DOSETAP-19 / DT-AUD-019

## Decision

DoseTap has one medication action boundary: `DoseActionCoordinator` applies the canonical registration policy, then `SessionRepository` and `EventStorage` perform the durable local transaction. UI, Flic, deep links, network clients, compatibility objects, and retry queues may not create a second medication mutation path.

The following inactive or conflicting surfaces are retired:

- public `DoseTapCore.takeDose`, `skipDose`, and `snooze` methods;
- writable medication-state properties on `DoseTapCore`;
- remote `/doses/take`, `/doses/skip`, and `/doses/snooze` client endpoints;
- the `DosingService` medication retry façade;
- the conflicting `TimeEngine` and `SimpleDoseWindowState` model;
- inactive `DatabaseSecurity` and `EncryptedEventStorage` scaffolding.

`DoseTapCore` remains a read-only observable compatibility view over repository state. Its public cross-module bridge accepts `DoseTapSessionStateProviding`, which contains observation state only and has no mutation requirements. Canonical dose-window decisions remain in `DoseWindowCalculator` and `DoseRegistrationPolicy`.

## Why

Dead safety-sensitive APIs are still hazards: a future call site can compile and bypass confirmation, timing, transaction, alarm, undo, and failure semantics. A remote retry can also replay a medication mutation after the local context has changed. Conflicting time models make exact 150-minute and 240-minute boundaries ambiguous. Inactive encryption APIs make the shipped protection boundary appear stronger than it is.

Removing those surfaces makes an invalid architecture fail at build or CI time instead of relying on developers to remember which public API is safe.

## Enforcement

`tools/check_legacy_safety_paths.sh` fails when retired source or symbols return, when a remote medication endpoint appears in shipping source, when `DoseTapCore` regains writable medication state or its retired networking initializer, or when retired files return to Package.swift or the Xcode project. It also runs the canonical dose-write call-site guard.

Characterization remains in the canonical suites:

- `DoseRegistrationPolicyTests` for eligibility and boundaries;
- `DoseActionCoordinatorClockTests` for action-scoped time;
- `MedicationMutationTransactionTests` for durable typed outcomes;
- `DoseWindowStateTests`, `DoseWindowEdgeTests`, and `SSOTComplianceTests` for timing semantics;
- API client tests for the two remaining non-medication endpoints only.

## Reintroduction rule

A future off-device medication feature requires a new architecture decision. It must preserve the local coordinator as the safety authority, define idempotency and replay semantics, handle conflicts and offline state, preserve transactional/alarm failure behavior, update privacy and API contracts, and pass signed-device review. Restoring a retired file or endpoint is not an acceptable implementation shortcut.

## Rollback

This structural change can be reverted by restoring the removed files and project references, but doing so reopens DT-AUD-019. Do not restore only the public mutation APIs: that would recreate the bypass without a complete integration design.
