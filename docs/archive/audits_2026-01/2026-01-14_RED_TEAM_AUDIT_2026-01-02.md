# DoseTap Hypercritical Red Team Audit Report

**Date:** January 2, 2026  
**Auditor:** AI Security Assessment  
**Severity Scale:** P0 (Critical) → P1 (High) → P2 (Medium) → P3 (Low) → P4 (Informational)

---

## Executive Summary

This audit examines DoseTap from an adversarial perspective, focusing on security vulnerabilities, architectural weaknesses, code quality issues, and potential failure modes in a **medical-adjacent medication timing application**.

### Critical Findings Overview

| Severity | Count | Category |
|----------|-------|----------|
| **P0 (Critical)** | 3 | Security, Data Integrity |
| **P1 (High)** | 7 | Security, Reliability |
| **P2 (Medium)** | 9 | Code Quality, Architecture |
| **P3 (Low)** | 8 | Best Practices |
| **P4 (Info)** | 5 | Recommendations |

---

## P0 — Critical Findings (Must Fix Before Any Release)

### P0-1: WHOOP API Credentials Hardcoded in Source

**File:** `ios/DoseTap/Secrets.swift`  
**Evidence:**
```swift
static let whoopClientID = "edf2495a-adff-4b87-b845-9529051a7b39"
static let whoopClientSecret = "0aca5c56ec53b210260d85ac24cf57ced13dc4b4e77cbf7cf2ca20b7d3a9ed9e"
```

**Risk:** While `Secrets.swift` is in `.gitignore`, the file exists on disk with production credentials. If:
- A developer accidentally removes the gitignore entry
- The file is included in an Xcode archive/IPA
- A backup or sync service captures it
- The file was ever committed historically (git log shows no history, but this is a time-bomb)

The client secret would be exposed, enabling:
- Unauthorized API access consuming your rate limit (10,000/day)
- Impersonation of DoseTap to WHOOP users
- Potential access to user health data

**Remediation:**
1. Rotate the WHOOP client secret immediately
2. Move credentials to environment variables or a secure vault (e.g., 1Password CLI, AWS Secrets Manager)
3. Use Xcode build configuration files that are never committed
4. Add pre-commit hook to detect credential patterns

---

### P0-2: OAuth State Parameter Stored in UserDefaults (CSRF Vulnerability)

**File:** `ios/DoseTap/WHOOP.swift` (lines 99-122)  
**Evidence:**
```swift
UserDefaults.standard.set(state, forKey: "whoop_oauth_state")
// ... later ...
let storedState = UserDefaults.standard.string(forKey: "whoop_oauth_state")
```

**Risk:** UserDefaults is:
- Not encrypted at rest
- Readable by other apps in the same app group
- Backed up to iCloud (unless explicitly excluded)
- Visible in device backups

An attacker with physical device access or backup access could:
1. Read the state parameter
2. Craft a malicious OAuth callback URL
3. Complete a CSRF attack to associate their WHOOP account with the victim's DoseTap

**Remediation:**
1. Store OAuth state in Keychain (you already have `KeychainHelper`)
2. Use a short TTL (5 minutes max) and validate expiration
3. Clear state immediately after use (currently done, but storage is insecure)

---

### P0-3: SQLite Database Not Encrypted — PHI at Rest

**File:** `ios/DoseTap/Storage/EventStorage.swift`  
**Evidence:**
```swift
dbPath = documentsPath.appendingPathComponent("dosetap_events.sqlite").path
// ... 
sqlite3_open(dbPath, &db)
```

**Risk:** The SQLite database contains:
- Medication timing data (XYWAV doses)
- Sleep event logs (bathroom visits, anxiety episodes, dreams)
- Morning check-in data (physical symptoms, mental state, narcolepsy flags)
- Pre-sleep logs

This is Protected Health Information (PHI) under HIPAA. Storing it unencrypted means:
- Any app with file access (jailbroken devices) can read it
- Device backups contain plaintext health data
- Forensic analysis of a seized device exposes all history

**Remediation:**
1. Implement SQLCipher or similar encrypted SQLite wrapper
2. Store encryption key in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
3. Consider iOS Data Protection class `.completeUntilFirstUserAuthentication` minimum
4. Add database encryption status to support bundle diagnostics

---

## P1 — High Severity Findings

### P1-1: Force Unwraps in HealthKit Date Calculations

**File:** `ios/DoseTapiOSApp/HealthKitManager.swift` (lines 115, 246, 290)  
**Evidence:**
```swift
guard let yesterday8PM = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: -1, to: now)!),
// ...
var currentTime = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: -1, to: now)!)!
```

**Risk:** These force unwraps will crash the app if:
- Calendar calculations fail (rare but possible with edge-case locales)
- Date arithmetic overflows
- System clock is corrupted

**Remediation:** Use optional binding with fallback dates or explicit error handling.

---

### P1-2: `try!` in Test Code Leaking into Production Patterns

**File:** `ios/DoseTapiOSApp/SetupWizardTests.swift` (lines 249, 252, 360, 393, 399)  
**Evidence:**
```swift
let data = try! JSONEncoder().encode(config)
let decodedConfig = try! JSONDecoder().decode(UserConfig.self, from: data)
try! manager.saveConfiguration(config)
```

**Risk:** While these are in test files, they establish a pattern that developers may copy. The existence of `try!` anywhere normalizes crash-on-error behavior.

**Remediation:** Use `XCTAssertNoThrow` or `do-catch` with `XCTFail` in tests.

---

### P1-3: Excessive `print()` Statements Expose Sensitive Data

**Files:** Multiple (50+ matches across codebase)  
**Evidence:**
```swift
print("🔗 URL \(url.absoluteString) handled: \(handled)")
print("📊 SessionRepository reloaded: session=\(activeSessionDate ?? "none"), dose1=\(d1?.description ?? "nil")")
print("✅ Dose event saved: \(eventType) at \(timestampStr)")
```

**Risk:**
- Console logs are captured in device logs accessible via Xcode/Console.app
- Crash reports may include recent console output
- Medication timing and health events are logged in plaintext
- Deep link URLs may contain sensitive parameters

**Remediation:**
1. Replace all `print()` with `os_log` using appropriate privacy levels
2. Use `%{private}` for any user data
3. Gate verbose logging behind `DEBUG` or a feature flag
4. Add a log redactor to support bundle export (you have `DataRedactor` but it's not used consistently)

---

### P1-4: Singleton Pattern Creates Testing Blind Spots

**Files:** `SessionRepository.shared`, `EventStorage.shared`, `EventLogger.shared`, `UserSettingsManager.shared`, `AlarmService.shared`, `AnalyticsService.shared`, `URLRouter.shared`, `WHOOPManager.shared`  

**Evidence:** 8+ singletons with `static let shared` pattern.

**Risk:**
- Unit tests share state across test cases (test pollution)
- Mocking requires runtime swizzling or dependency injection wrappers
- Race conditions in singleton initialization on multi-threaded access
- Makes isolated testing of components nearly impossible

**Remediation:**
1. Use protocol-based dependency injection
2. Pass dependencies through initializers
3. Use `@MainActor` singletons with explicit initialization
4. Create `MockableXxx` protocols for test doubles

---

### P1-5: Missing Input Validation in Deep Link Handler

**File:** `ios/DoseTap/URLRouter.swift` (lines 55-80)  
**Evidence:**
```swift
case "log":
    let eventName = queryItems.first(where: { $0.name == "event" })?.value ?? "unknown"
    let notes = queryItems.first(where: { $0.name == "notes" })?.value
    return handleLogEvent(name: eventName, notes: notes)
```

**Risk:**
- No validation of `eventName` against allowed event types
- `notes` parameter is stored directly without sanitization
- URL-encoded characters could contain injection payloads
- Excessively long strings could cause UI issues or storage problems

**Attack Vector:**
```
dosetap://log?event=<script>alert(1)</script>&notes=AAAA...10000chars
```

**Remediation:**
1. Whitelist valid event names against `SleepEventType` enum
2. Limit `notes` to 500 characters
3. Strip HTML/script tags from user input
4. Add URL input fuzzing to test suite

---

### P1-6: No Rate Limiting on Local Storage Operations

**File:** `ios/DoseTap/Storage/EventStorage.swift`

**Risk:** While you have `EventRateLimiter` for API calls, local SQLite operations have no throttling:
- Malicious deep links could flood the database
- Automated testing tools could fill storage
- No protection against infinite loops in event logging

**Remediation:**
1. Add local storage rate limiting (max 100 events/minute)
2. Implement database size monitoring with alerts
3. Add automatic purging for extreme cases

---

### P1-7: Notification Permission Requested at App Launch

**File:** `ios/DoseTap/DoseTapApp.swift` (lines 13-16)  
**Evidence:**
```swift
Task { @MainActor in
    let granted = await AlarmService.shared.requestPermission()
    print("🔔 Notification permission: \(granted ? "granted" : "denied")")
}
```

**Risk:**
- Requesting permissions at launch without context leads to lower grant rates
- Users may deny, making the app nearly useless for its core purpose
- No recovery flow if user denies then wants to enable later

**Remediation:**
1. Defer permission request until first dose is logged
2. Show explanatory UI before system prompt
3. Add "Notifications Disabled" warning banner with Settings link
4. Track permission state and re-prompt appropriately

---

## P2 — Medium Severity Findings

### P2-1: Duplicate Code Between Legacy and New Storage

**Files:** `ios/DoseTapiOSApp/SQLiteStorage.swift` vs `ios/DoseTap/Storage/EventStorage.swift`

**Evidence:** Both files contain similar SQLite operations, table schemas, and query patterns. The SSOT states SQLiteStorage is "BANNED" but it still exists in the codebase.

**Risk:**
- Maintenance burden
- Divergent behavior
- Confusion about which to use
- Potential for accidentally re-enabling

**Remediation:**
1. Delete `SQLiteStorage.swift` entirely (not just `#if false`)
2. Remove from Xcode project
3. Add git pre-commit hook to prevent re-addition

---

### P2-2: Inconsistent Error Handling Patterns

**Files:** Various

**Evidence:**
- Some methods throw errors: `savePreSleepLogOrThrow`
- Some methods return optionals: `fetchMorningCheckIn() -> StoredMorningCheckIn?`
- Some methods return bools: `saveDoseEvent() -> Bool`
- Some methods silently fail: `insertSleepEvent()` (just prints error)

**Risk:** Callers don't know how to handle failures consistently. Critical medication data could be silently lost.

**Remediation:** Standardize on Swift 5.5+ async/throws pattern with custom error types.

---

### P2-3: Session Rollover Timer Uses Weak Reference Without Nil Check

**File:** `ios/DoseTap/Storage/SessionRepository.swift` (line 181)  
**Evidence:**
```swift
rolloverTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
    Task { @MainActor in
        self?.updateSessionKeyIfNeeded(reason: "rollover_timer", forceReload: true)
    }
}
```

**Risk:** Timer fires, `self` is nil, session rollover doesn't happen, user stays in yesterday's session indefinitely.

**Remediation:** Add guard check and log warning if self is deallocated unexpectedly.

---

### P2-4: Color Hex Parsing Without Validation

**File:** `ios/DoseTap/UserSettingsManager.swift` (lines 7-30)  
**Evidence:**
```swift
init?(hex: String) {
    var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    // ... no validation of valid hex characters
    guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
```

**Risk:** Malformed hex strings from database corruption or malicious input could cause unexpected UI behavior.

**Remediation:** Add regex validation for `^#?[0-9A-Fa-f]{6,8}$` before parsing.

---

### P2-5: No Database Integrity Checking

**File:** `ios/DoseTap/Storage/EventStorage.swift`

**Risk:** SQLite databases can become corrupted due to:
- Crashes during writes
- Storage full conditions
- iOS killing app during background write

No `PRAGMA integrity_check` or recovery mechanism exists.

**Remediation:**
1. Run `PRAGMA integrity_check` on app launch
2. Implement database backup before migrations
3. Add recovery flow to rebuild from dose_events if current_session corrupts

---

### P2-6: Missing Keychain Access Control

**File:** `ios/DoseTapiOSApp/KeychainHelper.swift` (line 30)  
**Evidence:**
```swift
kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
```

**Risk:** `kSecAttrAccessibleAfterFirstUnlock` means:
- Keychain items accessible while device is locked (after first unlock since boot)
- Accessible to backups (unless `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`)

For OAuth tokens, this is too permissive.

**Remediation:**
1. Use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` for WHOOP tokens
2. Consider `kSecAccessControlBiometryCurrentSet` for high-security items

---

### P2-7: Undo Window Duration Stored in UserDefaults

**File:** `ios/DoseTap/UserSettingsManager.swift` (line 71)  
**Evidence:**
```swift
@AppStorage("undo_window_seconds") var undoWindowSeconds: Double = 5.0
```

**Risk:** User can modify this via Settings UI, but also via:
- Profile install
- MDM manipulation
- Device backup restore from modified backup

An attacker could set this to 0.0, making undo impossible, or to 3600, allowing undo of doses taken an hour ago.

**Remediation:**
1. Clamp values to valid range on read: `max(3.0, min(10.0, undoWindowSeconds))`
2. Validate against `validUndoWindowOptions` array

---

### P2-8: No TLS Certificate Pinning

**Files:** `ios/Core/APIClient.swift`, `ios/DoseTap/WHOOP.swift`

**Risk:** MITM attacks on WiFi networks could intercept:
- Dose timing data sent to API
- WHOOP OAuth tokens during exchange
- Any future PHI transmission

**Remediation:**
1. Implement certificate pinning for `api.dosetap.com`
2. Pin WHOOP API certificates for OAuth flow
3. Use `URLSession` with pinning delegate

---

### P2-9: Timezone Handling Assumes Single Timezone Per Session

**File:** `ios/DoseTap/Storage/SessionRepository.swift` (lines 280-320)

**Evidence:** `dose1TimezoneOffsetMinutes` is stored once at Dose 1 time, but users may:
- Travel across timezones
- Cross DST boundaries

**Risk:** Dose 2 window calculations could be off if user flies across timezones between doses. While `checkTimezoneChange()` exists, it only warns — doesn't adjust.

**Remediation:**
1. Display warning prominently (currently just a message)
2. Consider storing all timestamps in UTC with explicit offset
3. Allow user to acknowledge and dismiss timezone warnings

---

## P3 — Low Severity Findings

### P3-1: Unused Analytics Provider Interface

**File:** `ios/DoseTap/AnalyticsService.swift`  
**Evidence:** `private var providers: [AnalyticsProvider] = []` — never populated.

---

### P3-2: Debug Print Statements in Production Paths

Multiple `print("✅ ...")` statements should use `#if DEBUG`.

---

### P3-3: Magic Numbers in Window Calculations

**Evidence:** `150 * 60`, `240 * 60`, `15 * 60` scattered throughout. Should reference `DoseWindowConfig` constants.

---

### P3-4: No Accessibility Identifiers for UI Testing

Views lack `accessibilityIdentifier` modifiers for XCTest automation.

---

### P3-5: Missing DocC Documentation

Public APIs lack `///` documentation comments.

---

### P3-6: Combine Publishers Not Cancelled on View Dismissal

`sessionChangeCancellable` in `EventLogger` may cause retain cycles.

---

### P3-7: No App Transport Security Exceptions Needed but WHOOP Uses Production API

Currently connecting to `api.prod.whoop.com` — ensure this is intentional for App Store build.

---

### P3-8: WeeklyPlanner Uses UserDefaults Without Migration

**File:** `ios/DoseTap/WeeklyPlanner.swift`  
**Evidence:** Stores JSON in UserDefaults, but no versioned migration if schema changes.

---

## P4 — Informational Observations

### P4-1: Strong SSOT Documentation

The `docs/SSOT/README.md` is comprehensive and should be the model for all specs.

### P4-2: Good Use of Dependency Injection in Tests

`DoseWindowCalculator(now:)` pattern enables deterministic testing.

### P4-3: DataRedactor Exists But Underutilized

`ios/Core/DataRedactor.swift` is well-designed but not applied to logs or exports consistently.

### P4-4: Secrets.swift Never Committed (Verified)

`git log --all -- ios/DoseTap/Secrets.swift` returns empty — good hygiene, but still risky.

### P4-5: Session Notification Identifiers Centralized

`SessionRepository.sessionNotificationIdentifiers` is a good pattern for notification management.

---

## Recommendations Summary

### Immediate Actions (Before Any Beta)

1. ✴️ Rotate WHOOP client secret and move to secure vault
2. ✴️ Implement SQLite encryption (SQLCipher)
3. ✴️ Move OAuth state to Keychain
4. ✴️ Replace `print()` with `os_log` and privacy annotations

### Short-Term (Before App Store Submission)

5. Add TLS certificate pinning
6. Implement input validation for deep links
7. Defer notification permission request
8. Add database integrity checking
9. Standardize error handling patterns

### Medium-Term (Post-Launch)

10. Migrate away from singletons to DI
11. Add accessibility identifiers
12. Implement local storage rate limiting
13. Add comprehensive DocC documentation

---

## Appendix: Files Examined

| Path | Lines | Purpose |
|------|-------|---------|
| `ios/DoseTap/ContentView.swift` | 2942 | Main UI |
| `ios/DoseTap/Storage/SessionRepository.swift` | 1068 | State management |
| `ios/DoseTap/Storage/EventStorage.swift` | 2956 | SQLite persistence |
| `ios/DoseTap/DoseTapApp.swift` | 42 | App entry |
| `ios/DoseTap/UserSettingsManager.swift` | 414 | Settings |
| `ios/DoseTap/SettingsView.swift` | 1605 | Settings UI |
| `ios/DoseTap/WHOOP.swift` | 663 | WHOOP integration |
| `ios/DoseTap/URLRouter.swift` | 315 | Deep links |
| `ios/DoseTap/AlarmService.swift` | 327 | Notifications |
| `ios/Core/APIClient.swift` | 180 | Network layer |
| `ios/Core/APIErrors.swift` | 105 | Error types |
| `ios/Core/DataRedactor.swift` | 234 | PII redaction |
| `ios/DoseTapiOSApp/KeychainHelper.swift` | 135 | Secure storage |
| `docs/SSOT/README.md` | 1761 | Spec document |

---

**Report Generated:** 2026-01-02T22:15:00Z  
**Tool Version:** AI Red Team Audit v1.0  
**Confidence Level:** High (direct code inspection)
