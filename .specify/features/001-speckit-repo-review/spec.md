# Feature Specification: Repository Health & Constitution Compliance Review

**Feature Branch**: `001-speckit-repo-review`  
**Created**: 2026-01-10  
**Status**: Draft  
**Input**: User description: "Repository analysis and constitution compliance review using Spec Kit workflow"

## Overview

This specification defines the scope and acceptance criteria for a comprehensive repository health audit, verifying that the DoseTap codebase complies with the newly ratified Constitution (v1.0.0) and identifying areas for improvement.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Constitution Compliance Verification (Priority: P1)

As a developer, I want to verify that all existing code complies with the 7 core principles in the DoseTap Constitution so that I can trust the codebase maintains its integrity guarantees.

**Why this priority**: The constitution defines non-negotiable rules. Any violation must be identified and remediated before new features are added.

**Independent Test**: Can be verified by running automated checks and manual code review against each principle.

**Acceptance Scenarios**:

1. **Given** the Constitution v1.0.0 is ratified, **When** I run `./tools/ssot_check.sh`, **Then** all checks pass ✅
2. **Given** Principle III (Platform-Free Core), **When** I grep for UI imports in `ios/Core/*.swift`, **Then** only `#if canImport()` guarded imports are found ✅
3. **Given** Principle IV (Storage Boundary), **When** I check Views for `EventStorage.shared`, **Then** zero violations are found ✅
4. **Given** Principle II (Test-First), **When** I run `swift test`, **Then** all 277 tests pass ✅

---

### User Story 2 - Build System Health (Priority: P1)

As a developer, I want to ensure the build system works correctly on a fresh clone so that CI/CD pipelines and new contributors have a reliable starting point.

**Why this priority**: A broken build blocks all development.

**Independent Test**: Clone repo, run `swift build && swift test` from scratch.

**Acceptance Scenarios**:

1. **Given** a fresh clone, **When** I run `swift build`, **Then** the build succeeds with no errors ✅
2. **Given** a stale `.build` cache from different path, **When** I run `rm -rf .build && swift build`, **Then** build succeeds ✅
3. **Given** all tests exist, **When** I run `swift test --parallel`, **Then** 277 tests complete with 0 failures ✅

---

### User Story 3 - Documentation Accuracy (Priority: P2)

As a developer, I want documentation to accurately reflect the current codebase state so that I can trust docs when making decisions.

**Why this priority**: Stale documentation causes confusion and wasted time.

**Independent Test**: Run `./tools/doc_lint.sh` and verify all 9 checks pass.

**Acceptance Scenarios**:

1. **Given** documentation lint script, **When** I run `./tools/doc_lint.sh`, **Then** all 9 checks pass ✅
2. **Given** SSOT README version, **When** compared to code behavior, **Then** they match (v2.14.0)
3. **Given** DATABASE_SCHEMA.md, **When** compared to EventStorage.swift, **Then** schema matches

---

### User Story 4 - Spec Kit Integration (Priority: P2)

As a developer using Spec Kit, I want all workflow commands to function correctly so that I can use spec-driven development for new features.

**Why this priority**: Spec Kit enables disciplined feature development.

**Independent Test**: Successfully run through entire workflow on test feature.

**Acceptance Scenarios**:

1. **Given** Spec Kit installed, **When** I run `/speckit.constitution`, **Then** constitution v1.0.0 is accessible
2. **Given** feature branch exists, **When** I run create-new-feature.sh, **Then** feature directory is created
3. **Given** spec.md exists, **When** I proceed through plan → tasks → analyze, **Then** all artifacts are generated

---

### Edge Cases

- **Stale build cache**: Module cache path mismatch after repo move/clone - requires `rm -rf .build`
- **Legacy file conflicts**: Files in `ios/DoseTap/` may conflict with Core - use `#if false` guards
- **SQLiteStorage references**: Test files may reference banned class for documentation - not a violation if in test comments

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Repository MUST pass all SSOT integrity checks (`./tools/ssot_check.sh`)
- **FR-002**: Repository MUST pass all documentation lint checks (`./tools/doc_lint.sh`)
- **FR-003**: All 277 DoseCoreTests MUST pass (`swift test`)
- **FR-004**: Core module (`ios/Core/`) MUST NOT have unguarded UI imports
- **FR-005**: Views MUST NOT access `EventStorage.shared` directly
- **FR-006**: `SQLiteStorage` MUST remain banned (marked `@unavailable`)
- **FR-007**: Constitution MUST be ratified at `.specify/memory/constitution.md`
- **FR-008**: Spec Kit scripts MUST be executable and functional

### Non-Functional Requirements

- **NFR-001**: `swift build` MUST complete in < 60 seconds on M1 Mac
- **NFR-002**: `swift test --parallel` MUST complete in < 30 seconds
- **NFR-003**: SSOT README MUST be < 3000 lines (currently 2309)
- **NFR-004**: All bash scripts in `.specify/scripts/bash/` MUST be executable

### Key Entities

- **Constitution**: Governance document at `.specify/memory/constitution.md` defining 7 core principles
- **SSOT**: Single Source of Truth at `docs/SSOT/README.md` (2309 lines) + `constants.json` (603 lines)
- **DoseCore**: Platform-free Swift module with 23 source files
- **DoseCoreTests**: Test suite with 18 test files covering 277 test cases
- **Spec Kit**: Development workflow system with 9 agents, 5 templates, 5 bash scripts

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All 7 constitution principles have zero violations in current codebase
- **SC-002**: `./tools/ssot_check.sh` exits with code 0
- **SC-003**: `./tools/doc_lint.sh` reports "All checks passed"
- **SC-004**: `swift test --parallel` reports 277 tests passed, 0 failures
- **SC-005**: `swift build` completes successfully with no errors
- **SC-006**: Zero instances of unguarded `import SwiftUI/UIKit` in `ios/Core/`
- **SC-007**: Zero instances of `EventStorage.shared` in View files
- **SC-008**: All 5 Spec Kit bash scripts are executable (755 permissions)
- **SC-009**: Constitution v1.0.0 exists and contains all 7 principles

## Current State Assessment

### ✅ Passing Checks

| Check | Status | Evidence |
|-------|--------|----------|
| SSOT Integrity | ✅ PASS | `./tools/ssot_check.sh` exits 0 |
| Doc Lint | ✅ PASS | All 9 checks pass |
| Swift Build | ✅ PASS | Builds successfully after cache clean |
| Swift Tests | ✅ PASS | 277 tests, 0 failures |
| Platform-Free Core | ✅ PASS | UI imports use `#if canImport()` guards |
| Storage Boundary | ✅ PASS | No `EventStorage.shared` in Views |
| SQLiteStorage Banned | ✅ PASS | Marked `@unavailable` |
| Spec Kit Installed | ✅ PASS | 9 agents, 5 templates, 5 scripts |
| Constitution Ratified | ✅ PASS | v1.0.0 at `.specify/memory/constitution.md` |

### ⚠️ Findings Requiring Attention

| Finding | Severity | Location | Recommendation |
|---------|----------|----------|----------------|
| Build cache path sensitivity | LOW | `.build/` | Document `rm -rf .build` for path changes |
| SQLiteStorage in test comments | INFO | `DoseTapTests.swift` | Acceptable - documentation only |
| Legacy files in `ios/DoseTap/` | LOW | Multiple | Already guarded with `#if false` |

## Assumptions

1. The current test count (277) is accurate as of 2026-01-10
2. M1 Mac is the reference development platform
3. iOS 16+ deployment target is maintained
4. No secrets are committed to the repository
