# DoseTap Audit TODO - December 24, 2025

Master tracking for all audit findings. Updated as fixes are completed.

---

## ✅ COMPLETED

| # | Issue | Description | Date |
|---|-------|-------------|------|
| ✅ | Live Bug | Dose number logging (was always "Dose 1") | Dec 24 |
| ✅ | Live Bug | Schema mismatch (fetchDoseLog querying wrong table) | Dec 24 |
| ✅ | Live Bug | Dose persistence (saveDose1/saveDose2 calls added) | Dec 24 |
| ✅ | Live Bug | State restoration on app launch (loadCurrentSession) | Dec 24 |
| ✅ | Feature | Added "In Bed" event type | Dec 24 |
| ✅ | UI | Removed redundant Event History from Details tab | Dec 24 |

---

## ❌ P0 - CRITICAL (This Week)

### 1. [x] AUD-011: Add window validation to takeDose() ✅ DONE
- **File:** `ios/Core/DoseTapCore.swift`
- **Problem:** `takeDose()` allows Dose 2 immediately after Dose 1 (no window check)
- **Fix:** Added guard to check `currentStatus == .active || .nearClose` before setting `dose2Time`
- **Completed:** Dec 24, 2025

### 2. [x] AUD-001: Implement Undo mechanism ✅ DONE

- **Files:** Created `ios/Core/DoseUndoManager.swift`, `Tests/DoseCoreTests/DoseUndoManagerTests.swift`
- **Problem:** Undo documented in SSOT but NOT IMPLEMENTED
- **Fix:** Created DoseUndoManager actor with 5s window, 12 tests added (107 total now)
- **Completed:** Dec 24, 2025

### 3. [x] AUD-002: Move WHOOP tokens to Keychain ✅ DONE

- **File:** `ios/DoseTapiOSApp/HealthIntegrationService.swift`
- **Problem:** Tokens stored in UserDefaults (insecure)
- **Fix:** Changed to use KeychainHelper, added migration to clear legacy UserDefaults
- **Completed:** Dec 24, 2025

### 4. [x] AUD-003: Resolve undo window value conflict ✅ DONE

- **Files:** `docs/SSOT/contracts/SetupWizard.md`, `docs/SSOT/ascii/SetupWizard.md`
- **Problem:** SSOT says 5s, other docs said 15s
- **Fix:** Aligned all docs to 5s (matches DoseUndoManager implementation)
- **Completed:** Dec 24, 2025

---

## ⚠️ P1 - MAJOR (Next 2 Weeks)

### 5. [x] AUD-004: Fix water cooldown doc drift ✅ DONE

- **Files:** `docs/SSOT/README.md`, `docs/README.md`, `docs/FEATURE_ROADMAP.md`
- **Problem:** Code uses 300s, docs said 60s
- **Fix:** Changed all docs to 300s (5m) to match SleepEvent.swift
- **Completed:** Dec 24, 2025

### 6. [x] AUD-005: Add EventRateLimiter tests ✅ DONE

- **File:** `Tests/DoseCoreTests/EventRateLimiterTests.swift`
- **Problem:** Only 1 test for component with 6 public methods
- **Fix:** Added 16 comprehensive tests (123 total now)
- **Completed:** Dec 24, 2025

### 7. [x] AUD-006: Implement basic watchOS timer ✅ DONE

- **File:** `watchos/DoseTapWatch/ContentView.swift`
- **Problem:** watchOS companion was stub (no timer, no phase display)
- **Fix:** Added WatchDoseViewModel, TimerDisplay, phase-based UI, countdown timer
- **Completed:** Dec 24, 2025

### 8. [x] AUD-007: Consolidate SSOT documents ✅ DONE

- **Files:** `docs/SSOT/README.md`, `docs/SSOT/SSOT_v2.md`
- **Problem:** Both claimed to be authoritative
- **Fix:** Added deprecation notice to SSOT_v2.md, marked README.md as canonical
- **Completed:** Dec 24, 2025

---

## 📋 P2 - CLEANUP (Next Month)

### 9. [x] AUD-008: Implement OfflineQueue backoff ✅ DONE

- **File:** `ios/Core/OfflineQueue.swift`
- **Problem:** TODO in code - backoff delay not implemented
- **Fix:** Added exponential backoff with `Task.sleep`
- **Completed:** Dec 24, 2025

### 10. [x] AUD-009: Fix DoseCoreIntegration rate limiter ✅ DONE

- **File:** `ios/DoseTapiOSApp/DoseCoreIntegration.swift`
- **Problem:** Uses hardcoded `{bathroom: 60}` instead of `EventRateLimiter.default`
- **Fix:** Changed to `EventRateLimiter.default`
- **Completed:** Dec 24, 2025

### 11. [x] AUD-010: Update Phase 2 status in docs ✅ DONE

- **File:** `docs/IMPLEMENTATION_PLAN.md`
- **Problem:** Shows Phase 2 features as "In Progress" but code doesn't exist
- **Fix:** Changed to "Planned (Not Started)"
- **Completed:** Dec 24, 2025

### 12. [x] AUD-012: Add README known issues section ✅ DONE

- **File:** `README.md`
- **Problem:** No documentation of known gaps
- **Fix:** Added "Known Issues & Limitations" section
- **Completed:** Dec 24, 2025

---

## Progress

- **Total Issues:** 12
- **Completed:** 12 ✅
- **Remaining:** 0
- **Original Audit Score:** 58/100
- **Final Status:** ALL AUDIT ITEMS RESOLVED

---

Last updated: December 24, 2025
