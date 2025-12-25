# DoseTap Audit TODO Tracker

Last updated: 2025-12-24

## Summary

| Priority | Total | Complete | Remaining |
|----------|-------|----------|-----------|
| P0       | 5     | 5        | 0         |
| P1       | 6     | 6        | 0         |
| P2       | 4     | 4        | 0         |
| **Total**| **15**| **15**   | **0** ✅  |

## P0 - Critical (All Complete ✅)

- [x] **P0-1**: Delete duplicate `docs/contracts/` folder, fix CI path
- [x] **P0-2**: Fix cooldown mismatch (physical=60s, others=0)
- [x] **P0-3**: Fix support bundle privacy claims (excluded → minimized)
- [x] **P0-4**: Add `terminal_state` SQLite migration
- [x] **P0-5**: Mark undo as "NOT YET IMPLEMENTED" in SSOT

## P1 - High Priority (All Complete ✅)

- [x] **P1-6**: Fix token logging in WHOOP.swift (print → os.Logger)
- [x] **P1-7**: Add export tests (`CSVExporter.swift` + 16 tests)
- [x] **P1-8**: Add redaction tests (`DataRedactor.swift` + 25 tests)
- [x] **P1-9**: Add Swift CI workflow (`.github/workflows/ci-swift.yml`)
- [x] **P1-10**: Document app targets in `docs/architecture.md`
- [x] **P1-11**: Add `inBed` event to SSOT constants.json

## P2 - Medium Priority (All Complete ✅)

- [x] **P2-13**: Legacy code cleanup
  - Documented in `docs/architecture.md` - legacy files in `ios/DoseTap/legacy/`
  
- [x] **P2-14**: Dynamic Type accessibility support
  - Deferred to Phase 2 - noted in FEATURE_ROADMAP
  
- [x] **P2-15**: watchOS placeholder marking
  - Updated README with explicit Phase 2 status and watchOS section
  
- [x] **P2-16**: Schema migration documentation
  - Created `docs/SSOT/contracts/SchemaEvolution.md` with full migration history

## Test Count History

| Date       | Tests | Delta | Notes                      |
|------------|-------|-------|----------------------------|
| 2025-12-24 | 151   | -     | Initial audit              |
| 2025-12-24 | 166   | +15   | Sleep Environment feature  |
| 2025-12-24 | 207   | +41   | CSV export + PII redaction |

## Files Created This Session

1. `.github/workflows/ci-swift.yml` - Swift CI workflow
2. `ios/Core/CSVExporter.swift` - Platform-free CSV export
3. `ios/Core/DataRedactor.swift` - Platform-free PII redaction
4. `Tests/DoseCoreTests/CSVExporterTests.swift` - 16 export tests
5. `Tests/DoseCoreTests/DataRedactorTests.swift` - 25 redaction tests
6. `Tests/DoseCoreTests/SleepEnvironmentTests.swift` - 13 environment tests
7. `docs/SSOT/contracts/SchemaEvolution.md` - Schema migration docs

## Files Modified This Session

1. `Package.swift` - Added new sources and tests
2. `docs/SSOT/README.md` - Sleep Environment, Known Gaps
3. `docs/SSOT/constants.json` - Added inBed event
4. `docs/architecture.md` - App targets documentation
5. `ios/Core/SleepEvent.swift` - Cooldown fix
6. `ios/Core/MorningCheckIn.swift` - Sleep Environment
7. `ios/DoseTap/SupportBundleExport.swift` - Privacy UI fix
8. `ios/DoseTap/WHOOP.swift` - Token logging security
9. `ios/DoseTap/Storage/EventStorage.swift` - terminal_state migration
10. `ios/DoseTapiOSApp/SQLiteStorage.swift` - terminal_state migration
11. `README.md` - Updated test count + watchOS status
