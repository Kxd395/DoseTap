# Work Block & Sleep dashboard

DOSETAP-45, September 30, 2026. Implements the independent work-context portion of the September 30 addendum. Source: `ios/Core/WorkBlockContext.swift`, `WorkCycleProfile.swift`, `ios/DoseTap/Storage/EventStorage+WorkContext.swift` and `Views/Dashboard/DashboardWorkBlockView.swift`.

## Behavior

Dashboard opens Work Block & Sleep without adding a bottom-navigation destination. Users explicitly save effective roster dates, timezone and workdays, and can separately confirm attendance or add a planned work-date exception. Optional actual times remain absent until entered. None of these controls writes medication, wake schedules, alarms or sleep records.

Each main sleep requires a reviewed association with adjacent waking dates. Planned comparisons use the plan snapshot at that review; confirmed comparisons require explicit attendance. The UI calls a retrospectively entered plan a reviewed snapshot, never evidence that it was recorded before sleep. Historical revisions are retained. Overnight/ambiguous associations remain unknown rather than being forced into a daytime rule.

Comparison controls select Profile, Interval scatter or Block matrix. Scatter grouping changes labels, colors, shapes and CSV together; its neutral 150–240-minute spacing reference remains non-prescriptive. Matrix fill explicitly selects value intensity or categorical phase. Scheduled/actual work-date anchors preserve independent unknown endpoints.

The common classifier supplies entering, between, first post-block and later off-block/unknown positions. Later off-block sleeps retain an unknown sequence index when intervening main sleeps are unconfirmed. Profiles show individual observations, median and middle 50% interval on one minute scale; the block matrix retains missing cells and multiple observations. Record details and formula-safe CSV share the same classifications and values. Metric-specific available/missing counts and known distinct-block counts are visible. Source-specific sleep totals and valid D1–D2 intervals remain separate choices.

SQLite compare-and-swap transactions reject stale writes and any replacement of stored revision history, including prospective source prefixes and explicit shift events. The capture helper joins the caller's pre-sleep insertion transaction; the parent integration owns wiring it only to an eligible new completed pre-sleep save. Failed reads block editing. Clear All Data includes the context document; the raw nearby workSchedule dataset retains it for downstream interpretation.

## Validation

- Core through `50ccd7d`: 910 XCTest plus 43 Swift Testing cases passed. Corrective RED reproduced eight assertions before fixing capture limits, timezone alias resolution and CSV provenance/reference fields. Exact-ID association indexing preserves latest timestamp and first stored equal-timestamp semantics.
- Native storage/range: 7 tests passed, including prospective capture transaction rollback/idempotency and exact TEXT/UTF-8 payload rejection. Three payload-corruption assertions failed before the strict-read fix. Evidence: `.build/work-block-evidence/capture-storage-green.xcresult`; RED log is retained. The failed runner stalled collecting diagnostics after the suite and was terminated only after its PID/worktree were verified; its result is not a successful test run.
- Native UI: both save/reopen and comparison-encoding journeys passed on iPhone 17 Pro simulator at 12:29 EDT. They exercise navigation, disabled-until-review save, persistence, exclusive scatter grouping and separate matrix fill controls. Evidence: `.build/work-block-evidence/work-encodings-ui.xcresult`. Screenshot review found a clipped native horizontal legend; a vertical symbol/label legend fixes it. The focused rerun passed and its exported screenshot was inspected: `.build/work-block-evidence/work-legend-final.xcresult`. Earlier switch-targeting failure remains in `work-ui.log`. Automated simulator evidence does not establish owner, physical-device or full accessibility acceptance.
- Generic simulator build, repository workflow/SSOT/architecture guards and diff checks are required for this increment; delivery and integration are owned by the parent task.

## Acceptance boundaries

A plan is not attendance; off-block is not recovery. Existing historical wake settings and the reported Tuesday–Thursday pattern are never silently imported. The user still needs to enter actual effective dates and any applicable work history. Full VoiceOver, large-text/grayscale owner review, real roster/night association, signed-device acceptance, and interpretation of this new raw dataset by the separate iPad app remain separate gates. No automatic shift import, actual-hours chart, causal analysis or medication optimization is enabled.

## Canonical comparison core follow-on

`WorkCycleComparison` retains raw metric state/value/interval evidence separately from numeric contributions. It produces selected-period and monthly groups partitioned by metric/source/definition, phase, position and compatible context, with separate partial/not-applicable denominators. Exact physician periods withhold values whose bounds are missing or outside the period; duplicate identities cannot inflate groups. The selected-view CSV omits free-text notes by default while retaining override provenance and raw metric state.

Ten new core regressions plus the existing profile regressions passed after missing-API compile RED and CSV/privacy/bounds runtime RED. Full core: 1,059 XCTest and 43 Swift Testing tests passed. Evidence: `.build/work-block-evidence/comparison-core-green.log`. The screen migration and monthly-summary presentation remain pending.


## Canonical app comparison bridge

`DashboardAnalyticsModel.workCycleComparison(metric:period:)` projects the same published, filtered observation identities and frozen work/context snapshots for the dashboard and physician report. A failed or incomplete refresh returns an explicit issue; a valid filter with no matches returns an empty comparison. A separate projection keeps chart axis domains independent of filters. Numeric contributions preserve canonical partial and not-applicable states, exact-period boundaries, context strata and association provenance.

Seven native adapter regressions plus the existing range regression passed. Two Apple Health boundary assertions first reproduced RED: named sleep bounds disagreed with the contributing asleep intervals, and absent recorded intervals were incorrectly sufficient for exact-period contribution. The corrected adapter uses validated recorded asleep boundaries and checks any named endpoints for agreement. Evidence: `.build/work-block-evidence/work-factory-bounds-red.xcresult` and `work-factory-green.xcresult`. Full core checks and the normal enabled app hook accompany this checkpoint. WHOOP original endpoints, shared-screen migration, actual-shift measures and the remaining Work Addendum presentation are not claimed by this bridge.
