# Implementation Plan: Manual Dose Time Entry & Adjustment

**Feature ID**: 003-manual-dose-entry
**Spec Version**: 1.0
**Estimated Effort**: 3-4 days

---

## Phase Overview

| Phase | Focus | Effort | Dependencies |
| ----- | ----- | ------ | ------------ |
| 1 | Data model & validation | 4h | None |
| 2 | SessionRepository methods | 4h | Phase 1 |
| 3 | Manual entry UI | 6h | Phase 2 |
| 4 | Time adjustment UI | 4h | Phase 2 |
| 5 | Recovery flow | 4h | Phase 2 |
| 6 | Testing & polish | 6h | All |

---

## Phase 1: Data Model & Validation (4h)

### 1.1 Update Database Schema

**File**: `ios/DoseTap/Storage/EventStorage.swift`

Add columns to `dose_events`:

```swift
// Migration in createTables() or schema upgrade
db.execute("""
    ALTER TABLE dose_events ADD COLUMN source TEXT DEFAULT 'app';
    ALTER TABLE dose_events ADD COLUMN original_timestamp TEXT;
    ALTER TABLE dose_events ADD COLUMN entry_timestamp TEXT;
""")
```

### 1.2 Add Constants

**File**: `docs/SSOT/constants.json`

```json
"manualEntry": {
    "minIntervalMinutes": 90,
    "maxIntervalMinutes": 360,
    "maxAdjustmentMinutes": 30,
    "recoveryWindowHours": 12,
    "requiresConfirmation": true
}
```

### 1.3 Create Validation Module

**File**: `ios/Core/ManualEntryValidation.swift` (new)

```swift
public enum ManualEntryError: Error, Equatable {
    case tooEarlyAfterDose1(minMinutes: Int)
    case tooLateAfterDose1(maxMinutes: Int)
    case adjustmentTooLarge(maxMinutes: Int)
    case sessionTooOld(maxHours: Int)
    case confirmationRequired
    case sessionAlreadyComplete
}

public struct ManualEntryValidator {
    public static let minIntervalMinutes = 90
    public static let maxIntervalMinutes = 360
    public static let maxAdjustmentMinutes = 30
    public static let recoveryWindowHours = 12
    
    public static func validateManualDose2(
        time: Date,
        dose1At: Date
    ) -> ManualEntryError? {
        let interval = time.timeIntervalSince(dose1At) / 60
        
        if interval < Double(minIntervalMinutes) {
            return .tooEarlyAfterDose1(minMinutes: minIntervalMinutes)
        }
        if interval > Double(maxIntervalMinutes) {
            return .tooLateAfterDose1(maxMinutes: maxIntervalMinutes)
        }
        return nil
    }
    
    public static func validateAdjustment(
        newTime: Date,
        originalTime: Date
    ) -> ManualEntryError? {
        let adjustment = abs(newTime.timeIntervalSince(originalTime)) / 60
        
        if adjustment > Double(maxAdjustmentMinutes) {
            return .adjustmentTooLarge(maxMinutes: maxAdjustmentMinutes)
        }
        return nil
    }
    
    public static func validateRecovery(
        sessionDate: Date,
        now: Date = Date()
    ) -> ManualEntryError? {
        let age = now.timeIntervalSince(sessionDate) / 3600
        
        if age > Double(recoveryWindowHours) {
            return .sessionTooOld(maxHours: recoveryWindowHours)
        }
        return nil
    }
}
```

### Tests First ⚠️

**File**: `Tests/DoseCoreTests/ManualEntryValidationTests.swift` (new)

- [ ] `test_validateManualDose2_validTime_returnsNil`
- [ ] `test_validateManualDose2_tooEarly_returnsError`
- [ ] `test_validateManualDose2_tooLate_returnsError`
- [ ] `test_validateAdjustment_withinLimit_returnsNil`
- [ ] `test_validateAdjustment_exceedsLimit_returnsError`
- [ ] `test_validateRecovery_withinWindow_returnsNil`
- [ ] `test_validateRecovery_tooOld_returnsError`

---

## Phase 2: SessionRepository Methods (4h)

### 2.1 Extend Protocol

**File**: `ios/DoseTap/Storage/SessionRepository.swift`

```swift
// Add to SessionRepository
public func setDose2TimeManual(_ time: Date, confirmed: Bool) throws {
    guard confirmed else {
        throw ManualEntryError.confirmationRequired
    }
    guard let d1 = dose1Time else {
        throw ManualEntryError.sessionAlreadyComplete
    }
    
    if let error = ManualEntryValidator.validateManualDose2(time: time, dose1At: d1) {
        throw error
    }
    
    storage.saveDose2Manual(timestamp: time)
    dose2Time = time
    dose2Skipped = false
    
    Task {
        await DiagnosticLogger.shared.log(.dose2ManualEntry, sessionId: activeSessionDate) { entry in
            entry.dose2Time = time
            entry.source = "manual"
        }
    }
    
    sessionDidChange.send()
}

public func adjustDose2Time(_ newTime: Date) throws {
    guard let original = dose2Time else {
        throw ManualEntryError.sessionAlreadyComplete
    }
    
    if let error = ManualEntryValidator.validateAdjustment(newTime: newTime, originalTime: original) {
        throw error
    }
    
    storage.updateDose2Time(newTime: newTime, originalTime: original)
    dose2Time = newTime
    
    Task {
        await DiagnosticLogger.shared.log(.dose2TimeAdjusted, sessionId: activeSessionDate) { entry in
            entry.dose2Time = newTime
            entry.originalTime = original
            entry.source = "adjusted"
        }
    }
    
    sessionDidChange.send()
}

public func recoverSkippedSession(dose2Time: Date) throws {
    guard dose2Skipped else {
        throw ManualEntryError.sessionAlreadyComplete
    }
    
    if let sessionDate = activeSessionDate,
       let error = ManualEntryValidator.validateRecovery(sessionDate: ISO8601DateFormatter().date(from: sessionDate) ?? Date()) {
        throw error
    }
    
    try setDose2TimeManual(dose2Time, confirmed: true)
    storage.updateTerminalState(sessionDate: activeSessionDate ?? "", state: "completed_manual")
}
```

### 2.2 Extend EventStorage

**File**: `ios/DoseTap/Storage/EventStorage.swift`

```swift
public func saveDose2Manual(timestamp: Date) {
    // Similar to saveDose2 but with source = "manual"
    // and entry_timestamp = now
}

public func updateDose2Time(newTime: Date, originalTime: Date) {
    // UPDATE dose_events SET timestamp = newTime, 
    // original_timestamp = originalTime, source = 'adjusted'
    // WHERE ...
}
```

### Tests First ⚠️

**File**: `ios/DoseTapTests/SessionRepositoryTests.swift`

- [ ] `test_setDose2TimeManual_validTime_succeeds`
- [ ] `test_setDose2TimeManual_tooEarly_throws`
- [ ] `test_setDose2TimeManual_withoutConfirmation_throws`
- [ ] `test_adjustDose2Time_withinLimit_succeeds`
- [ ] `test_adjustDose2Time_exceedsLimit_throws`
- [ ] `test_recoverSkippedSession_validTime_succeeds`
- [ ] `test_recoverSkippedSession_tooOld_throws`

---

## Phase 3: Manual Entry UI (6h)

### 3.1 Create ManualDoseEntryView

**File**: `ios/DoseTap/Views/ManualDoseEntryView.swift` (new)

```swift
struct ManualDoseEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    
    let dose1Time: Date
    let sessionDate: String
    let onSave: (Date) -> Void
    
    @State private var selectedTime: Date
    @State private var isConfirmed = false
    @State private var errorMessage: String?
    
    init(dose1Time: Date, sessionDate: String, onSave: @escaping (Date) -> Void) {
        self.dose1Time = dose1Time
        self.sessionDate = sessionDate
        self.onSave = onSave
        // Default to optimal time (165 min after Dose 1)
        _selectedTime = State(initialValue: dose1Time.addingTimeInterval(165 * 60))
    }
    
    var body: some View {
        NavigationView {
            Form {
                sessionInfoSection
                timePickerSection
                intervalPreviewSection
                confirmationSection
            }
            .navigationTitle("Add Dose 2")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveEntry() }
                        .disabled(!isValidEntry)
                }
            }
        }
    }
    
    // ... sections implementation
}
```

### 3.2 Add "I Already Took It" Button

**File**: `ios/DoseTap/ContentView.swift`

In the expired window state section, add:

```swift
// After window expired, before auto-skip
if core.currentStatus == .closed && !core.isSkipped {
    Button {
        showManualEntrySheet = true
    } label: {
        Label("I Already Took It", systemImage: "clock.badge.checkmark")
    }
    .buttonStyle(.bordered)
}
```

### Tests First ⚠️

- [ ] UI snapshot tests for ManualDoseEntryView
- [ ] Test validation message display
- [ ] Test time picker constraints

---

## Phase 4: Time Adjustment UI (4h)

### 4.1 Create EditDoseTimeView

**File**: `ios/DoseTap/Views/EditDoseTimeView.swift` (new)

Similar to ManualDoseEntryView but for adjusting existing times with ±30 min constraint.

### 4.2 Add Edit Button to Session Detail

**File**: `ios/DoseTap/Views/SessionDetailView.swift`

Add edit icon next to dose times that opens EditDoseTimeView.

---

## Phase 5: Recovery Flow (4h)

### 5.1 Update Incomplete Session Banner

**File**: `ios/DoseTap/ContentView.swift`

Add "I took Dose 2" option to IncompleteSessionBanner:

```swift
struct IncompleteSessionBanner: View {
    // ...existing...
    
    var body: some View {
        HStack {
            // ...existing UI...
            
            Menu {
                Button("Complete Check-In") { onComplete() }
                Button("I Took Dose 2") { onRecovery() }  // NEW
                Button("Dismiss", role: .destructive) { onDismiss() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}
```

### 5.2 Recovery Sheet

Present ManualDoseEntryView when "I Took Dose 2" is tapped, then call `recoverSkippedSession()`.

---

## Phase 6: Testing & Polish (6h)

### 6.1 Integration Tests

- [ ] Full flow: Auto-skip → Recovery → Session shows as completed
- [ ] Full flow: Log dose → Adjust time → Verify update
- [ ] Edge: 12-hour recovery window boundary

### 6.2 Diagnostic Logging

Add new events to `DiagnosticEvent.swift`:

```swift
case dose2ManualEntry = "dose.2.manual_entry"
case dose2TimeAdjusted = "dose.2.adjusted"
case sessionRecovered = "session.recovered"
```

### 6.3 SSOT Update

Update `docs/SSOT/README.md` with:

- Manual entry rules
- New terminal state `completed_manual`
- Recovery window documentation

---

## Constitution Checkpoints

| Checkpoint | Principle | Verification |
| ---------- | --------- | ------------ |
| After Phase 1 | II. Test-First | All validation tests pass |
| After Phase 2 | IV. Storage Boundary | SessionRepository is only access point |
| After Phase 3 | I. SSOT-First | UI matches spec exactly |
| After Phase 6 | II. Test-First | All tests pass, >90% coverage |

---

## Rollout Plan

1. **Alpha**: Enable for TestFlight users
2. **Monitor**: Track manual entry frequency (target: <2/user/month)
3. **Iterate**: Adjust time constraints based on real usage
4. **GA**: Release with next version
