# Medication Logger Feature Specification

**Status:** 📋 Spec Ready  
**Priority:** P1  
**Dependencies:** SessionRepository (implemented), EventStorage (implemented)

---

## Overview

Add first-class medication logging for stimulants (Adderall IR, Adderall XR) with:
- Append-only event storage (never overwrite)
- Duplicate tap guard (hard stop warning within time window)
- Export as separate CSV rows

---

## 1. Canonical Medication Definitions

Add to `docs/SSOT/constants.json`:

```json
{
  "medications": {
    "stimulants": [
      {
        "id": "adderall_ir",
        "display_name": "Adderall",
        "generic_name": "amphetamine/dextroamphetamine",
        "formulation": "ir",
        "class": "stimulant",
        "default_unit": "mg",
        "common_doses": [5, 10, 15, 20, 25, 30]
      },
      {
        "id": "adderall_xr",
        "display_name": "Adderall XR",
        "generic_name": "amphetamine/dextroamphetamine extended-release",
        "formulation": "xr",
        "class": "stimulant",
        "default_unit": "mg",
        "common_doses": [5, 10, 15, 20, 25, 30]
      }
    ],
    "duplicate_guard_minutes": 5
  }
}
```

---

## 2. Database Schema

### New Table: `medication_events`

```sql
CREATE TABLE IF NOT EXISTS medication_events (
    id TEXT PRIMARY KEY,
    session_id TEXT,
    session_date TEXT NOT NULL,
    taken_at_utc TEXT NOT NULL,
    local_offset_minutes INTEGER NOT NULL,
    medication_id TEXT NOT NULL,
    dose_value REAL NOT NULL,
    dose_unit TEXT NOT NULL DEFAULT 'mg',
    formulation TEXT NOT NULL,
    confirmed_duplicate INTEGER NOT NULL DEFAULT 0,
    notes TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_medication_events_session ON medication_events(session_date);
CREATE INDEX IF NOT EXISTS idx_medication_events_medication ON medication_events(medication_id);
```

### Column Definitions

| Column | Type | Description |
| ------ | ---- | ----------- |
| id | TEXT | UUID primary key |
| session_id | TEXT | Links to sleep session (nullable for daytime doses) |
| session_date | TEXT | YYYY-MM-DD format, using 6PM boundary |
| taken_at_utc | TEXT | ISO8601 timestamp in UTC |
| local_offset_minutes | INTEGER | User's timezone offset at time of entry |
| medication_id | TEXT | One of: `adderall_ir`, `adderall_xr` |
| dose_value | REAL | Numeric dose (e.g., 20) |
| dose_unit | TEXT | Unit (default: `mg`) |
| formulation | TEXT | Redundant copy of `ir` or `xr` for export stability |
| confirmed_duplicate | INTEGER | 1 if user confirmed duplicate within guard window |
| notes | TEXT | Optional user notes |

---

## 3. Repository API

### SessionRepository Extensions

```swift
// MARK: - Medication Logging

/// Add a medication entry to the current session
/// Returns: (success: Bool, requiresConfirmation: Bool, existingEntry: MedicationEntry?)
func addMedicationEntry(
    medicationId: String,
    doseValue: Double,
    doseUnit: String = "mg",
    takenAt: Date = Date(),
    notes: String? = nil
) -> MedicationAddResult

/// List medication entries for active session
func listMedicationEntriesForActiveSession() -> [MedicationEntry]

/// List medication entries for a specific date
func listMedicationEntries(for sessionDate: String) -> [MedicationEntry]

/// Delete a medication entry by ID
func deleteMedicationEntry(id: String)

/// Confirm and add a duplicate entry (user acknowledged warning)
func confirmDuplicateMedicationEntry(
    medicationId: String,
    doseValue: Double,
    doseUnit: String = "mg",
    takenAt: Date = Date(),
    notes: String? = nil
)
```

### Result Type

```swift
enum MedicationAddResult {
    case success(entry: MedicationEntry)
    case requiresConfirmation(existingEntry: MedicationEntry, minutesAgo: Int)
    case error(String)
}

struct MedicationEntry: Identifiable, Codable {
    let id: String
    let sessionId: String?
    let sessionDate: String
    let takenAtUTC: Date
    let localOffsetMinutes: Int
    let medicationId: String
    let doseValue: Double
    let doseUnit: String
    let formulation: String
    let confirmedDuplicate: Bool
    let notes: String?
    let createdAt: Date
    
    var displayName: String {
        medicationId == "adderall_xr" ? "Adderall XR" : "Adderall"
    }
}
```

---

## 4. Duplicate Guard Logic

```swift
func checkDuplicateGuard(medicationId: String, takenAt: Date) -> (isDuplicate: Bool, existingEntry: MedicationEntry?, minutesAgo: Int) {
    let guardWindow = Constants.medications.duplicateGuardMinutes // 5
    let entries = listMedicationEntriesForActiveSession()
    
    for entry in entries {
        if entry.medicationId == medicationId {
            let minutesAgo = Int(takenAt.timeIntervalSince(entry.takenAtUTC) / 60)
            if minutesAgo < guardWindow {
                return (true, entry, minutesAgo)
            }
        }
    }
    return (false, nil, 0)
}
```

**Behavior:**
1. User taps "Add Adderall"
2. Check if same `medication_id` logged within 5 minutes
3. If yes → Show hard stop warning: "You logged Adderall 2 minutes ago. Add another entry?"
4. User must explicitly confirm to add duplicate
5. `confirmed_duplicate = 1` in database for audit trail

---

## 5. UI Specification

### Placement

**Primary:** Pre-Sleep Log view (`ios/DoseTap/Views/PreSleepLogView.swift`)  
**Secondary:** Tonight tab (quick access button)

### Components

#### Medication Picker

```
┌─────────────────────────────────────────┐
│ Add Medication                          │
├─────────────────────────────────────────┤
│ ○ Adderall (IR)                         │
│ ● Adderall XR                           │
├─────────────────────────────────────────┤
│ Dose: [ 20 ] mg                         │
│       5  10  15  20  25  30  (presets)  │
├─────────────────────────────────────────┤
│ Time: [ 2:30 PM ]                       │
├─────────────────────────────────────────┤
│ Notes: (optional)                       │
├─────────────────────────────────────────┤
│        [ Cancel ]    [ Add Entry ]      │
└─────────────────────────────────────────┘
```

#### Duplicate Warning Alert

```
┌─────────────────────────────────────────┐
│ ⚠️ Duplicate Entry                      │
├─────────────────────────────────────────┤
│ You logged Adderall XR 20mg             │
│ 2 minutes ago at 2:28 PM.               │
│                                         │
│ Are you sure you want to add            │
│ another entry?                          │
├─────────────────────────────────────────┤
│  [ Cancel ]          [ Add Anyway ]     │
└─────────────────────────────────────────┘
```

#### Medication List (in Pre-Sleep Log)

```
┌─────────────────────────────────────────┐
│ Today's Medications                     │
├─────────────────────────────────────────┤
│ Adderall XR 20mg         7:30 AM    ⋮  │
│ Adderall 10mg            12:30 PM   ⋮  │
│ Adderall 10mg            5:00 PM    ⋮  │
├─────────────────────────────────────────┤
│            [ + Add Medication ]         │
└─────────────────────────────────────────┘
```

Swipe-to-delete enabled. Overflow menu (⋮) shows: Edit, Delete.

---

## 6. Export Format

### File: `medication_events.csv`

```csv
id,session_date,taken_at_utc,medication_id,display_name,dose_value,dose_unit,formulation,confirmed_duplicate,notes
abc123,2025-12-24,2025-12-24T12:30:00Z,adderall_ir,Adderall,10,mg,ir,0,
def456,2025-12-24,2025-12-24T22:00:00Z,adderall_xr,Adderall XR,20,mg,xr,0,before bed
```

### Integration with Existing Export

Add to `DataExportService.exportData()`:
- Include `medication_events.csv` in combined export
- Add medication summary to HTML report

---

## 7. Test Cases

### Unit Tests (`Tests/DoseCoreTests/MedicationLoggerTests.swift`)

```swift
func test_addMedicationEntry_createsRow()
func test_addMedicationEntry_adderallXR_setsFormulationXR()
func test_duplicateWithinWindow_triggersWarning()
func test_confirmDuplicate_logsWithFlag()
func test_deleteMedicationEntry_removesRow()
func test_listEntries_returnsSessionEntries()
func test_persistence_survivesRestart()
func test_export_includesMedicationEvents()
```

### Integration Tests (`ios/DoseTapTests/MedicationLoggerIntegrationTests.swift`)

```swift
func test_addButton_showsPicker()
func test_duplicateTap_showsWarningAlert()
func test_confirmDuplicate_addsEntry()
func test_swipeDelete_removesEntry()
func test_entryList_sortsByTime()
```

---

## 8. Migration

### Schema Migration

Add to `EventStorage.createTables()`:
- Create `medication_events` table
- Add migration flag: `UserDefaults.didMigrateMedicationEvents`

No data migration needed (new feature).

---

## 9. Acceptance Criteria

- [ ] User can add Adderall IR entry with dose and time
- [ ] User can add Adderall XR entry with dose and time
- [ ] Duplicate tap within 5 minutes shows hard stop warning
- [ ] User can confirm to add duplicate (logged with flag)
- [ ] Entries persist across app restart
- [ ] Entries appear in Pre-Sleep Log medication list
- [ ] Entries export to `medication_events.csv`
- [ ] Swipe-to-delete works
- [ ] All unit tests pass
- [ ] All integration tests pass

---

## 10. Implementation Order

1. Add medication definitions to `constants.json`
2. Add `medication_events` table to `EventStorage.swift`
3. Add repository methods to `SessionRepository.swift`
4. Add `MedicationEntry` model
5. Add duplicate guard logic
6. Create `MedicationPickerView.swift`
7. Integrate into `PreSleepLogView.swift`
8. Add export integration
9. Write tests
10. Update SSOT status to ✅ Implemented

---

*Spec created: 2025-12-24*  
*Ready for implementation*
