# 11 — Known Issues & Technical Debt

> Archived on 2026-09-02. Plane and `docs/audit/2026-09-01/` are the current finding sources.

## P1 Status Summary

All P1 items from IMPROVEMENT_ROADMAP.md are resolved or explicitly deferred:

- ✅ P1-1: Night Review hardcoded health data — replaced with real WHOOP/HealthKit data
- ✅ P1-2: Timeline simulated biometrics — `extractBiometricData()` now uses real WHOOP API calls
- ✅ P1-3: Dashboard WHOOP fields — `whoopSummary` on aggregate, recovery/HRV/efficiency in views
- ✅ P1-4: Dose-sleep correlation — `DoseEffectivenessCalculator` with 43 tests + `IntervalFormat`
- ⏸️ P1-5: CloudKit sync — deferred (requires iCloud entitlement + paid developer team)
- ✅ P1-6: NightScoreCalculator surfaced in Night Review
- ✅ P1-7: Wake alarm semantic naming fixed

## Recently Resolved P0 Dose Policy Items

### Flic Late Dose Confirmation

- Flic dose actions route through `DoseActionCoordinator` with `.flic` registration surface.
- Late Dose 2 returns `.needsConfirm(.lateDose)` and Flic surfaces "Window closed - confirm in app" instead of writing Dose 2.

### Dose 2 After Skip Correction

- `DoseRegistrationPolicy.evaluateDose2` checks `dose2Skipped` before the `.completed` phase branch and returns `.needsConfirm(.afterSkip)`.
- Flic and deep-link Dose 2 after skip require in-app confirmation and preserve the skip marker until confirmed.
- Confirmed after-skip correction writes Dose 2 through `SessionRepository.setDose2Time` and clears the skip marker.

## Remaining Technical Debt

### P1: Extra Dose Not First-Class

- **Issue:** Extra dose (third+ dose) is special-cased in `CompactDoseButton` and `TonightView` but not in `DoseActionCoordinator`
- **Impact:** History tab, Flic, and deep links don't support extra dose consistently
- **Fix:** Add `.extraDose` case to `DoseActionCoordinator.takeDose2()` flow

### P1: History Diverges from Tonight

- **Issue:** `DoseButtonsSection` in `HistoryViews.swift` has its own dose registration logic separate from `DoseActionCoordinator`
- **Impact:** Inconsistent validation, missing confirmation dialogs
- **Fix:** Route History dose actions through the same coordinator

---

## Current: DoseRegistrationPolicy

```swift
// ios/Core/DoseRegistrationPolicy.swift
public enum DoseRegistrationPolicy {
    static func evaluateDose1(input: DoseRegistrationInput) -> RegistrationDecision
    static func evaluateDose2(input: DoseRegistrationInput, overrideConfirmed: Bool) -> RegistrationDecision
    static func evaluateSnooze(input: DoseRegistrationInput, config: DoseWindowConfig) -> RegistrationDecision
    static func evaluateSkip(input: DoseRegistrationInput) -> RegistrationDecision

    enum RegistrationSurface {
        case tonightButton, deepLink, flic, historyButton, notificationAction
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

### WHOOP Integration

- `WHOOPService.isEnabled` is dynamic through `UserDefaults("whoop_enabled")`.
- Dashboard, Settings, Night Review, Timeline, and Details use live WHOOP sleep/recovery fetches when connected.
- Collection fetchers follow `next_token` pagination with the WHOOP `nextToken` query parameter.
- Live OAuth/API validation still requires WHOOP developer credentials and a real account.

### Legacy Files (Quarantined or Retired)

These files are wrapped in `#if false` with explicit approval:

- `TimeEngine.swift` was retired from Core and removed as a stale Xcode reference on 2026-09-01; `DoseWindowCalculator` is canonical.
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
