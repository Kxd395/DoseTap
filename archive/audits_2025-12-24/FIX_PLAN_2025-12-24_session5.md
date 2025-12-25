# FIX PLAN — Session 5 (2025-12-24)

## Problem Statement

Session 4 claimed all contradictions were fixed, but duplicate documentation files existed outside the main `docs/` folder, creating "parallel doc multiverses."

## Root Cause

Historical advisory documents in `ios/DoseTap/review/` and a deprecated SSOT file in `docs/SSOT/` were never archived when the repository's persistence strategy changed from Core Data to SQLite.

## Canonical Documentation Hierarchy

**This is the authoritative declaration of what is canonical vs allowed-stale:**

```
README.md                           # Front door — MUST link to docs/SSOT/README.md
├── docs/
│   ├── README.md                   # Doc index — links to SSOT
│   ├── SSOT/
│   │   └── README.md               # ⭐ CANONICAL SPEC (authoritative)
│   │   └── contracts/              # API specs, schemas, data dictionary
│   │   └── navigation.md           # Quick nav for SSOT
│   ├── PRD.md                      # Canonical product requirements
│   ├── architecture.md             # Canonical architecture doc
│   ├── DATABASE_SCHEMA.md          # Canonical schema reference
│   └── *.md                        # Narrative docs (must align with SSOT)
└── archive/                        # Historical docs — ALLOWED TO BE STALE
    └── *                           # Excluded from lint checks except duplicate detection
```

**Rule:** Archive is excluded from lint checks except duplicate detection. Do not "fix" archived docs — that creates drift.

## Fix Strategy

1. Archive all conflicting files to `archive/` folder
2. Enhance lint script to detect future drift
3. Verify README hierarchy clearly points to canonical SSOT

## Changes Made

### 1. Archived `ios/DoseTap/review/` folder

Commands:

```bash
mkdir -p archive/ios_review_2025-12-24
mv ios/DoseTap/review/* archive/ios_review_2025-12-24/
rmdir ios/DoseTap/review
```

Files moved:
- `DoseTap_Application_Description_SSOT_v1.0.md`
- `DoseTap_SSOT_Advise.md`
- `DoseTap_Testing_Guide.md`
- `DoseTap_audit_analysis.md`
- `DoseTap_audit_changes.md`

### 2. Archived `docs/SSOT/SSOT_v2.md`

Command: `mv docs/SSOT/SSOT_v2.md archive/`

### 3. Removed duplicate `docs/archive/SSOT_v2.md`

Command: `rm docs/archive/SSOT_v2.md`

### 4. Enhanced `tools/ssot_check.sh`

**New checks added:**

- Detect SSOT files outside `docs/SSOT/` and `archive/`
- Detect duplicate canonical docs (`PRD.md`, `architecture.md`, `FEATURE_ROADMAP.md`, `DATABASE_SCHEMA.md`) outside `docs/` and `archive/`
- Detect markdown files in `ios/` referencing Core Data framework
- **HARD FAIL** if root README does not reference `docs/SSOT/README.md` as canonical spec

**Core Data detection strengthened:**

- Now checks for: `Core Data`, `CoreData`, `NSPersistentContainer`, `NSManagedObjectContext`
- Uses title case to avoid false positives on "core data handling" (meaning general data)
- Excludes known deprecation notices and audit logs

**Fixed existing check:**

- SleepEventType case count now uses `awk` to count only within that enum (was counting all enums in file)

## Verification

```bash
# Verify lint script passes (exit code 0 = pass)
bash tools/ssot_check.sh
echo "Exit code: $?"
# Expected: Exit code: 0

# Or capture full output for records
bash tools/ssot_check.sh 2>&1 | tee audit/ssot_check_session5.txt

# Files archived correctly
ls archive/ios_review_2025-12-24/
# DoseTap_Application_Description_SSOT_v1.0.md  DoseTap_audit_analysis.md
# DoseTap_SSOT_Advise.md                        DoseTap_audit_changes.md
# DoseTap_Testing_Guide.md

# Only one SSOT_v2.md exists
find . -name "SSOT_v2.md" -not -path "./.git/*"
# ./archive/SSOT_v2.md

# Tests still pass
swift test 2>&1 | tail -3
# Test Suite 'All tests' passed at ...
# Executed 207 tests, with 0 failures
```

## Not In Scope

The following pre-existing issues were **not addressed** in Session 5. They are tracked separately and do not affect source-of-truth consistency:

| Issue | Count | Reason Excluded |
|-------|-------|-----------------|
| Component IDs in SSOT not yet implemented in code | 15 warnings | Feature backlog, not doc conflict |
| API endpoints in SSOT not in OpenAPI spec | 11 warnings | Spec completeness, not doc conflict |
| Broken link to CHANGELOG.md | 1 warning | Missing file, not doc conflict |

**This repo is not "fully production ready"** — it has source-of-truth consistency for docs, but implementation gaps remain.

## Summary

All duplicate documentation files have been archived. The lint script now guards against:

1. SSOT files appearing outside canonical locations
2. Duplicate canonical docs (`PRD.md`, `architecture.md`, etc.) outside `docs/` and `archive/`
3. Markdown files in `ios/` referencing Core Data framework
4. Missing canonical SSOT reference in root README (hard fail)
5. Core Data framework references using expanded patterns

## Implemented Improvements

All recommended hardening was applied in this session:

| Improvement | Status |
| --- | --- |
| Expand Core Data detection patterns | ✅ Done — `Core Data`, `CoreData`, `NSPersistentContainer`, `NSManagedObjectContext` |
| Extend duplicate detection to canonical docs | ✅ Done — `PRD.md`, `architecture.md`, `FEATURE_ROADMAP.md`, `DATABASE_SCHEMA.md` |
| Change README hierarchy check from warn to fail | ✅ Done — Now exits nonzero |
| Avoid false positives on "core data handling" | ✅ Done — Uses title case matching |

Session 5 complete.
