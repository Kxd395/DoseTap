# Dashboard audit status

- Scope: owner-authorized audit and correction of the dashboard and analytics it displays; review adjacent shared calculators and Tonight metrics for disagreement.
- Baseline: `37da941`, `fix/locked-dose2-system-alarm`, `/Volumes/Developer/projects/DoseTap-main`.
- Preserved dirty file: `ios/DoseTap.xcodeproj/xcshareddata/xcschemes/DoseTapUITests.xcscheme` (pre-existing owner/Xcode edit).
- Read: repository AGENTS, README, SSOT, testing/workflow/constitution (current session), dashboard view/model/metrics/refresh/types/catalog and major cards, storage queries, prior Plane status.
- Plane: DOSETAP-45 created, preflighted and started In Progress with verified readback; DOSETAP-36 remains Done.
- Completed: baseline, source inventory/data-flow audit, DA-01…10 local corrections, build 0.4.15 (17), regression and simulator UI checks; detailed evidence below.
- Remaining: external gates are live-provider parity, signed-device/owner review, and comprehensive accessibility. Plane closeout result is recorded below.
- Blockers: physical Apple Health/WHOOP parity and owner accessibility acceptance cannot be established from simulator fixtures. No real medication database changes or phone installs are part of verification.
- Concurrent edit: Xcode reordered project.pbxproj entries during investigation; preserve that unrelated change alongside the scheme edit.
- Exact next step for owner acceptance: build `/Volumes/Developer/projects/DoseTap-main/ios/DoseTap.xcodeproj`, confirm 0.4.15 (17), compare 3–5 recorded nights to Timeline/Health/WHOOP, and review the dashboard on the phone. No further local implementation is pending in this pass.

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

## Dashboard layout checkpoint
- Overview/Trends/Data navigation, source selector, meaningful outcome counts, bathroom log counts, full WHOOP light/deep/REM composition, coverage language and visible empty/provider errors implemented.
- UI test passed in iPhone 17/iOS 26.5 simulator; four XCTest screenshots exported to `/tmp/dosetap-dashboard-ui-images` and inspected. Overview is readable; Data confirms old recent-row width overflow, and Trends confirms old chart fallback still differs from selected source. Both are next corrections, not accepted as final.
- Display-only simulator fixtures do not write data or connect providers. UI test/build plus Swift build/tests, SSOT/navigation, app version and Plane checks passed. New fixture initially lacked app target membership; moved into existing DashboardModels compilation unit and reran successfully, preserving owner project edits.

## Chart and comparison checkpoint
- DA-03/05/06/08: selected-source scatter/cohort charts, real zero versus missing weekday buckets, sample counts, linear interpolation, neutral timing-group and period language, and readable multi-line recent nights corrected.
- Eleven simulator unit tests passed, including a real 0% weekday with all other weekdays absent. Two UI tests passed and screenshots inspected: source selection now yields the correct five fixture readings, zero weekday remains visible, recent rows fit. Initial weekday annotations collided; shortened labels, moved sample counts beneath chart, reran and visually confirmed.
- Large-text screenshot exposed KPI columns colliding; landscape screenshot captured during rotation, so neither is accepted. Next: single-column accessibility layout and wait for rotation, Tonight weekly semantics, remaining sample labels, final verification/Plane closeout.
- Evidence: `/tmp/dosetap-dashboard-chart-tests.log`, `/tmp/dosetap-supply-build/Logs/Test/Test-DoseTapUITests-2026.09.05_00-19-42--0400.xcresult`, `/tmp/dosetap-dashboard-responsive`.

## Final implementation checkpoint
- Version now 0.4.15 (17), both DoseTap/DoseTapStaging Debug and Release verified. Twenty-four targeted iOS unit tests passed: 13 audit, 2 dose-integrity, 1 stress, 8 WHOOP. SwiftPM 634 XCTest + 43 Swift Testing passed; SSOT, app version and Plane checks passed.
- Three UI tests passed: dashboard section/source/weekday/recent/empty/error navigation, large-text/rotation, and existing first-item/nonpersistent bottle flow. Portrait large text now uses one KPI column; named tab buttons remain accessible with icons at accessibility sizes. A separate XCUIScreen capture after rotation resolved the application-screenshot crop artifact; landscape header/navigation fits. This is not full VoiceOver or every-screen accessibility acceptance.
- DA-09 discovered/corrected: Tonight fetched seven rows rather than seven finished civil nights, included orphan Dose 2 in numerator, and called it adherence/streak. Now Last 7 Nights with explicit Dose 2 recorded and unrecorded counts; dated regression passed.
- Removed inactive implicit provider fallback and streak/quality-flag calculators from dashboard aggregates. Compared rates now use percentage points, with a zero-baseline regression. Historical skip flags cannot override an actual recorded pair in timing-group comparisons.
- Evidence: `/tmp/dosetap-dashboard-final-unit.log`; UI bundle `Test-DoseTapUITests-2026.09.05_00-25-14--0400.xcresult`; additional landscape bundle `Test-DoseTapUITests-2026.09.05_00-29-34--0400.xcresult`; images `/tmp/dosetap-dashboard-final-images` and `/tmp/dosetap-dashboard-screen-capture`.
- Exact next step: finalize findings/metric inventory/decisions, preserve screenshot evidence in audit folder, commit documentation, apply and independently verify DOSETAP-45 closeout with provider/device/VoiceOver gates open. No phone installation or real database mutation performed.

## Provider missingness closeout checkpoint
- DA-10 corrected after final inventory review: incomplete WHOOP stages/awake/disturbances stay unavailable in dashboard totals/averages; recovery-enrichment failures retain scored sleep but expose a warning. The decoded partial fixture now verifies unavailable values rather than assumed zero.
- Final targeted run again passed 24 tests, zero skipped/failed: `/tmp/dosetap-supply-build/Logs/Test/Test-DoseTap-2026.09.05_00-36-43--0400.xcresult`. Built simulator Info.plist read back 0.4.15 (17). Swift build/test, SSOT, app version and Plane checks passed again. Real recovery outage is not behaviorally tested.

## Final commands and evidence

- `swift build -q`: passed. `swift test -q`: 634 XCTest + 43 Swift Testing passed, zero failures. Logs `/tmp/dosetap-dashboard-swift-{build,test}.log`.
- `xcodebuild test -project ios/DoseTap.xcodeproj -scheme DoseTap -destination 'platform=iOS Simulator,id=829089F8-76D6-475A-A794-CFBD0BE9F43B' -derivedDataPath /tmp/dosetap-supply-build -only-testing:DoseTapTests/DashboardAnalyticsAuditTests -only-testing:DoseTapTests/DashboardStressTrendTests -only-testing:DoseTapTests/DashboardDoseIntegrityMetricTests -only-testing:DoseTapTests/WHOOPDecodingTests CODE_SIGNING_ALLOWED=NO`: 24 passed; see `evidence/unit-results.json`.
- Same project/destination/derived-data, `-scheme DoseTapUITests`, selectors `testDashboardOverviewTrendsAndData`, `testDashboardLargeTextAndLandscape`, `testSupplyBottleIsFirstInPreSleepAndNeverCarriedForward`: 3 passed. Separate screen-capture rerun of large-text/landscape: 1 passed. Logs `/tmp/dosetap-dashboard-release-ui.log`, `/tmp/dosetap-dashboard-landscape.log`.
- `bash tools/ssot_check.sh`, `bash tools/check_app_version.sh`, `bash tools/check_plane_workflow.sh`, `bash tools/check_architecture_boundaries.sh`, `git diff --check`: passed. App version read back from all four target/configurations and built simulator Info.plist. Pre-commit also built the iOS simulator app on each source commit.
- Runtime screenshots are synthetic display-only fixtures; Health/WHOOP fetches are bypassed only with explicit DEBUG simulator test argument. No real provider outage, phone alarm delivery, every dashboard-card text-size combination, iPad, release optimization, or VoiceOver traversal was verified here.

## Action log — changed files

- `docs/SSOT/README.md`
- `docs/SSOT/navigation.md`
- `docs/audit/2026-09-04/dashboard/DECISIONS.md`
- `docs/audit/2026-09-04/dashboard/FINDINGS.md`
- `docs/audit/2026-09-04/dashboard/STATUS.md`
- `ios/DoseTap.xcodeproj/project.pbxproj`
- `ios/DoseTap/ContentView.swift`
- `ios/DoseTap/Views/Dashboard/DashboardAnalyticsCatalog.swift`
- `ios/DoseTap/Views/Dashboard/DashboardAnalyticsMetrics.swift`
- `ios/DoseTap/Views/Dashboard/DashboardAnalyticsMorning.swift`
- `ios/DoseTap/Views/Dashboard/DashboardAnalyticsPreSleep.swift`
- `ios/DoseTap/Views/Dashboard/DashboardAnalyticsRefresh.swift`
- `ios/DoseTap/Views/Dashboard/DashboardAnalyticsSupport.swift`
- `ios/DoseTap/Views/Dashboard/DashboardInsightCards.swift`
- `ios/DoseTap/Views/Dashboard/DashboardModels.swift`
- `ios/DoseTap/Views/Dashboard/DashboardOverviewCards.swift`
- `ios/DoseTap/Views/Dashboard/DashboardTrendCards.swift`
- `ios/DoseTap/Views/Dashboard/DashboardTypes.swift`
- `ios/DoseTap/Views/Dashboard/DashboardViews.swift`
- `ios/DoseTap/Views/WeeklyInsightsCard.swift`
- `ios/DoseTap/WHOOPDataFetching.swift`
- `ios/DoseTapTests/DashboardAnalyticsAuditTests.swift`
- `ios/DoseTapTests/UIStateTests.swift`
- `ios/DoseTapUITests/DoseTapUITests.swift`
- `docs/audit/2026-09-04/dashboard/evidence/`: seven fixture screenshots, XCTest summary JSON and evidence README.
- Preserved, excluded from commits: existing `DoseTapUITests.xcscheme` edits and concurrent Xcode project-entry reordering. Only eight version-value lines from project.pbxproj were staged. No dependencies installed, database/schema changes, Git push or deployment.

## Plane and handoff
- DOSETAP-45 structured closeout `946f6cde43de3703` applied and independently verified on 2026-09-05. State **In Progress**, acceptance incomplete only for the named device/provider/comprehensive-accessibility gates; local implementation and requested documentation are written and checked.
- Exact work item: http://plane.localhost:3301/dark-water-drones/browse/DOSETAP-45/
- Final source commit: `6ef4633`; audit baseline `37da941`; version 0.4.15 (17). Seven source commits preserve reviewable stages. Documentation closeout follows separately. Owner Xcode edits remain untouched.
