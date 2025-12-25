# DoseTap - Product Requirements Document (PRD)

**Version:** 2.1.0  
**Last Updated:** December 23, 2025  
**Status:** Active Development (Phase 2)  
**Owner:** DoseTap Team

---

## 1. Executive Summary

### 1.1 Product Vision
DoseTap is a purpose-built iOS and watchOS application designed to help patients manage the precise timing requirements of XYWAV (sodium oxybate) medication. The app ensures medication safety by enforcing the critical 150-240 minute window between Dose 1 and Dose 2.

### 1.2 Problem Statement
XYWAV patients must take two doses nightly with strict timing constraints:
- Dose 2 must occur 150-240 minutes after Dose 1
- Patients are often drowsy/asleep when Dose 2 is needed
- Missing the window requires skipping Dose 2 entirely
- Manual tracking is error-prone and unreliable

### 1.3 Solution
DoseTap provides:
- **Intelligent Timing**: Automatic window calculation and countdown
- **Reliable Alerts**: Notifications that cut through Do Not Disturb
- **Multi-Device Access**: iPhone, Apple Watch, and Flic button support
- **Safety Guardrails**: Prevents invalid dose configurations
- **Offline-First**: Works without internet connectivity
- **Sleep Tracking**: 13 event types for correlating sleep quality (v2.4.1)
- **Health Integration**: Apple HealthKit + WHOOP data aggregation (v2.4.1)

### 1.4 Core Timing Parameters (AUTHORITATIVE)

| Parameter | Value | Description |
|-----------|-------|-------------|
| **Window Opens** | 150 min | Earliest Dose 2 can be taken |
| **Window Closes** | 240 min | Latest Dose 2 (hard limit) |
| **Default Target** | 165 min | Recommended timing |
| **Valid Targets** | 165, 180, 195, 210, 225 | User selectable |
| **Snooze Duration** | 10 min | Fixed increment |
| **Max Snoozes** | 3 | Per night session |
| **Snooze Disabled** | <15 min | Safety cutoff |
| **Undo Window** | 5 sec | For accidental taps |

### 1.5 Success Metrics
| Metric | Target | Measurement |
|--------|--------|-------------|
| Dose 2 On-Time Rate | ≥95% | Within ±10min of target |
| Window Compliance | 100% | Never exceed 240min |
| App Crash Rate | <0.1% | Crash-free sessions |
| User Retention | ≥90% | 30-day active users |
| Notification Response | <5min | Alert to dose action |
| Sleep Event Logging | ≥3/night | User engagement |

---

## 2. Target Users

### 2.1 Primary Persona: The XYWAV Patient
**Demographics:**
- Adults 18+ diagnosed with narcolepsy or idiopathic hypersomnia
- Prescribed XYWAV medication (sodium oxybate)
- iPhone/Apple Watch users
- May have cognitive impairment due to condition

**Needs:**
- Reliable wake-up assistance for Dose 2
- Simple one-tap dose logging
- Peace of mind about timing safety
- Historical data for provider discussions

**Pain Points:**
- Grogginess when waking for Dose 2
- Anxiety about missing the dose window
- Difficulty remembering if dose was taken
- Tracking manually is cumbersome

### 2.2 Secondary Persona: The Caregiver
- Family member or partner who assists with medication
- Needs visibility into dose status
- May help physically administer medication
- Wants alerts if patient misses window

---

## 3. Product Scope

### 3.1 In Scope (v1.x)
| Feature | Priority | Status |
|---------|----------|--------|
| Tonight Dashboard | P0 | ✅ Complete |
| Dose 1/Dose 2 Logging | P0 | ✅ Complete |
| Window Countdown Timer | P0 | ✅ Complete |
| Push Notifications | P0 | ✅ Complete |
| watchOS Companion | P0 | ✅ Complete |
| 5-Second Undo | P0 | ✅ Complete |
| Snooze (10min, max 3) | P1 | ✅ Complete |
| Skip Dose with Reason | P1 | ✅ Complete |
| Timeline History | P1 | ✅ Complete |
| CSV Export | P1 | ✅ Complete |
| First-Run Setup Wizard | P1 | ✅ Complete |
| Flic Button Support | P2 | 🔄 In Progress |
| Inventory Management | P2 | 🔄 In Progress |
| Insights Analytics | P2 | 📋 Planned |
| WHOOP Integration | P3 | 📋 Planned |

### 3.2 Out of Scope
- Multi-medication tracking
- Pharmacy/refill integration
- Provider portal or data sharing
- Telehealth features
- Health insurance integration
- Controlled substance reporting
- Non-XYWAV medications

### 3.3 Technical Constraints
- iOS 16.0+ / watchOS 9.0+ minimum
- Swift 5.9 / SwiftUI
- Local-first architecture (no required backend)
- SQLite for persistence (via EventStorage.swift)
- Optional iCloud sync (disabled by default)

---

## 4. Functional Requirements

### 4.1 Core Dose Timing (P0)

#### FR-001: Dose 1 Recording
- **Description**: User can log taking Dose 1 with one tap
- **Acceptance Criteria**:
  - Single tap on "Take Dose 1" button logs event
  - Timestamp recorded in UTC
  - Window countdown begins immediately
  - 5-second undo available
  - Works offline with queue indicator

#### FR-002: Dose 2 Window Calculation
- **Description**: System calculates valid window for Dose 2
- **Acceptance Criteria**:
  - Window opens at Dose 1 + 150 minutes
  - Window closes at Dose 1 + 240 minutes
  - Default target is Dose 1 + 165 minutes
  - Target configurable: 165, 180, 195, 210, or 225 minutes

#### FR-003: Dose 2 Recording
- **Description**: User can log taking Dose 2 within valid window
- **Acceptance Criteria**:
  - Button enabled only within window (150-240min)
  - Single tap logs event with timestamp
  - Night session marked complete
  - 5-second undo available
  - Blocked before window opens
  - Blocked after window closes

#### FR-004: Skip Dose 2
- **Description**: User can skip Dose 2 with optional reason
- **Acceptance Criteria**:
  - Available after window opens
  - Optional reason selection (drowsy, side effects, other)
  - Night session marked as skipped
  - Cannot be undone after 5 seconds

#### FR-005: Snooze Function
- **Description**: Delay Dose 2 alert by 10 minutes
- **Acceptance Criteria**:
  - Fixed 10-minute delay
  - Maximum 3 snoozes per night
  - Disabled when <15 minutes remain
  - Counter shows snoozes remaining
  - Resets with new night session

### 4.2 Notifications (P0)

#### FR-010: Window Opening Alert
- **Description**: Notify user when Dose 2 window opens
- **Acceptance Criteria**:
  - Push notification at 150 minutes
  - Sound + vibration
  - Actionable: Take Now, Snooze, Skip
  - Works in Do Not Disturb (critical alert)

#### FR-011: Target Time Alert
- **Description**: Alert at user's target time
- **Acceptance Criteria**:
  - Push notification at target (default 165min)
  - Escalating urgency indicator
  - Shows time remaining in window

#### FR-012: Window Closing Alerts
- **Description**: Increasing urgency as window closes
- **Acceptance Criteria**:
  - Alerts at: 30min, 15min, 5min, 1min remaining
  - Visual urgency escalation (yellow → red)
  - Sound escalation optional
  - Final alert at window close

### 4.3 watchOS Companion (P0)

#### FR-020: Watch Dashboard
- **Description**: Simplified dose interface on Apple Watch
- **Acceptance Criteria**:
  - Shows current state (waiting, window open, complete)
  - Large tap targets for dose buttons
  - Countdown timer display
  - Haptic feedback for all actions

#### FR-021: Watch Complications
- **Description**: Glanceable status on watch face
- **Acceptance Criteria**:
  - Circular: countdown or checkmark
  - Modular: time remaining + state
  - Updates within 1 minute

#### FR-022: Watch-Phone Sync
- **Description**: Bidirectional state synchronization
- **Acceptance Criteria**:
  - Actions on watch sync to phone
  - Actions on phone sync to watch
  - Offline indicator when disconnected
  - Conflict resolution (latest wins)

### 4.4 Data & History (P1)

#### FR-030: Timeline View
- **Description**: Historical view of dose events
- **Acceptance Criteria**:
  - Chronological list of all events
  - Filter by week/month/all time
  - Shows: dose times, intervals, adherence
  - Offline events clearly marked

#### FR-031: CSV Export
- **Description**: Export dose history for sharing
- **Acceptance Criteria**:
  - Standard CSV format
  - Includes: date, dose1 time, dose2 time, interval
  - Configurable date range
  - iOS share sheet integration

#### FR-032: Data Persistence
- **Description**: Reliable local storage
- **Acceptance Criteria**:
  - SQLite database (via EventStorage.swift)
  - Survives app updates
  - Survives device restarts
  - Migration from legacy JSON format

### 4.5 User Configuration (P1)

#### FR-040: First-Run Setup Wizard
- **Description**: Guided onboarding for new users
- **Acceptance Criteria**:
  - 5-step wizard: Sleep, Medication, Window, Notifications, Privacy
  - Cannot access main app until complete
  - Can re-run from Settings
  - Validates all inputs

#### FR-041: Target Interval Setting
- **Description**: User configures preferred Dose 2 timing
- **Acceptance Criteria**:
  - Options: 165, 180, 195, 210, 225 minutes
  - Default: 165 minutes
  - Explains safety implications
  - Requires confirmation for changes

#### FR-042: Notification Preferences
- **Description**: User controls alert behavior
- **Acceptance Criteria**:
  - Enable/disable each alert type
  - Sound selection
  - Haptics toggle
  - Critical alerts toggle (requires permission)

---

## 5. Non-Functional Requirements

### 5.1 Performance
| Metric | Requirement |
|--------|-------------|
| App Launch | <2 seconds cold start |
| Button Response | <100ms tap feedback |
| Notification Delivery | <5 seconds from trigger |
| Watch Sync | <30 seconds |
| Timeline Load | <1 second for 1000 events |

### 5.2 Reliability
- 99.9% uptime for core dose logging
- Zero data loss (local persistence)
- Graceful degradation without network
- Automatic retry for failed syncs

### 5.3 Security & Privacy
- No personal health data leaves device by default
- No account/login required
- Optional anonymized analytics
- HIPAA-conscious design (not certified)
- No third-party tracking

### 5.4 Accessibility
- WCAG 2.1 AA compliance minimum
- Full VoiceOver support
- Dynamic Type support (up to XXL)
- Minimum 48pt touch targets
- High contrast mode support
- Reduced motion support

### 5.5 Battery Impact
- <5% battery per night on iPhone
- <5% battery per night on Apple Watch
- No background refresh abuse
- Minimal location services (timezone only)

---

## 6. User Interface Requirements

### 6.1 Design Principles
1. **Sleep-Safe**: High contrast, large text, works in dark room
2. **One-Tap Actions**: Primary actions need single tap
3. **Error Prevention**: Impossible to take invalid dose
4. **Calm Technology**: Not anxiety-inducing
5. **Glanceable**: Status visible at a glance

### 6.2 Screen Inventory
| Screen | Purpose | Priority |
|--------|---------|----------|
| Tonight | Primary dose dashboard | P0 |
| Timeline | Historical events | P1 |
| Insights | Analytics & trends | P2 |
| Devices | Flic/accessories | P2 |
| Settings | Configuration | P1 |
| Setup Wizard | Onboarding | P1 |
| Inventory | Medication supply | P2 |

### 6.3 Visual States
```
Tonight Screen States:
├── IDLE: No doses tonight, Dose 1 button active
├── DOSE1_TAKEN: Waiting for window, countdown shows
├── WINDOW_ACTIVE: Dose 2 button active, countdown critical
├── WINDOW_NEAR: <15 min remain, snooze disabled, urgent
├── DOSE2_TAKEN: Complete, checkmark, session summary
├── DOSE2_SKIPPED: Complete, skip noted
└── WINDOW_EXPIRED: Session failed, skip recorded
```

---

## 7. Technical Architecture

### 7.1 Module Structure
```
DoseTap/
├── DoseCore/          # Platform-independent logic (SwiftPM)
│   ├── DoseWindowState    # Window calculation
│   ├── APIClient          # Network layer
│   ├── OfflineQueue       # Offline resilience
│   └── EventRateLimiter   # Debouncing
├── DoseTap/           # iOS app target
│   ├── Views/             # SwiftUI screens
│   ├── Storage/           # SQLite (EventStorage)
│   └── Services/          # Notifications, sync
└── DoseTapWatch/      # watchOS app target
```

### 7.2 Data Flow
```
User Action → ViewModel → DoseCore → Persistence
                ↓
            API Client → OfflineQueue (if offline)
                ↓
            Notification Service
                ↓
            Watch Sync
```

### 7.3 Offline Architecture
1. All actions write to SQLite first
2. Actions queued for API sync
3. Queue retries with exponential backoff
4. Conflict resolution: latest timestamp wins
5. Offline indicator shows pending actions

---

## 8. Release Plan

### 8.1 MVP (v1.0) - Shipped
- Tonight dashboard with dose tracking
- Push notifications
- watchOS companion
- Basic timeline
- Setup wizard

### 8.2 v1.1 - Current
- ✅ Enhanced setup wizard
- ✅ User configuration management
- 🔄 Inventory management
- 🔄 Support bundle export

### 8.3 v1.2 - Planned
- Flic button integration
- Insights dashboard
- WHOOP data import
- Improved analytics

### 8.4 v2.0 - Future
- macOS companion (DoseTap Studio)
- Advanced sleep analytics
- Provider report generation
- CarPlay glance (stretch)

---

## 9. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Notification failure | Medium | High | Critical alerts, redundant methods |
| Data loss | Low | Critical | SQLite + backup export |
| User misses dose | Medium | High | Escalating alerts, watch backup |
| App crash during dose | Low | High | Crash recovery, auto-restore |
| Watch disconnection | Medium | Medium | Offline mode, phone fallback |

---

## 10. Open Questions

1. **Caregiver Mode**: Should we add multi-user support for caregivers?
2. **HealthKit Integration**: Import sleep data from Apple Health?
3. **Siri Shortcuts**: "Hey Siri, I took my dose"?
4. **iPad Support**: Native iPad layout?
5. **Localization**: Which languages for initial launch?

---

## Appendix A: Competitive Analysis

| Feature | DoseTap | Medisafe | Round Health |
|---------|---------|----------|--------------|
| XYWAV-specific | ✅ | ❌ | ❌ |
| Dose window timing | ✅ | ❌ | ❌ |
| watchOS app | ✅ | ❌ | ✅ |
| Offline-first | ✅ | ❌ | ❌ |
| No account required | ✅ | ❌ | ❌ |
| Free | ✅ | Freemium | Freemium |

---

## Appendix B: Regulatory Considerations

DoseTap is a **medication reminder** application, NOT a medical device:
- Does not diagnose, treat, or cure
- Does not calculate dosages
- Does not dispense medication
- User enters their own prescribed schedule

FDA classification: General wellness / medication reminder (exempt)

---

*Document maintained by DoseTap Product Team*
*Last review: December 23, 2025*
