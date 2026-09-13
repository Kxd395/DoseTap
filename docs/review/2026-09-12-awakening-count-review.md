# Awakening counts: source review and next implementation

Date: 2026-09-12 (America/New_York)
Status: Documentation/contract slice under DOSETAP-57; app behavior unchanged
Reviewed source baseline: `b96a17771312b5d2fde02b0f831b1fbc04cf3265`, 0.4.19 (55), merged PR #43

## Finding and decision

The reviewed Timeline already exposes the four dose/sleep durations and the Dose 2 awake episode with source samples and matching logs. Builds 46/48 delivered that bounded behavior. The next missing piece is a count definition that can be shared across consumers without reinterpreting older numbers.

The current Health summary counts selected awake segments after sleep has appeared. It does not require a continuous sleep-to-awake-to-sleep sequence. A terminal awake segment can count without a return, and split awake segments can increase the number. This is confirmed source behavior, not a reproduction using the owner's Health records or proof that any specific displayed night is wrong.

The [new implementation contract](../SSOT/contracts/reviewed-awakening-counts.md) defines one completed observed episode as a maximal awake band immediately bordered by resolved sleep on both sides. It separates terminal/incomplete episodes, retains known episodes when evidence elsewhere is partial, and keeps a complete-window total unavailable for gaps/conflicts. There is no arbitrary minimum-duration threshold. An episode spanning Dose 2 counts once; a separate subset includes episodes whose awakening starts at or after the actual dose. Final waking, quick logs and provider disturbances remain separate.

This is an engineering definition for forthcoming implementation. It does not replace the old counter, add an export key or establish owner acceptance of the measurement wording. The original duration calculator and source evidence remain unchanged.

## Source and consumer inventory

Paths below refer to the reviewed baseline. Follow symbols rather than assuming line numbers remain stable.

| Existing path / symbol | Meaning and migration requirement |
| --- | --- |
| `ios/Core/ReviewedNightSleepProjection.swift`, `ReviewedNightSleepProjection` | Reusable chronological consensus bands and coverage; no count yet. Preserve conflict and unmeasured bands. |
| `ios/Core/ReviewedDoseSleepMetrics.swift`, `ReviewedDoseSleepMetrics` | Existing strict dose-boundary durations. Reuse its exact-return association; counting must not change latency semantics. |
| `ios/DoseTap/Services/ReviewedNightSleepLoader.swift` | Fresh session/window/dose/provider snapshot and invalidation. The future result belongs here, not a separate direct view query. |
| `ios/DoseTap/HealthKitService.swift`, `sleepNightSummary` / `wakeCount` | Legacy selected-primary-episode awake-segment count; not reviewed-window completed episodes. Keep explicitly separate during adoption. |
| `ios/DoseTap/Views/Dashboard/DashboardAnalyticsMetrics.swift`, `averageWakeCount` | Mean of present legacy Health counts. A new count needs its own eligibility/status denominator. |
| `ios/DoseTap/Views/Dashboard/DashboardOverviewCards.swift` | Displays the old mean as Avg wakes · Health. Follow-up must identify the metric definition in the display. |
| `ios/DoseTap/SettingsStudioExport.swift`, `healthKit.wakeCount` | Exports the legacy number when a usable primary summary exists. Preserve old field semantics; add versioned reviewed results separately. |
| `macos/DoseTapStudio/Sources/Insights/Models/InsightModels.swift`, `wakeDisruptionCount` | Health-first selection with WHOOP disturbance fallback. This is not a source-independent completed-episode count. |
| `macos/DoseTapStudio/Sources/Views/NightDetail/NightDetailView.swift` | Displays provider count facts. Future reviewed counts need matching typed import, status, source and explanation. |
| `ios/Core/UnifiedSleepSession.swift`, `awakenings` | Compatibility model takes max of brief-wake logs and Health count, using zero for absent Health; its average includes all sessions. Do not reuse this formula. This audit did not establish a shipping iOS caller. |
| Bathroom/brief-wake questionnaires and quick logs | Reports of events or self-reported buckets, not timestamped provider transitions. Retain raw/source/normalized answers and existing event exports. |

The complete collected-data entry point remains the [collection/store/export reading guide](../audit/2026-09-12/README.md). This review adds the specific count-definition discrepancy; it is not a new complete-backup or provider-ledger audit.

## Implementation order and review examples

1. Add a pure, versioned count result and failing-first fixtures to the existing reviewed projection path. Preserve exact endpoints, incomplete evidence, coverage and per-metric status.
2. Add the result to one checked reviewed-night card, with native text-size/VoiceOver and same-night owner/provider comparison. Keep source samples and all logs inspectable.
3. Adopt the same result in wider chart/History/dashboard/Settings/Studio consumers. Review the additive archive and redaction contract and validate actual writer/import parity before replacing display labels or using new averages.

For the synthetic 02:40 awakening, 02:48 Dose 2 and 03:02 return, show one completed episode and the existing 8-minute pre-dose, 14-minute post-dose and 22-minute whole duration. It spans Dose 2 but does not start after it. A bathroom log inside that interval is additional context, not a second awakening or proof of what caused waking.

For an observed episode plus an unrelated coverage gap, retain the episode but say the whole-window total is unavailable. For trailing awake evidence, show an awakening without an observed return; do not infer a confirmed final wake. The contract includes exact-start/return, all-awake, unknown-only, split-sample, conflicting-source, midnight/DST and correction/late-response fixtures. These are future acceptance cases, not executed tests of a new calculator.

## Evidence and remaining gates

Fresh readback before this slice: main/origin matched with no open PRs; Documentation CI, Swift CI and CI all passed for `b96a177`. Exact Plane preflights and full workpads for DOSETAP-56/57 were read; both are high priority and In Progress. Their older descriptions contain dated pending-delivery wording; later workpads establish the implemented durations/inspection and outstanding gates.

Two independent source/document reviews checked the existing projection, count loop, consumer routes and boundary contract. The bounded documentation changes add the contract, inventory and navigation, correct the SSOT's stale source build 53 to 55, and identify PR #43 as merged in the review index. They preserve earlier dated delivery evidence.

Fresh local validation in the isolated documentation checkout: `swift build -q` passed; `swift test -q` passed 710 XCTest and 43 Swift Testing cases with no failures. `ssot_check.sh`, `doc_lint.sh`, `check_plane_workflow.sh` (15 tests, 80 assertions) and `git diff --check` passed; new-document relative links resolve. These regression checks exercise existing code, not the proposed counter. Review clarified the unchanged loader gate, malformed-projection rejection and the exact predecessor requirement for post-Dose-2 subsets. Local logs are under `.build/audits/2026-09-12-awakening-contract/` in the isolated checkout.

Final integration and hosted check readbacks are recorded in the exact DOSETAP-57 Plane workpad and associated PR. No new count implementation, phone installation, personal provider-record inspection or UI acceptance is claimed. The protected main checkout's ignored `docs/.DS_Store` still causes its local documentation lint to fail; it is preserved, outside this change. The clean isolated documentation checks above passed.

Open gates remain: count implementation and owner wording/measurement acceptance; full consumer/export/Studio parity; durable provider revision/deletion reconciliation; signed-phone/live-provider same-night parity; VoiceOver/full accessibility; privacy/security and release acceptance. Related pain/sleeping-setup owner gates are unchanged. Build remains 0.4.19 (55); documentation does not require a new installable build.
