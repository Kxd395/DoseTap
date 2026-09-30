# Work Block & Sleep dashboard

DOSETAP-45, September 30, 2026. Implements the independent work-context portion of the September 30 addendum. Source: `ios/Core/WorkBlockContext.swift`, `WorkCycleProfile.swift`, `ios/DoseTap/Storage/EventStorage+WorkContext.swift` and `Views/Dashboard/DashboardWorkBlockView.swift`.

## Behavior

Dashboard opens Work Block & Sleep without adding a bottom-navigation destination. Users explicitly save effective roster dates, timezone and workdays, and can separately confirm attendance or add a planned work-date exception. Optional actual times remain absent until entered. None of these controls writes medication, wake schedules, alarms or sleep records.

Each main sleep requires a reviewed association with adjacent waking dates. Planned comparisons use the plan snapshot at that review; confirmed comparisons require explicit attendance. The UI calls a retrospectively entered plan a reviewed snapshot, never evidence that it was recorded before sleep. Historical revisions are retained. Overnight/ambiguous associations remain unknown rather than being forced into a daytime rule.

The common classifier supplies entering, between, first post-block and later off-block/unknown positions. Later off-block sleeps retain an unknown sequence index when intervening main sleeps are unconfirmed. Profiles show individual observations, median and middle 50% interval on one minute scale; the block matrix retains missing cells and multiple observations. Record details and formula-safe CSV share the same classifications and values. Metric-specific available/missing counts and known distinct-block counts are visible. Source-specific sleep totals and valid D1–D2 intervals remain separate choices.

SQLite compare-and-swap transactions reject stale writes and any replacement of stored revision history. Failed reads block editing. Clear All Data includes the context document; the raw nearby workSchedule dataset retains it for downstream interpretation.

## Validation

- Core: 18 new domain/profile tests; full suite 897 XCTest plus 43 Swift Testing cases passed.
- Native storage: 4 tests passed, covering durable reopen, transaction failure, stale/history replacement rejection, Clear All Data and raw snapshot inclusion.
- Native UI: route and disabled-until-review controls were reached. The save/reopen journey hit a switch-row tap assertion; corrected control targeting awaits the serialized retry. Failed-run evidence is retained in `.build/work-block-evidence/work-ui.log`; no UI acceptance is claimed.
- Generic simulator build, repository workflow/SSOT/architecture guards and diff checks are required for this increment; delivery and integration are owned by the parent task.

## Acceptance boundaries

A plan is not attendance; off-block is not recovery. Existing historical wake settings and the reported Tuesday–Thursday pattern are never silently imported. The user still needs to enter actual effective dates and any applicable work history. Full VoiceOver, large-text/grayscale owner review, real roster/night association, signed-device acceptance, and interpretation of this new raw dataset by the separate iPad app remain separate gates. No automatic shift import, actual-hours chart, causal analysis or medication optimization is enabled.
