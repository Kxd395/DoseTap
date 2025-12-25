# Independent Code Review — 2025-12-25 (DoseTap v2.10.0)

Readiness score: **42/100** — Blocked by failing Xcode suites and a session-date boundary mismatch between persistence and business logic that can mis-file sessions and exports.

## P0 Findings
- **Xcode critical suites failing (6 tests)**: `URLRouterTests` fails to parse/record log events (`unknown` lowercasing, notes, skip feedback) and `NavigationFlowTests` fails to set actions from widget/quick event flows. Evidence: `ios/DoseTapTests/DoseTapTests.swift:632,690-751,1373-1383` with failure messages from `/tmp/DoseTap.xcresult` (see log entry 17:21:12-05:00).
- **Session date boundary conflict (persistence vs logic)**: `EventStorage.currentSessionDate()` uses a 6 AM cutoff (`ios/DoseTap/Storage/EventStorage.swift:88-110`), while `DoseWindowCalculator.sessionDateString` uses a 6 PM cutoff (`ios/Core/DoseWindowState.swift:134-177`). `SessionRepository.setDose1Time` derives session keys from the 6 AM path, so timeline/export and window logic can disagree on the session owning a dose, especially for evening doses—time correctness hazard despite passing unit tests.

## P1 Findings
- **Deleted sessions linger in exports/timeline**: `deleteSession` clears times but leaves `session_date` rows in `current_session` (`ios/DoseTap/Storage/EventStorage.swift:1062-1075`), while `getAllSessionDates` drives exports from that table (`ios/DoseTap/Storage/EventStorage.swift:133-152`). Deleted sessions can still appear as empty export rows and timeline entries after cascade deletes.
- **Docs/SSOT drift**: `tools/ssot_check.sh` reports 26 unresolved SSOT violations (missing component IDs, undocumented endpoints, stale Core Data reference) and `tools/doc_lint.sh` flags stale “12 event/types” text. Docs are not truthful to code.
- **Negative test plan note**: Manual cascade depends on enumerating every table in `EventStorage.deleteSession`. If a new table is added without being listed there, `test_sessionDelete_cascadesAllDependentTables` would stay green (it only checks the current allowedTables list) and exports/timeline would silently retain orphan rows. Add a failing test that asserts `fetchRowCount` errors on unknown tables or extend the cascade list + test to include any new table name.

## P2 Findings
- **Export metadata not implemented**: Support/export helpers never emit schema version or constants version; `test_export_includesSchemaVersion` only reads `getSchemaVersion()` and doesn’t cover actual export paths (`ios/DoseTap/Storage/EventStorage.swift:1234-1318`). Claims of metadata-rich export are NOT VERIFIED.
- **Dual storage sources in Timeline**: `TimelineViewModel` merges `SQLiteStorage` and `EventStorage` data (`ios/DoseTapiOSApp/TimelineView.swift:447-483`), creating two sources of truth for historical sessions; not currently failing tests but increases divergence risk.

## Evidence Table
| Claim | Evidence (file:line) | Proof (command/output) |
| --- | --- | --- |
| SwiftPM suites executed (265 tests) | `Tests/DoseCoreTests/TimeCorrectnessTests.swift` etc. | `swift test --verbose` @17:19:15-05:00 → “Test Suite 'All tests'… Executed 265 tests, 0 failures” |
| Timezone determinism verified | same suites | `TZ=UTC swift test --verbose` and `TZ=America/New_York swift test --verbose` → both “Executed 265 tests, 0 failures” |
| Xcode required suites failing | `ios/DoseTapTests/DoseTapTests.swift:632,690-751,1373-1383` | `xcodebuild … -resultBundlePath /tmp/DoseTap.xcresult` @17:21:12-05:00 → FAIL; `xcresulttool … testFailureSummaries` shows assertions (Unknown vs unknown, missing .takeDose1, missing .logEvent) |
| Session date boundary mismatch | `ios/DoseTap/Storage/EventStorage.swift:88-110` vs `ios/Core/DoseWindowState.swift:134-177` | File inspection; conflicting 6 AM vs 6 PM boundaries not reconciled in SessionRepository |
| DeleteSession leaves ghost session_date rows | `ios/DoseTap/Storage/EventStorage.swift:1062-1075` and `133-152` | Logic review; no DELETE/NULL of `session_date`, so `getAllSessionDates` still returns deleted sessions |
| Docs/SSOT drift | N/A | `bash tools/ssot_check.sh ; echo $?` → 26 issues, exit 1. `bash tools/doc_lint.sh ; echo $?` → stale “12 event/types”, exit 1 |

## Shipping Recommendation
**Block** until: (1) Xcode URLRouter/NavigationFlow failures are fixed and re-run green; (2) session-date boundary is unified (6 PM vs 6 AM) with tests covering persistence + window logic; (3) deleteSession clears `current_session` rows so exports/timeline don’t surface ghost sessions; (4) SSOT/doc lint issues are addressed or docs updated to reflect reality; (5) export metadata commitments are either implemented or documented as NOT VERIFIED.
