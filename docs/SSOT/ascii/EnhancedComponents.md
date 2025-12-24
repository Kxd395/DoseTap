# Enhanced UI Components ASCII Specifications

## Actionable Notifications

### Notification Banner (Active Window)
```
┌──────── Notification ────────┐
│ DoseTap                      │
│ Take Dose 2 — 42m left       │
│                               │
│ [ Take Now ]  ( Snooze +10m ) │
│ ( Skip )                      │
└───────────────────────────────┘
VO: "Dose two due in forty-two minutes. Take Now. Snooze plus ten minutes. Skip."
```

### Notification Banner (Near End - Snooze Disabled)
```
┌──────── Notification ────────┐
│ DoseTap                      │
│ Take Dose 2 — 8m left        │
│                               │
│ [ Take Now ]     ( Skip )     │
│ Snooze unavailable (<15m)     │
└───────────────────────────────┘
VO: "Dose two due in eight minutes. Take Now. Skip. Snooze unavailable."
```

### Critical Alert (Persistent)
```
┌──────────────────────────────┐
│ ⚠️ DoseTap - CRITICAL         │
│ Dose window closing in 3m     │
│                               │
│ [ Take Now ]     ( Skip )     │
│                               │
│ This alert stays until       │
│ you take action.             │
└──────────────────────────────┘
VO: "Critical alert. Dose window closing in three minutes. This alert stays until you take action."
```

## Inventory & Refill Management

### Inventory Status (Settings)
```
┌──────────────────────────────────────────────────────────────────────┐
│  Inventory                                                           │
│                                                                      │
│  Medication: { XYWAV }    On hand: { 2 bottles }                     │
│  Per-night total: { 675 mg }  Refill in: { 14 days }                 │
│  Status: 🟡 Low stock                                                │
│                                                                      │
│  [ Log Refill ]  ( Pharmacy Note )   ( Set Reminder Threshold )      │
│                                                                      │
│  VO: "Inventory. Two bottles on hand. Refill in fourteen days."      │
└──────────────────────────────────────────────────────────────────────┘
```

### Inventory Status Indicators
```
🟢 Good stock (>30 days)      🟡 Low stock (15-30 days)      
🔴 Critical (<15 days)        ⚠️ Empty (0 days)
```

### Log Refill Flow
```
┌──────────────────────────────────────────────────────────────────────┐
│  Log New Refill                                                     │
│                                                                      │
│  Medication        { XYWAV }                                         │
│  Bottles received  [ 3 ]                                             │
│  Pickup date       [ Today ▾ ]                                       │
│  Pharmacy          [ Central Pharmacy ] (Optional)                   │
│  Prescription #    [ RX123456 ] (Optional)                           │
│                                                                      │
│  New total: 5 bottles (~67 days remaining)                           │
│                                                                      │
│  [ Save Refill ]           ( Cancel )                                │
│  VO: "Log new refill. Save refill."                                  │
└──────────────────────────────────────────────────────────────────────┘
```

## Time Zone & Travel Support

### Time Zone Change Detection
```
┌──────────────────────────────────────────────────────────────────────┐
│  Time Zone Changed                                                   │
│  We detected { Europe/Paris }. Recalculate tonight's window?         │
│                                                                      │
│  Current schedule: 01:00 AM → 165m window                            │
│  New timezone:     07:00 AM → 165m window                            │
│                                                                      │
│  ( Keep current schedule )     [ Recalculate & Reschedule ]          │
│                                                                      │
│  VO: "Time zone changed. Recalculate and reschedule."                │
└──────────────────────────────────────────────────────────────────────┘
```

### Travel Mode Confirmation
```
┌──────────────────────────────────────────────────────────────────────┐
│  Travel Mode Active                                                  │
│                                                                      │
│  Your schedule has been adjusted for:                                │
│  📍 Paris, France (UTC+1)                                           │
│                                                                      │
│  Tonight's window: 07:00 AM → 09:45 AM (165m)                        │
│  Notifications rescheduled ✓                                        │
│                                                                      │
│  [ Continue ]        ( Manual Adjustment )                           │
│  VO: "Travel mode active. Schedule adjusted for Paris, France."      │
└──────────────────────────────────────────────────────────────────────┘
```

## Support & Diagnostics

### Support Bundle Export
```
┌──────────────────────────────────────────────────────────────────────┐
│  Support & Diagnostics                                               │
│                                                                      │
│  [ Export Support Bundle ]  →  events.csv, inventory.csv, logs.txt    │
│  ( View Privacy Policy )   ( Contact Support )                        │
│                                                                      │
│  Bundle contents (privacy-safe):                                     │
│  • Event timing patterns (no personal notes)                        │
│  • App performance data                                             │
│  • Error logs (no identifiers)                                      │
│                                                                      │
│  VO: "Export Support Bundle. Creates a zip without personal data."   │
└──────────────────────────────────────────────────────────────────────┘
```

### Bundle Generation Progress
```
┌──────────────────────────────────────────────────────────────────────┐
│  Generating Support Bundle                                           │
│                                                                      │
│  ▓▓▓▓▓▓▓▓░░░░  60%                                                   │
│                                                                      │
│  ✓ Anonymizing event data                                           │
│  ✓ Filtering debug logs                                             │
│  → Creating ZIP archive                                             │
│    Calculating bundle size                                          │
│                                                                      │
│  VO: "Generating support bundle. Sixty percent complete."            │
└──────────────────────────────────────────────────────────────────────┘
```

## Settings Enhancements

### Enhanced Settings Layout
```
┌──────────────────────────────────────────────────────────────────────┐
│  Settings                                                            │
│                                                                      │
│  Sync & Backup                                                      │
│    Sync with iCloud     [ OFF ]  (Private iCloud only)              │
│    Data retention       [ 1 year ▾ ]                                │
│                                                                      │
│  Medication & Inventory                                              │
│    Medication profile   [ XYWAV → ]                                  │
│    Inventory tracking   [ ON ]                                       │
│    Refill reminders     [ 10 days ▾ ]                                │
│                                                                      │
│  Notifications & Alerts                                              │
│    Dose reminders       [ ON ]                                       │
│    Critical alerts      [ Enabled ]                                  │
│    Auto-snooze         [ ON ]                                        │
│                                                                      │
│  Travel & Time Zones                                                 │
│    Auto-detect changes  [ ON ]                                       │
│    Current timezone     { America/New_York }                         │
│                                                                      │
│  Support & Privacy                                                   │
│    Export support bundle  [ → ]                                      │
│    Privacy policy         [ → ]                                      │
│    About & version        [ → ]                                      │
│                                                                      │
│  [ Done ]                                                            │
│  VO: "Settings. Done."                                               │
└──────────────────────────────────────────────────────────────────────┘
```

## Usage Guidelines

### Status Indicators
- 🟢 Green: Normal/Good state
- 🟡 Yellow: Warning/Attention needed  
- 🔴 Red: Critical/Urgent action required
- ⚠️ Warning: System alert/Important notice

### Button Hierarchy
- `[ Primary Action ]` - Main call-to-action (filled button)
- `( Secondary Action )` - Secondary option (outlined button)
- `→` - Navigation/Disclosure indicator
- `▾` - Dropdown/Picker indicator

### VoiceOver Patterns
- State first: "Critical alert. [content]"
- Action last: "[content]. Take Now."
- Progress indicators: "[task]. [percentage] complete."
- Navigation: "[screen name]. [exit action]."

### Responsive Behavior
- Layouts adapt to text size increases
- Maintains minimum touch targets (44pt)
- Preserves critical information at all sizes
- Graceful degradation for extreme zoom levels
