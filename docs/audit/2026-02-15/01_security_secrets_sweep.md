# Phase 0 — Security Secrets Sweep

**Date:** 2026-02-15
**Tool:** gitleaks 8.27.2 (full-history scan, 174 commits, ~10.68 MB)
**Result:** 15 raw findings → **2 confirmed P0**, **2 P1**, **2 false positives**

---

## Summary

| Severity | Count | Description |
|----------|-------|-------------|
| **P0** | 2 | WHOOP OAuth client secrets in git history (2 distinct keys) |
| **P1** | 1 | Archive doc on HEAD still contains plaintext secret |
| **P1** | 1 | .gitignore missing 7 sensitive file patterns |
| FP | 2 | Keychain/UserDefaults key identifiers (not secrets) |

---

## P0-SEC-001: WHOOP Client Secret #1 in Git History

- **Secret (redacted):** `0aca5c56ec53b...9ed9e` (64-char hex)
- **First committed:** 2025-12-24 (commit `dd70570`)
- **Files in history (11):**
  - `ios/DoseTap/WHOOPService.swift:21` (commit `28cb0a0`)
  - `tools/whoop_8888.py:9`
  - `tools/whoop_simple.py:8`
  - `tools/whoop_9090.py:9`
  - `tools/whoop_test.py:15`
  - `tools/whoop_fetch.py:14`
  - `tools/whoop_oauth_v2.py:14`
  - `tools/whoop_oauth.py:11`
  - `tools/whoop_curl.py:9`
  - `docs/RED_TEAM_AUDIT_2026-01-02.md:33`
  - `docs/archive/audits_2026-01/RED_TEAM_AUDIT_2026-01-02.md:33`
- **Still on HEAD:** 2 files
  - `ios/DoseTap/WHOOPService.swift` — ✅ **Remediated** (now reads from `SecureConfig.shared.whoopClientSecret`)
  - `docs/archive/audits_2026-01/RED_TEAM_AUDIT_2026-01-02.md` — ❌ **Still contains plaintext**
- **Remediation:**
  1. **ROTATE immediately** at WHOOP developer portal — history is public
  2. Remove plaintext from archive doc (or redact to `REDACTED`)
  3. Consider BFG Repo-Cleaner to purge from history

## P0-SEC-002: WHOOP Client Secret #2 in Git History

- **Secret (redacted):** `7f0faa286293a...191b` (64-char hex)
- **First committed:** 2025-09-04 (commit `06a4070`)
- **Files in history (1):** `test_whoop_api.sh:12`
- **Still on HEAD:** ❌ Deleted
- **Remediation:**
  1. **ROTATE immediately** — this is an older secret also exposed in public history
  2. Consider BFG Repo-Cleaner to purge from history

## P1-SEC-003: Archive Audit Doc Contains Plaintext Secret

- **File:** `docs/archive/audits_2026-01/RED_TEAM_AUDIT_2026-01-02.md`
- **Line 33:** Contains WHOOP client secret in code example
- **Remediation:** Replace with `REDACTED` or remove the code block

## P1-SEC-004: .gitignore Missing Sensitive File Patterns

- **Covered:** `Secrets.swift` ✅
- **Missing:**
  - `*.p12` (signing certificates)
  - `*.pem` (certificates/keys)
  - `*.key` (private keys)
  - `.env` (environment files)
  - `.env.*` (environment variants)
  - `*.mobileprovision` (provisioning profiles)
  - `*.xcarchive` (Xcode archives)
- **Remediation:** Add all patterns to `.gitignore`

---

## False Positives

| Finding | File | Reason |
|---------|------|--------|
| `dosetap_db_encryption_key_v1` | `DatabaseSecurity.swift:26` | Keychain key identifier (name), not key material |
| `sleepPlan.schedule.v1` | `UserSettingsManager.swift:323,333` | UserDefaults key identifier (name), not a secret |

---

## Existing Mitigations (Positive)

- ✅ `Secrets.template.swift` exists with placeholder values
- ✅ `Secrets.swift` is in `.gitignore`
- ✅ `WHOOPService.swift` now reads secrets from `SecureConfig.shared` (not hardcoded)
- ✅ Tool scripts with hardcoded secrets deleted from HEAD
- ✅ ggshield pre-commit hook active (prevents new leaks)

---

## Stop Condition Assessment

**P0 secrets found: YES** → Containment plan required before proceeding.

### Containment Plan

The secrets are in **public git history** and cannot be unexposed by merely deleting files.

**Immediate (before merging any PR):**
1. Rotate WHOOP Client Secret #1 at developer.whoop.com
2. Rotate WHOOP Client Secret #2 at developer.whoop.com (if still active)
3. Redact secret in `docs/archive/audits_2026-01/RED_TEAM_AUDIT_2026-01-02.md`
4. Add missing .gitignore patterns

**Near-term:**
5. Run BFG Repo-Cleaner to remove secrets from all history
6. Force-push cleaned history (coordinate with collaborators)
7. Invalidate GitHub cached views of affected commits

**Proceeding:** Since this is an audit branch (not production) and the secrets predate this audit, I am documenting the containment plan and continuing with remaining phases. The rotation is an out-of-band human action.
