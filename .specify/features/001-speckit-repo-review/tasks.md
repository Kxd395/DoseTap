# Tasks: Repository Health & Constitution Compliance Review

**Input**: Design documents from `.specify/features/001-speckit-repo-review/`
**Prerequisites**: plan.md (required), spec.md (required for user stories)

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)

---

## Phase 1: Verification Infrastructure (Complete)

**Purpose**: Establish verification baseline

- [x] T001 [US2] Run `rm -rf .build` to clear stale module cache
- [x] T002 [US2] Run `swift build` to verify clean build
- [x] T003 [US2] Run `swift test --parallel` to verify all 277 tests pass
- [x] T004 [US3] Run `./tools/ssot_check.sh` to verify SSOT integrity
- [x] T005 [US3] Run `./tools/doc_lint.sh` to verify documentation accuracy

**Checkpoint**: ✅ All automated verification passed

---

## Phase 2: Constitution Compliance Audit (Complete)

**Purpose**: Verify each of the 7 constitution principles

### Principle I: SSOT-First

- [x] T006 [P] [US1] Verify `docs/SSOT/README.md` exists and is canonical (2309 lines)
- [x] T007 [P] [US1] Verify `docs/SSOT/constants.json` exists (603 lines)
- [x] T008 [P] [US1] Verify `./tools/ssot_check.sh` passes (15 components, 9 sections)

### Principle II: Test-First Development

- [x] T009 [P] [US1] Verify test files exist in `Tests/DoseCoreTests/` (18 files)
- [x] T010 [P] [US1] Verify test count (277 tests)
- [x] T011 [P] [US1] Verify time injection pattern in calculators (`now: () -> Date`)

### Principle III: Platform-Free Core

- [x] T012 [US1] Grep for `import SwiftUI` in `ios/Core/*.swift`
- [x] T013 [US1] Grep for `import UIKit` in `ios/Core/*.swift`
- [x] T014 [US1] Verify all UI imports use `#if canImport()` guards

### Principle IV: Storage Boundary

- [x] T015 [US1] Grep for `EventStorage.shared` in View files
- [x] T016 [US1] Verify `SessionRepository` facade exists
- [x] T017 [US1] Verify `SQLiteStorage` is marked `@unavailable`

### Principle V: Deterministic Time

- [x] T018 [P] [US1] Verify `DoseWindowCalculator` uses time injection
- [x] T019 [P] [US1] Verify `TimeCorrectnessTests.swift` exists with DST tests

### Principle VI: Offline-First

- [x] T020 [P] [US1] Verify `OfflineQueue.swift` exists in `ios/Core/`
- [x] T021 [P] [US1] Verify `OfflineQueueTests.swift` exists

### Principle VII: XYWAV-Only Scope

- [x] T022 [US1] Verify no multi-medication CRUD features
- [x] T023 [US1] Verify SSOT documents XYWAV-only scope

**Checkpoint**: ✅ All 7 constitution principles verified

---

## Phase 3: Spec Kit Validation (Complete)

**Purpose**: Verify Spec Kit installation and workflow

### Installation Verification

- [x] T024 [P] [US4] Verify `.specify/memory/constitution.md` exists (v1.0.0)
- [x] T025 [P] [US4] Verify 9 agent files in `.github/agents/`
- [x] T026 [P] [US4] Verify 5 template files in `.specify/templates/`
- [x] T027 [P] [US4] Verify 5 bash scripts in `.specify/scripts/bash/`
- [x] T028 [US4] Verify bash scripts are executable (755 permissions)

### Workflow Validation

- [x] T029 [US4] Create feature branch `001-speckit-repo-review`
- [x] T030 [US4] Create feature directory `.specify/features/001-speckit-repo-review/`
- [x] T031 [US4] Generate `spec.md` from specification workflow
- [x] T032 [US4] Generate `plan.md` from planning workflow
- [x] T033 [US4] Generate `tasks.md` from task breakdown workflow
- [x] T034 [US4] Run `/speckit.analyze` to verify cross-artifact consistency
- [x] T035 [US4] Generate final compliance report (`analysis-report.md`)

**Checkpoint**: ✅ Spec Kit workflow 100% validated

---

## Phase 4: Documentation & Reporting

**Purpose**: Finalize audit and document findings

- [x] T036 [US3] Document build cache sensitivity issue
- [x] T037 [US3] Document legacy file handling approach
- [x] T038 Compile comprehensive audit report
- [ ] T039 Commit constitution and feature artifacts

**Checkpoint**: 🔄 Documentation 75% complete

---

## Summary

| Phase | Tasks | Complete | Status |
| ----- | ----- | -------- | ------ |
| Phase 1: Verification | 5 | 5 | ✅ 100% |
| Phase 2: Constitution | 18 | 18 | ✅ 100% |
| Phase 3: Spec Kit | 12 | 12 | ✅ 100% |
| Phase 4: Documentation | 4 | 3 | 🔄 75% |
| **Total** | **39** | **38** | **97%** |

## Findings Summary

### ✅ All Checks Passing

| Category | Items Verified |
| -------- | -------------- |
| Constitution Principles | 7/7 compliant |
| Core Files | 23 platform-free Swift files |
| Test Files | 18 test files, 277 test cases |
| SSOT Integrity | 15 components, 9 sections verified |
| Doc Lint | 9/9 checks passing |
| Spec Kit Components | 9 agents, 5 templates, 5 scripts |

### ⚠️ Minor Findings (Non-Blocking)

| Finding | Severity | Location | Status |
| ------- | -------- | -------- | ------ |
| Build cache path sensitivity | LOW | `.build/` | Documented |
| SQLiteStorage in test comments | INFO | `DoseTapTests.swift` | Acceptable |
| Legacy files guarded | LOW | `ios/DoseTap/` | Already mitigated |
