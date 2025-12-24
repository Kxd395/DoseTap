# Setup Wizard Contract

## Overview
First-run setup wizard to collect user preferences and establish the core invariant (150–240 minute dose window) with proper personalization.

## User Flow
5-step guided setup process that must be completed before accessing the main application.

## Step 1: Sleep Schedule
**Purpose**: Establish user's typical sleep pattern for dose timing optimization.

**Required Fields**:
- `usual_bedtime`: Time (HH:MM format, 12-hour with AM/PM)
- `usual_wake_time`: Time (HH:MM format, 12-hour with AM/PM)  
- `timezone`: String (IANA timezone identifier, auto-detected)
- `vary_bedtime`: Boolean (allows ±30 minute variance)

**Validation**:
- Bedtime and wake time must be at least 4 hours apart
- Timezone must be valid IANA identifier
- Default `vary_bedtime` to `true` for flexibility

**Storage**: Persisted to `DoseCore.UserConfig.sleepSchedule`

## Step 2: Medication Profile
**Purpose**: Configure medication details for dosage tracking and inventory management.

**Required Fields**:
- `medication_name`: String (default "XYWAV", allow custom)
- `dose_mg_dose1`: Integer (milligrams, typically 450-900)
- `dose_mg_dose2`: Integer (milligrams, typically 225-450)
- `doses_per_bottle`: Integer (default 60)
- `bottle_mg_total`: Integer (calculated: doses_per_bottle × (dose1 + dose2))

**Validation**:
- All dosage values must be positive integers
- Dose 2 should be ≤ Dose 1 (warn if not, but allow)
- Medication name required, max 50 characters

**Storage**: Persisted to `DoseCore.UserConfig.medicationProfile`

## Step 3: Dose Window Rules
**Purpose**: Configure timing rules while preserving the core 150–240 minute invariant.

**Fixed Values** (per SSOT core invariant):
- `min_minutes`: 150 (not user-configurable)
- `max_minutes`: 240 (not user-configurable)
- `near_window_threshold`: 15 (snooze disabled when <15m remain)
- `snooze_step_minutes`: 10 (fixed per SSOT)
- `undo_window_seconds`: 5 (fixed per SSOT)

**Configurable Fields**:
- `default_target_minutes`: Integer (default 165, enum: [165, 180, 195, 210, 225])
- `max_snoozes`: Integer (default 3, range 1-5)

**Validation**:
- `default_target_minutes` must be one of [165, 180, 195, 210, 225]
- Display warning if target is near boundaries (165 or 225)

**UI Presentation**:
- Show target as labeled buttons (2h 45m, 3h 00m, 3h 15m, 3h 30m, 3h 45m)
- Highlight default (2h 45m / 165m) with "Recommended" label

**Storage**: Persisted to `DoseCore.UserConfig.doseWindow`

## Step 4: Notifications & Permissions
**Purpose**: Configure notification preferences and request permissions.

**Permission Requests**:
- UNUserNotificationCenter authorization (required)
- Critical alerts authorization (optional, medical justification)

**Configuration Options**:
- `auto_snooze_enabled`: Boolean (default true)
- `notification_sound`: String (default "default", options: default, urgent, gentle)
- `focus_mode_override`: Boolean (attempt critical alerts, default false)

**Behavior**:
- Explain auto-snooze functionality
- Clarify undo window (5 seconds default, per SSOT)
- Warn about Focus/DND limitations
- Show sample notification with actions

**Storage**: Persisted to `DoseCore.UserConfig.notifications`

## Step 5: Privacy & Sync
**Purpose**: Configure data storage and sync preferences.

**Default Configuration**:
- `icloud_sync_enabled`: Boolean (default FALSE)
- `data_retention_days`: Integer (default 365)
- `analytics_enabled`: Boolean (default true, local only)

**Information Display**:
- Explain local-only default storage
- Detail what iCloud sync includes (events, config, NOT health data)
- Clarify data export options
- Privacy policy link

**Storage**: Persisted to `DoseCore.UserConfig.privacy`

## Completion Requirements
All 5 steps must be completed to access main application. Wizard can be re-run from Settings → "Reconfigure Setup".

## Configuration Schema
```swift
struct UserConfig: Codable {
    let schemaVersion: Int = 1
    let setupCompleted: Bool
    let setupCompletedAt: Date
    
    let sleepSchedule: SleepScheduleConfig
    let medicationProfile: MedicationConfig
    let doseWindow: DoseWindowConfig
    let notifications: NotificationConfig
    let privacy: PrivacyConfig
}
```

## Error Handling
- Network unavailable during timezone detection: use device timezone
- Invalid inputs: show inline validation with specific error messages
- Permission denied: continue with degraded functionality, show warning
- Setup interruption: save progress, allow resume from last completed step

## Accessibility
- VoiceOver labels for all input fields
- Dynamic Type support for all text
- High contrast mode support
- Reduced motion: disable animated transitions between steps

## Testing Requirements
- Test all validation rules with edge cases
- Verify configuration persistence across app restarts
- Test permission flows on various iOS versions
- Validate timezone handling across DST transitions
- Test setup wizard interruption and resume flows
