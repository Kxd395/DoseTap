# Inventory Management Contract

## Overview
Medication inventory tracking system to monitor supply levels, calculate remaining doses, and trigger refill reminders.

## Core Entities

### MedicationInventory
Primary inventory tracking entity with the following fields:

**Required Fields:**
- `medication_name`: String (matches UserConfig.medicationProfile.medication_name)
- `mg_per_dose1`: Integer (milligrams for first dose)
- `mg_per_dose2`: Integer (milligrams for second dose)
- `bottles_on_hand`: Integer (current inventory count)
- `mg_per_bottle`: Integer (total milligrams per bottle)
- `refill_threshold_days`: Integer (days remaining when reminder triggers)

**Calculated Fields:**
- `total_mg_available`: bottles_on_hand × mg_per_bottle
- `mg_per_night`: mg_per_dose1 + mg_per_dose2
- `estimated_nights_remaining`: total_mg_available ÷ mg_per_night
- `estimated_days_remaining`: estimated_nights_remaining (assuming one dose cycle per day)
- `refill_due_date`: current_date + estimated_days_remaining

**Optional Fields:**
- `pharmacy_note`: String (pharmacy contact info, prescription details)
- `last_refill_date`: Date (when inventory was last updated)
- `prescription_number`: String (for pharmacy reference)

## Events

### New Event Types
Extend the existing event system with inventory-related events:

**refill_logged**
- Triggered when user logs a new prescription pickup
- Fields: `bottles_added`, `pharmacy_note`, `prescription_number`
- Auto-updates `bottles_on_hand` and `last_refill_date`

**refill_reminder**
- System-generated when `estimated_days_remaining` ≤ `refill_threshold_days`
- Fields: `days_remaining`, `reminder_type` (first_warning, urgent, critical)
- Frequency: daily when in warning state

**inventory_adjustment**
- Manual inventory corrections
- Fields: `bottles_before`, `bottles_after`, `adjustment_reason`
- Use cases: spillage, loss, found extra bottles

## User Interface

### Settings → Inventory Section
**Display Components:**
- Current medication name and dosage summary
- Bottles on hand with visual indicator (green/yellow/red based on days remaining)
- Estimated days remaining with refill due date
- Quick action buttons: "Log Refill", "Adjust Inventory"

**Thresholds:**
- Green: >30 days remaining
- Yellow: 15-30 days remaining  
- Red: <15 days remaining
- Critical: <7 days remaining (persistent notification)

### Log Refill Flow
**Step 1: Confirm Details**
- Pre-filled medication name and dosage
- Input field for bottles received
- Optional pharmacy note field

**Step 2: Update Inventory**
- Calculate new total bottles on hand
- Update estimated days remaining
- Log refill_logged event with timestamp

### Pharmacy Note Management
- Store pharmacy contact information
- Prescription details (number, prescriber)
- Refill instructions or special notes
- Export capability for insurance/medical records

## Notifications

### Refill Reminders
**Timing:**
- First warning: when days_remaining = refill_threshold_days
- Daily reminders: while in warning state
- Urgent: when days_remaining ≤ 7
- Critical: when days_remaining ≤ 3

**Notification Content:**
- Title: "DoseTap Refill Reminder"
- Body: "X days of XYWAV remaining. Time to refill."
- Actions: "Log Refill", "Remind Tomorrow", "View Details"

### Critical Low Inventory
- Persistent notification when <3 days remaining
- Repeats daily at 9 AM until inventory updated (iOS cannot trap user in a notification)
- In-app banner remains visible until resolved
- Escalated priority if critical alerts enabled

## Data Export

### inventory.csv Schema
```
as_of_utc,medication_name,bottles_on_hand,mg_per_bottle,mg_per_dose1,mg_per_dose2,estimated_days_remaining,refill_threshold_days,pharmacy_note,last_refill_date,prescription_number
```

**Sample Data:**
```csv
2025-09-07T18:00:00Z,XYWAV,2,9000,450,225,26,10,"Central Pharmacy (555-1234)","2025-08-15T10:30:00Z",RX123456
```

### Event Integration
Inventory events integrate with existing events.csv export:
- `event_type`: refill_logged, refill_reminder, inventory_adjustment
- `event_data`: JSON containing inventory-specific fields
- Maintains chronological event history

## Business Logic

### Consumption Tracking
**Automatic Deduction:**
- When dose1_taken event logged: no inventory change (dose 1 taken at bedtime)
- When dose2_taken event logged: deduct (mg_per_dose1 + mg_per_dose2) from inventory
- If dose2_skipped: still deduct dose1 from previous night

**Manual Tracking Mode:**
- Option to disable automatic deduction
- User manually logs consumption
- Useful for irregular schedules or dose adjustments

### Threshold Calculations
**Days Remaining Formula:**
```
estimated_days = (bottles_on_hand × mg_per_bottle) ÷ (mg_per_dose1 + mg_per_dose2)
```

**Buffer Calculations:**
- Include 2-day safety buffer in refill reminders
- Account for weekend/holiday pharmacy closures
- Adjust for known schedule irregularities

## Error Handling

### Data Validation
- Inventory values must be non-negative
- Dosage amounts must match medication profile
- Refill threshold must be reasonable (3-60 days)

### Edge Cases
- Zero inventory: persistent critical alert
- Negative calculated inventory: flag for manual review
- Large adjustments: require confirmation
- Dosage changes: recalculate all estimates

### Recovery Scenarios
- Lost inventory data: import from backup or manual re-entry
- Incorrect calculations: audit log for tracking
- Pharmacy delays: extend reminder thresholds

## Privacy & Security

### Data Sensitivity
- Inventory data considered medical information
- Include in support bundle exports (anonymized)
- Exclude pharmacy notes from automatic exports unless explicitly requested

### iCloud Sync
- Inventory data syncs with iCloud (if enabled)
- Pharmacy notes encrypted in transit and at rest
- Prescription numbers hashed for privacy

## Testing Requirements

### Unit Tests
- Inventory calculation accuracy across various scenarios
- Threshold trigger logic with edge cases
- Event logging integration
- Data export format validation

### Integration Tests
- Notification scheduling and delivery
- iCloud sync behavior
- Cross-timezone inventory calculations
- Recovery from data corruption

### User Acceptance Tests
- Complete refill workflow from reminder to logging
- Inventory adjustment flows
- Export and import scenarios
- Critical low inventory handling
