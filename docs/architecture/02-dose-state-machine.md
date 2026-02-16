# 02 — Dose Window State Machine

File: `ios/Core/DoseWindowState.swift` (242 lines)

## Configuration

```swift
DoseWindowConfig(
    minIntervalMin:         150,   // Window opens
    maxIntervalMin:         240,   // Window closes (hard limit)
    nearWindowThresholdMin:  15,   // Snooze cutoff
    defaultTargetMin:       165,   // Default alarm target
    snoozeStepMin:           10,   // Each snooze adds
    maxSnoozes:               3,   // Per session
    sleepThroughGraceMin:    30    // Auto-expire after 240+30=270m
)
```

## 7 Phases

```text
 ┌──────────┐
 │ noDose1  │  No dose 1 logged yet
 └────┬─────┘
      │ takeDose1()
      ▼
 ┌──────────────┐
 │ beforeWindow │  0–150 min after D1
 │ (waiting)    │  CTA: countdown to window open
 └────┬─────────┘
      │ elapsed >= 150m
      ▼
 ┌──────────┐
 │  active  │  150–225 min after D1
 │          │  CTA: "Take Dose 2"
 └────┬─────┘
      │ remaining <= 15m
      ▼
 ┌───────────┐
 │ nearClose │  225–240 min after D1
 │           │  CTA: "Take before window ends"
 │           │  Snooze: DISABLED
 └────┬──────┘
      │ elapsed >= 240m
      ▼
 ┌──────────┐
 │  closed  │  >240 min after D1
 │          │  CTA: "Take Dose 2 (Late)" with override
 └────┬─────┘
      │ takeDose2() or skipDose2()
      ▼
 ┌───────────┐
 │ completed │  Dose 2 taken, skipped, or session ended
 └────┬──────┘
      │ Wake Up pressed (wakeFinalAt != nil)
      ▼
 ┌────────────┐
 │ finalizing │  Awaiting morning check-in
 └────────────┘
```

## Phase Transition Matrix

| From | Trigger | To |
| ---- | ------- | -- |
| `noDose1` | `takeDose1()` | `beforeWindow` |
| `beforeWindow` | elapsed ≥ 150m | `active` |
| `active` | remaining ≤ 15m | `nearClose` |
| `nearClose` | elapsed ≥ 240m | `closed` |
| `closed` | takeDose2(late) | `completed` |
| any (d2 taken/skipped) | — | `completed` |
| `completed` | Wake Up pressed | `finalizing` |
| `finalizing` | check-in done | `completed` (terminal) |

## Display Matrix (All 7 Phases)

| Phase | Primary CTA | Snooze | Skip | Countdown | Errors |
| ----- | ----------- | ------ | ---- | --------- | ------ |
| `noDose1` | disabled("Log Dose 1 first") | disabled | disabled | — | `dose1Required` |
| `beforeWindow` | waitingUntilEarliest(remaining) | disabled("Too early") | enabled | ✅ to window open | — |
| `active` | takeNow | enabled(remaining) | enabled | ✅ to window close | — |
| `nearClose` | takeBeforeWindowEnds(remaining) | disabled("<15m left") | enabled | ✅ urgent | — |
| `closed` | takeWithOverride("Window expired") | disabled | enabled | — | `windowExceeded` |
| `completed` | disabled("Completed") | disabled | disabled | — | — |
| `finalizing` | disabled("Complete Check-In") | disabled | disabled | — | — |

## Snooze Logic

```text
Snooze ENABLED when:
  ├── phase == .active
  ├── remaining > nearWindowThreshold (15m)
  └── snoozeCount < maxSnoozes (3)

Snooze DISABLED when:
  ├── phase != .active
  ├── remaining <= 15m
  ├── snoozeCount >= maxSnoozes
  └── reason displayed to user
```

## Sleep-Through Detection

```swift
shouldAutoExpireSession(dose1At:dose2TakenAt:dose2Skipped:) -> Bool
// True when: D1 exists, D2 not taken/skipped, elapsed > 270m (240+30 grace)
```

## Late Dose 1 Detection

```swift
lateDose1Info() -> (isLateNight: Bool, sessionDateLabel: String)
// Midnight–5:59 AM = previous day's session
```

## Timezone Change Detection

```swift
timezoneChange(from referenceOffsetMinutes: Int) -> Int?
// Returns delta in minutes (positive=east, negative=west)
// nil if no change
```

## Key Types

```swift
public enum DoseActionPrimaryCTA: Equatable {
    case takeNow
    case takeBeforeWindowEnds(remaining: TimeInterval)
    case waitingUntilEarliest(remaining: TimeInterval)
    case takeWithOverride(reason: String)
    case disabled(String)
}

public enum DoseSecondaryActionState: Equatable {
    case snoozeEnabled(remaining: TimeInterval)
    case snoozeDisabled(reason: String)
    case skipEnabled
    case skipDisabled(reason: String)
}

public struct DoseWindowContext: Equatable {
    let phase: DoseWindowPhase
    let primary: DoseActionPrimaryCTA
    let snooze: DoseSecondaryActionState
    let skip: DoseSecondaryActionState
    let elapsedSinceDose1: TimeInterval?
    let remainingToMax: TimeInterval?
    let errors: [DoseWindowError]
    let snoozeCount: Int
}
```
