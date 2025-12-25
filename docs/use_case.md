# DoseTap Use Case: The Nightly Dosing Flow

## Primary Actor
**The Patient**: A user prescribed XYWAV who is about to go to sleep.

## Preconditions
*   Device is registered.
*   Inventory is sufficient.
*   DoseTap app is open (or accessible via Widget/Watch).

## The Flow

### 1. Dose 1: Lights Out
1.  user prepares for bed and opens DoseTap.
2.  **UI State**: Shows "Take Dose 1" as the primary action.
3.  User takes the first dose and taps **"Take Dose 1"**.
4.  **System**:
    *   Logs the timestamp locally.
    *   Starts the **Safety Window Timer** (2.5 - 4 hours).
    *   Updates UI to "Dose 1 Taken" and shows the "Next Dose" countdown.
    *   Schedules local notifications for the start of the valid window (150m) and the optimal target (165m).

### 2. The Sleep Period
1.  User sleeps.
2.  **System**:
    *   Counts down silently.
    *   At T+150m (2.5 hours): Window opens. Notification sent (if configured). Use of "Take Dose 2" button becomes enabled.
    *   At T+165m (2.75 hours): Optimal target. Primary notification/alarm sounds.

### 3. Dose 2: The Critical Window
1.  User wakes up (either naturally or via alarm).
2.  **UI State**: Shows large countdown ring.
    *   **Green/Active**: "Window Open".
    *   **Yellow/Warning**: "Window Closing Soon" (<15m remaining).
3.  **Path A: Taken**
    *   User taps **"Take Dose 2"**.
    *   System records time, validates it is within 150-240m.
    *   System logs "Dose 2 Taken".
    *   Flow Complete.
4.  **Path B: Snooze**
    *   User is too groggy. Taps **"Snooze"** (or long-presses Flic).
    *   System schedules a new alarm in 10 minutes.
    *   *Constraint*: Snooze is disabled if current time > T+225m (15 min left in window).
5.  **Path C: Skip**
    *   User decides not to take dose (feels unsafe, woke up too late).
    *   User taps **"Skip Dose 2"**.
    *   System logs "Dose 2 Skipped".
    *   Flow Complete.

### 4. Morning Review
1.  User wakes up in the morning.
2.  User checks DoseTap "Insights" tab.
3.  System displays the night's chart: Dose 1 time, sleep duration, Dose 2 time (or skip), and window accuracy.

## Post-Conditions
*   Events are strictly logged to SQLite (via EventStorage).
*   If online, events are synced to backend.
*   If offline, events are queued for sync.

## Invariant Rules
1.  **Safety Window**: Dose 2 CANNOT be logged < 150 minutes after Dose 1.
2.  **Hard Stop**: Dose 2 CANNOT be logged > 240 minutes after Dose 1 (it becomes a "Missed" or "New Dose 1").
3.  **Snooze Safety**: No snoozing allowed in the final 15 minutes of the window.
