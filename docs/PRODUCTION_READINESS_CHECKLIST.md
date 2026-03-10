# DoseTap Production Readiness Checklist

**Date:** 2026-02-13  
**Branch:** `004-dosing-amount-model`  
**Version:** 2.1.0

---

## Audit Status Summary

### ✅ COMPLETED

| Item | Status | Evidence |
|------|--------|----------|
| **Legacy persistence layer removed** | ✅ Done | Commit `ae4e7f1` - PersistentStore gutted, xcdatamodel deleted |
| **Event type normalization migration** | ✅ Done | `EventStorage.migrateEventTypes()` added |
| **Dose duplication fix (new data)** | ✅ Done | ContentView no longer writes doses to sleep_events |
| **iCloud toggle disabled** | ✅ Done | SetupWizardView toggle hidden |
| **Privacy manifest added** | ✅ Done | `PrivacyInfo.xcprivacy` in bundle |
| **SwiftPM build passes** | ✅ Done | 0 errors, 0 warnings |
| **497 SwiftPM unit tests pass** | ✅ Done | `swift test -q` (29 test files) |
| **12 XCUITest smoke tests added** | ✅ Done | DoseTapUITests target |
| **Xcode app build passes** | ✅ Done | BUILD SUCCEEDED |
| **ContentView god file split** | ✅ Done | 2,850 → 228 lines, 8 extracted files |
| **EventStorage god file split** | ✅ Done | 1,948 → 277 lines, 3 extension files |
| **CI governance active** | ✅ Done | 3 workflows + branch protection |
| **ios/build/ added to gitignore** | ✅ Done | Commit `ae4e7f1` |

### ⏳ PENDING VERIFICATION (Requires Runtime Testing)

| Item | Status | Acceptance Criteria |
|------|--------|---------------------|
| **No dose entries in sleep_events** | ⏳ Pending | After app use: `SELECT count(*) FROM sleep_events WHERE lower(event_type) LIKE '%dose%'` = 0 |
| **Event types are snake_case** | ⏳ Pending | All `sleep_events.event_type` values in snake_case |
| **Timeline/History parity** | ⏳ Pending | UI shows identical events in Timeline and History tabs |
| **CSV export works** | ⏳ Pending | Export produces valid CSV with all events |
| **Migration runs on upgrade** | ⏳ Pending | Existing data normalized after app update |

### 🔴 REMAINING P0/P1 ISSUES (from Audit)

| Priority | Issue | Status | Effort |
|----------|-------|--------|--------|
| **P0** | Session ID consistency (UUID vs date fallback) | 🔴 Not started | 6h |
| **P1** | CSV export async + error handling | 🔴 Not started | 4h |
| **P1** | FK constraints for cascade deletes | 🔴 Not started | 3h |
| **P2** | Move DB off main thread | 🔴 Not started | 8h |

---

## Runtime Verification Steps

### Step 1: Fresh Install Test
```bash
# Boot simulator
xcrun simctl boot "iPhone 17 Pro"

# Uninstall and reinstall
xcrun simctl uninstall booted com.dosetap.ios
xcrun simctl install booted /tmp/DoseTapBuild/Build/Products/Debug-iphonesimulator/DoseTap.app
xcrun simctl launch booted com.dosetap.ios
```

### Step 2: Create Test Data (Manual)
In the app:
1. Tap "Take Dose 1"
2. Tap quick log buttons: Bathroom, Lights Out, Water
3. Wait for dose window or tap "Take Dose 2"
4. Complete morning check-in

### Step 3: Database Verification
```bash
CONTAINER=$(xcrun simctl get_app_container booted com.dosetap.ios data)
sqlite3 "$CONTAINER/Documents/dosetap_events.sqlite" << 'EOF'
.headers on
.mode column

-- Check no doses in sleep_events
SELECT '=== Dose in sleep_events (should be 0) ===' as check;
SELECT count(*) as cnt FROM sleep_events WHERE lower(event_type) LIKE '%dose%';

-- Check event type format
SELECT '=== sleep_events event_types ===' as check;
SELECT DISTINCT event_type FROM sleep_events ORDER BY event_type;

-- Check dose_events
SELECT '=== dose_events event_types ===' as check;
SELECT DISTINCT event_type FROM dose_events ORDER BY event_type;

-- Count totals
SELECT '=== Row counts ===' as check;
SELECT 'dose_events' as tbl, count(*) as cnt FROM dose_events
UNION ALL
SELECT 'sleep_events', count(*) FROM sleep_events
UNION ALL
SELECT 'sleep_sessions', count(*) FROM sleep_sessions;
EOF
```

### Step 4: CSV Export Test
1. Go to Settings > Export Data
2. Export CSV
3. Verify file contains:
   - UTF-8 BOM
   - Proper headers
   - All events from both tables
   - No duplicates

### Step 5: Timeline/History Parity Test
1. Open Timeline tab - note events shown
2. Open History tab - compare events
3. Both should show identical data (doses + sleep events)

---

## Go/No-Go Criteria

### ✅ GO (Safe to Ship)
- [ ] All P0 items verified or fixed
- [ ] Runtime verification steps pass
- [ ] CSV export produces valid output
- [ ] No crash in 10-minute smoke test
- [ ] Timeline/History show matching data

### 🔴 NO-GO (Block Ship)
- Session ID still uses date fallback for new sessions
- Dose entries appear in sleep_events after new actions
- CSV export fails silently
- App crashes during normal use

---

## Current Assessment

| Criteria | Status |
|----------|--------|
| **Code changes committed** | ✅ Yes |
| **Build passes** | ✅ Yes |
| **Tests pass** | ✅ Yes (497 SwiftPM + 134 Xcode + 12 XCUITest) |
| **Runtime verified** | ⏳ Pending (needs manual testing) |
| **P0 issues resolved** | ⚠️ Partial (1 of 3 done) |
| **P1 issues resolved** | 🔴 Not started |

### Verdict: **NOT YET PRODUCTION READY**

**Blockers:**
1. Runtime verification not yet completed (user needs to test in app)
2. P0: Session ID consistency not addressed
3. P1: CSV export error handling not implemented

**Recommendation:**
1. Complete runtime verification (15 min manual testing)
2. If P0-2 (session ID) can be deferred, ship with known limitation documented
3. For App Store submission, complete at least P0s and P1-1 (CSV export)

---

## Quick Commands Reference

```bash
# Build
cd /Volumes/Developer/projects/DoseTap/ios
xcodebuild -project DoseTap.xcodeproj -scheme DoseTap -sdk iphonesimulator -configuration Debug -derivedDataPath /tmp/DoseTapBuild build

# Run tests
swift test -q

# Install to simulator
xcrun simctl install booted /tmp/DoseTapBuild/Build/Products/Debug-iphonesimulator/DoseTap.app

# Check DB
CONTAINER=$(xcrun simctl get_app_container booted com.dosetap.ios data)
sqlite3 "$CONTAINER/Documents/dosetap_events.sqlite" ".tables"
```
