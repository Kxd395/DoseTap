# Agent Prompt: Dosing Amount Architecture

**Branch:** `004-dosing-amount-model`  
**Created:** January 19, 2026  
**Status:** Schema and models complete, UI integration pending

## The Critical Insight

> "How much did I take" is not a nice-to-have field. It is the whole reason DoseTap exists, because half-life math and wear-off timing is meaningless if the app only knows "Dose 1 happened" but not the amount.

## Two-Layer Architecture

### Layer 1: Regimen (The Plan/Prescription)
- What the user is **supposed** to take
- Total nightly amount, split configuration
- Can change over time (date-bounded for prescription changes)

### Layer 2: Dose Events (What Actually Happened)
- Each administration with timestamp AND AMOUNT
- Grouped into bundles for split dose tracking
- Source of truth for analytics

## Data Model

### Regimen Table (`regimens`)
```sql
CREATE TABLE regimens (
    id TEXT PRIMARY KEY,
    medication_id TEXT NOT NULL,
    start_at TEXT NOT NULL,
    end_at TEXT,                    -- NULL = currently active
    target_total_amount_value REAL NOT NULL,
    target_total_amount_unit TEXT DEFAULT 'mg',
    split_mode TEXT DEFAULT 'equal',  -- 'none', 'equal', 'custom'
    split_parts_count INTEGER DEFAULT 2,
    split_parts_ratio_json TEXT DEFAULT '[0.5, 0.5]',
    notes TEXT,
    prescribed_by TEXT
);
```

### Dose Bundle Table (`dose_bundles`)
```sql
CREATE TABLE dose_bundles (
    id TEXT PRIMARY KEY,
    regimen_id TEXT,
    session_id TEXT NOT NULL,
    session_date TEXT NOT NULL,
    target_total_amount_value REAL NOT NULL,
    target_total_amount_unit TEXT DEFAULT 'mg',
    target_split_ratio_json TEXT DEFAULT '[0.5, 0.5]',
    bundle_started_at TEXT NOT NULL,
    bundle_completed_at TEXT,
    bundle_label TEXT DEFAULT 'Bedtime'
);
```

### Dose Events (Updated Columns)
```sql
-- New columns added to dose_events:
amount_value REAL,           -- THE CRITICAL MISSING PIECE
amount_unit TEXT DEFAULT 'mg',
source TEXT DEFAULT 'manual', -- 'manual', 'automatic', 'migrated', 'imported'
bundle_id TEXT,
part_index INTEGER,          -- 0-based: 0 = first dose, 1 = second dose
parts_count INTEGER,
medication_id TEXT,
notes TEXT
```

## Split Configurations

| Mode | Ratio | Example (4.5g total) |
|------|-------|---------------------|
| 50/50 | `[0.5, 0.5]` | 2.25g + 2.25g |
| 60/40 (bigger earlier) | `[0.6, 0.4]` | 2.7g + 1.8g |
| 40/60 (bigger later) | `[0.4, 0.6]` | 1.8g + 2.7g |
| 3-way | `[0.5, 0.3, 0.2]` | 2.25g + 1.35g + 0.9g |
| Single | `[1.0]` | 4.5g |

## Key Files

| File | Purpose |
|------|---------|
| `ios/Core/DosingModels.swift` | Swift structs: Regimen, DoseBundle, DoseEventWithAmount |
| `ios/DoseTap/Storage/DosingAmountSchema.swift` | Schema SQL + migrations + repository methods |
| `Tests/DoseCoreTests/DosingAmountTests.swift` | Unit tests (18 tests) |

## Usage Examples

### Creating a Regimen
```swift
// Xyrem 4.5g, 50/50 split
let regimen = Regimen(
    medicationId: "xyrem",
    startAt: Date(),
    targetTotalAmountValue: 4500,  // mg
    targetTotalAmountUnit: .mg,
    splitMode: .equal,
    splitPartsCount: 2,
    splitPartsRatio: [0.5, 0.5]
)
storage.insertRegimen(regimen)
```

### Logging a Dose with Amount
```swift
let event = DoseEventWithAmount(
    eventType: "dose1",
    occurredAt: Date(),
    sessionId: currentSessionId,
    sessionDate: currentSessionDate,
    amountValue: 2250,
    amountUnit: .mg,
    source: .manual,
    bundleId: bundle.id,
    partIndex: 0,
    partsCount: 2
)
storage.insertDoseEventWithAmount(event)
```

### Checking Bundle Status
```swift
if let status = storage.getBundleStatus(bundleId: bundleId) {
    print("Taken: \(status.totalAmountTaken) mg")
    print("Remaining: \(status.remainingAmount) mg")
    print("Adherence: \(status.adherenceStatus.displayText)")
}
```

## Migration Rules for Legacy Data

1. **Legacy dose_events** (no amount_value):
   - Set `source = 'migrated'`
   - Leave `amount_value = NULL`
   - Analytics MUST filter by `source.hasReliableAmount`

2. **Analytics queries**:
   - Always check `amount_value IS NOT NULL` for reliable data
   - Or filter by `source IN ('manual', 'automatic', 'imported')`

3. **UI display**:
   - Show "Unknown" for migrated events without amounts
   - Prompt user to add amount if editing old data

## Validation Rules

### Regimen
- `target_total_amount_value > 0`
- `split_parts_count == splitPartsRatio.count`
- `sum(splitPartsRatio) == 1.0` (±0.001 tolerance)
- `end_at > start_at` if end_at is set

### Dose Event
- `amount_value > 0` if present
- `part_index < parts_count` if both present
- `eventType` not empty

### Bundle
- `target_total_amount_value > 0`
- `split_ratio.count >= 1`

## Pending Work (For Future Agent Sessions)

### P0: UI Integration
1. Add amount input to dose logging flow
2. Show regimen target vs actual in session view
3. Add regimen setup screen in Settings
4. Display adherence status on History view

### P1: Analytics Integration
1. Update half-life calculation to use actual amounts
2. Add adherence reporting
3. Filter analytics by reliable amount sources

### P2: Enhancements
1. Import amounts from health records
2. Medication concentration support (mg/mL → mg)
3. Split ratio recommendations based on history

## How to Run the Schema Migration

The migration runs automatically when EventStorage initializes.
Call manually if needed:

```swift
EventStorage.shared.runDosingAmountMigrations()
```

This:
1. Creates `regimens` and `dose_bundles` tables
2. Adds new columns to `dose_events`
3. Marks existing dose_events as `source='migrated'`

All operations are idempotent (safe to run multiple times).
