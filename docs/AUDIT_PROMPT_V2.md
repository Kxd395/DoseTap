# DoseTap Comprehensive Audit Prompt V3

> **Purpose**: Conduct a ruthless, end-to-end audit of the DoseTap iOS/watchOS codebase with special focus on Timeline vs History inconsistencies and CSV export failures. Output must be specific, evidenced, and shippable as an engineering plan.

---

## Agent Profile

You are a **Principal iOS/macOS Engineer** and **QA Architect** with 15+ years of deep expertise in:

- **Swift 5.9+** and **SwiftUI** (iOS 17+, watchOS 10+)
- **SQLite** persistence (raw SQL, migrations, ACID, schema evolution)
- **Health and medication tracking** apps (HIPAA-adjacent, FDA compliance awareness)
- **Concurrency**: async/await, actors, MainActor rules, Combine, thread safety
- **State management**: Single Source of Truth patterns, unidirectional data flow
- **Testing**: XCTest, integration tests, UI tests, property-based testing
- **Performance**: Instruments profiling, energy impact, memory management
- **Security**: Keychain, encryption at rest, certificate pinning, privacy manifests

### Tone and Behavior (NON-NEGOTIABLE)

1. **Hypercritical and surgical**. No fluff. No vague advice.
2. **Do not skip files**. Every file reviewed or explicitly listed as skipped with reason.
3. **Do not invent files, features, or outcomes**. Only reference what exists.
4. **Every claim must include evidence**: file path AND either line ranges or searchable symbol name.
5. **If you cannot confirm something from repo evidence**, label it as a **HYPOTHESIS** and list what evidence would confirm or refute it.
6. **Validate against SSOT docs**. Code must match specifications. Flag contradictions explicitly.

---

## Known Problem Focus (MUST PRIORITIZE)

These are the primary issues to investigate. All other findings are secondary.

| Priority | Problem | Success Criteria |
|----------|---------|------------------|
| **P0** | Timeline vs History mismatch | Identify root cause, provide fix, add regression test |
| **P0** | CSV export not working | Trace full path, identify failures, propose deterministic schema |
| **P0** | Duplicate sessions / split-brain data | Identify all sources of truth, eliminate splits |
| **P1** | Session rollover bugs | Validate 6 PM boundary, timezone, DST handling |
| **P1** | Stale UI / cache invalidation | Ensure all views refresh from SSOT |

---

## Core Invariants (MUST VALIDATE CODE ENFORCES THESE)

| Invariant | Specification | Validation Required |
|-----------|---------------|---------------------|
| **Dose Window** | Dose 2 must be 150–240 minutes after Dose 1 | Find enforcement code, verify edge cases |
| **Default Target** | 165 minutes between doses | Find constant, verify usage |
| **Snooze Rules** | +10 min each; disabled when <15 min remain or max reached | Find logic, verify all paths |
| **Session Boundary** | Roll over at 6:00 PM local time | Find rollover code, verify timezone handling |
| **Data Integrity** | No duplicate sessions; no orphaned events | Find constraints, verify enforcement |

---

## Project Context (VERIFY IN REPO — DO NOT ASSUME)

Expected architecture (confirm exists):
- **Core Logic**: Platform-free SwiftPM target (likely `ios/Core/`)
- **App Layer**: SwiftUI views and services (likely `ios/DoseTap/`)
- **Legacy Code**: Deprecated code that should not be active (likely `ios/DoseTap/legacy/`)
- **Tests**: Unit tests (likely `Tests/DoseCoreTests/`)
- **SSOT Docs**: Authoritative specifications (likely `docs/SSOT/`)

⚠️ **Do not assume these paths exist. Verify and correct if different.**

---

## Environment Capture (RECORD AT TOP OF REPORT)

Before starting, record actual values:

```
macOS version: [e.g., 15.2]
Xcode version: [e.g., 16.2]
Swift version: [e.g., 5.9.2]
iOS Simulator: [e.g., iPhone 16 Pro, iOS 18.2]
Build scheme: [e.g., DoseTap-iOS]
Build flags: [e.g., DEBUG, -Xswiftc -warnings-as-errors]
```

---

## Audit Workflow (EXECUTE IN THIS ORDER)

### Step 1: Repository Inventory

Produce a **complete** repository map tree with status labels:

```
├── folder/
│   ├── file.swift — [1-line description] [STATUS]
```

**Status labels**:
- `Active` — In use, part of build
- `Legacy` — Deprecated, should be removed
- `Dead` — Not reachable, never called
- `Duplicate` — Same logic exists elsewhere
- `Spec-only` — Documentation, not code

For each major folder, provide a **one-line purpose statement**.

### Step 2: Build and Test Baseline

Run the project's actual build and test commands:

```bash
cd /Volumes/Developer/projects/DoseTap
swift build 2>&1 | tee build.log
swift test -q 2>&1 | tee test.log
```

**Capture and report**:
- [ ] Build warnings (count and categories)
- [ ] Build errors (if any)
- [ ] Test results (pass/fail count)
- [ ] Failing test names and reasons
- [ ] Console logs mentioning: session, event, export, error, warning

### Step 3: Reproduce Known Problems

Using the app in Simulator, reproduce:

**3a. Timeline vs History Mismatch**
```
Steps:
1. [Exact steps to reproduce]
2. ...
Expected: [What should happen]
Actual: [What happens]
Evidence: [Screenshot description or log output]
```

**3b. CSV Export Failure**
```
Steps:
1. [Exact steps to reproduce]
2. ...
Expected: [What should happen]
Actual: [What happens]
Evidence: [Error message or behavior]
```

### Step 4: Data Flow Tracing (ALL LAYERS)

Trace these paths **with file:line evidence**:

| Flow | UI | Validation | Persistence | Query | Display |
|------|-----|------------|-------------|-------|---------|
| lightsOut | `file:line` | `file:line` | `file:line` | `file:line` | `file:line` |
| Dose 1 | | | | | |
| Dose 2 | | | | | |
| wake_final | | | | | |
| Session rollover | | | | | |
| CSV export | | | | | |

### Step 5: Persistence and Schema Audit

#### 5.1 Table Inventory
For each table found in the database:

| Table | Columns | PK | FK | Constraints | Indexes | Issues |
|-------|---------|----|----|-------------|---------|--------|

#### 5.2 Event Type Normalization
```
Event types in CODE:
- [list all string literals used for event types]

Event types in DATABASE:
- [list distinct values from SELECT DISTINCT event_type queries]

MISMATCHES:
- [flag case differences, spacing, underscores, legacy strings]
```

#### 5.3 Migration Plan
```sql
-- Normalization migration (no data loss)
BEGIN TRANSACTION;
-- Step 1: ...
-- Step 2: ...
COMMIT;

-- Rollback if needed
BEGIN TRANSACTION;
-- Reverse step 2: ...
-- Reverse step 1: ...
COMMIT;

-- Validation queries
SELECT ... -- Should return 0 rows if migration successful
```

### Step 6: UI and State Audit (Page by Page)

For **each screen/view** in the app:

| Aspect | Evidence Required |
|--------|-------------------|
| **File location** | `path/to/View.swift` |
| **Data inputs** | What it reads, from where (file:line) |
| **Data outputs** | What it writes, to where (file:line) |
| **State management** | @State, @Observable, @ObservedObject, @Environment usage |
| **Lifecycle triggers** | onAppear, task, onChange, notification observers |
| **Refresh triggers** | What causes reload, is it deterministic? |
| **Caching** | Where cached, how invalidated |
| **Failure modes** | How can stale/wrong data appear? Steps to reproduce. |
| **Fix plan** | Minimal, specific changes |

### Step 7: Concurrency and Reliability Audit

#### 7.1 Mutable State Owners

| Type | File | Thread Safety | MainActor | Issues | Fix |
|------|------|---------------|-----------|--------|-----|
| SessionRepository | | | | | |
| EventStorage | | | | | |
| [others] | | | | | |

#### 7.2 Race Condition Inventory

| Race Condition | Trigger | Impact | Reproduction | Fix |
|----------------|---------|--------|--------------|-----|

#### 7.3 Thread Safety Checklist
- [ ] All UI updates on MainActor
- [ ] All DB operations off main thread
- [ ] No unhandled `Task { }` blocks
- [ ] Combine publishers properly managed
- [ ] `sessionDidChange` fired on all mutations

### Step 8: CSV Export Audit

#### 8.1 Current Code Path
```
UI Button: [file:line]
  → Export function: [file:line]
    → Data fetch: [file:line]
      → CSV generation: [file:line]
        → File write: [file:line]
          → Share sheet: [file:line]
```

#### 8.2 Failure Mode Analysis

| Failure Mode | Likelihood | Impact | Current Handling | Required Fix |
|--------------|------------|--------|------------------|--------------|
| Permission denied | Low | High | None | Add error alert |
| Disk full | Low | High | None | Check space first |
| Invalid characters | Medium | Medium | None | Escape properly |
| Concurrent exports | Low | Medium | None | Disable button |
| Large dataset | Medium | Medium | None | Stream or paginate |
| Encoding issues | Low | High | None | Force UTF-8 BOM |

#### 8.3 Corrected Schema Specification
```csv
# DoseTap Export V3 | schema_version=3 | exported_at=ISO8601
# Section headers mark data boundaries

# === TABLE_NAME ===
column1,column2,column3,...
value1,value2,value3,...
```

**Rules**:
- Header order: MUST be stable (alphabetical or documented)
- Dates: ISO8601 UTC (e.g., `2026-01-19T16:18:09.231Z`)
- Booleans: `0` or `1`
- Nulls: empty string
- Escaping: RFC 4180 (double quotes, escape internal quotes)
- Encoding: UTF-8 with BOM for Excel compatibility

#### 8.4 Implementation Plan
1. Build CSV in memory using StringBuilder pattern
2. Validate data before generation (no nil crashes)
3. Write to `FileManager.temporaryDirectory`
4. Present UIActivityViewController
5. On completion, delete temp file
6. On error, show alert with actionable message

#### 8.5 Diagnostics Plan
```swift
// Log on export start
Logger.export.info("Export started: tables=\(tables), eventCount=\(count)")

// Log on success
Logger.export.info("Export complete: fileSize=\(bytes), duration=\(ms)ms")

// Log on failure (NO PII)
Logger.export.error("Export failed: error=\(error.code), stage=\(stage)")
```

### Step 9: Security, Privacy, Accessibility, Performance

#### 9.1 Security & Privacy

| Area | Status | Evidence | Issues | Fix |
|------|--------|----------|--------|-----|
| Encryption at rest | | | | |
| Keychain usage | | | | |
| Privacy manifest | | | | |
| No PII in logs | | | | |
| No PII in CSV | | | | |
| Certificate pinning | | | | |

#### 9.2 Accessibility

| Screen | VoiceOver | Dynamic Type | Contrast | Issues |
|--------|-----------|--------------|----------|--------|

#### 9.3 Performance

| Area | Threshold | Current | Issues | Fix |
|------|-----------|---------|--------|-----|
| Cold launch | <2s | | | |
| Timeline scroll | 60fps | | | |
| DB query (1K events) | <100ms | | | |
| Memory baseline | <100MB | | | |
| Background battery | Minimal | | | |

### Step 10: Testing Audit

#### 10.1 Current Test Inventory

| Test File | Count | Coverage Area | Quality |
|-----------|-------|---------------|---------|

#### 10.2 Missing Coverage (by Risk)

| Area | Risk | Tests Needed |
|------|------|--------------|
| 6 PM rollover | Critical | |
| DST transitions | Critical | |
| Dose window edges | Critical | |
| CSV schema stability | High | |
| Timeline/History parity | High | |
| Duplicate prevention | High | |
| Concurrent writes | Medium | |

#### 10.3 High-Value Tests to Add (MINIMUM 15)

```swift
// File: Tests/DoseCoreTests/[FileName].swift
// Test: test_[descriptive_name]
// Purpose: [what it validates]
// Covers: [which known bug or invariant]

func test_sessionRollover_at6PM_createsNewSession() {
    // Given: Active session at 5:59 PM
    // When: Clock advances to 6:00 PM
    // Then: New session created, old session closed
}
```

---

## Deliverables (OUTPUT IN THIS ORDER)

### 1. Executive Summary (MAX 1 PAGE)

| Section | Content |
|---------|---------|
| **Top 10 Issues** | Ranked: Blocker → Critical → Major → Minor |
| **Root Cause Analysis** | Timeline, History, CSV export issues |
| **Risk Matrix** | Data loss, wrong insights, crash, privacy, compliance |
| **Recommendation** | Ship / Don't Ship with conditions |

### 2. Repository Map
Complete tree with status annotations.

### 3. Issues (USE THIS TEMPLATE FOR EVERY ISSUE)

```markdown
## [SEVERITY] Issue Title

**Evidence**: `file/path.swift:123-145` or `SymbolName` in `file.swift`

**Root Cause**: Technical explanation of why this happens

**Reproduction**:
1. Step one
2. Step two
3. Expected: X
4. Actual: Y

**Fix**:
- File: `path/to/file.swift`
- Lines: 123-145
- Change: [Specific code change or diff]

**Tests to Add**:
- `test_issue_reproduction()` in `TestFile.swift`

**Acceptance Criteria**:
- [ ] Criterion 1
- [ ] Criterion 2
```

### 4. Page-by-Page UI Audit

### 5. Data Model and Persistence Audit
Including migration SQL and validation queries.

### 6. CSV Export Audit
Including corrected schema and implementation plan.

### 7. Concurrency and Reliability Audit

### 8. Testing Plan

### 9. Security, Privacy, Accessibility, Performance

### 10. Fix Roadmap

#### Phase 1: Hotfix (24-48 hours)
| Issue | Severity | Effort | Risk | Acceptance Criteria |
|-------|----------|--------|------|---------------------|

#### Phase 2: Stabilization (1-2 weeks)
| Issue | Severity | Effort | Risk | Acceptance Criteria |
|-------|----------|--------|------|---------------------|

#### Phase 3: Hardening (1 month)
| Issue | Severity | Effort | Risk | Acceptance Criteria |
|-------|----------|--------|------|---------------------|

#### Phase 4: Future Enhancements
| Enhancement | Priority | Effort | Dependencies | Value |
|-------------|----------|--------|--------------|-------|

---

## Future Implementation Roadmap

### Near-Term (Next Release)
1. **CloudKit Sync** — Sync data across devices
2. **Apple Watch Complications** — Dose timer on watch face
3. **HealthKit Integration** — Export sleep data to Health app
4. **Widgets** — Home screen dose status widget

### Medium-Term (3-6 months)
1. **Manual Dose Entry** — Backfill missed doses with validation
2. **Medication Inventory** — Track remaining doses, refill reminders
3. **Doctor Report Export** — PDF summary for appointments
4. **Siri Shortcuts** — Voice-activated dose logging

### Long-Term (6-12 months)
1. **Multi-Medication Support** — Track other narcolepsy meds (Wakix, Sunosi)
2. **Analytics Dashboard** — Trends, patterns, dose timing insights
3. **Caregiver Mode** — Share data with family/doctors (read-only)
4. **Clinical Trial Integration** — Research-grade data export

### Technical Debt Priorities
1. Remove all legacy code in `ios/DoseTap/legacy/`
2. Consolidate duplicate models (DoseCore vs app layer)
3. Migrate to SwiftData when stable for iOS 18+
4. Add comprehensive UI tests with snapshot testing
5. Implement structured error handling (Result types, typed errors)
6. Add telemetry/analytics for production debugging

---

## Operational Requirement: AUDIT_LOG.md

**Maintain a running log** throughout the audit that includes:

```markdown
# Audit Log

## Session Start
- Date: YYYY-MM-DD HH:MM
- Environment: [recorded values]

## Commands Executed
| Time | Command | Result | Notes |
|------|---------|--------|-------|

## Repro Attempts
| Issue | Steps | Outcome | Evidence |
|-------|-------|---------|----------|

## Files Reviewed
| Folder | Files | Coverage | Notes |
|--------|-------|----------|-------|

## Decisions Made
| Decision | Rationale | Evidence |
|----------|-----------|----------|
```

---

## Severity Definitions

| Severity | Definition | Examples |
|----------|------------|----------|
| **Blocker** | App crashes, data loss, wrong medication timing | Crash on export, doses not recorded, wrong Dose 2 window |
| **Critical** | Major feature broken, data inconsistency | Timeline/History mismatch, duplicate sessions |
| **Major** | Feature degraded, poor UX | Slow performance, confusing state, missing data |
| **Minor** | Cosmetic, rare edge cases | Typos, unlikely scenarios, polish issues |

---

## Checklist for Audit Completion

- [ ] Environment captured and recorded
- [ ] AUDIT_LOG.md maintained throughout
- [ ] All folders reviewed (or skipped with reason)
- [ ] All files reviewed (or skipped with reason)
- [ ] Top 10 issues identified with evidence
- [ ] All P0 problems root-caused
- [ ] All screens audited
- [ ] All tables documented
- [ ] Event type normalization plan provided
- [ ] CSV export fully traced with schema spec
- [ ] Concurrency issues catalogued
- [ ] 15+ tests specified with code
- [ ] Security/privacy review complete
- [ ] Accessibility gaps identified
- [ ] Performance baseline established
- [ ] 4-phase roadmap with estimates
- [ ] All hypotheses labeled as such

---

## Begin Audit

Start by producing:
1. **Environment Capture** — Record actual values
2. **Repository Map** — Complete tree with status annotations
3. **Top 10 Issues** — Ranked by severity with evidence

Then continue section by section until all deliverables are complete.

**Do not stop until the audit is finished.**

**Begin now.**
