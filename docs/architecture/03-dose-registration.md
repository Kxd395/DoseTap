# 03 — Dose Registration

All paths that record a dose event, their validation, and confirmation flows.

## Entry Surfaces

```text
┌─────────────────────────────────────────────┐
│ 4 surfaces can register doses:              │
│                                             │
│  1. CompactDoseButton (Tonight tab)         │
│  2. URLRouter (dosetap://dose1, dose2)      │
│  3. FlicButtonService (hardware button)     │
│  4. HistoryViews DoseButtonsSection         │
│                                             │
│         ALL route through:                  │
│                                             │
│      DoseActionCoordinator                  │
│           │                                 │
│           ▼                                 │
│      SessionRepository                      │
│           │                                 │
│           ▼                                 │
│      EventStorage+Dose (SQLite)             │
└─────────────────────────────────────────────┘
```

## Architecture Map

```text
User Gesture / Deep Link / Flic
          │
          ▼
┌───────────────────────────────┐
│ Entry Surfaces                │
│ CompactDoseButton             │
│ URLRouter (dosetap://dose2)   │
│ FlicButtonService             │
│ History DoseButtonsSection    │
└──────────┬────────────────────┘
           │
           ▼
┌───────────────────────────────┐
│ DoseActionCoordinator         │
│ .takeDose1() → ActionResult   │
│ .takeDose2() → ActionResult   │
│ .snooze()    → ActionResult   │
│ .skip()      → ActionResult   │
│                               │
│ Returns:                      │
│  .success(message)            │
│  .needsConfirm(type)         │
│  .blocked(reason)             │
└──────────┬────────────────────┘
           │
           ▼
┌───────────────────────────────┐
│ DoseTapCore.takeDose(...)     │
│ Gating by DoseWindowPhase     │
└──────────┬────────────────────┘
           │
           ▼
┌───────────────────────────────┐
│ SessionRepository             │
│ setDose1Time(_:)              │
│ setDose2Time(_:isEarly:       │
│              isExtraDose:)    │
│ skipDose2(reason:)            │
│ incrementSnoozeCount()        │
└──────────┬────────────────────┘
           │
           ▼
┌───────────────────────────────┐
│ EventStorage+Dose             │
│ saveDose1/saveDose2           │
│ saveDoseSkipped/saveSnooze    │
│ current_session updates       │
└──────────┬────────────────────┘
           │
           ▼
        SQLite
```

## DoseActionCoordinator

File: `ios/DoseTap/DoseActionCoordinator.swift` (241 lines)

### Confirmation Types

| Type | Trigger | User Sees |
| ---- | ------- | --------- |
| `earlyDose` | phase == beforeWindow | "Window hasn't opened yet. Taking Dose 2 too early may reduce effectiveness." → hold-to-confirm |
| `lateDose` | phase == closed | "The 240-minute window has passed. Are you sure?" |
| `afterSkip` | dose2Skipped == true | "Dose 2 was skipped. Do you want to un-skip?" |
| `extraDose` | dose2Time != nil | "STOP — Dose 2 Already Taken. I Accept Full Responsibility" |

### Override Types

| Override | When Applied |
| -------- | ------------ |
| `.none` | Normal flow |
| `.earlyConfirmed` | User confirmed early dose |
| `.lateConfirmed` | User confirmed late dose |
| `.afterSkipConfirmed` | User un-skipped |

### Result Flow

```swift
enum ActionResult: Equatable {
    case success(message: String)       // → update UI, show feedback
    case needsConfirm(ConfirmationType) // → show dialog, call again with override
    case blocked(reason: String)        // → show reason to user
}
```

## Happy Path (Dose 1 → Dose 2)

```text
 User taps "Take Dose 1"
   │
   ▼
 DoseActionCoordinator.takeDose1()
   ├── core.dose1Time == nil ✓
   ├── core.takeDose()  → sets dose1Time
   ├── eventLogger.logEvent("Dose 1")
   ├── undoState.register(.takeDose1(at:))
   ├── alarmService.scheduleDose2Alarm(at: d1+165m)
   └── return .success("Dose 1 logged")

     ⋯ 150–240 minutes pass ⋯

 User taps "Take Dose 2"
   │
   ▼
 DoseActionCoordinator.takeDose2()
   ├── phase == .active ✓
   ├── core.takeDose()  → sets dose2Time
   ├── sessionRepo.setDose2Time(now)
   ├── alarmService.cancelDose2Alarm()
   ├── undoState.register(.takeDose2(at:))
   └── return .success("Dose 2 logged • 168m interval")
```

## Late Dose Flow (>240m)

```text
 User taps "Take Dose 2 (Late)"
   │
   ▼
 DoseActionCoordinator.takeDose2(override: .none)
   ├── phase == .closed
   └── return .needsConfirm(.lateDose)

 UI shows confirmation alert
   │
   ▼
 User confirms
   │
   ▼
 DoseActionCoordinator.takeDose2(override: .lateConfirmed)
   ├── core.takeDose(lateOverride: true)
   ├── sessionRepo.setDose2Time(now, isLate: true)
   └── return .success("Late dose logged")
```

## Early Dose Flow (<150m)

```text
 User taps "Take Dose 2" while beforeWindow
   │
   ▼
 DoseActionCoordinator.takeDose2(override: .none)
   ├── phase == .beforeWindow
   └── return .needsConfirm(.earlyDose(minutesRemaining: X))

 UI shows warning + hold-to-confirm (EarlyDoseOverrideSheet)
   │
   ▼
 User holds to confirm
   │
   ▼
 DoseActionCoordinator.takeDose2(override: .earlyConfirmed)
   ├── core.takeDose(earlyOverride: true)
   └── return .success("Early dose logged")
```

## Extra Dose Flow (Dose 2 already taken)

```text
 User taps button after dose 2 already recorded
   │
   ▼
 CompactDoseButton detects dose2Time != nil
   └── return .needsConfirm(.extraDose)

 UI shows "STOP — Dose 2 Already Taken"
   │
   ▼
 User confirms "I Accept Full Responsibility"
   │
   ▼
 sessionRepo.saveDose2(isExtraDose: true)
 eventLogger.logEvent("extra_dose")
```

## Skip Flow

```text
 User taps "Skip Dose 2"
   │
   ▼
 DoseActionCoordinator.skip()
   ├── sessionRepo.skipDose2(reason: userChoice)
   ├── undoState.register(.skipDose(seq: 2, reason:))
   └── return .success("Dose 2 skipped")
```

## Snooze Flow

```text
 User taps "Snooze +10m"
   │
   ▼
 DoseActionCoordinator.snooze()
   ├── Check: snoozeCount < maxSnoozes (3) ✓
   ├── Check: remaining > 15m ✓
   ├── sessionRepo.incrementSnoozeCount()
   ├── alarmService.rescheduleAlarm(+10m)
   ├── undoState.register(.snooze(minutes: 10))
   └── return .success("Snoozed +10m")
```

## Deep Link Flow

```text
 dosetap://dose1 or dosetap://dose2
   │
   ▼
 URLRouter.handle(_:)
   ├── validate URL scheme/host
   ├── InputValidator.validateDeepLink(url)
   ├── selectedTab = .tonight
   └── core.takeDose() via coordinator
```

## Flic Button Flow

```text
 Single press → FlicButtonService.handleGesture(.singlePress)
   │
   ▼
 FlicButtonService.executeTakeDose()
   ├── Reads SessionRepository state
   ├── DoseWindowCalculator.context()
   ├── Routes to dose1 or dose2 based on phase
   └── DoseActionCoordinator.takeDose1/2()
```

## Undo System

File: `ios/DoseTap/UndoStateManager.swift`

```text
 Action registered → 10s countdown starts
   │
   ├── Timer expires → onCommit() (action stays)
   │
   └── User taps Undo → onUndo() → revert:
        ├── .takeDose1 → sessionRepo.clearDose1()
        ├── .takeDose2 → sessionRepo.clearDose2()
        ├── .skipDose  → sessionRepo.clearSkip()
        └── .snooze    → sessionRepo.decrementSnoozeCount()
```

## Known Issues (from review)

1. **Flic late dose path** may skip confirmation UI for late doses
2. **History DoseButtonsSection** diverges from Tonight behavior
3. **Extra dose** is UI-special-cased, not a first-class coordinator action
4. **Recommended:** Create `DoseRegistrationPolicy` unifying all surfaces (see `11-known-issues.md`)
