# DoseTap Project Review (Rescoped XYWAV-Only Night Assistant)

## 📋 Executive Summary

Pivot complete: DoseTap is now a focused two-dose nightly assistant with HealthKit-informed adaptive timing, strict Dose 2 clamp (150–240m), minimal event logging, and an emerging discrete planner. Legacy ambitions (multi-med, microservices, dashboards) removed to prioritize reliability, accuracy, privacy, accessibility, and low friction.

## ✅ Current Strengths

| Area | Status | Notes |
|------|--------|-------|
| Scope Discipline | High | Non-core features aggressively cut |
| Button Logic | Solid | Undo + Snooze rules + errors documented |
| API Surface | Minimal | Only device auth + dose/events/export |
| Adaptive Baseline | Defined | Median TTFW approach clear |
| Documentation | Improving | Core specs aligned; some legacy docs pending |

## 🧨 Residual Risks (Post-Pivot)

| Risk | Impact | Present Mitigation | Needed Action |
|------|--------|--------------------|---------------|
| DST / Timezone shifts | Incorrect interval, user confusion | Conceptual notes only | Implement harness + proof tests |
| Offline burst actions | Potential lost ordering | Queue planned | Add idempotent write + replay tests |
| Undo race w/ sync | Inconsistent state after server ack | 5s window assumption | Snapshot + cancel token design |
| Accessibility timing | Missed VoiceOver cues | Spec placeholders | Implement announcement scheduler |
| Battery overhead | User churn if drain high | No instrumentation | Add sampling + profiling harness |
| Planner misunderstanding | User distrust | Rationale planned | Surface plain-language justification |

## 🎯 Phase Alignment (Roadmap Cross-Check)

| Phase | Core Outcome | Review Focus |
|-------|--------------|--------------|
| v0.1 | Accurate manual timing + clamp | Interval math, Snooze block enforcement |
| v0.2 | Baseline adaptation | Outlier filtering, missing night handling |
| v0.3 | Insights + Export | CSV determinism, aggregation correctness |
| v0.4 | Planner preview | Safe interval selection, rationale clarity |
| v0.5 | Accessibility + Reliability | VoiceOver timing, offline queue durability |
| v0.6 | watchOS parity | Haptic escalation, hold-to-confirm safety |
| v0.7 | DST / Travel hardening | Harness breadth, boundary edge validation |
| v0.8 | Polish & performance | Battery impact, log pruning |

## 🔍 Key Evaluation Dimensions

### 1. Interval Accuracy

Success depends on never presenting a Dose 2 recommendation outside the clamp and maintaining target drift within evolving performance goals (≤10m early → ≤6m). Requires deterministic computation immune to timezone transitions.

Action Items:

1. Build TimeEngine with explicit UTC anchors.
2. Add test fixtures for DST forward/back and trans-meridian travel (±8h shifts).
3. Include invariant assertions (interval >=150 && <=240) at runtime in debug builds.

### 2. Reliability & Persistence

Every tap (take, skip, snooze, bathroom) must survive connectivity loss and process restarts.

Action Items:

1. Local append-only journal with monotonic sequence.
2. Offline queue flush strategy (exponential backoff + jitter, max depth cap + oldest-drop alert if exceeded).
3. Idempotent server event key (device_id + seq + hash). Reject duplicates gracefully.

### 3. Undo Integrity

Undo within 5s must fully revert local+pending state without ghost server records.

Action Items:

1. Stage event record with pending flag; only finalize after undo window.
2. Cancellation token that aborts network dispatch if undo fired.
3. Race test: undo at 4.9s with delayed network ack.

### 4. Accessibility & Low Friction

Night usage likely drowsy; clarity and minimal cognition essential.

Action Items:

1. High contrast palette toggle persists (UserDefaults) and syncs to watch.
2. VoiceOver scheduled announcements: −5m to target, target, window close.
3. Larger touch targets (≥48pt) and single primary action affordance.
4. Haptic escalation on watch: gentle → medium → strong if no response.

### 5. Adaptive Transparency

Planner must always justify choices simply.

Action Items:

1. Rationale template: “Chose {X}m (recent natural wake near {Y}m; inside safe range).”
2. Beta param debug panel (dev builds) to trace interval exploration.
3. Instant disable/rollback path: revert to baseline target.

### 6. Privacy & Data Minimization

No user profile / PII; only operational events.

Action Items:

1. Ensure export contains only approved columns.
2. Periodic lint script scanning for banned field names (email, name, phone).
3. Document exact synced payload schema snapshot.

### 7. Performance & Battery

Instrumentation-first approach prevents regressions.

Action Items:

1. Lightweight metrics collector (in-memory rolling window).
2. Nightly debug panel exposing: avg event latency, max queue depth, battery delta.
3. Prune logs older than 30 nights except aggregate stats.

## 📊 Current Metric Baselines (Establish Early)

| Metric | Baseline (Target to Set) | Notes |
|--------|--------------------------|-------|
| Event loss rate | (capture after harness) | Expect 0 in synthetic runs |
| Undo success under load | (harness) | Stress test with 50 rapid events |
| Target drift (median) | (after v0.2) | Post-baseline instrumentation |
| Battery delta | (10-night sample) | Compare control vs instrumented |
| VoiceOver cue accuracy | (manual audit) | Log actual vs scheduled timestamps |

## 🧪 Test Coverage Priorities

| Domain | Minimum Cases |
|--------|---------------|
| DST | Forward 1h, backward 1h, crossing midnight pre/post change |
| Snooze | Edge at 16m remaining (allowed) vs 14m (blocked) |
| Undo | Action, wait 4.9s undo, ensure no server persists |
| Queue Replay | 20 queued events flush order preserved |
| Planner | Beta update after success/failure; rationale string fallback |
| Export | Deterministic hash stable across runs |

## 🧩 Open Questions

| Question | Decision Needed By | Notes |
|----------|--------------------|-------|
| Sync optional or default? | Before v0.1 freeze | Drives privacy policy wording |
| Snooze cap numeric value? | Before v0.1 | Needed for test harness script |
| Planner reward proxy final? | Before v0.4 dev start | Natural wake + no skip? |

## 🧭 Recommendations (Next 2 Weeks)

1. Build and run DST & travel harness (blocker for future confidence).
2. Implement offline queue + idempotent keying before adding planner complexity.
3. Ship initial accessibility pass early (reduces late rework).
4. Instrument metrics before optimization—measure, then tune.

## 📌 Definition of Done (Evaluation Perspective)

1. No clamp violations in automated nightly simulation.
2. Undo race test passes (no orphan events) across 1k iterations.
3. VoiceOver timestamps within ±2s of schedule.
4. Export hash unchanged for same underlying event set.
5. Battery delta within target over sample.
6. Privacy scan finds zero banned identifiers.

---
Last Updated: 2025-09-03
Owner: DoseTap Technical Team
