# Phase 3 — Full Security Audit

**Date:** 2026-02-15
**Scope:** Dependencies, entitlements, privacy, runtime security, data protection

---

## Dependency Analysis

| Area | Status |
|------|--------|
| External SPM dependencies | **Zero** — no third-party packages |
| Package.resolved | Not present (no external deps to resolve) |
| Supply chain risk | **Minimal** — no transitive dependency tree |

**Assessment:** Excellent. Zero third-party dependencies eliminates supply chain attack surface entirely. ✅

---

## Entitlements Audit

### `DoseTap.entitlements` (Full)

| Entitlement | Present | Justified |
|-------------|---------|-----------|
| `com.apple.developer.healthkit` | ✅ | ✅ Reads sleep, HR, HRV, SpO2 |
| `com.apple.developer.healthkit.background-delivery` | ✅ | ✅ Background sleep data |
| `com.apple.developer.icloud-container-identifiers` | ✅ | ⚠️ See SEC-005 |
| `com.apple.developer.icloud-services` (CloudKit) | ✅ | ⚠️ See SEC-005 |

### `DoseTap.NoCloud.entitlements` (No Cloud)

| Entitlement | Present | Justified |
|-------------|---------|-----------|
| `com.apple.developer.healthkit` | ✅ | ✅ |
| `com.apple.developer.healthkit.background-delivery` | ✅ | ✅ |

**Note:** Critical alerts entitlement (`com.apple.developer.usernotifications.critical-alerts`) is NOT in entitlements files yet — SSOT says "add only after Apple approves the entitlement request." This is correct per process. ✅

---

## Findings

### SEC-005 (P2): CloudKit entitlement present but no implementation

- **File:** `ios/DoseTap/DoseTap.entitlements`
- **Evidence:** iCloud container `iCloud.com.dosetap.ios` and CloudKit service declared. Zero CloudKit imports (`CKContainer`, `CKRecord`, `CKDatabase`) found in app Swift code.
- **Risk:** Unused entitlement increases attack surface. If CloudKit container is provisioned, it could be accessed by any build using the same signing identity.
- **SSOT says:** "Cloud sync: not implemented."
- **Fix:** Remove iCloud/CloudKit from `DoseTap.entitlements` until feature is built. Use `DoseTap.NoCloud.entitlements` as the default.

### SEC-006 (P1): Missing privacy manifest (PrivacyInfo.xcprivacy)

- **Evidence:** `find ios -name 'PrivacyInfo.xcprivacy'` returns empty.
- **Risk:** Apple requires privacy manifests for apps accessing certain APIs since Spring 2024. HealthKit usage, UserDefaults, file timestamp APIs are likely required reasons.
- **App Store impact:** App review may reject submissions without this file.
- **Fix:** Create `PrivacyInfo.xcprivacy` with:
  - `NSPrivacyAccessedAPITypeReasons` for UserDefaults (`C56D.1`)
  - `NSPrivacyAccessedAPITypeReasons` for file timestamp APIs if used
  - `NSPrivacyCollectedDataTypes` declaring health data collection

---

## Positive Security Controls

### SQL Injection Protection ✅

All SQLite queries use `sqlite3_prepare_v2` + `sqlite3_bind_text` parameterized statements. No string interpolation into SQL was found. Verified across:
- `EventStorage.swift`
- `EventStorage+Dose.swift`
- `EventStorage+Session.swift`
- `EventStorage+Schema.swift`

### Input Validation ✅

`InputValidator` provides:
- Whitelist-based event name validation for deep links
- Color hex regex validation
- Integer range clamping with safe defaults
- All external inputs (deep links via `URLRouter`) routed through validator

### Certificate Pinning ✅

`CertificatePinning` (Core module) implements:
- SHA-256 SPKI pinning
- `URLSessionDelegate` integration
- Proper logging via `os.Logger`
- Available for iOS 15+, watchOS 8+, macOS 12+

### Secrets Management ✅ (Partial)

`SecureConfig` implements 12-factor app pattern:
1. Environment variables (CI/CD)
2. Keychain storage
3. Fallback to `Secrets.swift` (gitignored)

`DatabaseSecurity` manages encryption keys via Keychain with device-only access.

### No `print()` in Production Code ✅

Zero `print()` calls found in `ios/Core/` and `ios/DoseTap/`. All logging uses `os.Logger`. Compliant with project constitution.

### Data Redaction ✅

`DataRedactor` provides PII/PHI redaction with configurable levels. Uses CryptoKit for hashing device IDs.

### HealthKit Usage Descriptions ✅

Proper NSHealthShareUsageDescription and NSHealthUpdateUsageDescription set in pbxproj build settings (4 target configurations).

---

## Stop Condition Assessment

No P0 findings in this phase. 1 P1 (missing privacy manifest) and 1 P2 (unused CloudKit entitlement). **Proceeding to Phase 4.**
