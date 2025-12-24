# DoseTap HyperCritical Audit Report

**Audit Date:** December 24, 2025  
**Auditor:** Senior Principal iOS Engineer + Security Reviewer + QA Lead  
**Scope:** Full codebase surgical audit against SSOT  

---

## 1. Executive Audit Summary

### Readiness Score: 58/100

**Justification:**
- Core DoseCore module is well-architected with 95 passing tests
- SSOT documents are comprehensive but contain internal conflicts
- Critical safety features (undo mechanism) are NOT IMPLEMENTED despite being documented
- Security posture is mixed: Keychain helper exists but not universally used
- Test coverage is shallow for rate limiting and integration scenarios
- watchOS companion is a stub with no real functionality

### Issue Breakdown

| Severity | Count | Examples |
| -------- | ----- | -------- |
| **P0 (Blocker)** | 3 | Undo not implemented, WHOOP tokens in UserDefaults, Doc drift on undo window |
| **P1 (Major)** | 5 | Water cooldown conflict, EventRateLimiter undertested, watchOS stub, SSOT duplication |
| **P2 (Cleanup)** | 7 | Legacy files, test naming inconsistency, missing Phase 2 features |

---

## 2. Findings Report

### AUD-001: Undo Mechanism NOT IMPLEMENTED

**Severity:** P0  
**Category:** Logic, UX, Safety  

**Evidence:**
- SSOT states: "Undo window: 5 seconds" for all dose actions
- `docs/SSOT/README.md` line 81: `| Undo Window | **5 seconds** | For all dose actions |`
- `docs/SSOT/SSOT_v2.md` line 46: `| Undo window | 5 seconds | Time to undo accidental tap |`
- Searched entire codebase for `undo`, `Undo`, `UNDO` - NO implementation found
- `UndoManager.swift`, `UndoSnackbar.swift` mentioned in copilot-instructions but files do NOT EXIST

**Impact:**
- Users cannot undo accidental dose taps
- Violates SSOT safety requirements
- Could lead to incorrect medication tracking

**Fix:**
1. Create `ios/Core/UndoManager.swift` with 5-second timer and cancellation token
2. Create `ios/DoseTapiOSApp/UndoSnackbar.swift` SwiftUI component
3. Integrate into `DoseCoreIntegration.takeDose1()`, `takeDose2()`, `skip()`
4. Cancel pending API calls in `OfflineQueue` if undo triggered

**Tests to Add:**
- `testUndo_withinWindow_revertsState()`
- `testUndo_afterWindow_noEffect()`
- `testUndo_cancelsQueuedAPICall()`
- `testUndo_multipleActions_onlyRevertsLast()`

---

### AUD-002: WHOOP Tokens Stored in UserDefaults (Security Violation)

**Severity:** P0  
**Category:** Security  

**Evidence:**
- `ios/DoseTapiOSApp/HealthIntegrationService.swift` lines 263-270:
```swift
accessToken = UserDefaults.standard.string(forKey: "whoop_access_token")
refreshToken = UserDefaults.standard.string(forKey: "whoop_refresh_token")
```
- `KeychainHelper.swift` EXISTS and is used correctly in `ios/DoseTap/WHOOP.swift`
- Two different token storage mechanisms in codebase

**Impact:**
- OAuth tokens accessible without device unlock
- Violates Apple security guidelines
- Could expose user's WHOOP account data

**Fix:**
1. Replace UserDefaults calls in `HealthIntegrationService.swift` with `KeychainHelper.shared`
2. Remove all `UserDefaults` references for sensitive data
3. Add migration path for existing users

**Tests to Add:**
- `testTokenStorage_usesKeychain()`
- `testTokenStorage_notInUserDefaults()`
- `testTokenMigration_fromUserDefaultsToKeychain()`

---

### AUD-003: Undo Window Value Conflict

**Severity:** P0  
**Category:** Docs, State Machine  

**Evidence:**
- SSOT: "5 seconds" (both `SSOT_v2.md` line 46 and `README.md` line 81)
- `ios/DoseTapiOSApp/SetupWizardService.swift` line 40: `var undoWindowSeconds: Int = 15`
- `ios/DoseTapiOSApp/SetupWizardView_Enhanced.swift` lines 431-433: Options are 10s, 15s, 30s (NO 5s option)
- `docs/SSOT/contracts/SetupWizard.md` line 49: `undo_window_seconds: Integer (default 15, range 10-30)`

**Impact:**
- Contract conflict between SSOT and implementation spec
- User confusion about actual undo duration
- If 5s is correct, current setup is unsafe; if 15s is correct, SSOT is wrong

**Fix:**
Determine canonical value and update ALL sources:
- If 5s: Update SetupWizard default and range to include 5s
- If 15s: Update SSOT core invariants table

**Tests to Add:**
- `testUndoWindow_defaultMatchesSSOT()`

---

### AUD-004: Water Cooldown Value Conflict (DOC DRIFT)

**Severity:** P1  
**Category:** Docs, Logic  

**Evidence:**
- `docs/SSOT/README.md` line 109: `| Water | water | 60s | Physical |`
- `docs/SSOT/SSOT_v2.md` line 455: `water: 300s`
- `docs/SSOT/SSOT_v2.md` line 614: `| water | 300s | Multiple drinks |`
- `ios/Core/SleepEvent.swift` line 46: `case .water: return 300`
- `docs/FEATURE_ROADMAP.md` line 138: `| water | 60s |`

**Impact:**
- Inconsistent behavior depending on which doc developers reference
- Could frustrate users if they expect different cooldown

**Fix:**
Canonical value should be **300 seconds** (5 min) per code. Update:
1. `docs/SSOT/README.md` line 109: Change `60s` to `300s`
2. `docs/FEATURE_ROADMAP.md` line 138: Change `60s` to `300s`

**Tests to Add:**
- `testWaterCooldown_is300Seconds()` (exists conceptually in SleepEventTests)

---

### AUD-005: EventRateLimiter Has Only 1 Test

**Severity:** P1  
**Category:** Tests  

**Evidence:**
- `Tests/DoseCoreTests/EventRateLimiterTests.swift` has exactly 1 test: `testBathroomDebounce60s`
- EventRateLimiter has 6 public methods: `register`, `shouldAllow`, `canLog`, `remainingCooldown`, `reset`, `resetAll`
- 12 different event types with varying cooldowns (60s to 3600s)

**Impact:**
- Most EventRateLimiter functionality is untested
- Could allow rapid event spam to hit API
- Edge cases (boundary values, concurrent events) not verified

**Fix:**
Add comprehensive tests:

**Tests to Add:**
- `testLightsOutCooldown_3600Seconds()`
- `testCanLog_doesNotRegister()`
- `testRemainingCooldown_accurateCalculation()`
- `testReset_clearsSpecificEvent()`
- `testResetAll_clearsAllEvents()`
- `testConcurrentEvents_differentTypesAllowed()`
- `testBoundary_exactlyCooldownElapsed()`
- `testBoundary_oneLessSecond()`

---

### AUD-006: watchOS Companion is a Stub

**Severity:** P1  
**Category:** Feature Completeness  

**Evidence:**
- `watchos/DoseTapWatch/ContentView.swift` is 31 lines total
- Only 4 buttons: Dose 1, Dose 2, Bathroom, Snooze
- NO window logic, NO timer display, NO phase state
- SSOT `README.md` "Definition of Done" for watchOS:
  - `[ ] Complications update within 1 minute`
  - `[ ] Timer shows on watch face`
  - `[ ] Offline mode clearly indicated`
  - `[ ] Battery usage <5% per night`

**Impact:**
- watchOS users have no visibility into dose window status
- PRD lists watchOS as P0 Complete but it's not functional
- Safety risk: users may take dose outside window without timer

**Fix:**
1. Port `DoseWindowCalculator` context to watch
2. Add timer display showing remaining window time
3. Add phase-based button states (disable Dose 2 outside window)
4. Implement complications

**Tests to Add:**
- `testWatch_dose2Button_disabledOutsideWindow()`
- `testWatch_timerDisplay_matchesiOS()`

---

### AUD-007: Dual SSOT Documents

**Severity:** P1  
**Category:** Docs  

**Evidence:**
- `docs/SSOT/SSOT_v2.md`: Version 2.1.0, Last Updated December 23, 2025
- `docs/SSOT/README.md`: Version 2.1.0, Last Updated January 6, 2025
- Both claim to be "authoritative" and "supersede all previous documents"
- Content differs (e.g., cooldown tables, module structure)

**Impact:**
- Developers may reference wrong doc
- Conflicts like water cooldown occur
- Maintenance burden doubles

**Fix:**
1. Designate ONE authoritative file (recommend `README.md` as it's more recent)
2. Add deprecation notice to `SSOT_v2.md` pointing to `README.md`
3. Merge any unique content from `SSOT_v2.md` into `README.md`
4. Update `navigation.md` to clarify which is canonical

---

### AUD-008: OfflineQueue Missing Backoff Implementation

**Severity:** P2  
**Category:** Logic  

**Evidence:**
- `ios/Core/OfflineQueue.swift` lines 52-54:
```swift
// TODO: Implement proper backoff delay when needed
// let delay = pow(config.backoffBaseSeconds, Double(task.attempts))
// For now, we just increment attempts and retry immediately
```

**Impact:**
- Under failure conditions, queue will spam retries without delay
- Could hit rate limits
- Non-deterministic behavior in tests

**Fix:**
Implement actual exponential backoff:
```swift
let delay = pow(config.backoffBaseSeconds, Double(task.attempts))
try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
```

**Tests to Add:**
- `testBackoff_delayIncreases()`
- `testBackoff_respectsMaxRetries()`

---

### AUD-009: DoseCoreIntegration Uses Hardcoded Legacy Cooldown

**Severity:** P2  
**Category:** Logic  

**Evidence:**
- `ios/DoseTapiOSApp/DoseCoreIntegration.swift` line 61:
```swift
let rateLimiter = EventRateLimiter(cooldowns: ["bathroom": 60])
```
- Should use `EventRateLimiter.default` which has all 12 event cooldowns

**Impact:**
- Only bathroom events are rate-limited in production
- Other events can be spammed without cooldown

**Fix:**
Change to:
```swift
let rateLimiter = EventRateLimiter.default
```

**Tests to Add:**
- `testDoseCoreIntegration_usesDefaultRateLimiter()`

---

### AUD-010: Missing Phase 2 Features Listed as "In Progress"

**Severity:** P2  
**Category:** Docs  

**Evidence:**
- `docs/IMPLEMENTATION_PLAN.md` lists these as "Phase 2 Next":
  - `SleepDataAggregator` - NOT FOUND in codebase
  - `HeartRateChartView` - NOT FOUND
  - `WHOOPRecoveryCard` - NOT FOUND
  - `SleepStagesChart` - NOT FOUND

**Impact:**
- Misleading status indicators
- Feature roadmap out of sync with reality

**Fix:**
Update `IMPLEMENTATION_PLAN.md` status to "📋 Planned" not "🔄 IN PROGRESS" for unstarted items

---

## 3. Doc Drift Table

| Topic | SSOT Statement | Conflicting Statement | Source | Risk | Fix |
| ----- | -------------- | --------------------- | ------ | ---- | --- |
| Undo Window | "5 seconds" | "15 seconds (default)" | SetupWizard.md | HIGH - Safety | Align to single value |
| Water Cooldown | "300s" (SSOT_v2) | "60s" | README.md line 109 | MEDIUM | Change README to 300s |
| Water Cooldown | "300s" (SSOT_v2) | "60s" | FEATURE_ROADMAP.md | MEDIUM | Change to 300s |
| Test Count | "95 tests" | "95 tests (NEW)" | SSOT_v2.md | LOW - Outdated label | Remove "(NEW)" |
| Phase 2 Status | Not started | "🔄 IN PROGRESS" | IMPLEMENTATION_PLAN.md | MEDIUM | Change to 📋 Planned |

---

## 4. Traceability Matrix

### Core Invariants

| Invariant | SSOT Reference | Implementing File | Test File | Gap |
| --------- | -------------- | ----------------- | --------- | --- |
| Min interval 150m | SSOT_v2 §1 | DoseWindowState.swift:13 | DoseWindowEdgeTests:test_exact_150 | ✅ None |
| Max interval 240m | SSOT_v2 §1 | DoseWindowState.swift:14 | DoseWindowEdgeTests:test_exact_240 | ✅ None |
| Default target 165m | SSOT_v2 §1 | DoseWindowState.swift:16 | DoseWindowEdgeTests:test_exact_165 | ✅ None |
| Near-close 15m | SSOT_v2 §1 | DoseWindowState.swift:15 | DoseWindowStateTests:test_nearClose | ✅ None |
| Snooze step 10m | SSOT_v2 §1 | DoseWindowState.swift:17 | None | ⚠️ No direct test |
| Max snoozes 3 | SSOT_v2 §1 | DoseWindowState.swift:18 | DoseWindowStateTests:test_snoozeLimitReached | ✅ None |
| Undo 5s | SSOT_v2 §1 | **NOT IMPLEMENTED** | None | ❌ CRITICAL |
| UTC timestamps | SSOT_v2 §1 | APIClient.swift (ISO8601) | Indirect | ⚠️ No direct test |
| Offline queue | SSOT_v2 §1 | OfflineQueue.swift | OfflineQueueTests | ✅ Partial |
| Rate limiting | SSOT_v2 §7 | EventRateLimiter.swift | EventRateLimiterTests | ⚠️ Shallow |

### API Endpoints

| Endpoint | SSOT Reference | Implementing Method | Test | Gap |
| -------- | -------------- | ------------------- | ---- | --- |
| POST /doses/take | SSOT_v2 §5 | APIClient.takeDose() | APIClientTests | ✅ None |
| POST /doses/snooze | SSOT_v2 §5 | APIClient.snooze() | APIClientTests | ✅ None |
| POST /doses/skip | SSOT_v2 §5 | APIClient.skipDose() | APIClientTests | ✅ None |
| POST /events/log | SSOT_v2 §5 | APIClient.logEvent() | APIClientTests | ✅ None |
| GET /analytics/export | SSOT_v2 §5 | APIClient.exportAnalytics() | APIClientTests | ✅ None |

### Error Codes

| Error Code | SSOT Reference | APIError Case | Test | Gap |
| ---------- | -------------- | ------------- | ---- | --- |
| 422 WINDOW_EXCEEDED | SSOT_v2 §6 | .windowExceeded | APIErrorsTests | ✅ None |
| 422 SNOOZE_LIMIT | SSOT_v2 §6 | .snoozeLimit | APIErrorsTests | ✅ None |
| 422 DOSE1_REQUIRED | SSOT_v2 §6 | .dose1Required | APIErrorsTests | ✅ None |
| 409 ALREADY_TAKEN | SSOT_v2 §6 | .alreadyTaken | APIErrorsTests | ✅ None |
| 429 RATE_LIMIT | SSOT_v2 §6 | .rateLimit | APIErrorsTests | ✅ None |
| 401 DEVICE_NOT_REGISTERED | SSOT_v2 §6 | .deviceNotRegistered | APIErrorsTests | ✅ None |

---

## 5. Test Quality Scores

| Suite | Tests | Coverage | Assertions/Test | Edge Cases | Score | Notes |
| ----- | ----- | -------- | --------------- | ---------- | ----- | ----- |
| DoseWindowStateTests | 7 | Good | 1-2 | Partial | 2 | Missing snooze step test |
| DoseWindowEdgeTests | 6 | Excellent | 1-2 | Good | 3 | DST test included |
| APIClientTests | 11 | Good | 1-2 | Partial | 2 | No timeout/retry tests |
| APIErrorsTests | 12 | Excellent | 1-2 | Good | 3 | All error codes covered |
| CRUDActionTests | 25 | Comprehensive | 1-3 | Good | 3 | State transitions tested |
| OfflineQueueTests | 4 | Partial | 1-2 | Minimal | 2 | Missing backoff test |
| EventRateLimiterTests | 1 | **Poor** | 3 | None | 1 | Only bathroom tested |
| SleepEventTests | 29 | Excellent | 1-2 | Good | 3 | All event types covered |

**Overall Test Score: 2.4/4 (Acceptable with gaps)**

---

## 6. Proposed README Updates

```diff
--- a/README.md
+++ b/README.md
@@ -16,6 +16,10 @@ DoseTap is a medication timing app...
 3.  **Warning**: Do not commit secrets to `Config.plist`.
+4.  **Important**: WHOOP tokens MUST be stored in Keychain, not UserDefaults.
+5.  **Note**: Undo functionality is not yet implemented. See AUD-001 in AUDIT_LOG.md.

+## Known Issues
+- Undo mechanism documented but not implemented (P0)
+- watchOS companion is a stub without timer display (P1)
+- See `AUDIT_LOG.md` for full audit findings
```

---

## 7. Recommended Actions (Priority Order)

### Immediate (P0 - This Week)
1. Implement undo mechanism with 5-second timer
2. Fix WHOOP token storage to use Keychain
3. Resolve undo window value (5s vs 15s) across all docs

### Short-term (P1 - Next 2 Weeks)
1. Merge/consolidate SSOT documents
2. Fix water cooldown doc drift
3. Add comprehensive EventRateLimiter tests
4. Implement basic watchOS timer display

### Medium-term (P2 - Next Month)
1. Implement OfflineQueue backoff delay
2. Fix DoseCoreIntegration to use default rate limiter
3. Update Phase 2 status in implementation docs
4. Add integration tests for full dose flow

---

## 8. Additional Findings from Live App Testing (Dec 24 2025)

### AUD-011: CRITICAL - Dose 2 Can Be Taken Immediately After Dose 1

**Severity:** P0  
**Category:** Logic, Safety  

**Evidence (from screenshots):**
- Dose 1 taken at 8:23 AM
- Dose 2 taken at 8:23 AM (SAME TIME!)
- Window Opens shows 10:53 AM
- Window Closes shows 12:23 PM
- Interval shows "0 minutes"

**Root Cause:** `ios/Core/DoseTapCore.swift` lines 57-68:
```swift
public func takeDose() async {
    let now = Date()
    await MainActor.run {
        if dose1Time == nil {
            dose1Time = now
        } else {
            dose2Time = now  // NO VALIDATION OF WINDOW!
        }
        updateStatus()
    }
}
```

The `takeDose()` function does NOT check if the dose window is open before setting `dose2Time`. The UI checks `currentStatus == .beforeWindow` but this check can be bypassed.

**Impact:**
- SAFETY VIOLATION: Users can take Dose 2 immediately after Dose 1
- Violates core invariant of 150-minute minimum
- Could lead to medication overdose

**Fix:**
```swift
public func takeDose() async {
    let now = Date()
    await MainActor.run {
        if dose1Time == nil {
            dose1Time = now
        } else {
            // VALIDATE WINDOW BEFORE ALLOWING DOSE 2
            guard currentStatus == .active || currentStatus == .nearClose else {
                print("❌ Cannot take Dose 2: window not open")
                return
            }
            dose2Time = now
        }
        updateStatus()
    }
}
```

**Tests to Add:**
- `testTakeDose2_beforeWindow_rejected()`
- `testTakeDose2_afterWindowClosed_rejected()`
- `testTakeDose2_duringWindow_allowed()`

---

### AUD-012: History View Shows "No dose data" Despite Doses Being Taken

**Severity:** P1  
**Category:** Storage, UI Sync  

**Evidence (from screenshots):**
- Details tab shows: Dose 1 at 8:23 AM, Dose 2 at 8:23 AM
- History tab shows: "No dose data for this date"
- History tab DOES show events (Bathroom, Water, Dose 1)

**Root Cause:** Two separate storage systems:
1. `DoseTapCore` stores doses in memory only (not persisted)
2. `EventStorage` stores events in SQLite
3. `EventLogger.logEvent()` stores "Dose 1" as a sleep event, not a dose log

The `fetchDoseLog()` queries `dose_events` table, but doses are only stored in memory via `DoseTapCore.dose1Time/dose2Time`. The dose times are never written to the `dose_events` table.

**Impact:**
- Lost dose data on app restart
- History view is broken
- No persistent record of medication

**Fix:**
1. In `DoseTapCore.takeDose()`, persist to SQLite:
```swift
// After setting dose1Time or dose2Time:
EventStorage.shared.insertDoseLog(dose1Time: dose1Time, dose2Time: dose2Time, ...)
```
2. On app launch, load dose state from SQLite

**Tests to Add:**
- `testDoseLog_persistsToSQLite()`
- `testHistory_showsDoseData()`
- `testAppRestart_restoresDoseState()`

---

### AUD-013: Missing "In Bed" Event Type

**Severity:** P2  
**Category:** Feature Gap  

**Evidence:**
- User requested "In Bed" event (distinct from "Lights Out")
- SSOT lists 12 event types, none is "In Bed"
- Common use case: getting in bed to read, watch TV before sleep

**Current event types (12):**
1. Bathroom, Water, Snack (Physical)
2. Lights Out, Wake Up, Brief Wake (Sleep Cycle)
3. Anxiety, Dream, Heart Racing (Mental)
4. Noise, Temperature, Pain (Environment)

**Missing recommended events:**
- **In Bed** - Getting into bed (before lights out)
- **Get Up** - Getting out of bed (distinct from Wake Up)
- **Medication** - Taking other meds/vitamins
- **Caffeine** - Late caffeine (affects sleep)
- **Alcohol** - Affects XYWAV metabolism
- **Screen Time** - Phone/TV before bed

**Fix:**
Add to `ios/Core/SleepEvent.swift`:
```swift
case inBed          // Got into bed
case getUp          // Got out of bed  
case medication     // Took other medication
case caffeine       // Consumed caffeine
case alcohol        // Consumed alcohol
case screenTime     // Phone/TV usage
```

---

### AUD-014: Tonight Tab Shows Only 4 Events vs Details Tab Shows 12

**Severity:** P2  
**Category:** UX Inconsistency  

**Evidence (from screenshots):**
- Tonight tab "Quick Log": 4 buttons (Bathroom, Water, Brief Wake, Anxiety)
- Details tab "Log Sleep Event": 12 buttons (all event types)

**Root Cause:** `QuickEventPanel` in `ContentView.swift` lines 554-560 hardcodes 4 events:
```swift
private var quickEvents: [(name: String, icon: String, color: Color)] {
    [
        ("Bathroom", "toilet.fill", .blue),
        ("Water", "drop.fill", .cyan),
        ("Brief Wake", "moon.zzz.fill", .indigo),
        ("Anxiety", "brain.head.profile", .purple)
    ]
}
```

**Impact:**
- Users must switch to Details tab for other events
- Inconsistent logging experience

**Fix Options:**
1. Add scroll/expand to show all 12 on Tonight tab
2. Make quick events user-configurable in Settings
3. Show 8 most-used events

---

### AUD-015: Dose Events Mixed with Sleep Events in Timeline

**Severity:** P2  
**Category:** UX  

**Evidence (from screenshot 4):**
- Event History shows: Bathroom, Water, **Dose 1** at 8:23 AM
- "Dose 1" is logged as an event via `eventLogger.logEvent(name: "Dose 1", ...)`

**Root Cause:** `CompactDoseButton.handlePrimaryButtonTap()` calls:
```swift
eventLogger.logEvent(name: "Dose 1", color: .green, cooldownSeconds: 3600 * 8)
```

This treats doses as sleep events rather than separate dose records.

**Impact:**
- Mixes medication logs with sleep events
- Dose data not structured correctly
- Could confuse analytics

**Fix:**
- Store doses in `dose_events` table, not `sleep_events`
- Show doses in separate section or with distinct visual treatment

---

## 9. Updated Priority List

### P0 (Blockers - THIS WEEK)
1. **AUD-011**: Fix Dose 2 validation to enforce 150-minute window
2. **AUD-001**: Implement undo mechanism
3. **AUD-012**: Fix dose persistence to SQLite
4. **AUD-002**: Move WHOOP tokens to Keychain

### P1 (Major - Next 2 Weeks)
5. **AUD-003**: Resolve undo window value (5s vs 15s)
6. **AUD-004**: Fix water cooldown doc drift
7. **AUD-005**: Add EventRateLimiter tests
8. **AUD-006**: Implement basic watchOS timer
9. **AUD-007**: Consolidate SSOT documents

### P2 (Cleanup - Next Month)
10. **AUD-013**: Add "In Bed" and other missing events
11. **AUD-014**: Expand Tonight tab quick events
12. **AUD-015**: Separate dose logs from event timeline
13. **AUD-008**: Implement offline queue backoff
14. **AUD-009**: Use default rate limiter

---

*Audit completed December 24, 2025*
