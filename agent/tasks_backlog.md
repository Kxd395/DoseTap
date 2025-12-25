# Tasks Backlog

## Completed (v2.4.4)
- [x] CSV exporter - Real implementation with share sheet
- [x] Debounce bathroom presses (60s) - EventRateLimiter implemented
- [x] Undo snackbar (5s) w/ cancel token - DoseUndoManager + UndoSnackbarView with configurable speed
- [x] Add APIClient endpoints: take, skip, snooze, events/log, analytics/export
- [x] Typed error decoding (422_WINDOW_EXCEEDED, 422_SNOOZE_LIMIT, 422_DOSE1_REQUIRED, 409_ALREADY_TAKEN, 429_RATE_LIMIT, 401_DEVICE_NOT_REGISTERED, OFFLINE)
- [x] Offline queue infra (enqueue, flush, cancel)
- [x] DoseWindowState model (pure) + unit tests skeleton
- [x] Alarm UI Indicator - AlarmIndicatorView shows scheduled wake time
- [x] Hard Stop Countdown - HardStopCountdownView + CompactStatusCard countdown

## High Priority (Next Up)
- [ ] URL scheme and event router
- [ ] Reminder scheduling (identifier: secondDose)
- [ ] HealthKit permission + Sleep read (14–30 nights)
- [ ] TTFW baseline computation
- [ ] Same-night nudge (±10–15 min)
- [ ] Snooze 10m if reminder pending

## Medium Priority
- [ ] WHOOP OAuth screen + token storage
- [ ] WHOOP sleep/cycle fetch (history import)
- [ ] Insights: Avg interval, natural vs alarm %, bathroom clustering

## watchOS
- [ ] Watch app: Dose1/Dose2/Bathroom buttons
- [ ] Press-and-hold (1s) Take interaction
- [ ] Snooze 10m + Skip actions
- [ ] Dose1 guardrail (require Dose1 before Dose2)
- [ ] Flic single/long/double mapping implementation

---

## XYWAV Modernization (SSOT-Aligned)

### PR-1: XYWAV Hard-Lock + Endpoint Wiring

- [ ] Remove multi-med UI/strings/modules
- [ ] Rename tabs: Tonight / Timeline / Insights / Devices / Settings
- [x] Add APIClient endpoints: take, skip, snooze, events/log, analytics/export
- [x] Typed error decoding (422_WINDOW_EXCEEDED, 422_SNOOZE_LIMIT, 422_DOSE1_REQUIRED, 409_ALREADY_TAKEN, 429_RATE_LIMIT, 401_DEVICE_NOT_REGISTERED, OFFLINE)
- [x] Offline queue infra (enqueue, flush, cancel)  *(cancel pending via Undo still TODO)*
- [x] DoseWindowState model (pure) + unit tests skeleton

Progress (2025-12-25): Core networking + state machine + offline queue in place with 223 passing tests. Undo snackbar implemented with configurable speed. Remaining PR-1 scope: legacy multi-med purge, tab renames.

### PR-2: Night-First UI + Accessibility

- [x] Countdown ring hero component (CompactStatusCard)
- [ ] Button logic state machine integration
- [x] Snooze disable <15m + CTA swap
- [x] Undo snackbar (5s) w/ cancel token
- [ ] Timeline: stage bands + HR/RR overlay scaffolding
- [ ] Insights metrics calculations (on-time %, interval stats, natural wake %, WASO)
- [x] CSV export hook integration
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
