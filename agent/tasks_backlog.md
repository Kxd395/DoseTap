# Tasks Backlog

## Completed (v2.10.0)
- [x] WHOOP OAuth screen + token storage - WHOOPService.swift with OAuth 2.0 flow, Keychain storage
- [x] WHOOP sleep/cycle fetch (history import) - WHOOPDataFetching.swift, WHOOPSleepRecord model
- [x] WHOOP Settings UI - WHOOPSettingsView.swift, WHOOPStatusRow
- [x] HR/RR overlay on sleep timeline - SleepTimelineOverlays.swift, EnhancedSleepTimeline, BiometricOverlay

## Completed (v2.9.0)
- [x] Settings: Reduced Motion toggle - shouldReduceMotion, ReducedMotionSupport.swift, accessibleAnimation modifier
- [x] Flic single/long/double mapping implementation - FlicButtonService.swift, FlicButtonSettingsView
- [x] Analytics dispatcher + exact event names - AnalyticsService.swift with 50+ event types

## Completed (v2.8.0)
- [x] Integration: Wire SleepStageTimeline to HealthKitService data - LiveSleepTimelineView, SleepTimelineContainer
- [x] Settings: High Contrast color tokens with ≥7:1 validation - HighContrastColors.swift, DoseColors enum
- [x] watchOS: Enhanced Watch app with Dose1/Dose2/Bathroom/Events buttons

## Completed (v2.7.0)
- [x] CSV exporter - Real implementation with share sheet
- [x] Debounce bathroom presses (60s) - EventRateLimiter implemented
- [x] Undo snackbar (5s) w/ cancel token - DoseUndoManager + UndoSnackbarView with configurable speed
- [x] Add APIClient endpoints: take, skip, snooze, events/log, analytics/export
- [x] Typed error decoding (422_WINDOW_EXCEEDED, 422_SNOOZE_LIMIT, 422_DOSE1_REQUIRED, 409_ALREADY_TAKEN, 429_RATE_LIMIT, 401_DEVICE_NOT_REGISTERED, OFFLINE)
- [x] Offline queue infra (enqueue, flush, cancel)
- [x] DoseWindowState model (pure) + unit tests skeleton
- [x] Alarm UI Indicator - AlarmIndicatorView shows scheduled wake time
- [x] Hard Stop Countdown - HardStopCountdownView + CompactStatusCard countdown
- [x] URL scheme and event router - URLRouter.swift handles dosetap:// deep links
- [x] Insights: Avg interval, natural vs alarm %, bathroom clustering - InsightsCalculator.swift
- [x] Tab rename: Details → Timeline
- [x] Reminder scheduling (identifier: secondDose) - AlarmService.scheduleDose2Reminders()
- [x] HealthKit permission + Sleep read (14–30 nights) - HealthKitService.swift
- [x] TTFW baseline computation - computeTTFWBaseline(days:)
- [x] Same-night nudge (±10–15 min) - calculateNudgeSuggestion(), sameNightNudge()
- [x] Weekly Planner engine - WeeklyPlanner.swift with 4 strategies
- [x] VoiceOver timed announcements & accessibility labels - CompactStatusCard, buttons
- [x] Timeline stage bands visualization - SleepStageTimeline.swift

## High Priority (Next Up)

- [ ] Press-and-hold (1s) Take interaction (watchOS UX polish)

## Medium Priority

- [ ] Combine HealthKit + WHOOP sleep comparison view

## watchOS (Completed in v2.8.0)
- [x] Watch app: Dose1/Dose2/Bathroom buttons
- [x] Snooze 10m + Skip actions
- [x] Dose1 guardrail (require Dose1 before Dose2)
- [x] QuickEventGrid: bathroom, lights_out, wake_final
- [x] Local state persistence (session-based)
- [x] WatchConnectivity with queued message delivery
- [ ] Press-and-hold (1s) Take interaction (optional UX polish)

---

## XYWAV Modernization (SSOT-Aligned)

### PR-1: XYWAV Hard-Lock + Endpoint Wiring

- [ ] Remove multi-med UI/strings/modules
- [x] Rename tabs: Tonight / Timeline / Insights / Devices / Settings
- [x] Add APIClient endpoints: take, skip, snooze, events/log, analytics/export
- [x] Typed error decoding (422_WINDOW_EXCEEDED, 422_SNOOZE_LIMIT, 422_DOSE1_REQUIRED, 409_ALREADY_TAKEN, 429_RATE_LIMIT, 401_DEVICE_NOT_REGISTERED, OFFLINE)
- [x] Offline queue infra (enqueue, flush, cancel)  *(cancel pending via Undo still TODO)*
- [x] DoseWindowState model (pure) + unit tests skeleton

Progress (2025-12-25): Core networking + state machine + offline queue in place with 246 passing tests. URL scheme, insights metrics, tab rename, Dose 2 reminders, HealthKit integration, Weekly Planner, VoiceOver accessibility, live timeline, high contrast colors, and watchOS app complete. Remaining PR-1 scope: legacy multi-med purge.

### PR-2: Night-First UI + Accessibility (MOSTLY COMPLETE)

- [x] Countdown ring hero component (CompactStatusCard)
- [ ] Button logic state machine integration
- [x] Snooze disable <15m + CTA swap
- [x] Undo snackbar (5s) w/ cancel token
- [x] Timeline: stage bands + live HealthKit data
- [x] Insights metrics calculations (on-time %, interval stats, natural wake %, WASO)
- [x] CSV export hook integration
- [x] Settings: High Contrast color tokens
- [ ] Settings: Reduced Motion toggle
- [x] VoiceOver timed announcements & large tap targets

### PR-3: watchOS + Flic (PARTIALLY COMPLETE)

- [ ] Press-and-hold (1s) Take interaction
- [x] Snooze 10m + Skip actions
- [x] Dose1 guardrail (require Dose1 before Dose2)
- [ ] Flic single/long/double mapping implementation

### PR-4: Weekly Planner + Deep Links + Analytics

- [x] Planner engine (discrete set {165,180,195,210,225})
- [x] Generate 7-day plan + rationale storage
- [x] Deep link router `dosetap://log?event=...`
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
