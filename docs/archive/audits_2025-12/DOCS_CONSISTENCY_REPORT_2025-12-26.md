# Documentation Consistency Report

**Date:** 2025-12-26  
**Auditor:** Documentation Consistency Auditor  
**Status:** ✅ All active docs consistent

---

## Canonical Facts Table

| Fact | Canonical Value |
|------|-----------------|
| **SSOT Version** | 2.12.0 |
| **Test Count** | 275 tests pass |
| **SQLite Filename** | `dosetap_events.sqlite` |
| **SQLiteStorage Status** | BANNED (`#if false` wrapper) |

---

## Files Changed

| File | Changes |
|------|---------|
| `.github/workflows/ci-swift.yml` | Expanded docs guard to scan ALL markdown files repo-wide (not just `docs/`), added `Completed (v2.*)` to allowed changelog exceptions |

**No other docs required changes** — previous fixes already corrected:
- `docs/STORAGE_UNIFICATION_2025-12-26.md` header (275 tests)
- `docs/architecture.md` (#if false wrapper)
- `docs/codebase.md` (#if false wrapper)
- `docs/README.md` (#if false wrapper)
- `docs/SSOT/README.md` (#if false wrapper)
- `docs/STORAGE_ENFORCEMENT_REPORT_2025-12-26.md` (#if false wrapper)

---

## CI Guard Logic

**Location:** `.github/workflows/ci-swift.yml` → `storage-enforcement` job → `Docs consistency check` step

**Scan scope:**
```bash
find . -name "*.md" -type f ! -path "*/archive/*" ! -path "*/legacy/*"
```

**Stale tokens detected:**
- `\b268\b` (old test count)
- `v2.10.0` (old SSOT version)
- `v2.11.0` (old SSOT version)
- `dosetap.db` (wrong filename)
- `@available.*unavailable` (wrong enforcement mechanism)

**Allowed exceptions (not flagged):**
- `Before.*After` tables (historical comparison)
- `| 268 | 275` (before/after columns)
- `Recent Updates.*v2.10` (SSOT changelog headers)
- `New in v2.10` (SSOT changelog headers)
- `Completed.*v2.10` (backlog/history sections)
- `Completed.*v2.11` (backlog/history sections)

**On failure:** Prints file path, line number, and matched token.

---

## Verification Commands & Outputs

### Before: Stale Token Scan

```bash
# Command
find . -name "*.md" -type f ! -path "*/archive/*" ! -path "*/legacy/*" \
  -exec grep -Hn "\b268\b\|v2\.10\.0\|v2\.11\.0\|dosetap\.db\|@available.*unavailable" {} \; \
  | grep -v "Before.*After\|| 268 | 275\|Recent Updates.*v2\.10\|New in v2\.10\|Completed.*v2\.10\|Completed.*v2\.11"

# Result
✅ No stale references in active docs
```

### Intentional Fail Test

```bash
# Create file with stale token
echo "Test count: 268 tests" > ./docs/TEST_STALE.md

# Run guard
❌ FAIL (expected):
./docs/TEST_STALE.md:1:Test count: 268 tests

# Cleanup
rm ./docs/TEST_STALE.md
```

### After Cleanup: Guard Passes

```bash
# Result
✅ No stale references in active docs
```

---

## Summary

| Check | Status |
|-------|--------|
| 268 refs in active docs | ✅ None (except allowed before/after tables) |
| v2.10.0/v2.11.0 refs in active docs | ✅ None (except changelog headers) |
| dosetap.db refs | ✅ None |
| @available unavailable refs | ✅ None |
| CI guard catches stale tokens | ✅ Verified |
| CI guard allows exceptions | ✅ Verified |

**Verdict:** Documentation is internally consistent. CI enforces it repo-wide.
