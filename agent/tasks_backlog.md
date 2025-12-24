# Tasks Backlog

- [ ] URL scheme and event router
- [ ] Reminder scheduling (identifier: secondDose)
- [ ] HealthKit permission + Sleep read (14–30 nights)
- [ ] TTFW baseline computation
- [ ] Same-night nudge (±10–15 min)
- [ ] WHOOP OAuth screen + token storage
- [ ] WHOOP sleep/cycle fetch (history import)
- [ ] Watch app: Dose1/Dose2/Bathroom buttons
- [ ] Insights: Avg interval, natural vs alarm %, bathroom clustering
- [ ] CSV exporter
- [ ] Debounce bathroom presses (60s)
- [ ] Snooze 10m if reminder pending

---

## XYWAV Modernization (SSOT-Aligned)

### PR-1: XYWAV Hard-Lock + Endpoint Wiring

- [ ] Remove multi-med UI/strings/modules
- [ ] Rename tabs: Tonight / Timeline / Insights / Devices / Settings
- [x] Add APIClient endpoints: take, skip, snooze, events/log, analytics/export
- [x] Typed error decoding (422_WINDOW_EXCEEDED, 422_SNOOZE_LIMIT, 422_DOSE1_REQUIRED, 409_ALREADY_TAKEN, 429_RATE_LIMIT, 401_DEVICE_NOT_REGISTERED, OFFLINE)
- [x] Offline queue infra (enqueue, flush, cancel)  *(cancel pending via Undo still TODO)*
- [x] DoseWindowState model (pure) + unit tests skeleton

Progress (2025-09-04): Core networking + state machine + offline queue in place with 23 passing tests. Remaining PR-1 scope: legacy multi-med purge, tab renames, undo-cancel pathway.

### PR-2: Night-First UI + Accessibility

- [ ] Countdown ring hero component
- [ ] Button logic state machine integration
- [ ] Snooze disable <15m + CTA swap
- [ ] Undo snackbar (5s) w/ cancel token
- [ ] Timeline: stage bands + HR/RR overlay scaffolding
- [ ] Insights metrics calculations (on-time %, interval stats, natural wake %, WASO)
- [ ] CSV export hook integration
- [ ] Settings: clamp display, default interval (165m), Nudge step, High Contrast, Reduced Motion toggles
- [ ] VoiceOver timed announcements & large tap targets

### PR-3: watchOS + Flic

- [ ] Press-and-hold (1s) Take interaction
- [ ] Snooze 10m + Skip actions
- [ ] Dose1 guardrail (require Dose1 before Dose2)
- [ ] Flic single/long/double mapping implementation

### PR-4: Weekly Planner + Deep Links + Analytics

- [ ] Planner engine (discrete set {165,180,195,210,225})
- [ ] Generate 7-day plan + rationale storage
- [ ] Deep link router `dosetap://log?event=...`
- [ ] Analytics dispatcher + exact event names

### PR-5: Tests + CI

- [ ] Edge tests: 239–240m window boundary
- [ ] DST/timezone shift tests
- [ ] Offline queue flush + Undo cancellation tests
- [ ] Error handling tests (422/409/401/429)
- [ ] Deep link action tests
- [ ] UI tests: Tonight states, Insights export, Settings toggles, watchOS interactions
- [ ] GitHub Actions workflow (build + test, fail on warnings)

### Cross-Cutting

- [ ] Replace “Medication Event” user-facing copy where needed (retain metric id if backend requires)
- [ ] Documentation refresh (user-guide, implementation-roadmap, upgrades)
- [ ] High contrast color tokens + ≥7:1 validation
- [ ] Central analytics event enum
- [ ] Time source abstraction for tests
