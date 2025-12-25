# DoseTap Fix Plan - Session 4

**Date:** 2025-12-24  
**Status:** ✅ COMPLETED

---

## Summary

All P0 contradictions identified in the audit have been fixed. The repository now has a single consistent narrative:

- **Persistence:** SQLite via `EventStorage.swift`
- **Event Types:** 13 (bathroom, inBed, lightsOut, wakeFinal, wakeTemp, snack, water, anxiety, dream, noise, temperature, pain, heartRacing)
- **Test Count:** 207

---

## Patches Applied

### 1. Documentation Updates

| # | File | Change | Risk |
|---|------|--------|------|
| 1 | `docs/IMPLEMENTATION_PLAN.md` | 123→207 tests, 12→13 events | Low |
| 2 | `docs/codebase.md` | Core Data→SQLite | Low |
| 3 | `docs/use_case.md` | Core Data→SQLite | Low |
| 4 | `docs/USE_CASES.md` | Core Data→SQLite (2 places) | Low |
| 5 | `docs/PRD.md` | Core Data→SQLite (5 places) | Low |
| 6 | `docs/PRODUCT_DESCRIPTION.md` | Core Data→SQLite | Low |
| 7 | `docs/FEATURE_ROADMAP.md` | Removed stale code block, Core Data→SQLite | Low |
| 8 | `docs/FUTURE_ROADMAP.md` | 12→13 events, 123→207 tests | Low |
| 9 | `docs/HYPERCRITICAL_AUDIT_2025-12.md` | Core Data→SQLite migration | Low |

### 2. Code Updates

| # | File | Change | Risk |
|---|------|--------|------|
| 10 | `ios/DoseTapiOSApp/SettingsView.swift` | "12 event"→"13 event" | Low |
| 11 | `ios/DoseTapiOSApp/DoseCoreIntegration.swift` | Comment 12→13 | Low |
| 12 | `ios/DoseTapiOSApp/SetupWizardService.swift` | Core Data→SQLite comment | Low |
| 13 | `ios/DoseTapiOSApp/UserConfigurationManager.swift` | Core Data→SQLite comment | Low |
| 14 | `ios/DoseTapiOSApp/BUILD_SUMMARY.md` | Core Data→SQLite | Low |

### 3. Project Configuration

| # | File | Change | Risk |
|---|------|--------|------|
| 15 | `ios/DoseTap.xcodeproj/project.pbxproj` | Remove EventStoreCoreData.swift refs | Medium |

### 4. Tooling Updates

| # | File | Change | Risk |
|---|------|--------|------|
| 16 | `tools/ssot_check.sh` | Add contradiction checks | Low |

---

## Verification Checklist

- [x] `swift test` passes with 207 tests
- [x] No "Core Data" refs in active docs (excluding audit logs)
- [x] No "12 event" refs in active docs
- [x] No "123 tests" refs in active docs
- [x] Lint script contradiction checks pass
- [x] `EventStoreCoreData.swift` removed from project

---

## Remaining Work (Non-blocking)

1. **Component IDs:** Some SSOT component IDs reference planned features not yet implemented
2. **OpenAPI Spec:** Table parsing in lint script creates false warnings
3. **CHANGELOG link:** Broken link in SSOT README (file doesn't exist)
4. **Archive cleanup:** Old iOS folders can be archived (DoseTapNative, TempProject, etc.)

---

## Definition of Done

✅ All P0 contradictions resolved  
✅ Lint script catches future drift  
✅ 207 tests passing  
✅ Dose safety logic verified (early dose, extra dose)
