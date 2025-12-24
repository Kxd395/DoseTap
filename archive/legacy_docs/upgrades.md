# DoseTap Technical Hardening & Upgrade Plan (XYWAV-Only Scope)

Focused on on-device accuracy, resilience, privacy, accessibility, and minimal API reliability. All web/microservice, multi-med, payments, IoT, real-time dashboards, and heavy analytics items are intentionally out-of-scope.

## 🎯 Objectives

1. Keep Dose 2 timing accurate (clamp 150–240m; target drift ≤6m by v0.8).
2. Guarantee action recording even offline (zero lost events in test harness).
3. Maintain user trust: local-first, only minimal event sync (if enabled) of dose + adjunct events.
4. Provide accessible, low-friction nightly flow (≤2 taps typical; hold-to-confirm on watch).
5. Preserve battery (overnight incremental cost <2%).
6. Enable transparent adaptive evolution (baseline → planner) without opaque ML.

## 🧱 Scope Boundary

In: Dose logging, Snooze constraints, Undo, Adaptive baseline, Discrete planner intervals, HealthKit ingestion (sleep, HR, RR, HRV, SpO₂), export CSV, accessibility, DST/timezone correctness, watchOS parity.

Out: Multi-med management, web dashboards, microservices, OAuth providers, subscription billing, caregiver portals, heavy real-time socket features, third-party data brokering.

## 🗂 Upgrade Pillars

| Pillar | Goal | Key Activities | Success Metric |
|--------|------|----------------|----------------|
| Timing Accuracy | Clamp enforcement & interval precision | Deterministic interval math, DST harness, test edge cases | 0 failing DST tests; clamp never violated |
| Reliability | Never lose an action | Offline queue, idempotent event writes, conflict resolution | 0 lost events across 10k simulated sequences |
| Accessibility | Inclusive nightly use | VoiceOver announcements, high contrast theme, large targets | All WCAG AA relevant checks pass |
| Adaptive Evolution | Safe iterative improvement | Baseline median, optional discrete bandit, rationale strings | Planner opt-in disable <2 taps |
| Privacy & Minimal Sync | User data control | Event minimization, local encryption, explicit export | No PII in payloads; export manual only |
| Performance & Battery | Low overhead | Instrumentation, diff sampling, log pruning | <2% added battery drain |
| Observability (Lean) | Debug without noise | Local structured log, lightweight counters, anomaly flags | Root cause any failure <30m |

## 🔐 Security & Privacy Hardening

| Area | Action | Rationale |
|------|--------|-----------|
| Auth | Device bearer token only | Reduce surface |
| Data Minimization | Store only dose + adjunct events, baseline aggregates | Limit breach value |
| Export Control | On-demand CSV via share sheet | User explicit consent |
| Local Protection | iOS protected storage (FileProtection.completeUntilFirstUserAuthentication) | Safeguard on reboot |
| Network | TLS only; retry backoff (1s,2s,5s,10s max) | Avoid thundering herd |
| Identifiers | Short random device_id; no email/user profile | De-identify events |

## 🧪 Reliability & Test Harness

| Test Domain | Cases |
|-------------|-------|
| Interval Math | 150, 165, 180, 195, 210, 225, 240, DST forward/back, timezone travel east/west mid-night |
| Snooze Rules | <15m remaining blocked, cap reached, clamp exceed attempt |
| Undo | 0–5s window, post-sync rollback, network race |
| Offline Queue | Burst actions (dose→snooze→bathroom), airplane mode, reorder arrival |
| Planner | Beta param update, opt-out mid-run, rationale text fallback |
| Export | Empty nights, partial night, 30-night span, localization neutrality |
| Accessibility | VoiceOver focus order, announcement timing, high contrast toggle persistence |

## ⚙️ Core Module Upgrade Plan

| Module | Current | Upgrade | Definition of Done |
|--------|---------|--------|-------------------|
| TimeEngine | Simple diff calc | DST-safe, timezone-aware, clamp guard | All harness cases pass |
| EventStore | Flat append JSON | Indexed by date, offline queue + retry meta | 0 lost events simulation |
| UndoManager | Basic in-memory revert | Snapshot, rollback intents, collision guard | Pass race tests |
| SnoozeController | Fixed +10m | Policy enforcement (min remaining, cap) | Violations blocked w/ code |
| BaselineModel | Median TTFW naive | Outlier filter (IQR), minimum nights threshold | Accurate vs fixture set |
| PlannerModule | Placeholder | Discrete Thompson Sampling + rationale builder | Interval distribution logged |
| AccessibilityLayer | Basic labels | VoiceOver timed cues, large hit targets | A11y script passes |
| ExportFormatter | CSV draft | Deterministic column order & ISO 8601 | Hash stable across runs |

## 📏 Performance & Battery

Instrumentation additions:

1. Timestamp delta from Dose1 to Dose2 event processing completion.
2. Queue depth (max, p95) per night.
3. Battery delta sampling (start-night vs morning) for 10 test nights vs control build.
4. Log size growth curve and pruning effectiveness.

Targets:

| Metric | Target |
|--------|--------|
| Event write latency (local) | <10ms p95 |
| Queue flush after reconnect | <2s p95 |
| Additional overnight battery | <2% |
| Log storage footprint | <5MB rolling |

## 🧩 Migration / Sequencing

1. Harden TimeEngine + EventStore (foundation for all reliability).
2. Implement offline queue & idempotent write contract.
3. Add UndoManager race-safe rollback.
4. Integrate baseline median model w/ outlier filtering.
5. AccessibilityLayer full pass (contrast, VoiceOver, haptics).
6. ExportFormatter deterministic & tested.
7. PlannerModule (opt-in) + rationale rendering.
8. Battery / performance instrumentation & tuning.

## 🛠 Tooling Enhancements (Lean)

| Tool | Purpose |
|------|---------|
| Local Harness Script | Simulate 10k night sequences w/ failures |
| DST Simulator | Inject time jumps + timezone changes |
| VoiceOver Script | Automated rotor focus & announcement capture |
| Export Comparator | Hash+diff previous vs new CSV outputs |

## 🗃 Data Lifecycle

| Data | Retention | Purge Policy |
|------|-----------|-------------|
| Events | 365 nights rolling | Drop >365d nightly sweep |
| Baseline | Recomputed nightly | Derived – no standalone retention |
| Planner Beta Params | Decayed continually | Reset on opt-out |
| Export Artifact | Ephemeral | Not stored after share sheet |

## 📌 Definition of Done (Upgrade Items)

1. Metrics added & observable in local diagnostics screen.
2. All harness suites green (interval, snooze, undo, offline, DST).
3. A11y audit checklist signed (contrast ratios, labels, VO timing).
4. No new privacy surface (payload diff verified empty of PII).
5. Energy sample run shows ≤ target battery delta.
6. Documentation (spec + roadmap) references new capability.

## 🚫 Explicit Non-Goals

Microservices, distributed tracing, GraphQL layer, caregiver sharing portals, real-time push sockets, subscription billing, advanced analytics dashboards, third-party monetization pathways.

## 📅 Immediate Next Steps

1. Implement DST/timezone harness & add failing tests (then fix TimeEngine).
2. Add offline queue with replay + collision resolution logic.
3. Integrate undo snapshotting w/ event staging.

---
Last Updated: 2025-09-03
Owner: DoseTap Technical Team
