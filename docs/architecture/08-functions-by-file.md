# 08 — Functions by File

Complete function inventory for review. Format: `function()` — purpose.

---

## DoseCore (ios/Core/) — 25 files

### DoseWindowState.swift (242 lines)

```text
DoseWindowConfig.init(...)              — Window timing configuration
DoseWindowCalculator.init(config:now:)  — Injectable calculator
DoseWindowCalculator.context(...)       — Compute phase + CTA + snooze/skip state
DoseWindowCalculator.shouldAutoExpireSession(...)  — Sleep-through detection (270m)
DoseWindowCalculator.lateDose1Info()    — Late-night session date assignment
DoseWindowCalculator.currentTimezoneOffsetMinutes()  — UTC offset
DoseWindowCalculator.timezoneChange(from:)  — Detect TZ shift
DoseWindowCalculator.timezoneChangeDescription(from:)  — Human-readable TZ delta
```

### DosingModels.swift (584 lines)

```text
AmountUnit (enum)               — mg/g/mL/mcg/tablet
AmountUnit.toMilligrams(_:)     — Normalize to mg
DoseAmount (struct)             — value + unit
Regimen (struct)                — Nightly plan (total, split config)
DoseEvent (struct)              — Single administration event
DoseBundle (struct)             — Group of events for one session
AdherenceCalculator             — Compute adherence metrics
```

### DoseTapCore.swift (ios/Core) (~300 lines)

```text
DoseTapCore.init()                     — Observable state holder
DoseTapCore.takeDose(earlyOverride:lateOverride:)  — Gate + record dose
DoseTapCore.setSessionRepository(_:)   — Wire to SessionRepository
DoseTapCore.dose1Time (published)      — Current Dose 1 time
DoseTapCore.dose2Time (published)      — Current Dose 2 time
DoseTapCore.windowPhase (computed)     — Current DoseWindowPhase
```

### APIClient.swift (179 lines)

```text
APIClient.init(baseURL:transport:)     — Create client
APIClient.takeDose(type:at:)           — POST /doses/take
APIClient.skipDose(sequence:reason:)   — POST /doses/skip
APIClient.snoozeDose(minutes:)         — POST /doses/snooze
APIClient.logEvent(name:at:)           — POST /events/log
APIClient.exportAnalytics()            — GET /analytics/export
```

### APIErrors.swift

```text
APIError (enum)               — Transport-level errors
DoseAPIError (enum)           — Domain-specific API errors
APIErrorMapper.map(data:status:)  — Decode error responses
APIErrorPayload (struct)      — Server error JSON { code, message }
```

### APIClientQueueIntegration.swift

```text
DosingService.perform(_:)     — Execute action (API → offline queue fallback)
DosingService.flushPending()  — Retry offline queue
DosingService.Action (enum)   — takeDose/skipDose/snooze/logEvent
```

### OfflineQueue.swift

```text
OfflineQueue.enqueue(_:)      — Queue failed action
OfflineQueue.flushPending()   — Retry all queued
OfflineQueue.pendingCount()   — Queue size
OfflineQueue.clear()          — Clear queue
```

### EventRateLimiter.swift

```text
EventRateLimiter.shouldAllow(_:)  — Check if event allowed
EventRateLimiter.recordEvent(_:)  — Record event timestamp
```

### CertificatePinning.swift (251 lines)

```text
CertificatePinning.init(pins:domains:allowFallback:)
CertificatePinning.forDoseTapAPI()   — Factory with configured pins
CertificatePinning.hasConfiguredPins — Bool
urlSession(_:didReceive:completionHandler:)  — TLS validation
```

### DataRedactor.swift (234 lines)

```text
DataRedactor.init(config:)     — Configure redaction rules
DataRedactor.redact(_:)        — Redact PII from text
DataRedactor.redactEmails(_:)  — Email pattern removal
DataRedactor.redactUUIDs(_:)   — UUID hashing
DataRedactor.redactIPAddresses(_:)  — IP removal
```

### NightScoreCalculator.swift (204 lines)

```text
NightScoreCalculator.calculate(_:)  — Compute night score 0-100
NightScoreInput (struct)            — 4 component inputs
NightScoreResult (struct)           — Score + component breakdown
Components: interval(0.40), dose(0.25), session(0.20), sleep(0.15)
```

### DiagnosticLogger.swift / DiagnosticEvent.swift

```text
DiagnosticLogger.shared                — Singleton actor
DiagnosticLogger.logAppLaunched(...)   — Tier 1 event
DiagnosticLogger.logDoseAction(...)    — Tier 2 event
DiagnosticLogger.logError(...)         — Tier 3 event
DiagnosticLogger.updateSettings(...)   — Toggle tiers
DiagnosticEvent (struct)               — id, type, timestamp, payload
```

### Other Core Files

```text
TimeEngine.swift           — Time computation helpers
TimeIntervalMath.swift     — minutesBetween(start:end:), formatted intervals
SleepEvent.swift           — Sleep event type definitions
SleepPlan.swift            — Sleep plan calculation
SessionKey.swift           — Session key computation
MorningCheckIn.swift       — Check-in model/validation
MedicationConfig.swift     — Medication configuration
RecommendationEngine.swift — Sleep recommendations
UnifiedSleepSession.swift  — Cross-source sleep model
EventStore.swift           — (Core) Event definitions
CSVExporter.swift          — CSV export
DoseUndoManager.swift      — Undo action types
```

---

## App Layer (ios/DoseTap/) — ~130 files

### DoseTapApp.swift (252 lines)

```text
DoseTapApp.init()              — App startup, migration, diagnostics
DoseTapApp.body                — Scene with setup guard
handleScenePhaseChange(_:)     — Background/foreground lifecycle
logTimezoneChange(from:to:)    — TZ shift logging
runPostSetupBootstrapTasksIfNeeded()  — Post-setup initialization
migrateSetupStateIfNeeded()    — Legacy migration
handleSignificantTimeChangeStatic()   — Day boundary handling
```

### ContentView.swift (229 lines)

```text
ContentView.body               — 5-tab TabView with custom tab bar
shareVisiblePage()             — Screenshot sharing
captureCurrentWindowScreenshot()  — UIGraphicsImageRenderer
setupUndoCallbacks()           — Wire undo onCommit/onUndo
CustomTabBar (struct)          — Bottom navigation bar
```

### DoseActionCoordinator.swift (241 lines)

```text
DoseActionCoordinator.init(core:alarmService:...)
takeDose1() async → ActionResult
takeDose2(override:) async → ActionResult
snooze() async → ActionResult
skip() async → ActionResult
ActionResult (enum)            — success/needsConfirm/blocked
ConfirmationType (enum)        — earlyDose/lateDose/afterSkip/extraDose
DoseOverride (enum)            — none/earlyConfirmed/lateConfirmed/afterSkipConfirmed
```

### SessionRepository.swift (1713 lines)

```text
SessionRepository.shared           — Singleton
reload()                           — Load from SQLite
setDose1Time(_:)                   — Record D1
setDose2Time(_:isEarly:isExtraDose:)  — Record D2
skipDose2(reason:)                 — Mark skipped
incrementSnoozeCount()             — +1 snooze
decrementSnoozeCount()             — Undo snooze
clearDose1() / clearDose2() / clearSkip()  — Undo operations
deleteSession(sessionDate:)        — Wipe session
fetchRecentSessions(days:)         — History data
fetchTonightSleepEvents()          — Tonight's events
insertSleepEvent(...)              — Persist event
savePreSleepLog(answers:...)       — Pre-sleep survey
saveMorningCheckIn(answers:...)    — Morning survey
currentSessionIdString()           — Session UUID
currentSessionDateString()         — "YYYY-MM-DD"
checkRollover()                    — Session boundary check
scheduleRolloverTimer()            — Background timer
```

### AlarmService.swift (607 lines)

```text
scheduleDose2Alarm(at:dose1Time:)  — Main alarm
scheduleDose2Reminders(dose1Time:) — Window reminders
rescheduleAlarm(addingMinutes:)    — Snooze
cancelDose2Alarm()                 — Cancel on D2 taken
cancelAllSessionNotifications()    — Rollover cleanup
triggerAlarmUI()                   — Fullscreen ringing
stopAlarm()                        — User acknowledged
configureAudioSession()            — AVAudioSession setup
registerNotificationCategories()   — Snooze/Stop actions
```

### FlicButtonService.swift (724 lines)

```text
handleGesture(_:)              — Route gesture to action
executeTakeDose()              — D1 or D2 based on phase
executeSnooze()                — +10m
executeUndo()                  — Undo last
executeLogEvent(_:)            — Quick event
executeSkip()                  — Skip D2
```

### URLRouter.swift (395 lines)

```text
handle(_: URL) → Bool          — Parse and execute deep link
processAction(_:)              — Execute URL action
showFeedback(message:)         — Transient banner
URLAction (enum)               — takeDose1/2, snooze, skip, logEvent, navigate
```

### EventLogger.swift (196 lines)

```text
logEvent(name:color:cooldownSeconds:persist:notes:)
isOnCooldown(_:) → Bool
clearCooldown(for:)
loadEventsFromStorage()
canonicalEventType(_:) → String
```

### Views (key files)

```text
TonightView.swift (478 lines)
  LegacyTonightView.body        — Main tonight layout
  IncompleteSessionBanner        — Previous night incomplete

HistoryViews.swift (1214 lines)
  HistoryView.body               — Calendar + day view
  SelectedDayView                — Single day detail
  DoseButtonsSection             — Dose action buttons in history
  RecentSessionsList             — Last 7 sessions

DashboardModels.swift (1429 lines)
  DashboardDateRange (enum)      — 7D/14D/30D/90D/1Y/All
  DashboardNightAggregate        — Per-night summary model
  DashboardViewModel             — Aggregation engine

NightReviewView.swift (~880 lines)
  NightReviewView.body           — Score + health summary
  NightScoreCard                 — Circular score ring 0-100

PreSleepLogView.swift (~1443 lines)
  PreSleepLogView.body           — Multi-step sleep survey
  Caffeine: oz units (2-48/2-96)

MorningCheckInView.swift
  MorningCheckInView.body        — Morning survey

SettingsView.swift (696 lines)
  SettingsView.body              — All settings sections
```

### Security

```text
InputValidator.swift (337 lines)
  validateEventName(_:) → String?
  sanitizeText(_:maxLength:) → String?
  validateDeepLinkURL(_:) → Bool
  validEventTypes: Set<String>

DatabaseSecurity.swift
  setFileProtection(_:)
  validateDatabaseIntegrity()

SecureLogger.swift
  Logging with PII redaction
```

### Storage

```text
EventStorage.swift (277 lines)           — Core SQLite operations
EventStorage+Schema.swift (681 lines)    — DDL and migrations
EventStorage+Dose.swift                  — Dose CRUD
EventStorage+Session.swift               — Session CRUD
EventStorage+CheckIn.swift               — Survey persistence
EventStorage+EventStore.swift            — Sleep event CRUD
EventStorage+Exports.swift               — Data export
EventStorage+Maintenance.swift           — Cleanup and vacuum
StorageModels.swift (867 lines)          — All stored model types
DosingAmountSchema.swift                 — Dosing amount table
EncryptedEventStorage.swift              — Encryption wrapper
JSONMigrator.swift                       — Legacy JSON → SQLite
```
