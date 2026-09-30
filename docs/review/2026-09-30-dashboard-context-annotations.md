# Dashboard context annotations and compatible periods

Tracker: DOSETAP-45. Blueprint acceptance: B24. Definition: `dashboard_context_v1`.

The projection consumes the validated immutable medication-preset schema1 ledger and recorded questionnaire content versions. A patient-entered label reference can establish an explicitly dated reference period. It does not verify a prescription, establish that medication was taken, or confirm that a prescription changed. Confirmed administration rows remain separate recorded source evidence, with actual components and optional occurrence time preserved.

Questionnaire observations carry source record ID, instrument, content version, language when recorded and observation time. Their rollout/effective date is unknown; the projection never assigns the first response timestamp as a rollout date. Missing language and explicitly supplied text use distinct compatibility keys. Missing content version, absent observation time or missing reference history yields an observation-specific unknown stratum.

The shared elapsed-time projection applies half-open reference intervals and exact revision-chain supersession. An observation spanning a reference boundary receives its own stratum. Compatible periods require the same reference revisions and questionnaire content keys. No current preference, missing dose or check-in completion timestamp reconstructs a historical treatment or sleep interval. Older legacy regimen UI/table facilities are not promoted to verified prescription history.

`DashboardContextTimeline.annotations` preserves ID, kind, optional effective instant, observed instant, source record IDs, definition version, title, detail and uncertainty. Its range selector can include the active pre-period label reference as baseline while retaining its original effective date. Unplaced records are selected by observation time and remain unplaced in output.

Consumer contract:

- Dose, sleep, work and daytime comparison adapters add `DashboardContextStratum.id` before aggregation. Unknown/crossing strata are not silently pooled.
- Existing source, outcome, work-position, clock-band, instrument, timezone and sampling-protocol partitions remain applicable.
- Report/export adapters preserve the canonical annotation fields rather than derive independent treatment changes.
- A failed source read must remain unavailable or retain a visibly stale snapshot; an empty collection is not evidence that no changes occurred.

Core test-first evidence begins with `/tmp/dosetap-context-red.log`, which fails for the absent shared projection types before implementation. The focused 10-test suite then passed. Full core validation passed 932 tests (889 XCTest + 43 Swift Testing), along with SwiftPM build, Plane workflow (15 tests/80 assertions), SSOT and whitespace checks. Logs: `/tmp/dosetap-context-green.log`, `/tmp/dosetap-context-core-build.log`, `/tmp/dosetap-context-core-tests.log`. Native source-adapter integration remains the next checkpoint; these results do not establish device or release acceptance.
