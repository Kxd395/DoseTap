# DoseTap - XYWAV Dose Timing App

A focused iOS app for XYWAV dose timing with persistent event logging and comprehensive dose history tracking.

## Current Status: ✅ FUNCTIONAL APP DEPLOYED

DoseTap is now a **fully functional iOS application** with persistent data storage, ready for daily use.

## Core Features (Implemented)

### 📱 Essential Dose Logging
- **Three-button interface:** Dose 1, Dose 2, Bathroom Event
- **Instant timestamps:** Automatic time/date capture for each event
- **Persistent storage:** JSON-based data that survives app restarts
- **Event history:** Complete timeline of all logged events

### 🌙 Night-Optimized Design
- **Dark theme interface** optimized for nighttime use
- **Large, accessible buttons** for easy 3 AM operation
- **Clear feedback system** with immediate confirmation
- **Minimal cognitive load** design for sleep-impaired states

### 💾 Reliable Data Management
- **JSON file storage** in iOS Documents directory
- **Human-readable format** for data transparency
- **Automatic persistence** with every event logged
- **Data accessibility** through Settings panel

### 📊 Comprehensive Tracking
- **Event timeline display** with precise timestamps
- **Storage location visibility** for data management
- **Event counter** showing total logged events
- **Export-ready format** for future analysis

## Technical Implementation

### Current Architecture

```text
DoseTap iOS App
├── ContentView.swift          # Main UI with dose logging buttons
├── EventStorage.swift         # JSON persistence layer  
├── DoseTapApp.swift          # SwiftUI app entry point
└── Supporting Files/          # Assets and configuration
```

### Data Storage

**Format:** JSON file in iOS Documents directory
**Location:** `dose_events.json` (accessible via Settings)
**Structure:**

```json
[
  {
    "id": "UUID-string",
    "type": "dose1|dose2|bathroom",
    "timestamp": "2024-01-15T03:30:00Z"
  }
]
```

### Event Types

- **Dose 1:** First nightly dose logging
- **Dose 2:** Second dose (optimal window: 2.5-4h later)  
- **Bathroom:** Bathroom visit tracking for sleep disruption analysis

## Getting Started

### Prerequisites

- **iOS Device:** iPhone or iPad running iOS 15+
- **Xcode:** Version 14+ for building from source
- **Apple Developer Account:** For device installation

### Installation

1. **Clone Repository:**

   ```bash
   git clone https://github.com/yourusername/DoseTap.git
   cd DoseTap/ios
   ```

2. **Open in Xcode:**

   ```bash
   open DoseTap.xcodeproj
   ```

3. **Build and Run:**
   - Select your target device
   - Press ⌘+R to build and install

### First Use

1. **Launch App:** Tap DoseTap icon
2. **Log First Event:** Tap "Dose 1" when taking first dose
3. **View History:** Use History button to see logged events
4. **Check Settings:** Settings panel shows storage location and event count

## Usage

### Daily Workflow

1. **Before Sleep:** Take Dose 1, tap "Dose 1" button
2. **Middle of Night:** Take Dose 2, tap "Dose 2" button  
3. **As Needed:** Log bathroom visits with "Bathroom" button
4. **Review History:** Check timeline for adherence tracking

### Data Management

- **View Events:** History screen shows all logged events
- **Storage Info:** Settings panel displays file location
- **Data Access:** JSON file accessible via iOS Files app
- **Export Ready:** Human-readable format for future analysis

## Privacy & Security

- **Local Storage Only:** All data remains on your device
- **No Cloud Sync:** No automatic data transmission
- **User Control:** Data accessible and exportable by user
- **Medical Privacy:** Compliant with personal health data practices

## Future Enhancements

### Planned Features

- **Dose Window Timing:** 2.5-4 hour optimal window calculations
- **Smart Notifications:** Local reminders for dose timing
- **Advanced Analytics:** Adherence tracking and pattern analysis
- **WatchOS Support:** Apple Watch companion app

### Integration Possibilities

- **HealthKit:** Sleep stage data for optimal timing
- **CSV Export:** Data export for self-analysis
- **Universal App:** iPad and Mac support

## Support

### Medical Disclaimer

This app is a timing aid only and does not provide medical advice. For questions about XYWAV dosing, consult your healthcare provider.

### Technical Support

- **Issues:** GitHub Issues for bug reports
- **Features:** Feature requests welcome
- **Privacy:** No personal data collected or transmitted

## License

Proprietary - For personal/research use only
```

Notes: If these endpoints aren’t set or respond with a different shape, the app falls back to a best‑effort parser. Units are normalized to bpm, breaths/min, SpO₂ 0–1, and HRV ms (use `value_scale` to adjust if an API returns percent).

## Disclaimers

- This is an assistive logging/reminder tool—not medical advice.
- Keep the Flic app running; do **not** force-quit (it maintains the BLE connection).
