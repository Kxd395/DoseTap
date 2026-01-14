<!--
Sync Impact Report:
- Version change: None → 1.0.0
- Modified principles: Initial ratification
- Added sections: All (initial constitution)
- Removed sections: None
- Templates requiring updates: 
  ✅ spec-template.md - Aligned with SSOT-first principle
  ✅ plan-template.md - Aligned with test-first principle
  ✅ tasks-template.md - Aligned with deterministic testing principle
- Follow-up TODOs: None
-->

# DoseTap Constitution

> **Authoritative Governance**: This constitution defines non-negotiable development principles for DoseTap.
> All code, documentation, and practices MUST comply with these principles.

## Core Principles

### I. SSOT-First (Single Source of Truth)

**MUST**: `docs/SSOT/README.md` is THE canonical specification. All behavior, thresholds, states, and contracts are defined there. If code differs from the SSOT, the code is wrong.

**Implementation Requirements**:
- All numeric constants live in `docs/SSOT/constants.json` (machine-readable)
- All API contracts in `docs/SSOT/contracts/`
- All behavior changes MUST update SSOT first, then code
- CI enforces SSOT compliance via `tools/ssot_check.sh`

**Rationale**: Medical software requires absolute clarity. A single authoritative document prevents drift, ambiguity, and contradictions. The SSOT is the contract between stakeholders, developers, and the product.

### II. Test-First Development (NON-NEGOTIABLE)

**MUST**: Unit tests are written BEFORE implementation for all core logic.

**Implementation Requirements**:
- All `DoseCore` (SwiftPM) logic has tests in `Tests/DoseCoreTests/`
- Red-Green-Refactor cycle strictly enforced
- Time injection required: all time-based logic uses `now: () -> Date` parameter
- DST edge cases explicitly tested
- CI blocks merge if tests fail (`swift test` must pass)

**Rationale**: XYWAV dosing is time-critical medical logic. Defects can harm patients. Tests provide confidence and enable refactoring. Time injection ensures deterministic testing across time zones and DST transitions.

### III. Platform-Free Core Logic

**MUST**: `DoseCore` (SwiftPM target) remains completely independent of UIKit/SwiftUI.

**Implementation Requirements**:
- No `import SwiftUI` or `import UIKit` in `ios/Core/*.swift`
- Use `#if canImport(SwiftUI)` guards only in app/UI layer
- Actors for mutable state (`OfflineQueue`, `DosingService`, `EventRateLimiter`)
- Value types preferred for data models (deterministic, testable)
- Protocol-based dependencies for testability

**Rationale**: Platform independence enables comprehensive unit testing, watchOS reuse, potential macOS support, and faster iteration cycles without building the full app.

### IV. Storage Boundary Enforcement

**MUST**: Views access storage ONLY through `SessionRepository`. Direct `EventStorage.shared` access from Views is banned.

**Architecture Layers** (strictly enforced):
1. Views → `SessionRepository` only
2. `SessionRepository` → `EventStorage` only
3. `EventStorage` → SQLite only
4. `SQLiteStorage` is permanently banned (wrapped in `#if false`)

**CI Enforcement**:
- Build fails if `EventStorage.shared` used in Views
- Build fails if `SQLiteStorage` referenced anywhere

**Rationale**: Clean Architecture prevents split-brain bugs and makes state changes predictable. Centralizing storage access through SessionRepository ensures all UI updates are broadcast consistently.

### V. Deterministic Time Handling

**MUST**: All time-based calculations use injected time sources, never direct `Date()` calls in core logic.

**Implementation Requirements**:
- Time injection: `now: () -> Date` parameter in calculators
- All timestamps stored as absolute UTC (ISO8601)
- `session_date` is grouping key only, never used to reconstruct times
- Midnight rollover handled explicitly (interval math treats next-day times correctly)

**Rationale**: Medical dosing timing must be accurate across time zones, DST transitions, and device clock changes. Deterministic time enables comprehensive edge case testing.

### VI. Offline-First with Queue Resilience

**MUST**: All features work offline. Network failures enqueue actions for later retry.

**Implementation Requirements**:
- `OfflineQueue` actor persists failed actions
- Exponential backoff retry with `flushPending()`
- Rate limiting via `EventRateLimiter` (e.g., bathroom: 60s cooldown)
- API errors uniformly mapped via `APIErrorMapper` to `DoseAPIError`

**Rationale**: Users take medication at 3 AM with unreliable connectivity. Critical actions (dose recording, skip) must never fail silently. Queuing ensures eventual consistency.

### VII. XYWAV-Only Scope (Non-Negotiable)

**MUST**: No multi-medication CRUD, refills, pharmacy integration, or provider portals.

**In Scope**:
- XYWAV Dose 1 & Dose 2 timing (150–240 minute window)
- Sleep environment logging (13 event types)
- Morning check-in questionnaire
- CSV export (v1 format)
- Support bundle (with PII redaction)

**Out of Scope**:
- Multi-medication management
- Refill tracking or pharmacy integration
- Caregiver or provider portals
- Payment or subscription features

**Rationale**: Focused scope ensures quality and reliability. XYWAV's strict timing requirements differ fundamentally from other medications. Generalizing prematurely introduces complexity without user benefit.

## Architecture Constraints

### Swift Package Manager (SwiftPM) Structure

- **DoseCore**: Platform-free business logic (no UI dependencies)
- **DoseTap**: iOS app target (SwiftUI views, ViewModels)
- **DoseTapWatch**: watchOS companion (placeholder, Phase 2)

### Persistence Layer

- **ONLY SQLite** via `EventStorage.swift` (no Core Data)
- Schema canonical in `docs/DATABASE_SCHEMA.md`
- Migrations documented in `docs/SSOT/contracts/SchemaEvolution.md`

### Banned Legacy Patterns

- **SQLiteStorage** (wrapped in `#if false`, permanently deprecated)
- **Core Data** (never used, references are legacy only)
- **Direct EventStorage.shared** from Views (CI enforced ban)

## Development Workflow

### SSOT Update Checklist (Always First)

Before any behavior change:
1. Update `docs/SSOT/README.md` for states, thresholds, errors
2. Update `docs/SSOT/navigation.md` if navigation changes
3. Update `docs/SSOT/contracts/*` if contracts change
4. Run `tools/ssot_check.sh` to verify consistency
5. Link exact tests added/updated in PR description

### Typical Slice Workflow

1. **Write failing test** in `Tests/DoseCoreTests/*`
2. **Implement logic** in `ios/Core/*` (platform-free)
3. **Add/extend SSOT docs** reflecting exact UX states
4. **Run `swift test -q`** until green
5. **Update SessionRepository** if state changes needed
6. **Wire UI** consuming `DoseWindowContext` or `SessionRepository`

### Build & Test Commands

```bash
# Core logic (fast iteration)
swift build -q
swift test -q

# iOS app (Xcode required)
open ios/DoseTap/DoseTap.xcodeproj
```

**Known Good State**: `swift build` succeeds, all DoseCoreTests pass (see CI for count).

### CI/CD Requirements

- All PRs MUST pass `swift test`
- SSOT lint checks MUST pass (`tools/ssot_check.sh`, `tools/doc_lint.sh`)
- Storage boundary guards MUST pass (no banned patterns)
- Token/secret detection MUST pass (no committed secrets)

## Security & Compliance

### Secrets Management

**MUST**: All secrets (WHOOP tokens, API keys) stored in Keychain only. Never commit to git.

**Implementation**:
- Remove `Config.plist` from git history if secrets found
- Load at runtime from Keychain
- Graceful fallback when secrets missing

### PII Redaction

**MUST**: Support bundles redact all PII before export.

**Implementation**:
- CSV export includes no device IDs or user identifiers (SSOT v1 format)
- Support bundle redacts tokens, timestamps obfuscated
- Settings export excludes authentication tokens

## Quality Gates

### Pre-Release Verification Checklist

- [ ] Window opens at exactly 150m (test harness)
- [ ] Snooze disabled at exactly 225m (15m remaining)
- [ ] Session survives app termination and restore
- [ ] Export contains expected fields and values
- [ ] Undo works within 5s, fails after 5s
- [ ] History shows correct data, delete removes all traces
- [ ] All DoseCoreTests pass (see CI for count)
- [ ] No tokens in console logs (`OSLog` with redaction only)

### Definition of P0 Bug

Any Product Guarantee violation (see `docs/SSOT/contracts/ProductGuarantees.md`) is a P0 bug:
- Incorrect window timing
- Data loss
- Snooze behavior deviation
- Notification failures (when expected)

## Spec-Driven Development (Spec Kit)

For larger features or architectural changes, use the Spec Kit workflow:

```
/speckit.constitution  → Review project principles (this document)
/speckit.specify       → Write detailed specification
/speckit.clarify       → Ask clarifying questions (optional)
/speckit.plan          → Create implementation plan
/speckit.tasks         → Break into actionable tasks
/speckit.implement     → Execute implementation
/speckit.checklist     → Verify completion
```

Spec artifacts stored in `.specify/` MUST be committed with the feature.

## Governance

### Amendment Process

1. Constitution changes require explicit documentation
2. Version increment per semantic versioning:
   - **MAJOR**: Backward incompatible principle removals/redefinitions
   - **MINOR**: New principles added or materially expanded
   - **PATCH**: Clarifications, wording, non-semantic refinements
3. All dependent templates/docs MUST be updated
4. Migration plan required for breaking changes

### Compliance Verification

- All PRs MUST verify compliance with relevant principles
- Code reviews MUST check for banned patterns
- Complexity MUST be justified against principles
- When in doubt, refer to SSOT first, then this constitution

### Conflict Resolution

- **Constitution > SSOT**: If conflict, constitution wins (but SSOT should be updated)
- **SSOT > Code**: If conflict, code is wrong
- **SSOT > Other Docs**: If conflict, SSOT is authoritative

**Version**: 1.0.0 | **Ratified**: 2026-01-10 | **Last Amended**: 2026-01-10
