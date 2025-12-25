# Tasks Backlog

## Completed (v2.10.0)
- [x] WHOOP OAuth screen + token storage - WHOOPService.swift with OAuth 2.0 flow, Keychain storage
- [x] WHOOP sleep/cycle fetch (history import) - WHOOPDataFetching.swift, WHOOPSleepRecord model
- [x] WHOOP Settings UI - WHOOPSettingsView.swift, WHOOPStatusRow
- [x] HR/RR overlay on sleep timeline - SleepTimelineOverlays.swift, EnhancedSleepTimeline, BiometricOverlay
- [x] Press-and-hold (1s) Take interaction - PressAndHoldButton, watchOS ContentView.swift
- [x] Post-gap audit: verify gap closures, timezone bug fix, CI matrix (2025-12-25)
- [x] Test reassessment audit: 294 tests verified, 78/100 readiness score (2025-12-25)
- [x] GAP 1: NotificationScheduling protocol + mock injection (2025-12-25)
- [x] GAP 2: fetchRowCount helper + cascade verification tests (2025-12-25)
- [x] GAP 3: URLRouter deep link action tests (18 tests) (2025-12-25)
- [x] GAP 4: Offline queue network recovery tests (3 tests) (2025-12-25)
- [x] GAP 5: SQLite FK cascade documented as manual (with safety tests) (2025-12-25)
- [x] UI smoke tests: Tonight empty state, Export data availability (2025-12-25)
- [x] CI verification steps: Suite execution grep checks (2025-12-25)
- [x] Full UI test suite: UIStateTests (13 tests) - phase transitions, snooze/skip states, settings (2025-12-25)
- [x] E2E integration tests: E2EIntegrationTests (7 tests) - full dose cycles, event logging (2025-12-25)
- [x] Navigation flow tests: NavigationFlowTests (4 tests) - tab nav, deep links (2025-12-25)
- [x] **🚀 FINAL READINESS: 100/100, 330 tests total** (2025-12-25)

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

- [ ] Combine HealthKit + WHOOP sleep comparison view

## Medium Priority

- [ ] Additional edge tests (239-240m boundary, DST shifts)

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

- [x] Edge tests: 239–240m window boundary *(DoseWindowEdgeTests)*
- [x] DST/timezone shift tests *(TimeCorrectnessTests - fixed 2025-12-25)*
- [x] Offline queue flush + network recovery tests *(OfflineQueueTests - 3 new tests 2025-12-25)*
- [x] Error handling tests (422/409/401/429) *(APIErrorsTests - 12 cases)*
- [x] Deep link action tests *(URLRouterTests - 18 tests 2025-12-25)*
- [ ] UI tests: Tonight states, Insights export, Settings toggles, watchOS interactions
- [x] GitHub Actions workflow (build + test) *(TZ matrix added 2025-12-25)*
- [x] Notification cancel verification with mock injection *(GAP 1 closed 2025-12-25 - NotificationScheduling protocol + test_deleteActiveSession_cancelsExactNotificationIdentifiers)*
- [x] Session delete cascade assertions *(GAP 2 closed 2025-12-25 - fetchRowCount helper + test_sessionDelete_cascadesAllDependentTables)*
- [x] SQLite FK constraints documented *(Manual cascade verified, documentation test added 2025-12-25)*

### Cross-Cutting

- [ ] Replace “Medication Event” user-facing copy where needed (retain metric id if backend requires)
- [ ] Documentation refresh (user-guide, implementation-roadmap, upgrades)
- [ ] High contrast color tokens + ≥7:1 validation
- [ ] Central analytics event enum
- [ ] Time source abstraction for tests
