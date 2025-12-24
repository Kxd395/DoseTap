# DoseTap Product Guarantees

> **What This App Promises to Do Correctly Every Time**
>
> If the app fails to meet any guarantee below, it is a **P0 bug**.

## Core Guarantees

### 1. Window Timing Is Correct

| Guarantee | Implementation |
|-----------|----------------|
| Window opens exactly at 150 minutes after Dose 1 | `DoseWindowCalculator` with injected clock |
| Window closes exactly at 240 minutes after Dose 1 | Same |
| Timer displays accurate countdown to the second | `Timer.publish(every: 1)` with UTC reference |
| Time zone changes do not corrupt window math | All timestamps stored in UTC ISO8601 |

**Test**: `DoseWindowEdgeTests.swift` covers boundary conditions and DST transitions.

---

### 2. Snooze Behavior Is Predictable

| Guarantee | Implementation |
|-----------|----------------|
| Each snooze adds exactly 10 minutes | Fixed constant, not configurable |
| Maximum 3 snoozes per session | Enforced in `DoseWindowContext` |
| Snooze disabled when <15 minutes remain | Checked every state calculation |
| Snooze count persists across app restarts | SQLite `current_session.snooze_count` |

**Test**: `DoseWindowStateTests.swift` validates all snooze edge cases.

---

### 3. Data Is Never Lost

| Guarantee | Implementation |
|-----------|----------------|
| Dose actions persist immediately | SQLite write on every action |
| Sleep events persist immediately | SQLite write on every log |
| App crash does not lose session state | State restored from SQLite on launch |
| Offline actions queue and sync later | `OfflineQueue` actor with persistence |

**Test**: `OfflineQueueTests.swift`, app termination scenarios.

---

### 4. Notifications Fire When Expected

| Guarantee | Implementation |
|-----------|----------------|
| Window open notification at 150m | `UNNotificationRequest` scheduled on Dose 1 |
| Near-close warning at 225m | Scheduled with window open |
| Wake alarms fire at scheduled times | `UNCalendarNotificationTrigger` |
| Notifications respect Do Not Disturb | iOS handles via `.timeSensitive` category |

**Caveat**: iOS may delay or suppress notifications. App shows status in UI.

---

### 5. History Is Accurate and Deletable

| Guarantee | Implementation |
|-----------|----------------|
| History shows all past sessions | `fetchRecentSessions()` from `dose_events` |
| Each session shows correct dose times | Aggregated from `dose_events` by `session_date` |
| Delete removes all related data | Deletes from 3 tables: `dose_events`, `sleep_events`, `current_session` |
| Deleted data cannot be recovered | Hard delete, no soft delete |

**Test**: `EventStorageTests.swift` (if exists), manual verification.

---

### 6. Export Contains Complete Data

| Guarantee | Implementation |
|-----------|----------------|
| Export includes all sessions in range | CSV generated from SQLite queries |
| Export includes all sleep events | `sleep_events` table dump |
| Export timestamps are UTC with timezone noted | ISO8601 + `schema_version.json` |
| Export is versioned | `schema_version` field in bundle |
| Export contains no secrets | Settings export excludes tokens |

---

### 7. Undo Works Within Window

| Guarantee | Implementation |
|-----------|----------------|
| 5-second undo window after dose/skip | `DoseUndoManager` timer |
| Undo reverts UI and database state | Restore previous values |
| Undo window is not configurable | Fixed 5s constant |
| Undo expired = action is permanent | No undo after 5s |

---

## Non-Guarantees (Known Limitations)

These are **not bugs**—they are documented limitations:

| Limitation | Reason |
|------------|--------|
| Notifications may be delayed by iOS | OS controls delivery timing |
| watchOS companion is not integrated | Planned, not shipped |
| WHOOP sync may fail if token expires | User must re-authenticate |
| HealthKit data may be unavailable | User controls Health permissions |
| No multi-medication support | XYWAV-only by design |

---

## How to Report a Guarantee Violation

If the app fails any guarantee above:

1. Note the exact behavior vs expected behavior
2. Include timestamps and timezone
3. Export support bundle (`Settings > Export Support Bundle`)
4. File issue with `[P0-GUARANTEE]` tag

---

## Verification Checklist

Before each release, verify:

- [ ] Window opens at exactly 150m in test harness
- [ ] Snooze disabled at exactly 225m (15m remaining)
- [ ] Session survives app termination and restore
- [ ] Export contains expected fields and values
- [ ] Undo works within 5s, fails after 5s
- [ ] History shows correct data, delete removes all traces
