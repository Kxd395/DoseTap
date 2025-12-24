# DoseTap - Use Cases

> **Complete User Workflow Documentation**

---

## Table of Contents

1. [Nightly Dose Workflow](#1-nightly-dose-workflow)
2. [First-Time Setup](#2-first-time-setup)
3. [watchOS Workflows](#3-watchos-workflows)
4. [Notification Interactions](#4-notification-interactions)
5. [Error Recovery](#5-error-recovery)
6. [Data Management](#6-data-management)
7. [Flic Button Workflows](#7-flic-button-workflows)
8. [Edge Cases](#8-edge-cases)

---

## 1. Nightly Dose Workflow

### UC-1.1: Standard Night (Happy Path)

**Actor:** XYWAV Patient  
**Precondition:** App installed, setup complete, no doses taken tonight  
**Trigger:** User ready to take Dose 1 at bedtime

**Main Flow:**

```
1. User opens DoseTap app
2. System displays Tonight screen with "Take Dose 1" button active
3. User takes physical Dose 1 medication
4. User taps "Take Dose 1" button
5. System records event with timestamp
6. System displays 5-second undo option
7. System starts countdown to dose window (150 minutes)
8. System schedules notifications for window events
9. User goes to sleep
   
   ... 150 minutes pass ...

10. System sends "Dose window now open" notification
11. User wakes, sees notification
12. User opens app (or taps notification action)
13. System displays Tonight screen with:
    - "Dose 1 taken at 10:30 PM" 
    - Countdown: "90 minutes remaining"
    - "Take Dose 2" button active
14. User takes physical Dose 2 medication
15. User taps "Take Dose 2" button
16. System records event with timestamp
17. System displays completion summary
18. System cancels remaining notifications
19. User returns to sleep
```

**Postcondition:** Both doses recorded, night session complete

**Success Metrics:**
- Dose 2 taken within window (150-240 min)
- Total interaction time < 30 seconds

---

### UC-1.2: Snooze Flow

**Actor:** XYWAV Patient  
**Precondition:** Dose 1 taken, dose window is open, >15 minutes remain  
**Trigger:** User receives alert but wants more sleep

**Main Flow:**

```
1. System sends notification at target time (e.g., 165 minutes)
2. User wakes but feels too groggy
3. User taps "Snooze" action (from notification or app)
4. System validates: snooze_count < 3 AND remaining > 15min
5. System adds 10 minutes to reminder
6. System displays: "Snoozed. Next reminder in 10 min. (1/3 used)"
7. System reschedules notification
8. User sleeps 10 more minutes
9. System sends new notification
10. User wakes, takes Dose 2
```

**Alternative Flow - Snooze Limit Reached:**

```
4a. System detects snooze_count = 3
5a. System displays: "Maximum snoozes reached. Take dose or skip."
6a. Snooze button disabled
7a. User must Take or Skip
```

**Alternative Flow - Near Window Close:**

```
4b. System detects remaining < 15 minutes
5b. System displays: "Cannot snooze. Less than 15 minutes remain."
6b. Snooze button disabled
7b. User must Take or Skip immediately
```

---

### UC-1.3: Skip Dose 2

**Actor:** XYWAV Patient  
**Precondition:** Dose 1 taken, dose window open or expired  
**Trigger:** User decides not to take Dose 2

**Main Flow:**

```
1. User taps "Skip Dose 2" button
2. System displays reason picker:
   - "Feeling alert enough"
   - "Side effects"
   - "Other reason"
3. User selects reason (optional)
4. System displays confirmation: "Skip Dose 2?"
5. User confirms
6. System records skip event with reason
7. System marks night session as skipped
8. System cancels remaining notifications
9. System displays: "Dose 2 skipped. Night complete."
```

**Business Rule:** Skipped doses count as missed for adherence metrics

---

### UC-1.4: Undo Accidental Dose

**Actor:** XYWAV Patient  
**Precondition:** Dose action taken within last 5 seconds  
**Trigger:** User accidentally tapped wrong button

**Main Flow:**

```
1. User taps "Take Dose 1" (or Dose 2) accidentally
2. System records event
3. System displays undo banner with 5-second countdown:
   "Dose 1 recorded. [UNDO - 5s]"
4. User taps "UNDO" within 5 seconds
5. System removes recorded event
6. System restores previous state
7. System displays: "Dose 1 undone"
```

**Alternative Flow - Timeout:**

```
4a. 5 seconds pass without undo tap
5a. System hides undo option
6a. Event becomes permanent
7a. User must contact support for manual correction
```

---

## 2. First-Time Setup

### UC-2.1: New User Onboarding

**Actor:** New XYWAV Patient  
**Precondition:** App just installed, first launch  
**Trigger:** User opens app for first time

**Main Flow:**

```
Step 1: Welcome
1. System displays welcome screen with app overview
2. User taps "Get Started"

Step 2: Sleep Schedule
3. System asks for typical bedtime
4. User selects time (picker, default 10:30 PM)
5. System asks for typical wake time
6. User selects time (picker, default 6:30 AM)

Step 3: Medication Profile
7. System displays XYWAV-specific information
8. User confirms they take XYWAV (toggle)
9. System displays dose amount options
10. User selects Dose 1 amount (g)
11. User selects Dose 2 amount (g)

Step 4: Dose Window Configuration
12. System explains 150-240 minute window
13. System displays target time options:
    - 2h 45m (165 min) - Recommended
    - 3h 00m (180 min)
    - 3h 15m (195 min)
    - 3h 30m (210 min)
    - 3h 45m (225 min)
14. User selects preferred target

Step 5: Notifications
15. System requests notification permission
16. User grants permission (or skips)
17. System explains critical alerts
18. User enables/disables critical alerts

Step 6: Privacy
19. System displays privacy commitment
20. User acknowledges data practices
21. User enables/disables anonymous analytics

Step 7: Complete
22. System marks setup complete
23. System displays Tonight screen
24. User is ready to use app
```

**Postcondition:** User configuration saved, main app accessible

---

### UC-2.2: Reconfigure Settings

**Actor:** Existing User  
**Precondition:** Setup previously completed  
**Trigger:** User wants to change configuration

**Main Flow:**

```
1. User opens Settings screen
2. User taps "Reconfigure Setup"
3. System displays warning: "This will restart the setup wizard"
4. User confirms
5. System launches setup wizard at Step 1
6. User completes wizard with new preferences
7. System updates configuration
8. System returns to Tonight screen
```

---

## 3. watchOS Workflows

### UC-3.1: Take Dose from Watch

**Actor:** XYWAV Patient wearing Apple Watch  
**Precondition:** Watch app installed, paired with iPhone  
**Trigger:** User wants to log dose without reaching for phone

**Main Flow:**

```
1. User raises wrist to wake watch
2. User opens DoseTap complication or app
3. Watch displays current state:
   - "Take Dose 1" button (if no dose tonight)
   - OR countdown + "Take Dose 2" button (if in window)
4. User taps appropriate dose button
5. Watch displays haptic confirmation
6. Watch syncs event to iPhone
7. Watch displays completion checkmark
```

**Alternative Flow - Phone Unreachable:**

```
5a. Watch cannot reach iPhone
6a. Watch records event locally
7a. Watch displays: "Offline - will sync"
8a. Watch icon shows offline indicator
9a. When phone reconnects, events sync automatically
```

---

### UC-3.2: Glance at Complication

**Actor:** XYWAV Patient  
**Precondition:** Complication added to watch face  
**Trigger:** User glances at watch

**Main Flow:**

```
1. User looks at watch face
2. Complication displays current state:
   - Circular: Checkmark (complete) / Timer (waiting) / "!" (action needed)
   - Modular: "2h 15m" remaining / "Take Now" / "✓ Done"
3. User glances and understands status without interaction
```

---

## 4. Notification Interactions

### UC-4.1: Actionable Notification

**Actor:** XYWAV Patient  
**Precondition:** Dose window open, notification received  
**Trigger:** Push notification appears

**Main Flow:**

```
1. System sends notification: "Time for Dose 2"
2. Device displays notification with actions
3. User sees notification (on lock screen or banner)
4. User long-presses or expands notification
5. User sees action buttons:
   - "Take Now"
   - "Snooze 10min"
   - "Skip"
6. User taps "Take Now"
7. System records dose without opening app
8. System displays confirmation: "Dose 2 recorded"
```

**Alternative Flow - Tap to Open:**

```
6a. User taps notification body (not action)
7a. System opens DoseTap app
8a. System displays Tonight screen
9a. User taps button in app
```

---

### UC-4.2: Critical Alert

**Actor:** XYWAV Patient with critical alerts enabled  
**Precondition:** Dose window ending soon (<15 min)  
**Trigger:** Urgent action needed

**Main Flow:**

```
1. System detects <15 minutes remaining in window
2. System sends critical alert (bypasses DND/silent)
3. Device plays sound even if muted
4. Notification displays: "⚠️ URGENT: 10 min to take Dose 2"
5. User wakes from sleep
6. User takes action
```

---

## 5. Error Recovery

### UC-5.1: Offline Mode

**Actor:** XYWAV Patient without internet  
**Precondition:** Device offline  
**Trigger:** User takes dose while offline

**Main Flow:**

```
1. User taps "Take Dose" button
2. System detects no network connection
3. System records event locally
4. System displays: "Saved offline ☁️"
5. System adds event to sync queue
6. UI shows offline indicator badge
   
   ... later, when network restores ...
   
7. System detects connectivity
8. System syncs queued events to server
9. System removes offline indicator
10. System displays: "All synced ✓"
```

---

### UC-5.2: Window Expired

**Actor:** XYWAV Patient who slept through window  
**Precondition:** Dose 1 taken, 240+ minutes have passed  
**Trigger:** User opens app after window close

**Main Flow:**

```
1. User opens app
2. System detects window expired
3. System displays:
   - "Dose 2 window has closed"
   - "Window closed at 2:30 AM"
   - "This dose has been marked as skipped"
4. System automatically records skip event
5. System displays night summary
6. System prepares for next night
```

---

### UC-5.3: App Crash Recovery

**Actor:** XYWAV Patient  
**Precondition:** App crashed mid-action  
**Trigger:** User reopens app after crash

**Main Flow:**

```
1. User opens app after unexpected close
2. System checks for interrupted state
3. System restores last known state from Core Data
4. System validates dose events integrity
5. System resumes countdown if applicable
6. System displays current state
7. User continues as normal
```

---

## 6. Data Management

### UC-6.1: Export History

**Actor:** XYWAV Patient  
**Precondition:** Has dose history to export  
**Trigger:** User wants to share data with provider

**Main Flow:**

```
1. User navigates to Timeline screen
2. User taps "Export" button
3. System displays export options:
   - Date range: Last 30 days / 90 days / All time / Custom
   - Format: CSV
4. User selects options
5. User taps "Generate Export"
6. System creates CSV file with:
   - Date, Dose1Time, Dose2Time, Interval, OnTime, Skipped
7. System displays iOS share sheet
8. User shares via email, AirDrop, Files, etc.
```

---

### UC-6.2: Clear All Data

**Actor:** XYWAV Patient  
**Precondition:** User wants fresh start  
**Trigger:** User initiates data deletion

**Main Flow:**

```
1. User opens Settings
2. User taps "Clear All Data"
3. System displays warning:
   "This will permanently delete:
    - All dose history
    - All settings
    - All exported data references
    This cannot be undone."
4. User taps "I Understand, Delete"
5. System requires confirmation:
   "Type DELETE to confirm"
6. User types "DELETE"
7. System wipes all Core Data entities
8. System resets UserDefaults
9. System displays setup wizard
```

---

## 7. Flic Button Workflows

### UC-7.1: Pair Flic Button

**Actor:** XYWAV Patient with Flic button  
**Precondition:** Flic button available, unpaired  
**Trigger:** User wants to set up physical button

**Main Flow:**

```
1. User navigates to Devices screen
2. User taps "Add Flic Button"
3. System enables Bluetooth scanning
4. User puts Flic button in pairing mode
5. System discovers button
6. System displays: "Flic Button found"
7. User taps "Pair"
8. System establishes connection
9. System configures button actions:
   - Single press: Take next dose
   - Double press: Snooze
   - Long press: Undo
10. System displays: "Flic ready!"
11. User can test with "Test Button" option
```

---

### UC-7.2: Use Flic Button at Night

**Actor:** XYWAV Patient with paired Flic  
**Precondition:** Flic paired, dose window open  
**Trigger:** User presses Flic to take dose

**Main Flow:**

```
1. User wakes to notification
2. User reaches for Flic button (no screen needed)
3. User presses Flic once
4. Flic sends signal to iPhone
5. DoseTap receives button event
6. System determines appropriate action (Dose 2 if in window)
7. System records dose event
8. iPhone plays success sound
9. User returns to sleep without looking at screen
```

---

## 8. Edge Cases

### UC-8.1: Time Zone Change

**Actor:** Traveling XYWAV Patient  
**Precondition:** Dose 1 taken, user crosses time zones  
**Trigger:** Device time changes

**Main Flow:**

```
1. System detects time zone change
2. System logs system event
3. System recalculates window times in new zone
4. System displays interstitial:
   "Time Zone Changed
    From: EST (New York)
    To: PST (Los Angeles)
    
    Your dose window has been adjusted.
    Window now closes at: 11:30 PM PST"
5. User acknowledges
6. System updates all notifications
7. System continues tracking in new zone
```

---

### UC-8.2: Daylight Saving Time

**Actor:** XYWAV Patient  
**Precondition:** Dose 1 taken before DST change  
**Trigger:** Clock springs forward or falls back

**Main Flow:**

```
1. System detects DST transition
2. System calculates elapsed time (uses UTC internally)
3. Window timing remains accurate:
   - If 150 minutes elapsed in real time = window opens
   - Display times update to new local time
4. System notifies user of display time change
5. Safety window (150-240 min) preserved
```

---

### UC-8.3: Dose 1 Close to Midnight

**Actor:** XYWAV Patient with late bedtime  
**Precondition:** User takes Dose 1 at 11:30 PM  
**Trigger:** Dose window spans midnight

**Main Flow:**

```
1. User takes Dose 1 at 11:30 PM (Dec 23)
2. System calculates window:
   - Opens: 2:00 AM Dec 24
   - Closes: 3:30 AM Dec 24
3. System correctly handles date boundary
4. Timeline shows both doses on correct dates
5. Session groups both doses together
```

---

### UC-8.4: Battery Dies Mid-Night

**Actor:** XYWAV Patient  
**Precondition:** Dose 1 taken, then phone dies  
**Trigger:** Phone powers back on

**Main Flow:**

```
1. Phone dies at 1:00 AM
2. User wakes, plugs in phone
3. Phone powers on at 3:00 AM
4. DoseTap launches (or receives notification trigger)
5. System checks current state:
   - Dose 1 recorded: Yes
   - Current time: 3:00 AM
   - Window status: Expired (if >240 min)
6. System marks Dose 2 as skipped (system-recorded)
7. System displays: "Dose window expired while device was off"
8. System notes: "reason: device_powered_off"
```

---

## Summary: Use Case Coverage

| Category | Use Cases | Priority |
|----------|-----------|----------|
| Core Dosing | UC-1.1 to UC-1.4 | P0 |
| Setup | UC-2.1 to UC-2.2 | P1 |
| watchOS | UC-3.1 to UC-3.2 | P0 |
| Notifications | UC-4.1 to UC-4.2 | P0 |
| Error Recovery | UC-5.1 to UC-5.3 | P1 |
| Data | UC-6.1 to UC-6.2 | P1 |
| Flic | UC-7.1 to UC-7.2 | P2 |
| Edge Cases | UC-8.1 to UC-8.4 | P1 |

---

*Last Updated: December 23, 2025*
