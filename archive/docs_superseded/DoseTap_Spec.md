# DoseTap – Product Spec & Presentation Pack

**One‑liner:** Tap once for Dose 1. Inside the **2.5–4 h** window, we remind you at a minute you’re likely to surface, then tap again for Dose 2. Bathroom/Out‑of‑Bed events help the timing model. Data is local‑first; optional minimal sync (dose + adjunct events only) can be enabled.

## Problem → Opportunity

Split‑dose XYWAV at ~3 AM is easy to miss or mishandle. Phones are bright and slow. We replace screens with one tactile button and an adaptive reminder that never leaves the **2.5–4 h** label window.

## Solution (XYWAV-Only)

- **Hardware button (Flic 2)** → URL scheme → app logs `dose1|dose2|bathroom` and schedules Dose 2 reminders.
- **Adaptive placement:** baseline = median Time‑to‑First‑Wake (TTFW) from Health/WHOOP history; same‑night nudges in `nudge_step_min` (default 10); **hard clamp 150–240 min** (never violated).

## Architecture

- iOS SwiftUI app + watchOS companion (three-button interface: Take / Snooze / Skip).
- HealthKit: Sleep Analysis (stages), HR/RR/HRV/SpO₂ read (adaptive scheduling + insights; on-device only).
- WHOOP API v2: sleep history + historical HR/RR for personalization only.
- Unified on‑device store (SSOT): merges Apple Health, WHOOP, manual dose_events → timeline + insights. JSON persisted; CSV export.
- Optional minimal sync service: device bearer token; payload = event type + UTC timestamp + offset only (no PII, no health metrics) for backup if user opts in.

## Events (codes)

`dose1`, `dose2`, `bathroom`, `lights_out`, `wake_final`, `snooze`

All events share fields: `type`, `at` (UTC ISO 8601), `local_offset_sec`, optional `meta` (string→string, tightly controlled). Idempotency key = `type + at + device_id`.

## MVP (Re-scoped)

- URL handler: `dosetap://log?event=dose1|dose2|bathroom` (+ lights_out, wake_final optional logging later).
- Dose 2 adaptive reminder: default 165 min; clamp [150, 240].
- Watch: three large buttons; haptic (success / warning / notify variants).
- Tonight: countdown ring + Take / Snooze (10m) / Skip only.
- Timeline: sleep stages + HR/RR sparklines + markers (dose1/dose2/bathroom).
- Insights: Dose timing (median/min/max + on-time %), Natural‑wake %, WASO post Dose 2; CSV export.
- Undo: 5s rollback window after any staging action (dose1, dose2, snooze, adjunct events).

## Limitations & Mitigations

- iOS background: keep the Flic app running (don’t force‑quit).
- WHOOP latency: use for **history**, not live staging.
- HealthKit variability: rely on multi‑night baselines, small same‑night nudges.

## Roadmap

- v0.1 Tonight‑ready slice
- v0.2 HealthKit baseline & nudges
- v0.3 WHOOP history personalization
- v0.4 Insights + CSV export

## Action Plan (Weeks)

- **Week 0:** URL scheme, notifications, 165‑min default
- **Week 1:** HealthKit sleep read + baseline; Snooze 10m
- **Week 2:** WHOOP OAuth + 30‑night import; Insights v1
- **Week 3:** Polish, slides, demo

## Success Metrics (Product)

- % Dose 2 on‑time (inside 2.5–4 h)
- % natural‑wake nights (wake_final without external alarm)
- Median Dose1→Dose2 interval stability (variance ↓)
- WASO minutes post-Dose2 (trend ↓)

## Data Model (Authoritative)

<!-- Removed duplicate tab-indented JSON block (lint) -->

## Adaptive Planning Details (Preview)

Phases:

1. Baseline Only: Use median TTFW from last N nights (N=14–30) → target = min(max(median,150),240) else default 165 if insufficient data (<5 nights).
2. Discrete Interval Bandit (Opt‑In): Candidate set C = {165,180,195,210,225}. Maintain Beta(α,β) for each interval where “success” = natural wake OR user reports was “already awake” at dose2 (meta flag). Choose interval with highest sampled value each night (Thompson Sampling). Always clamp inside [150,240].

State Persistence:

- Store (interval_minutes, alpha, beta, last_selected_at) per candidate.
- Reset (reinitialize all α=1, β=1) if user disables planner for >7 nights.

Rationale String Examples:

- “Selected 195m (recent natural wakes clustering near 193–197m).”
- “Using baseline 165m (insufficient data for adaptive).”

Safeguards:

- Minimum nights before activation: 5 baseline nights.
- Never schedule <150 or >240 even if sampled interval drifts.
- If previous night labeled ‘poor wake’, weight that interval’s β += 1.

## DST & Timezone Handling

Canonical storage = UTC. Each event stores `local_offset_sec` for reconstruction.

Rules:

1. Dose2 scheduling uses absolute UTC delta from dose1 (not wall clock arithmetic).
2. On DST forward skip (spring): if scheduled local time falls in missing hour, fire at earliest valid local minute ≥ clamp min.
3. On DST backward repeat (fall): maintain original UTC; if duplicate local time occurs, annotate display with “(1)” or “(2)” pass to disambiguate.
4. Timezone travel: if device timezone changes before dose2, do not recompute interval; display adjusts via offset only.
5. Export always uses ISO 8601 UTC + separate local offset column.

Harness Cases:

- Spring forward with dose1 30m before jump.
- Fall back with dose2 landing in repeated hour.
- Eastward travel (+5h) between dose1 and planned dose2.
- Westward travel (−8h) mid-window.

## Accessibility Acceptance Criteria

| Area | Criterion | Measure |
|------|-----------|---------|
| VoiceOver Cues | Pre-target (−5m), target, window end announced | Timestamps within ±2s in harness |
| Hit Targets | Primary buttons ≥48×48pt | Audit in snapshots |
| Contrast | High contrast mode ≥4.5:1 | WCAG tool pass |
| Dynamic Type | No truncation at XL sizes | Manual + automated snapshot |
| Haptics | Distinct patterns (success, warning, notify) | Pattern IDs documented |
| Watch Hold | Hold-to-confirm duration 600–900ms | Timer measurement |

## Undo Semantics

Window = 5s from staging. If undo occurs after network queued but before send, event removed from queue. If network already sent, a compensating “retract” event (type same + meta.retracted=true) is appended (server idempotent ignore). Local UI always reflects final state within 200ms.

## Minimal Sync (Optional)

Disabled by default. If enabled:

- Endpoint: POST /events/batch (max 50 events).
- Payload fields: device_id (random), events[{type, at, offset_sec, idempotency_key}].
- Response: ack_ids[]. No health metrics or WHOOP data transmitted.
- Removal: toggle off purges remote copy at next maintenance call.

## Export CSV Schema

Columns: date, dose1_time_utc, dose2_time_utc, dose_interval_min, within_window (bool), bathroom_count, natural_wake (bool), waso_minutes.

Deterministic ordering; newline terminator always LF.

## Error Codes (Reference)

| Code | Meaning |
|------|---------|
| WINDOW_EXCEEDED | Attempted dose2 outside clamp |
| DOSE1_REQUIRED | Dose2 before dose1 logged |
| ALREADY_TAKEN | Duplicate dose event |
| SNOOZE_LIMIT | Snooze blocked (<15m or overshoot) |
| DEVICE_NOT_REGISTERED | Sync attempted without device auth |
| RATE_LIMIT | Too many actions in short window |

## Observability (On-Device)

Local metrics overlay (debug builds): queue_depth, last_flush_ms, avg_write_ms, battery_delta_pct, undo_window_remaining_s, selected_interval.

## Security Constraints

- No PII; device_id random UUID v4.
- No sharing of health metrics externally.
- Encrypted at rest via iOS data protection.
- Export only manual; no auto background export.

## Acceptance Criteria (Definition of Done)

1. No UI or docs reference any non-XYWAV medication (names, CRUD actions, refill, pharmacy).
2. Tonight shows countdown ring + Take / Snooze / Skip only (after dose1 logged).
3. Adaptive scheduling never proposes outside 150–240 min; default used if insufficient data.
4. Timeline renders sleep stages + markers for all dose_events and bathroom events.
5. Insights shows Dose Timing, Natural Wake %, WASO; CSV export yields only those metrics.
6. Watch app provides three-button interface with distinct haptics + hold-to-confirm where required.
7. API limited to: POST /doses/take, POST /doses/skip, POST /doses/snooze, POST /events/log, GET /doses/history, GET /analytics/export.
8. Undo available for 5s for all staged actions; race tests pass.
9. Accessibility criteria table all green in harness.
10. DST harness all test cases pass; no clamp violations.

## Removed (Explicit)

- Medication list / multi-drug CRUD
- Refill & pharmacy flows
- Adherence-by-medication analytics
- Generic medication examples (Metformin, Lisinopril, etc.)
- Web dashboards / microservices / subscription billing / caregiver portals
