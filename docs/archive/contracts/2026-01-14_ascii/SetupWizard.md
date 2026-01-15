# Setup Wizard ASCII Specifications

## First-Run Setup Wizard Screens

### Step 1: Sleep Schedule Configuration
```
┌──────────────────────────────────────────────────────────────────────┐
│  Welcome to DoseTap                                                 │
│  Let's set up your nightly schedule                                 │
│                                                                      │
│  Bedtime          [ 01:00 AM ▾ ]                                     │
│  Wake time        [ 06:30 AM ▾ ]                                     │
│  Time zone        { America/New_York } ( Change )                    │
│  Bedtime varies   [ ON ]  (±30 minutes)                               │
│                                                                      │
│  [ Continue ]                                                        │
│  VO: "Set your typical bedtime and wake time. Continue."             │
└──────────────────────────────────────────────────────────────────────┘
```

### Step 2: Medication Profile
```
┌──────────────────────────────────────────────────────────────────────┐
│  Medication Profile                                                  │
│                                                                      │
│  Name               [ XYWAV ▾ ] (Add custom)                         │
│  Dose 1 (mg)        [ 450 ]                                          │
│  Dose 2 (mg)        [ 225 ]                                          │
│  Doses per bottle   [ 60 ]   Bottle mg [ 9000 ]                      │
│                                                                      │
│  [ Continue ]             ( Back )                                   │
│  VO: "Medication profile. Continue."                                 │
└──────────────────────────────────────────────────────────────────────┘
```

### Step 3: Dose Window Rules
```
┌──────────────────────────────────────────────────────────────────────┐
│  Dose Window Rules                                                   │
│                                                                      │
│  Target interval    { 165 minutes }                                  │
│  Allowed window     { 150–240 minutes }                              │
│  Snooze step        [ 10m ▾ ]   Max snoozes [ 3 ▾ ]                  │
│  Undo window        [ 5s ▾ ]                                         │
│                                                                      │
│  [ Enable Notifications ]   ( Not now )                              │
│  VO: "Enable notifications. Snooze disabled with less than 15        │
│       minutes remaining."                                            │
└──────────────────────────────────────────────────────────────────────┘
```

### Step 4: Notifications & Permissions
```
┌──────────────────────────────────────────────────────────────────────┐
│  Notifications & Alerts                                              │
│                                                                      │
│  Allow Notifications    [ Enable ]                                   │
│  Critical Alerts        [ Request ]  (Medical necessity)             │
│  Auto-snooze           [ ON ]                                        │
│  Focus override        [ OFF ]                                       │
│                                                                      │
│  Sample notification:                                                │
│  ┌─── DoseTap ─────────────────────────┐                            │
│  │ Take Dose 2 — 42m left              │                            │
│  │ [ Take Now ] ( Snooze ) ( Skip )     │                            │
│  └─────────────────────────────────────┘                            │
│                                                                      │
│  [ Continue ]             ( Back )                                   │
│  VO: "Enable notifications for dose reminders. Continue."           │
└──────────────────────────────────────────────────────────────────────┘
```

### Step 5: Privacy & Sync
```
┌──────────────────────────────────────────────────────────────────────┐
│  Privacy & Data Sync                                                │
│                                                                      │
│  Data Storage       { Local Device Only }                            │
│  iCloud Sync        [ OFF ] (Enable later in Settings)              │
│  Data Retention     [ 1 year ▾ ]                                     │
│  Analytics          [ ON ] (Local processing only)                   │
│                                                                      │
│  Your data stays on your device by default.                         │
│  Health data is never synced or shared.                             │
│                                                                      │
│  ( Privacy Policy )                                                  │
│                                                                      │
│  [ Complete Setup ]       ( Back )                                   │
│  VO: "Privacy settings. Data stays local. Complete setup."          │
└──────────────────────────────────────────────────────────────────────┘
```

## Usage Guidelines

### VoiceOver Labels
- All form controls have descriptive labels
- Progress indication ("Step 2 of 5")
- Clear action descriptions for buttons
- Contextual help for complex fields

### Validation States
- Inline validation for required fields
- Visual indicators for valid/invalid inputs
- Clear error messages with correction guidance
- Disabled "Continue" until step is valid

### Responsive Design
- Layouts adapt to Dynamic Type sizes
- Maintains usability at 200% text scale
- High contrast mode support
- Reduced motion alternatives

### Navigation Patterns
- Linear progression through steps
- Back button available after step 1
- Skip options for non-critical features
- Clear exit/cancel behavior

### Accessibility Features
- Screen reader optimization
- Keyboard navigation support
- Voice Control compatibility
- Switch Control accessible
