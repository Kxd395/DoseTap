# Implementation Roadmap (XYWAV-Only, On-Device Focus)

All prior multi-med, provider, pharmacy, web dashboard, and microservices plans are removed. Roadmap now targets a lean iOS + watchOS app with a minimal API for event persistence. Adaptive intelligence remains fully on-device.

## 🎯 Core Objectives

1. Reliable Dose 2 timing within 150–240m clamp (default target 165m).
2. Minimize night friction (≤2 taps typical night; optional Snooze).
3. Preserve data privacy (dose & adjunct events only leave device).
4. Provide transparent adaptive rationale (simple intervals, no opaque ML).
5. Ship incremental, testable slices (weekly vertical cuts).

## ✅ Current Completed (Baseline)

| Area | Status | Notes |
|------|--------|-------|
| API Slimming | Done | Only auth, doses, snooze, skip, events, history, export |
| Button Logic Spec | Done | Undo, Snooze rules, edge cases captured |
| User Guide | Done | Night-first quick start |
| UI/UX Spec | Done | Tonight / Timeline / Insights / Devices / Settings |
| Product Description | Done | Single-regimen narrative |

## 🗺 Phased Delivery (v0.x Series)

| Version | Focus Slice | Key Deliverables | Exit Criteria |
|---------|-------------|------------------|---------------|
| v0.1 | Tonight Core | Log Dose1/Dose2, window calc, fixed 165m, Skip, Snooze disabled <15m | 3 consecutive nights logged; clamp enforced |
| v0.2 | Adaptive Baseline | HealthKit sleep import (last 14 nights), baseline TTFW median, adjust target (still within clamp) | Target shifts ±10m vs default when justified |
| v0.3 | Insights & Export | Timeline (stages + events), Insights panel (timing stats, natural wake %, bathroom count), CSV export | CSV columns match spec; 30-night retention validated |
| v0.4 | Planner Preview | Local Thompson Sampling among {165,180,195,210,225}, rationale sheet, opt-in toggle | Planner never outside clamp; can disable instantly |
| v0.5 | Accessibility & Reliability | High contrast, VoiceOver timed announcements, offline queue w/ retry UI, Undo hardened | All a11y acceptance criteria met; offline tests pass |
| v0.6 | watchOS Enhancement | Hold-to-confirm take, haptic escalation, complication shortcut | 100% functional parity for core actions |
| v0.7 | DST & Travel Hardening | TZ shift tests, DST boundary simulation, interval correctness proofs | All DST cases retain proper elapsed minutes |
| v0.8 | Quality & Polish | Performance budgets, battery impact audit, log pruning, error copy refinement | <1% crash rate, <2% battery impact overnight |

## 🧬 Adaptive / Planner Evolution

Phase progression for adaptation:

1. Baseline only (median TTFW) → deterministic target.
2. Add same-night nudges (light/REM wake clusters ±10m).
3. Introduce discrete bandit (prior Beta(1,1) each interval). Reward = on-time subjective wake quality proxy (placeholder: natural wake flag & absence of skip). Update nightly; pick argmax sampled value. Always clamp.
4. Provide transparent rationale surface: “Chose 195m tonight (recent light wake cluster ~194m).”

## 🗃 Data & Storage

| Artifact | Location | Retention | Notes |
|---------|----------|-----------|-------|
| dose_events JSON | Local (Core Data / file) | Rolling 365 nights | Purged after export optional |
| adaptive_baseline | Local | Recomputed nightly | Median of validated nights |
| planner_state | Local | 30-day half-life decay | Beta params per interval |
| export CSV | User share sheet only | Ephemeral | Not persisted post-share |

## ⚙️ Minimal API Contract (Reference)

Already defined in `api-documentation.md`; no new endpoints planned through v0.8. Planner remains client-only.

## 🔐 Security & Privacy Posture

| Area | Approach | Rationale |
|------|----------|-----------|
| Auth | Device token (bearer) | Simple; no user PII |
| Data Scope | Dose + adjunct events only | Reduces breach impact |
| Encryption | iOS at-rest + TLS in transit | Platform native |
| Export | CSV only, manual trigger | User-controlled sharing |

## 📏 Success Metrics

| Metric | Target v0.1 | Target v0.4 | Target v0.8 |
|--------|-------------|------------|------------|
| % Dose2 inside window | ≥90% | ≥93% | ≥95% |
| Median deviation from target | ≤10m | ≤8m | ≤6m |
| Night actions (avg) | ≤3 | ≤3 | ≤3 |
| Undo usage rate (err corr) | Baseline | ↓ (stability) | ↓ further |
| Crash free sessions | 98% | 99% | 99.5% |
| Battery impact overnight | — | <3% | <2% |

## 🧪 Test Matrix (Incremental Additions)

| Phase | New Critical Tests |
|-------|--------------------|
| v0.1 | Clamp edges (150/240), Snooze disable <15m, Undo timing |
| v0.2 | Baseline calc with missing nights, noisy outlier exclusion |
| v0.3 | CSV export correctness, insight stats recompute after late Dose2 |
| v0.4 | Bandit selection reproducibility (seeded), rationale text accuracy |
| v0.5 | VoiceOver announcements schedule, offline queue flush after 3 retries |
| v0.6 | watchOS hold-to-confirm guard, haptic escalation timing |
| v0.7 | DST forward/back shift, timezone travel mid-window |
| v0.8 | Battery profiling, error copy consistency |

## 🔄 Operational Cadence

| Cadence | Activity |
|---------|----------|
| Daily | Standup + prior-night anomaly scan |
| Weekly | Release (if green), planner effectiveness review (once enabled) |
| Monthly | A11y & crash audit, battery impact sample |

## 🪲 Risk Register (Slim Scope)

| Risk | Impact | Mitigation |
|------|--------|-----------|
| HealthKit permission revoked mid-night | Missed adaptive adjustment | Fallback to fixed target (165m) + banner |
| Excessive snoozes degrade adherence | Interval drift beyond comfort | Snooze cap + disable <15m remaining |
| Bandit converges to suboptimal interval | Reduced on-time % | 30-day half-life decay + manual disable |
| DST logic regression | Incorrect clamp rendering | Dedicated DST test harness |
| Offline queue overflow | Lost events | Size cap + oldest-drop + user alert |

## 🧩 Out-of-Scope (Explicit)

Removed permanently for this cycle: multi-med lists, pharmacy/refill flows, provider portals, web dashboards, real-time chat, pill bottle IoT, FHIR/insurance, subscription billing.

## 📌 Definition of Done (Per Feature)

1. All acceptance criteria in spec satisfied.
2. Unit + integration tests added (≥1 happy path + ≥1 edge per new function).
3. Accessibility pass (VoiceOver + Dynamic Type + contrast) complete.
4. No lint or markdown errors introduced.
5. Energy profile unchanged (±0.5% battery overnight) unless feature explicitly energy-related.
6. Docs (spec, user guide, button mapping) updated for any new UI element.

## 🔁 Change Management

Lightweight ADR note stored inline at top of modified spec sections for any planner algorithm tweak, DST handling change, or undo semantics alteration.

## 📅 Next Immediate Steps

1. Integrate baseline HealthKit importer (sleep + HR/RR) – v0.2 gate.
2. Insert planner placeholder section into `DoseTap_Spec.md` (v0.4 prep).
3. Build DST test harness + add cases (pre-work for v0.7).

---
Last Updated: 2025-09-03
Owner: DoseTap Technical Team
