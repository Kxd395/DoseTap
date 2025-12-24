<!-- SSOT: Single Source of Truth for DoseTap (XYWAV-only) Modernization -->
# DoseTap SSOT – XYWAV-Only Modernization Plan

> Source-of-truth plan driving the audit + phased PR implementation to convert DoseTap into a night-first, XYWAV-only, safety-focused app across iOS / watchOS (and supporting docs). This replaces prior multi-med / generic flows.

---

## Role (Agent Mission)

You act as a senior iOS/watchOS architect. Audit and modernize the DoseTap app to be **XYWAV-only**, night-first with strict 2.5–4h (150–240m) Dose2 window logic. Implement updated UI/UX, timing safety rails, Undo flows, offline resilience, planner, accessibility, integrations, and tests. Produce **small, reviewable, shippable PRs**.

---

## Authoritative Inputs (Read First)

* `docs/DoseTap_Spec.md` – XYWAV scope, clamp 150–240m, defaults
* `docs/ui-ux-specifications.md` – night-first, palette, typography, accessibility targets
* `docs/button-logic-mapping.md` – button states, near-window rules, errors, Undo, deep links, Flic mapping
* `docs/api-documentation.md` – endpoints contract
* `docs/user-guide.md`, `docs/implementation-roadmap.md` – trim to match XYWAV-only scope

---

## Non-Goals (Purge Everywhere)

Remove legacy or out-of-scope elements: multi-med CRUD, refills/pharmacy, caregiver/provider portals, generic auth flows beyond device registration, payment scaffolding.

---

## Scope & Constraints

* On‑label timing only: Dose2 valid only within 150–240 minutes of Dose1 anchor.
* On-device first: planner + analytics computed locally; server only for dose actions, event log, export.
* No secrets committed.
* Tooling: SwiftPM / Xcode; GitHub Actions (macOS). Optional Node only for docs tooling.

---

## Deliverables (Planned PRs)

### PR-1: XYWAV Hard-Lock + Endpoint Wiring

* Remove multi-med artifacts, routes, strings.
* Wire endpoints:
  * `POST /doses/take` body `{ "type": "dose1|dose2", "timestamp": ISO8601 }`
  * `POST /doses/skip` body `{ "sequence": 2, "reason"?: string }`
  * `POST /doses/snooze` body `{ "minutes": 10 }`
  * `POST /events/log` for `bathroom|lights_out|wake_final`
  * `GET /analytics/export`
* Error surfaces (UX copy must match spec): `422_WINDOW_EXCEEDED`, `422_SNOOZE_LIMIT`, `422_DOSE1_REQUIRED`, `409_ALREADY_TAKEN`, `429_RATE_LIMIT`, `401_DEVICE_NOT_REGISTERED`, `OFFLINE`.

### PR-2: Night-First UI + Accessibility

* Tonight screen: countdown ring hero + actions: Take / Snooze 10m / Skip.
* Near-window: disable Snooze when <15m remaining; primary CTA flips to “Take Before Window Ends (MM:SS)”; block after close.
* Undo snackbar (5s) for Take / Skip (reverts local state + cancels queued call if pending).
* Timeline: stage bands + HR/RR overlays + immutable markers.
* Insights: On-time %, Dose1→Dose2 interval stats, Natural-wake %, WASO; CSV export.
* Settings → XYWAV: show clamp (read-only), default interval (165m), Nudge step, accessibility toggles (High Contrast, Reduced Motion).
* Accessibility: VoiceOver announcements at ±5m and at window close; Dynamic Type up to XXL; ≥48pt targets; high contrast ≥7:1 for action cluster.

### PR-3: watchOS + Flic Ergonomics

* watchOS dose card: press‑and‑hold 1s required for Take; Snooze 10m; Skip; guard to log Dose1 if absent.
* Flic mapping: single‑press = Take, long‑press = Snooze, double‑press = Bathroom event.

### PR-4: Weekly Planner + Deep Links + Analytics Events

* Client-only planner: choose from discrete safe set `{165,180,195,210,225}`; generate 7-day plan (date, interval_min, rationale); persist local.
* Deep links: `dosetap://log?event=dose1|dose2|bathroom|lights_out|wake_final`.
* Emit analytics events (exact names): `dose1_taken`, `dose2_taken`, `dose2_snoozed`, `dose2_skipped`, `bathroom_event_logged`, `analytics_exported`, `undo_performed`, `weekly_plan_generated`, `deeplink_invoked`.

### PR-5: Tests + CI

* Unit: window math (DST/timezones), near-window edge (239–240m), Undo correctness, offline queue flush, deep link actions, error handling (422/409/401/429), snooze clamp logic.
* UI: Tonight buttons state transitions, Insights export, Settings toggles, watchOS interactions (gesture/press-and-hold), Undo flow.
* CI: macOS workflow building + running unit/UI tests; fail on warnings where feasible.

---

## Repo Tasks (Execution Steps)

1. Codebase sweep / deletion:
	* Remove residual multi-med modules/directories (e.g., `Medication*`, refill/pharmacy, caregiver/provider views), purge strings.
	* Rename navigation / tabs to: Tonight, Timeline, Insights, Devices, Settings.
	* Replace language (“Medication Event”) with XYWAV-specific phrasing where appropriate (but preserve analytics identifiers if required by backend contract).
2. Wire endpoints + central state:
	* Preflight clamp before enabling Take/Snooze buttons.
	* Offline queue (Take/Snooze/Skip) with `[Queued]` chip; auto flush on connectivity restoration.
3. Implement button logic per `docs/button-logic-mapping.md` (component IDs, state transitions, Undo, error surfaces, test matrix alignment).
4. Planner module: analyze past intervals, propose 7-day safe sequence, store rationale; surfaced in Insights (Generate Weekly Plan).
5. Integrations: HealthKit, optional WHOOP import (one-time backfill), Flic hardware binding, deep link handlers.
6. Documentation refresh: update `user-guide.md` (XYWAV Quick Start), trim `implementation-roadmap.md` & `upgrades.md` to on-device focus; ensure `api-documentation.md` + `button-logic-mapping.md` reflect final payloads & errors.

---

## Acceptance Criteria

1. No multi-med UI or endpoints remain—only XYWAV flows.
2. Tonight screen: countdown ring + Take/Snooze/Skip; Snooze disabled <15m; window-close blocking state.
3. Undo (5s) for Take/Skip reverts local state + cancels queued network if pending.
4. Timeline immutable; Insights metrics & CSV export functional.
5. Settings exposes clamp (read-only), defaults, Nudge step, accessibility toggles; high contrast ≥7:1.
6. watchOS: press-and-hold 1s requirement; Snooze/Skip functional; Dose1 guard enforced.
7. Flic mapping exact: single=Take, long=Snooze, double=Bathroom event log.
8. Deep links invoke actions; analytics events emitted with exact naming.
9. Tests cover edge cases (239–240m, DST/timezone shifts, offline queue, error codes 422/409/401/429, snooze limit, Undo consistency).
10. CI passes (no warnings where enforced).

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Half-asleep mis-taps | Press-and-hold for Take (watch); Undo 5s; near-window warnings. |
| DST / timezone shifts | Use absolute timestamps; anchor Dose2 window to stored Dose1 timestamp; robust tests. |
| Offline nights | Queue actions with explicit `[Queued]`; single-send flush on reconnect; idempotent client IDs if needed. |
| Snooze abuse | Enforce limit + window clamp preflight, explicit 422 errors. |
| Visual overload / A11y | High contrast mode, reduced motion, large tap targets, progressive disclosure in Timeline. |

---

## PR Naming & Owners (Template)

* `pr/xywav-endpoints-wiring` — Owner: iOS core
* `pr/night-first-ui-a11y` — Owner: iOS UI
* `pr/watchos-flic-deeplinks` — Owner: watchOS / integrations
* `pr/weekly-planner-client` — Owner: analytics
* `pr/tests-and-ci` — Owner: QA / infra

---

## Implementation Notes / Guidance

* Favor deterministic state machines for button logic (testable pure functions) feeding SwiftUI views.
* Maintain separation: networking layer (APIClient) vs. domain timing engine vs. presentation.
* Introduce small analytics dispatcher with enum → string mapping (centralized) to avoid typos.
* Planner: keep heuristic rationale strings standardized for CSV export & potential future ML.
* Undo should maintain an operation token to cancel pending network (e.g., maintain Task handle or queue entry removal) rather than issuing compensating calls.
* Use dependency injection for time source (facilitates DST + edge tests).

---

## Next Actions (Kickoff Checklist)

1. Tag legacy multi-med references (grep & log) – create deletion diff.
2. Introduce feature flags (if needed) for Tonight redesign & planner.
3. Define DoseWindowState model (input: now, dose1Time, dose2Taken?, snoozeCount) → outputs (ctaPrimary, ctaSecondaryStates, windowRemaining, errors?).
4. Draft tests for DoseWindowState before UI wiring.
5. Extend `APIClient` with new endpoints + typed error decoding.
6. Implement offline queue abstraction (protocol + in-memory store) with flush tests.

---

## Changelog Policy

Each PR updates this SSOT only in sections it touches (append “Change Log” subsection summarizing deltas). Avoid broad edits outside scope.

---

End of SSOT.

---

## Change Log (Modernization Progress)

### 2025-09-03

Added core foundations for PR-1:

* Introduced `DoseCore` SwiftPM target isolating pure logic from UI.
* Implemented `DoseWindowCalculator` (phases: noDose1, beforeWindow, active, nearClose, closed, completed) with primary / secondary CTA modeling and snooze limit handling.
* Added boundary + near-close tests (`DoseWindowStateTests`, `DoseWindowEdgeTests`) including exact 150 / 165 / 225 / 239 / 240 minute transitions and a DST forward jump simulation.
* Implemented API error mapping (`DoseAPIError`, `APIErrorMapper`) covering server codes: 422_WINDOW_EXCEEDED, 422_SNOOZE_LIMIT, 422_DOSE1_REQUIRED, 409_ALREADY_TAKEN, 429_RATE_LIMIT, 401_DEVICE_NOT_REGISTERED, plus local OFFLINE placeholder.
* Added offline resiliency layer skeleton (`OfflineQueue` protocol and `InMemoryOfflineQueue` actor) with enqueue / retry (exponential backoff) / max retry drop logic and tests.
* Temporarily removed executable app & watch targets from Package.swift to keep CI green while legacy source cleanup is pending; they will be reintroduced after pruning invalid SwiftUI / legacy constructs.

### 2025-09-04

Incremental progress toward PR-1 wiring and minimal UI reactivation:

* Reintroduced a minimal executable iOS app target (`DoseTap`) containing `DoseTapApp.swift` + `TonightView.swift` to exercise the pure `DoseWindowCalculator` in a live SwiftUI context (still intentionally lean; full Tonight UX pending).
* Added `APIClient` with endpoints: takeDose (`POST /doses/take`), skipDose (`POST /doses/skip`), snooze (`POST /doses/snooze`), logEvent (`POST /events/log`), export analytics (`GET /analytics/export`) including uniform error mapping for all 4xx/5xx responses via existing `APIErrorMapper`.
* Implemented `DosingService` actor façade integrating `APIClient` + `OfflineQueue` (wraps failed actions into `AnyOfflineQueueTask` for later flush) – initial heuristic queues all failures; will refine to network/offline classification.
* Added `APIClientTests` validating request formation (paths, methods, bodies) and error code mapping for 422_SNOOZE_LIMIT; expanded Package manifest to include new sources & tests.
* Standardized error handling across all dose/event endpoints (previously some POSTs ignored status code path).
* Full test suite now at 23 passing tests covering window logic, DST edge, error decoding, queue behavior, and API client basics.
* Updated Package.swift to explicitly list new core files (`APIClient.swift`, `APIClientQueueIntegration.swift`).
* SSOT updated with this change entry to maintain authoritative modernization trace.

Planned next (short-term): refine offline error differentiation, introduce Undo token model tied to queued tasks, expand tests for queue integration & export analytics content expectations.

## Current Status Snapshot

| Component | Status | Notes |
| --------- | ------ | ----- |
| Dose window pure model | Complete (initial) | Edge tests green; may extend for future planner hints. |
| API error decoding | Complete | Ready to integrate into upcoming `APIClient` refactor. |
| Offline queue | MVP complete | Actor-based; integrate with endpoint layer & Undo cancellation tokens next. |
| Legacy removal | Pending | Multi-med artifacts still present in app target (excluded from build). |
| Executable targets | Temporarily disabled | To be restored after cleanup + endpoint wiring. |
| watchOS press-and-hold ergonomics | Not started | Requires reintroduction of watch target. |
| Planner module | Not started | Will consume dose history + recommendation engine. |
| Undo infrastructure | Not started | Design will tie into queue (remove enqueued task) vs compensating call. |
| CI workflow | Not started | Add GitHub Actions after endpoint wiring stabilized. |

## Upcoming (Next Iteration)

1. Reintroduce iOS app target with only files required for Tonight screen + state binding to `DoseWindowCalculator`.
2. Implement dose endpoints in `APIClient` with unified error mapping & integrate OfflineQueue.
3. Implement Undo manager tokenization allowing cancel of queued operations pre-flight.
4. Reinstate watchOS target minimal scaffold (ContentView + press-and-hold gesture) once iOS core stable.
5. Begin pruning legacy files & references (UnifiedStore, WHOOP placeholder adjustments) aligning with XYWAV scope.

## Tech Debt / Follow-Ups

* Replace ad-hoc date math test for DST with property-based test fuzzing time zone transitions.
* Evaluate switching exponential backoff sleep to a scheduler abstraction for deterministic time-travel testing.
* Add structured logging for queue retries (with jitter) before production hardening.
* Consider adding stable semantic versioning for `DoseCore` if planner logic reused externally.

