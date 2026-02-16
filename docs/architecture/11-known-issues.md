# 11 — Known Issues & Technical Debt

## Open P1 Items (from IMPROVEMENT_ROADMAP.md)

### P1-2: Timeline Simulated Biometrics

- **File:** `ios/DoseTap/SleepTimelineOverlays.swift:354-394`
- **Issue:** Heart rate and HRV overlays use `sin()` and `Double.random()` to generate fake data
- **Impact:** Users see simulated biometrics that look real
- **Fix:** Guard behind WHOOP feature flag, show "Connect device" placeholder when off
- **Blocked by:** WHOOP `isEnabled = false`

### P1-3: Dashboard WHOOP Fields

- **File:** `ios/DoseTap/Views/Dashboard/DashboardModels.swift`
- **Issue:** `DashboardNightAggregate` has no WHOOP-specific fields
- **Impact:** Recovery score, HRV, strain not available in dashboard
- **Fix:** Add optional WHOOP fields to aggregate model
- **Blocked by:** WHOOP `isEnabled = false`

### P1-4: Dose-Sleep Correlation View

- **Issue:** No view correlating dose timing with sleep quality
- **Impact:** Users can't see if earlier/later D2 affects sleep
- **Fix:** New view using NightScoreCalculator + interval data
- **Effort:** Large (new view + data aggregation)

### P1-5: CloudKit Sync Decision

- **Issue:** CloudKit sync code exists but is not fully wired
- **Impact:** Data is local-only
- **Fix:** Either enable and test, or remove dead CloudKit code
- **Decision needed from user**

---

## Dose Registration Findings (from review 2026-02-15)

### P0: Flic Late Dose Without Confirmation

- **File:** `ios/DoseTap/FlicButtonService.swift:~221`
- **Issue:** When Flic single-press triggers `executeTakeDose()` during `.closed` phase, the late dose path may skip the confirmation UI that TonightView shows
- **Fix:** Route through `DoseActionCoordinator.takeDose2()` which returns `.needsConfirm(.lateDose)`, then surface confirmation via notification or post-action alert

### P0: Dose 2 Blocked After Skip

- **File:** `ios/Core/DoseWindowState.swift:85`
- **Issue:** When `dose2Skipped == true`, `DoseWindowCalculator.context()` returns `.completed` immediately, blocking dose 2 registration even if the user changes their mind
- **Current workaround:** `DoseActionCoordinator` has `.afterSkip` confirmation type
- **Fix:** Ensure all surfaces support the after-skip un-skip flow consistently

### P1: Extra Dose Not First-Class

- **Issue:** Extra dose (third+ dose) is special-cased in `CompactDoseButton` and `TonightView` but not in `DoseActionCoordinator`
- **Impact:** History tab, Flic, and deep links don't support extra dose consistently
- **Fix:** Add `.extraDose` case to `DoseActionCoordinator.takeDose2()` flow

### P1: History Diverges from Tonight

- **Issue:** `DoseButtonsSection` in `HistoryViews.swift` has its own dose registration logic separate from `DoseActionCoordinator`
- **Impact:** Inconsistent validation, missing confirmation dialogs
- **Fix:** Route History dose actions through the same coordinator

---

## Recommended: DoseRegistrationPolicy

From the dose registration architecture review:

```swift
// Proposed: ios/Core/DoseRegistrationPolicy.swift
public struct DoseRegistrationPolicy {
    /// Determine what action is allowed for the current state
    static func evaluate(
        dose1Time: Date?,
        dose2Time: Date?,
        dose2Skipped: Bool,
        snoozeCount: Int,
        windowPhase: DoseWindowPhase,
        surface: RegistrationSurface
    ) -> RegistrationDecision

    enum RegistrationSurface {
        case tonightButton, deepLink, flic, historyButton
    }

    enum RegistrationDecision {
        case allowed
        case requiresConfirmation(ConfirmationType)
        case blocked(reason: String)
    }
}
```

### Target Contract (from review)

- **Rule A:** Every surface MUST call the same policy function before registering a dose
- **Rule B:** If policy returns `.requiresConfirmation`, the surface MUST show UI before proceeding
- **Rule C:** Late dose override requires explicit user confirmation on ALL surfaces
- **Rule D:** Extra dose requires double-confirmation ("I Accept Full Responsibility") on ALL surfaces
- **Rule E:** Undo is available for all dose actions regardless of surface

---

## Other Technical Debt

### WHOOP Integration (Decorative)

- `WHOOPService.isEnabled = false` — feature flag OFF
- All WHOOP data display uses simulated/hardcoded values
- OAuth flow implemented but untested with real API
- `client_secret` restored (dc51cfd) but needs real credentials
- **Decision:** Enable for real or remove dead code

### Legacy Files (Quarantined)

These files are wrapped in `#if false` with explicit approval:

- `TimeEngine.swift` (app-layer duplicate of Core version)
- `EventStore.swift` (app-layer duplicate)
- `UndoManager.swift` (replaced by `DoseUndoManager`)
- `DoseTapCore.swift` (old version, now in Core)
- `ContentView_Old.swift` (replaced)
- `DashboardView.swift` (replaced by `DashboardViews.swift`)

### Xcode Project Settings

- "Update to recommended settings" warning in Xcode
- Not yet applied (low priority)

### CloudKit Tombstones

- `cloudkit_tombstones` table exists in schema
- CloudKit sync not fully wired
- Dead code accumulating

### Session Repository Size

- `SessionRepository.swift` at 1713 lines — god file candidate
- Could split into: `SessionRepository+Dose.swift`, `+Rollover.swift`, `+Queries.swift`
