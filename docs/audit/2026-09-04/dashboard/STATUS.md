# Dashboard audit status

- Scope: owner-authorized audit and correction of the dashboard and analytics it displays; review adjacent shared calculators and Tonight metrics for disagreement.
- Baseline: `37da941`, `fix/locked-dose2-system-alarm`, `/Volumes/Developer/projects/DoseTap-main`.
- Preserved dirty file: `ios/DoseTap.xcodeproj/xcshareddata/xcschemes/DoseTapUITests.xcscheme` (pre-existing owner/Xcode edit).
- Read: repository AGENTS, README, SSOT, testing/workflow/constitution (current session), dashboard view/model/metrics/refresh/types/catalog and major cards, storage queries, prior Plane status.
- Plane: DOSETAP-45 created, preflighted and started In Progress with verified readback; DOSETAP-36 remains Done.
- Completed: baseline, initial source inventory and data-flow trace. Findings are code-reviewed until regression/runtime checks are recorded.
- Remaining: verify date/sample/source/missingness defects; regression fixtures; corrections in small tested commits; UI navigation/empty/populated screenshots; integration limits; metric inventory and improvement plan; build identity and Plane closeout.
- Blockers: physical Apple Health/WHOOP parity and owner accessibility acceptance cannot be established from simulator fixtures. No real medication database changes or phone installs are part of verification.
- Concurrent edit: Xcode reordered project.pbxproj entries during investigation; preserve that unrelated change alongside the scheme edit.
- Exact next step: preflight new Plane item, complete remaining dashboard/calculator input audit, write focused regressions for range boundaries, unknown-vs-zero and source attribution before correcting calculations.

## Calculation checkpoint
- DA-01 civil range and DA-05 pair/pending denominators corrected. Exact seconds retained; negative intervals excluded, active outcome separated. Six simulator unit tests passed (DashboardAnalyticsAuditTests + DashboardDoseIntegrityMetricTests), including both DST transitions and morning night identity.
- Swift build passed; Swift tests 634 XCTest + 43 Swift Testing passed; SSOT, app version and Plane checks passed. First app compile exposed local DoseWindowConfig shadowing; qualified DoseCore type and reran successfully.
- Evidence: `/tmp/dosetap-dashboard-math-tests.log`, `/tmp/dosetap-supply-build/Logs/Test/Test-DoseTap-2026.09.05_00-02-33--0400.xcresult`.
- Next: canonical refresh/history coverage; missing-answer and source-specific comparisons; UI organization and runtime fixtures.

## Data-source checkpoint
- DA-01/02/07: refresh now enumerates discovered history, projects canonical dose events without inferred doses or current-session cache fallbacks, uses repository pre-sleep fallback, yields between nights, and awaits owned refresh tasks. WHOOP fetch errors now surface; provider horizons are labeled.
- DA-06 additional confirmed defect: WHOOP nightly summaries admitted naps and undated records. Excluded both; for multiple overnight segments mapped to one night, dashboard selects longest scored sleep (does not sum potentially overlapping intervals).
- Fifteen targeted simulator tests passed: seven audit regressions and eight WHOOP decoding/integration-boundary tests. In-memory SQLite fixture verified 2020 history survives All Time. Swift build/tests, SSOT and Plane workflow checks passed again.
- Evidence: `/tmp/dosetap-dashboard-refresh-tests.log`. Simulator native CUA inspection timed out; use XCTest attachments for UI verification.

## Missingness checkpoint
- DA-04: caffeine/alcohol/exercise/screens/meal rates now use answered completed logs; unknown and skipped logs do not enter negative cohorts. Stressors deduplicate bedtime/morning per night. Updated old regression expectation that encoded the duplicate count.
- DA-06: aggregate sleep and period comparisons use explicit Apple Health/WHOOP choice without fallback. Provider-specific report enrichment follows that choice.
- Ten simulator tests passed (nine audit tests plus existing stress suite), including explicit No versus unknown/skipped and provider non-fallback. Swift build/tests, SSOT and Plane checks passed. Next: expose source control and restructure UI; remove misleading duration and confidence labels; chart zero/missing fixtures.
