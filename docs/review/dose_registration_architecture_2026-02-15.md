# Dose Registration Architecture (ASCII + Flow)

Last updated: 2026-02-15
Scope: iOS DoseTap dose registration paths (Dose 1, Dose 2, late override, extra/third dose)

## 1) User-Facing ASCII Design (Current)

### 1.1 Tonight Tab (primary registration UX)

```
+--------------------------------------------------------------------------------+
| LegacyTonightView                                                              |
|                                                                                |
|  [DoseTap Header] [Theme Toggle]                                               |
|  [Alarm Indicator]                                                             |
|                                                                                |
|  +---------------------------- CompactStatusCard ----------------------------+  |
|  | Icon + Title (Ready / Waiting / Open / Closing / Closed / Complete)      |  |
|  | - beforeWindow: live countdown + "Window opens at HH:MM"                 |  |
|  | - nearClose: hard-stop countdown visualization                            |  |
|  | - otherwise: status description text                                      |  |
|  +--------------------------------------------------------------------------+  |
|                                                                                |
|  +---------------------------- CompactDoseButton ----------------------------+  |
|  | [Primary CTA]                                                             |  |
|  |  - noDose1      -> "Take Dose 1"                                         |  |
|  |  - beforeWindow -> "Waiting..."                                           |  |
|  |  - active       -> "Take Dose 2"                                          |  |
|  |  - nearClose    -> "Take Dose 2"                                          |  |
|  |  - closed       -> "Take Dose 2 (Late)"                                   |  |
|  |  - completed    -> "Complete ✓"                                            |  |
|  |  - finalizing   -> "Check-In"                                             |  |
|  |                                                                          |  |
|  | [Secondary CTAs, hidden for noDose1/completed]                           |  |
|  |  [Snooze +10m] [Skip]                                                     |  |
|  +--------------------------------------------------------------------------+  |
|                                                                                |
|  [Quick Event Panel] [Wake Up Button] [Session Summary] [Live Dose Intervals] |
+--------------------------------------------------------------------------------+
```

### 1.2 Alerts / Confirmation Surfaces

```
A) Early Dose Warning (beforeWindow)
   "The dose window hasn't opened yet... Taking Dose 2 too early may reduce effectiveness."
   [Cancel] [I Understand the Risk]
      -> opens hold-to-confirm EarlyDoseOverrideSheet
      -> confirm path calls core.takeDose(earlyOverride: true)

B) Late Dose Override (closed)
   "The 240-minute window has passed... Are you sure?"
   [Cancel] [Take Dose 2 Anyway]
      -> calls core.takeDose(lateOverride: true)

C) Extra Dose Warning (Dose 2 already taken)
   "STOP - Dose 2 Already Taken..."
   [Cancel] [I Accept Full Responsibility]
      -> calls sessionRepo.saveDose2(isExtraDose: true)
      -> logs event type extra_dose
```

## 2) Architecture Map (Dose Registration)

```
User Gesture / Deep Link / Flic
          |
          v
+-------------------------------+
| Entry Surfaces                |
| - CompactDoseButton           |
| - URLRouter (dosetap://dose2) |
| - FlicButtonService           |
| - History DoseButtonsSection  |
+-------------------------------+
          |
          v
+-------------------------------+
| DoseTapCore.takeDose(...)     |
| gating by DoseStatus          |
+-------------------------------+
          |
          v
+-------------------------------+
| SessionRepository             |
| - setDose1Time               |
| - setDose2Time               |
| - skipDose2 / incrementSnooze|
| - computes extra-dose index  |
+-------------------------------+
          |
          v
+-------------------------------+
| EventStorage +Dose            |
| - saveDose1 / saveDose2       |
| - saveDoseSkipped / saveSnooze|
| - current_session updates     |
+-------------------------------+
          |
          v
        SQLite
```

## 3) Full Function Inventory (Dose Registration Related)

### 3.1 Core window/gating functions

- `DoseTapCore.takeDose(earlyOverride:lateOverride:)`
  - File: `/Volumes/Developer/projects/DoseTap/ios/Core/DoseTapCore.swift:201`
  - Behavior: blocks Dose 2 unless window open OR override flag set.
- `DoseWindowCalculator.context(...)`
  - File: `/Volumes/Developer/projects/DoseTap/ios/Core/DoseWindowState.swift:74`
  - Behavior: emits `.noDose1/.beforeWindow/.active/.nearClose/.closed/.completed/.finalizing`.

### 3.2 Session repository (canonical domain operations)

- `SessionRepository.setDose1Time(_:)`
  - File: `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Storage/SessionRepository.swift:495`
- `SessionRepository.setDose2Time(_:isEarly:isExtraDose:)`
  - File: `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Storage/SessionRepository.swift:527`
  - Key behavior: derives `nextDoseIndex` from dose events; dose index >=3 becomes extra-dose path.
- `SessionRepository.skipDose2()`
  - File: `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Storage/SessionRepository.swift:605`
- `SessionRepository.saveDose1(timestamp:)` wrapper
  - File: `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Storage/SessionRepository.swift:1585`
- `SessionRepository.saveDose2(timestamp:isEarly:isExtraDose:)` wrapper
  - File: `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Storage/SessionRepository.swift:1591`
- `SessionRepository.fetchDoseEventsForActiveSession()`
  - File: `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Storage/SessionRepository.swift:1362`

### 3.3 Storage persistence functions

- `EventStorage.saveDose1(...)`
  - File: `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Storage/EventStorage+Dose.swift:13`
- `EventStorage.saveDose2(...isEarly:isExtraDose:isLate...)`
  - File: `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Storage/EventStorage+Dose.swift:25`
  - Key behavior: writes `event_type = "dose2"` or `"extra_dose"`; updates `current_session.dose2_time` only for non-extra doses.
- `EventStorage.saveDoseSkipped(...)`
  - File: `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Storage/EventStorage+Dose.swift:44`
- `EventStorage.saveSnooze(...)`
  - File: `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Storage/EventStorage+Dose.swift:59`
- `EventStorage.clearDose1(...)`
  - File: `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Storage/EventStorage+Dose.swift:70`
- `EventStorage.clearDose2(...)`
  - File: `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Storage/EventStorage+Dose.swift:94`
- `EventStorage.clearSkip(...)`
  - File: `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Storage/EventStorage+Dose.swift:118`
- `EventStorage.saveDoseEvent(type:timestamp:isHazard:)`
  - File: `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Storage/EventStorage+Dose.swift:249`
- `EventStorage.hasDose(type:sessionDate:)`
  - File: `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Storage/EventStorage+Dose.swift:296`

### 3.4 User entry-point handlers (display + action)

- Tonight primary button handler
  - `CompactDoseButton.handlePrimaryButtonTap()`
  - File: `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Views/CompactDoseButton.swift:82`
- Tonight late override action
  - `CompactDoseButton.takeDose2WithOverride()`
  - File: `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Views/CompactDoseButton.swift:148`
- Tonight CTA text mapping
  - `CompactDoseButton.primaryButtonText`
  - File: `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Views/CompactDoseButton.swift:159`
- Deep link path
  - `URLRouter.handleDose1()` and `URLRouter.handleDose2()`
  - File: `/Volumes/Developer/projects/DoseTap/ios/DoseTap/URLRouter.swift:153`
  - File: `/Volumes/Developer/projects/DoseTap/ios/DoseTap/URLRouter.swift:178`
- Hardware button path
  - `FlicButtonService.handleTakeDose(gesture:)`
  - File: `/Volumes/Developer/projects/DoseTap/ios/DoseTap/FlicButtonService.swift:181`
- Secondary/historical dose button path
  - `DoseButtonsSection.handlePrimaryButtonTap()`
  - File: `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Views/History/HistoryViews.swift:991`
- Explicit extra-dose confirmation action
  - `LegacyTonightView` alert action using `sessionRepo.saveDose2(isExtraDose: true)`
  - File: `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Views/TonightView.swift:261`

## 4) Current Display Matrix (What User Sees)

| Status | Primary Label | Primary Behavior | Override UX | File |
|---|---|---|---|---|
| `noDose1` | `Take Dose 1` | Registers Dose 1 | None | `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Views/CompactDoseButton.swift:161` |
| `beforeWindow` | `Waiting...` | Blocks direct take; opens early warning | Early override sheet | `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Views/CompactDoseButton.swift:162` |
| `active` | `Take Dose 2` | Registers Dose 2 | Not needed | `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Views/CompactDoseButton.swift:163` |
| `nearClose` | `Take Dose 2` | Registers Dose 2 | Not needed | `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Views/CompactDoseButton.swift:163` |
| `closed` | `Take Dose 2 (Late)` | Requires user confirm | Late override alert | `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Views/CompactDoseButton.swift:164` |
| `completed` | `Complete ✓` | Tap used as extra-dose trigger path only (Tonight) | Extra-dose warning alert | `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Views/CompactDoseButton.swift:165` |
| `finalizing` | `Check-In` | Dose action generally unavailable | None | `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Views/CompactDoseButton.swift:166` |

## 5) End-to-End Flow Diagrams (ASCII)

### 5.1 Dose 2 in-window (happy path)

```
User taps "Take Dose 2"
   -> CompactDoseButton.handlePrimaryButtonTap()
      -> core.takeDose()
         -> DoseTapCore.takeDose()
            -> sessionRepository.setDose2Time(...isExtraDose:false)
               -> SessionRepository computes nextDoseIndex=2
               -> EventStorage.saveDose2(eventType="dose2", isLate maybe false)
               -> update current_session.dose2_time
            -> async DosingService.perform(.takeDose)
```

### 5.2 Dose 2 late (past 240 min)

```
Status = .closed
User taps primary
   -> show "Window Expired" alert
User confirms "Take Dose 2 Anyway"
   -> core.takeDose(lateOverride: true)
      -> takeDose allows because lateOverride=true
      -> SessionRepository.setDose2Time(...)
      -> EventStorage.saveDose2(... isLate=true)
```

### 5.3 Extra/third dose (Tonight explicit hazardous path)

```
Precondition: doseCount >= 2 for active session
User taps primary
   -> CompactDoseButton detects doseCount>=2
   -> show "STOP - Dose 2 Already Taken" alert
User confirms responsibility
   -> sessionRepo.saveDose2(isExtraDose:true)
      -> SessionRepository.setDose2Time(...)
      -> nextDoseIndex >= 3 => isExtra path
      -> EventStorage.saveDose2(eventType="extra_dose")
      -> DOES NOT replace current_session.dose2_time
```

### 5.4 Deep link path (`dosetap://dose2`)

```
URLRouter.handleDose2()
  - blocks if no Dose 1
  - blocks if dose2Time already set
  - blocks beforeWindow
  - if closed -> auto applies late override
  - if completed/finalizing -> blocks ("Dose 2 unavailable right now")
```

### 5.5 Flic path

```
FlicButtonService.handleTakeDose()
  - noDose1      -> saveDose1
  - beforeWindow -> reject
  - active/near  -> saveDose2
  - closed       -> saveDose2 (late) WITHOUT explicit confirmation UI
  - completed/finalizing -> reject
```

## 6) Hypercritical Findings (Behavior Mismatches)

### P0. Inconsistent late/extra behavior across channels

- Tonight UI requires explicit user confirmation for late Dose 2; Flic path logs late dose directly without explicit confirmation.
- Deep link path supports late override in `.closed`, but rejects in `.completed/.finalizing` even when user intent may be to log a corrective dose.
- Evidence:
  - `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Views/CompactDoseButton.swift:35`
  - `/Volumes/Developer/projects/DoseTap/ios/DoseTap/FlicButtonService.swift:221`
  - `/Volumes/Developer/projects/DoseTap/ios/DoseTap/URLRouter.swift:197`

### P0. "Always allow second dose" is not true after skip/completed state

- `DoseWindowCalculator.context` marks session `.completed` if `dose2Skipped == true`.
- `DoseTapCore.takeDose` only checks `dose2Time == nil` then requires open/override; with status `.completed`, non-override paths fail and many surfaces do not offer override.
- Result: second-dose registration can be blocked after skip even though dose2 timestamp is empty.
- Evidence:
  - `/Volumes/Developer/projects/DoseTap/ios/Core/DoseWindowState.swift:85`
  - `/Volumes/Developer/projects/DoseTap/ios/Core/DoseTapCore.swift:208`

### P1. Third-dose path is UI-special-cased, not a first-class API capability

- No direct `DoseTapCore.takeExtraDose(...)` API.
- Extra dose requires one specific alert action in `TonightView`; other channels (URL/Flic/History) cannot invoke equivalent intent safely.
- Evidence:
  - `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Views/TonightView.swift:261`
  - `/Volumes/Developer/projects/DoseTap/ios/Core/DoseTapCore.swift:237`

### P1. History action surface diverges from Tonight behavior

- History `DoseButtonsSection` disables button when `.completed`, preventing extra-dose/override recovery behavior available in Tonight screen.
- Evidence:
  - `/Volumes/Developer/projects/DoseTap/ios/DoseTap/Views/History/HistoryViews.swift:950`

## 7) Recommended Target Contract (for implementation review)

```
Rule A: If Dose 1 exists, user can always register another dose event.
Rule B: First post-dose1 event should remain canonical Dose 2 timestamp.
Rule C: Any subsequent dose should be explicitly classified as extra_dose.
Rule D: Late or post-skip dose actions require explicit user confirmation across ALL channels.
Rule E: Channel parity (Tonight / URL / Flic / History) must share a single policy function.
```

## 8) Candidate Unification Design (ASCII)

```
+-----------------------------+
| DoseRegistrationPolicy      |
| evaluateIntent(context,     |
|                intent)      |
+--------------+--------------+
               |
               +--> .allowDose1
               +--> .allowDose2(early|onTime|late, requiresConfirm)
               +--> .allowExtraDose(requiresConfirm)
               +--> .deny(reason)

All entry surfaces call this first:
- CompactDoseButton
- URLRouter
- FlicButtonService
- History DoseButtonsSection
```

This removes fragmented rules and makes override behavior deterministic.
