# Implementation Plan: Repository Health & Constitution Compliance Review

**Branch**: `001-speckit-repo-review` | **Date**: 2026-01-10 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-speckit-repo-review/spec.md`

## Summary

This plan documents the verification that the DoseTap repository complies with the newly ratified Constitution (v1.0.0) and establishes baseline metrics for ongoing compliance monitoring. The primary deliverable is a comprehensive audit report with actionable findings.

## Technical Context

**Language/Version**: Swift 5.9+ (SwiftPM)  
**Primary Dependencies**: Foundation, Combine (Core); SwiftUI, UIKit (App only)  
**Storage**: SQLite via EventStorage.swift  
**Testing**: XCTest via `swift test` (277 tests in 18 files)  
**Target Platform**: iOS 16.0+, macOS 14.0+ (development)  
**Project Type**: Mobile (iOS/watchOS)  
**Performance Goals**: Build < 60s, Tests < 30s on M1 Mac  
**Constraints**: Offline-capable, platform-free core logic, deterministic time handling  
**Scale/Scope**: 23 core files, 18 test files, 2309-line SSOT

## Constitution Check

*GATE: All 7 principles verified. Re-checked at completion.*

| Principle | Status | Evidence |
| --------- | ------ | -------- |
| I. SSOT-First | ✅ PASS | `docs/SSOT/README.md` canonical (v2.14.0), `./tools/ssot_check.sh` passes |
| II. Test-First | ✅ PASS | 277 tests pass, time injection used throughout |
| III. Platform-Free Core | ✅ PASS | `ios/Core/` uses `#if canImport()` guards only |
| IV. Storage Boundary | ✅ PASS | No `EventStorage.shared` in Views |
| V. Deterministic Time | ✅ PASS | All calculators accept `now: () -> Date` |
| VI. Offline-First | ✅ PASS | `OfflineQueue` actor exists with persistence |
| VII. XYWAV-Only Scope | ✅ PASS | No multi-medication features in codebase |

## Project Structure

### Documentation (this feature)

```text
.specify/features/001-speckit-repo-review/
├── spec.md              # Feature specification ✅
├── plan.md              # This file ✅
└── tasks.md             # Task breakdown (next step)
```

### Source Code (repository structure)

```text
ios/
├── Core/                    # Platform-free business logic (23 files)
│   ├── DoseWindowState.swift
│   ├── APIClient.swift
│   ├── APIErrors.swift
│   ├── OfflineQueue.swift
│   ├── EventRateLimiter.swift
│   └── ... (18 more)
├── DoseTap/                 # iOS app target (SwiftUI)
│   ├── Storage/
│   │   ├── EventStorage.swift    # SQLite wrapper
│   │   └── SessionRepository.swift # Facade (required for Views)
│   ├── Views/
│   └── Theme/
└── DoseTapTests/            # Xcode test target

Tests/
└── DoseCoreTests/           # SwiftPM test target (18 files, 277 tests)

docs/
└── SSOT/
    ├── README.md            # Canonical spec (2309 lines)
    ├── constants.json       # Machine-readable (603 lines)
    └── contracts/           # API, schemas, guarantees

.specify/
├── memory/
│   └── constitution.md      # Ratified v1.0.0
├── templates/               # 5 templates
├── scripts/bash/            # 5 scripts
└── features/                # Feature artifacts

tools/
├── ssot_check.sh            # SSOT integrity verification
├── doc_lint.sh              # Documentation linting (9 checks)
└── ...
```

**Structure Decision**: Existing structure follows Clean Architecture with clear separation between platform-free Core and iOS-specific App code. No structural changes needed.

## Phases

### Phase 0: Verification (Complete)

**Objective**: Verify all automated checks pass

**Deliverables**:
- ✅ `swift build` succeeds
- ✅ `swift test --parallel` passes (277/277)
- ✅ `./tools/ssot_check.sh` passes
- ✅ `./tools/doc_lint.sh` passes (9/9 checks)

### Phase 1: Constitution Compliance Audit

**Objective**: Manual verification of each principle

**Deliverables**:
- ✅ Principle I: SSOT document exists and is canonical
- ✅ Principle II: All core logic has tests
- ✅ Principle III: No unguarded UI imports in Core
- ✅ Principle IV: Storage boundary enforced
- ✅ Principle V: Time injection pattern followed
- ✅ Principle VI: Offline queue implemented
- ✅ Principle VII: XYWAV-only scope maintained

### Phase 2: Spec Kit Validation

**Objective**: Verify Spec Kit workflow functions correctly

**Deliverables**:
- ✅ Constitution ratified (v1.0.0)
- ✅ All 9 agent files present
- ✅ All 5 template files present
- ✅ All 5 bash scripts executable
- ✅ Feature directory created successfully
- ✅ spec.md generated from workflow
- ✅ plan.md generated from workflow
- 🔄 tasks.md generation (in progress)
- 🔄 analyze command execution (pending)

### Phase 3: Documentation & Report

**Objective**: Generate comprehensive audit report

**Deliverables**:
- Final compliance report
- Recommendations for improvements
- Commit constitution changes

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
| ---- | ---------- | ------ | ---------- |
| Stale build cache | Medium | Low | Document `rm -rf .build` requirement |
| Legacy file conflicts | Low | Medium | Files already guarded with `#if false` |
| Test count drift | Low | Low | CI enforces test pass |

## Complexity Tracking

No constitution violations requiring justification. All checks pass.

## Metrics Summary

| Metric | Value | Status |
| ------ | ----- | ------ |
| Core Files | 23 | ✅ |
| Test Files | 18 | ✅ |
| Test Cases | 277 | ✅ |
| SSOT Lines | 2309 | ✅ (< 3000) |
| Constants JSON Lines | 603 | ✅ |
| Constitution Principles | 7 | ✅ All compliant |
| Spec Kit Agents | 9 | ✅ |
| Spec Kit Templates | 5 | ✅ |
| Spec Kit Scripts | 5 | ✅ |
| SSOT Checks | 15 components, 9 sections | ✅ |
| Doc Lint Checks | 9 | ✅ All pass |
