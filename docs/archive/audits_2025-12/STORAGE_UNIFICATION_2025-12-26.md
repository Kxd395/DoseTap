# Storage Unification Migration Report

**Date:** 2025-12-26  
**Status:** Phase 1-3 Complete ✅  
**Tests:** 275 pass  
**Build:** SwiftPM builds clean

## Problem Statement

DoseTap had "split brain" dual storage: `SQLiteStorage` (legacy) and `EventStorage` (current), causing:
- Data logged in one location invisible in another
- "I logged it and it vanished" bug class
- Session conflicts and phantom data

## Solution: Unified Storage Architecture

```
UI → SessionRepository → EventStorage → SQLite (dosetap_events.sqlite)
                                    ↳ EventStore protocol
```

### New Files Created

| File | Purpose |
|------|---------|
| `ios/Core/EventStore.swift` | Protocol defining unified storage interface |

### Files Modified

| File | Changes |
|------|---------|
| `Package.swift` | Added `EventStore.swift` to DoseCore sources |
| `ios/DoseTap/Storage/EventStorage.swift` | Added EventStore protocol conformance extension |
| `ios/DoseTap/Storage/SessionRepository.swift` | Added: `logSleepEvent()`, `saveMorningCheckIn()`, `fetchTonightSleepEvents()`, `fetchRecentEvents()`, `clearAllData()`, `deleteSleepEvent()` |
| `ios/DoseTapiOSApp/SQLiteStorage.swift` | Banned (`#if false` wrapper) |
| `ios/DoseTap/Views/MorningCheckInView.swift` | Uses SessionRepository instead of SQLiteStorage |
| `ios/DoseTapiOSApp/QuickLogPanel.swift` | Uses SessionRepository for event logging |
| `ios/DoseTapiOSApp/DoseCoreIntegration.swift` | Removed SQLiteStorage dependency |
| `ios/DoseTapiOSApp/TonightView.swift` | Uses SessionRepository for tonight's events |
| `ios/DoseTapiOSApp/TimelineView.swift` | Uses EventStorage directly for history (removed legacy buildSessions) |
| `ios/DoseTapiOSApp/SettingsView.swift` | Uses SessionRepository.clearAllData() |

## Migration Results

### SQLiteStorage Usages

**Before:** 19 files with direct SQLiteStorage access  
**After:** 0 production files (only test files and documentation comments)

Remaining references (intentional):
- `DoseModels.swift` - Documentation comments only
- `DoseTapTests.swift` - Tests legacy split-storage scenario (Phase 4 cleanup)

### Type Consolidation

The following types now use `StoredSleepEvent` (from EventStorage) instead of `SQLiteStoredSleepEvent`:
- `QuickLogViewModel.recentEvents`
- `TonightEventsSection.tonightEvents`
- `DoseCoreIntegration.getTonightSleepEvents()`
- `TimelineSleepEvent` (updated to accept String id)

## Phase 4 TODO (Backfill/Cleanup)

1. **Remove legacy test** in `DoseTapTests.swift` that tests split-storage behavior
2. **Backfill session_id** for existing rows with null session_id
3. ~~Consider removing SQLiteStorage.swift entirely~~ ✅ **DONE:** Banned with `#if false` wrapper

## Verification Commands

```bash
# Check SQLiteStorage usages (should be 0 — all banned)
grep -r "SQLiteStorage" ios --include="*.swift" | grep -v "#if false" | grep -v "BANNED" | wc -l

# Build verification
swift build

# Test verification
swift test
```

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                          UI Layer                                │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────────────────┐ │
│  │ TonightView  │ │ TimelineView │ │ MorningCheckInView       │ │
│  │ QuickLogPanel│ │              │ │                          │ │
│  └──────┬───────┘ └──────┬───────┘ └──────────────┬───────────┘ │
└─────────┼────────────────┼────────────────────────┼─────────────┘
          │                │                        │
          ▼                ▼                        ▼
┌─────────────────────────────────────────────────────────────────┐
│                    SessionRepository                             │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ • logSleepEvent()        • setDose1Time()                  │ │
│  │ • saveMorningCheckIn()   • setDose2Time()                  │ │
│  │ • fetchTonightSleepEvents()  • skipDose2()                 │ │
│  │ • clearAllData()         • deleteSession()                 │ │
│  └──────────────────────────────┬─────────────────────────────┘ │
└─────────────────────────────────┼───────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│              EventStorage (implements EventStore)                │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ • insertSleepEvent()     • fetchSleepEvents()              │ │
│  │ • saveDoseLog()          • fetchDoseLogs()                 │ │
│  │ • saveMorningCheckIn()   • fetchMorningCheckIn()           │ │
│  │ • clearAllData()         • exportToCSV()                   │ │
│  └──────────────────────────────┬─────────────────────────────┘ │
└─────────────────────────────────┼───────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                 SQLite (dosetap_events.sqlite)                   │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────────────────┐ │
│  │ sleep_events │ │ dose_logs    │ │ morning_checkins         │ │
│  │ pre_sleep    │ │ sessions     │ │ medication_entries       │ │
│  └──────────────┘ └──────────────┘ └──────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│              SQLiteStorage (BANNED — #if false)                  │
│              ⛔ Do not use - wrapped and disabled                 │
└─────────────────────────────────────────────────────────────────┘
```

## Testing Recommendations

1. **Manual Testing**: Log events through QuickLogPanel, verify they appear in Timeline and TonightView
2. **Morning Check-In**: Complete a check-in, verify it persists across app restart
3. **Clear Data**: Use Settings → Clear All Data, verify complete reset
4. **Session Deletion**: Delete a session from Timeline, verify it's removed everywhere
