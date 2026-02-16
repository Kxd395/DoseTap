# 11 — Known Issues & Technical Debt

## P1 Status Summary

All P1 items from IMPROVEMENT_ROADMAP.md are resolved or explicitly deferred:

- ✅ P1-1: Night Review hardcoded health data — replaced with real WHOOP/HealthKit data
- ✅ P1-2: Timeline simulated biometrics — `extractBiometricData()` now uses real WHOOP API calls
- ✅ P1-3: Dashboard WHOOP fields — `whoopSummary` on aggregate, recovery/HRV/efficiency in views
- ✅ P1-4: Dose-sleep correlation — `DoseEffectivenessCalculator` with 43 tests + `IntervalFormat`
- ⏸️ P1-5: CloudKit sync — deferred (requires iCloud entitlement + paid developer team)
- ✅ P1-6: NightScoreCalculator surfaced in Night Review
- ✅ P1-7: Wake alarm semantic naming fixed

## Remaining Technical Debt

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
