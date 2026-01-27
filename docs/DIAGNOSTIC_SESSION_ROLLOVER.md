# Session & Rollover Diagnostic Document

**Created:** January 15, 2026  
**Purpose:** Map all session state logic to find why rollover isn't working correctly

---

## 1. THE CORE PROBLEM (from screenshots)

### What we're seeing:
- History shows "Thursday, Jan 15" with:
  - Dose 1: 10:37 PM
  - Dose 2: 1:08 AM
  - Interval: 2h 30m

### What's WRONG:
1. **Date attribution bug**: Dose 1 (10:37 PM) was taken on **Wed Jan 14**, Dose 2 (1:08 AM) on **Thu Jan 15**
2. **Both doses showing under "Thursday, Jan 15"** - they should be under the SLEEP SESSION for Wed night → Thu morning
3. **Session rollover** didn't happen properly after morning check-in
4. **Tonight tab** may still be showing old session

### The Sleep Day concept:
```
Wed Jan 14 evening ──────────────────────────────────────> Thu Jan 15 morning
        │                    MIDNIGHT                              │
        ▼                       │                                  ▼
   Dose 1 @ 10:37 PM           │                        Wake @ 6:30 AM
                               │    Dose 2 @ 1:08 AM
                               
ALL of this is ONE "sleep session" with key = "2026-01-14" (the night it started)
```

---

## 2. KEY DATA STRUCTURES

### Session Identity
**File:** `ios/Core/SessionKey.swift`

```swift
public struct SessionIdentity {
    public let key: String        // e.g., "2026-01-14"
    public let displayDate: Date
    
    public init(date: Date, timeZone: TimeZone, rolloverHour: Int = 18) {
        // If before rollover hour (6 PM), use yesterday's date
        // If after rollover hour, use today's date
    }
}
```

**Rollover Hour Logic:**
- Default: 18 (6:00 PM)
- At 10:37 PM on Jan 14 → session key = "2026-01-14" ✓
- At 1:08 AM on Jan 15 → session key should STILL be "2026-01-14" (before 6 PM)
- At 6:30 AM on Jan 15 → session key should STILL be "2026-01-14"
- After morning check-in completes → session should CLOSE, new key = "2026-01-15"

### Session Repository State
**File:** `ios/DoseTap/Storage/SessionRepository.swift`

```swift
class SessionRepository: ObservableObject {
    // PUBLISHED STATE (drives UI)
    @Published var currentSessionKey: String      // e.g., "2026-01-14"
    @Published var activeSessionId: String?       // UUID of active session
    @Published var activeSessionDate: String?     // "2026-01-14"
    @Published var dose1Time: Date?
    @Published var dose2Time: Date?
    @Published var wakeFinalTime: Date?
    @Published var checkInCompleted: Bool
    
    // SIGNALS
    let sessionDidChange = PassthroughSubject<Void, Never>()
}
```

### DoseTapCore State
**File:** `ios/Core/DoseTapCore.swift`

```swift
class DoseTapCore: ObservableObject {
    var dose1Time: Date? { sessionRepository?.dose1Time }
    var dose2Time: Date? { sessionRepository?.dose2Time }
    
    var currentStatus: DoseStatus {
        // Computed from dose1Time, dose2Time, and window math
    }
}
```

---

## 3. STATE FLOW DIAGRAM

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           USER ACTION FLOW                                   │
└─────────────────────────────────────────────────────────────────────────────┘

[App Launch / Foreground]
         │
         ▼
┌─────────────────────────────────────────┐
│ SessionRepository.updateSessionKeyIfNeeded()                                │
│   - Computes SessionIdentity from current time                              │
│   - If key changed: currentSessionKey = newKey                              │
│   - Calls reload() to load session from DB                                  │
└─────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│ SessionRepository.reload()                                                   │
│   - Queries: SELECT * FROM sleep_sessions WHERE session_date = currentKey   │
│   - Populates: activeSessionId, dose1Time, dose2Time, etc.                  │
│   - Sends: sessionDidChange.send()                                          │
└─────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│ DoseTapCore receives sessionDidChange                                        │
│   - Calls: objectWillChange.send()                                          │
│   - SwiftUI rebuilds views using new state                                  │
└─────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│ ContentView / LegacyTonightView                                              │
│   - Reads: core.dose1Time, core.dose2Time, core.currentStatus               │
│   - Reads: sessionRepo.currentSessionKey for header date                    │
│   - Renders UI based on these values                                        │
└─────────────────────────────────────────┘
```

---

## 4. DOSE RECORDING FLOW

### Take Dose 1 (10:37 PM Wed Jan 14)

```
[User taps "Take Dose 1"]
         │
         ▼
CompactDoseButton.handlePrimaryButtonTap()
         │
         ▼
DoseTapCore.takeDose()
         │
         ▼
SessionRepository.setDose1Time(now)     // now = Wed Jan 14 @ 10:37 PM
         │
         ├──> Computes sessionKey: "2026-01-14" (Wed night session)
         ├──> Writes to DB: sleep_sessions.dose1_time = "2026-01-14T22:37:00Z"
         ├──> Sets in-memory: dose1Time = Date(...)
         └──> sessionDidChange.send()
```

**DB Record Created:**
```sql
INSERT INTO sleep_sessions (session_date, session_id, dose1_time, ...)
VALUES ('2026-01-14', 'uuid-xxx', '2026-01-14T22:37:00Z', ...)
```

### Take Dose 2 (1:08 AM Thu Jan 15)

```
[User taps "Take Dose 2"]
         │
         ▼
DoseTapCore.takeDose()
         │
         ▼
SessionRepository.setDose2Time(now)     // now = Thu Jan 15 @ 1:08 AM
         │
         ├──> SHOULD use existing session: "2026-01-14" (still before rollover!)
         ├──> Writes to DB: sleep_sessions.dose2_time = "2026-01-15T01:08:00Z"
         └──> sessionDidChange.send()
```

**QUESTION: Is this correctly using session "2026-01-14" or creating a new session for "2026-01-15"?**

---

## 5. MORNING CHECK-IN & ROLLOVER FLOW

### Before Fix (BROKEN)

```
[User completes morning check-in @ 6:30 AM Thu Jan 15]
         │
         ▼
MorningCheckInView.onComplete()
         │
         ▼
SessionRepository.completeCheckIn()
         │
         ▼
SessionRepository.closeActiveSession()
         │
         ├──> storage.closeSession(sessionId, sessionDate, endTime, "checkin_completed")
         ├──> clearInMemoryState()  // Sets activeSessionId = nil, etc.
         ├──> sessionDidChange.send()
         └──> scheduleRolloverTimer()   ← PROBLEM: Never updates currentSessionKey!
```

**RESULT:** `currentSessionKey` stays "2026-01-14", UI still shows old session

### After Fix (SHOULD WORK)

```
SessionRepository.closeActiveSession()
         │
         ├──> storage.closeSession(...)
         ├──> clearInMemoryState()
         ├──> updateSessionKeyIfNeeded()  ← NEW: Computes new key!
         │         │
         │         ▼
         │    At 6:30 AM Jan 15:
         │    - Current time is before 6 PM
         │    - SessionIdentity computes: key = "2026-01-14" (still yesterday!)
         │    
         └──> sessionDidChange.send()
```

**WAIT - THIS IS THE BUG!**

Even after the fix, at 6:30 AM the SessionIdentity will compute key = "2026-01-14" because it's before the rollover hour (6 PM). The session key won't actually change until 6 PM!

---

## 6. THE REAL BUG: Session Key vs Active Session

There are TWO separate concepts being conflated:

### 1. Session Key (which "sleep day" we're in)
- Computed by time of day vs rollover hour
- At 6:30 AM on Jan 15, key = "2026-01-14" (correct for viewing last night's data)
- At 6:30 PM on Jan 15, key = "2026-01-15" (new night begins)

### 2. Active Session (is there an open session?)
- After morning check-in: there should be NO active session
- `activeSessionId = nil`, `dose1Time = nil`, etc.
- Tonight view should show "Ready for Dose 1" (new night prep)

**The problem is:** Tonight view is using `currentSessionKey` to LOAD data, not checking if there's an ACTIVE session.

---

## 6.1 INVARIANTS (MUST HOLD)

These invariants are non-negotiable for correct behavior:

| # | Invariant | Enforcement Point |
|---|-----------|-------------------|
| A | `currentSessionKey` pointing to prior night until rollover hour (6 PM) is **correct by design** | SessionIdentity |
| B | If `activeSessionId == nil`, Tonight UI must show IDLE state, **never** stale dose data | ContentView/LegacyTonightView |
| C | Published fields (`dose1Time`, `dose2Time`, `wakeFinalTime`) must represent the **OPEN** session only. If `terminal_state != nil`, those fields must be `nil` | `reload()` in SessionRepository |
| D | `reload()` loading a CLOSED session into published "current" state **recreates the zombie bug** | `reload()` guard |

**Key Insight:** The session key not changing until 6 PM is expected. The bug is that `reload()` hydrates published state from closed sessions, creating a "zombie session" in the UI.

---

## 7. FILE-BY-FILE AUDIT

### SessionRepository.swift - Key Methods

| Method | Purpose | Bug Risk |
|--------|---------|----------|
| `updateSessionKeyIfNeeded()` | Computes session key from time | May not differentiate "active" vs "historical" |
| `reload()` | Loads session from DB by key | Always loads, even if session is closed |
| `setDose1Time()` | Records Dose 1 | Needs to ensure correct session |
| `setDose2Time()` | Records Dose 2 | Needs to ensure same session as Dose 1 |
| `completeCheckIn()` | Closes session | Now calls updateSessionKeyIfNeeded (fixed) |
| `closeActiveSession()` | Marks session closed | Now calls updateSessionKeyIfNeeded (fixed) |

### ContentView.swift - Key Bindings

| Property | Source | Issue |
|----------|--------|-------|
| `sessionRepo.currentSessionKey` | Published | Used for header date |
| `core.dose1Time` | SessionRepository | Shows dose times |
| `core.currentStatus` | Computed | Drives button state |

---

## 8. DATABASE SCHEMA

### sleep_sessions table

```sql
CREATE TABLE sleep_sessions (
    session_date TEXT PRIMARY KEY,    -- "2026-01-14"
    session_id TEXT,                  -- UUID
    dose1_time TEXT,                  -- ISO8601 timestamp
    dose2_time TEXT,                  -- ISO8601 timestamp
    start_time TEXT,                  -- When session started
    end_time TEXT,                    -- When session closed
    terminal_state TEXT,              -- "checkin_completed", "slept_through", etc.
    ...
);
```

### sleep_events table

```sql
CREATE TABLE sleep_events (
    id TEXT PRIMARY KEY,
    event_type TEXT,                  -- "dose1", "dose2", "wake_final", etc.
    timestamp TEXT,                   -- ISO8601
    session_date TEXT,                -- Links to sleep_sessions
    session_id TEXT,
    ...
);
```

---

## 9. HISTORY VIEW BUG

Looking at the screenshot, History shows "Thursday, Jan 15" with doses from Wed night.

**Likely cause:** History view is grouping events by CALENDAR DATE of the timestamp, not by SESSION DATE.

### What History is doing (WRONG):
```swift
// Grouping by calendar date of dose timestamp
let dateKey = Calendar.current.startOfDay(for: dose.timestamp)  // Jan 15 for 1:08 AM dose
```

### What History SHOULD do:
```swift
// Group by session_date from the database
let dateKey = dose.sessionDate  // "2026-01-14" for both doses
```

---

## 10. RECOMMENDED FIXES

### Fix 0: reload() Must Not Hydrate Closed Sessions (CRITICAL)
This is the ROOT CAUSE fix. Without this, all other fixes are ineffective.

```swift
func reload() {
    // ... fetch session by currentSessionKey ...
    
    // CRITICAL GUARD: terminal_state != nil means session is closed
    if session.terminal_state != nil {
        clearInMemoryState()  // Force idle state in UI
        return
    }
    
    // ... only then hydrate dose1Time, dose2Time, etc. ...
}
```

### Fix 1: History View - Group by Session Date
The History view should display sessions by their `session_date`, not by calendar date of events.

### Fix 2: Tonight View - Check for Active Session
Tonight should check `activeSessionId != nil` before showing dose data:
```swift
if sessionRepo.activeSessionId == nil {
    // Show "Ready for tonight" / "Take Dose 1" state
} else {
    // Show active session with dose times
}
```

### Fix 3: Session Close Should Force "No Active Session" State
After morning check-in, the UI should NOT show the closed session's data.

### Fix 4: Dose Date Display - Include Date When Cross-Midnight
When displaying dose times, if they span midnight, show the date:
```
Dose 1: Wed 10:37 PM
Dose 2: Thu 1:08 AM
```

---

## 11. TEST CASES

### Test 1: Normal Night (No Midnight Crossing)
- Dose 1: 11:00 PM Mon
- Dose 2: 2:30 AM Tue
- Wake: 6:30 AM Tue
- **Expected:** Both doses under session "Monday" in History

### Test 2: After Morning Check-In
- Complete check-in at 6:30 AM
- **Expected:** Tonight shows "Ready for Dose 1" (no old session data)

### Test 3: Before Rollover Hour
- Time: 2:00 PM Thu
- No doses taken yet today
- **Expected:** Tonight shows "Ready for Dose 1" for Thu night session

### Test 4: After Rollover Hour
- Time: 7:00 PM Thu
- Dose 1 taken
- **Expected:** Tonight shows Dose 1 time, waiting for Dose 2

---

## 12. IMMEDIATE ACTION ITEMS

### Priority 1: Fix reload() (ROOT CAUSE)
**File:** `SessionRepository.swift` `reload()` method
**Action:** Add guard - if session has `terminal_state != nil`, call `clearInMemoryState()` and return early. Do NOT hydrate published fields from closed sessions.

### Priority 2: Gate Tonight UI on activeSessionId
**File:** `ContentView.swift` `LegacyTonightView`
**Action:** Wrap active session UI in `if sessionRepo.activeSessionId != nil { ... }`. When nil, show "Ready for tonight" idle state.

### Priority 3: Tonight Header When Idle
**File:** `ContentView.swift` header date display
**Action:** When `activeSessionId == nil`, show "upcoming night" (computed from today's date), not `currentSessionKey` (which may point to closed session).

### Priority 4 (Optional): Remove Misleading Fix
**File:** `SessionRepository.swift` `closeActiveSession()`
**Action:** Remove the `updateSessionKeyIfNeeded()` call added earlier - it's harmless but misleading since the key won't change until 6 PM by design.

### Debug Logging to Add:
```swift
print("📊 Session State:")
print("  - currentSessionKey: \(currentSessionKey)")
print("  - activeSessionId: \(activeSessionId ?? "nil")")
print("  - activeSessionDate: \(activeSessionDate ?? "nil")")
print("  - dose1Time: \(dose1Time?.description ?? "nil")")
print("  - dose2Time: \(dose2Time?.description ?? "nil")")
print("  - terminal_state: \(terminalState ?? "nil")")
```

---

## 14. BUGS FOUND

### Bug 1: History View Date/Data Mismatch (CONFIRMED)

**Location:** `ContentView.swift` line ~2600, `SelectedDayView`

**Problem:** 
- User taps "Jan 15" on calendar
- `dateTitle` shows "Thursday, Jan 15" (calendar date)
- But `loadData()` calls `sessionDateString(for: date)` which returns "2026-01-14" (session key)
- So it shows "Thursday, Jan 15" but loads Wednesday night's data!

**Code:**
```swift
private var dateTitle: String {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE, MMM d"
    return formatter.string(from: date)  // ← Shows calendar date
}

private func loadData() {
    let sessionDate = sessionRepo.sessionDateString(for: date)  // ← Loads session date
    events = sessionRepo.fetchSleepEvents(for: sessionDate)
    // ...
}
```

**Fix:** Either:
1. Show the session date in the title, not calendar date, OR
2. Add subtitle explaining "Night of Wed Jan 14 → Thu Jan 15"

### Bug 2: Dose Times Missing Dates (CONFIRMED)

**Location:** `SelectedDayView` line ~2440

**Problem:** Dose times show only time, not date:
```swift
Text(dose.dose1Time.formatted(date: .omitted, time: .shortened))  // "10:37 PM"
Text(d2.formatted(date: .omitted, time: .shortened))               // "1:08 AM"
```

When doses cross midnight, this is confusing. User sees:
- Dose 1: 10:37 PM
- Dose 2: 1:08 AM
- Thinks they're on the same day

**Fix:** When Dose 1 and Dose 2 are on different calendar days, show the day:
```swift
// "Wed 10:37 PM" / "Thu 1:08 AM"
```

### Bug 3: Zombie Session After Close (NOT FIXED - ROOT CAUSE)

**Location:** `SessionRepository.swift` `reload()` method

**Problem:** After morning check-in completes:
1. `closeActiveSession()` writes `terminal_state = "checkin_completed"` to DB
2. `clearInMemoryState()` sets `activeSessionId = nil`, `dose1Time = nil`, etc.
3. But later, `reload()` is called (e.g., on app foreground, timer, etc.)
4. `reload()` loads the CLOSED session back into published fields!
5. UI shows zombie session data

**Root Cause:** `reload()` does not check `terminal_state`. It blindly hydrates published fields from whatever session matches `currentSessionKey`.

**Why the previous "fix" doesn't work:** Adding `updateSessionKeyIfNeeded()` in `closeActiveSession()` is useless because at 6:30 AM, `SessionIdentity` still computes key = "2026-01-14". The key won't change until 6 PM by design.

**Real Fix:** `reload()` must guard:
```swift
func reload() {
    // ... existing code to fetch session by currentSessionKey ...
    
    // GUARD: Do not hydrate published fields from closed sessions
    guard session.terminal_state == nil else {
        clearInMemoryState()  // Ensure UI shows idle state
        return
    }
    
    // ... rest of existing hydration logic ...
}
```

---

## 15. FIXES TO APPLY

### Fix 1: History Date Title - Show Session Date Context

```swift
private var dateTitle: String {
    let sessionKey = sessionRepo.sessionDateString(for: date)
    
    // Parse session date to get actual night-of date
    let nightOfDate = dateFromSessionKey(sessionKey)
    
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE, MMM d"
    
    let title = formatter.string(from: nightOfDate)
    
    // If viewing data spans two calendar days, note it
    let cal = Calendar.current
    let nextDay = cal.date(byAdding: .day, value: 1, to: nightOfDate)!
    
    if !cal.isDate(date, inSameDayAs: nightOfDate) {
        return "Night of \(title)"
    }
    return title
}
```

### Fix 2: Dose Times - Show Date When Crossing Midnight

```swift
private func formatDoseTime(_ time: Date, relativeTo session: Date) -> String {
    let cal = Calendar.current
    if cal.isDate(time, inSameDayAs: session) {
        // Same calendar day as session start
        return time.formatted(date: .omitted, time: .shortened)
    } else {
        // Different calendar day - show abbreviated day
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"  // "Thu 1:08 AM"
        return formatter.string(from: time)
    }
}
```

