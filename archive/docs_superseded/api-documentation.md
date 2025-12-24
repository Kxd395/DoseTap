# DoseTap API Documentation (XYWAV-Only, Slim Surface)

## 🌙 Overview

Base URL: `https://api.dosetap.com/v1`

Only the minimum endpoints required for: taking / skipping / snoozing Dose 2, logging Dose 1, logging adjunct night events (bathroom, lights_out, wake_final), retrieving recent history, and exporting analytics. All adaptive scheduling intelligence runs on-device (no planner or profile mutating endpoints). Profile & generic medication CRUD, device status dashboards, notification preference CRUD, and multi-med analytics have been removed.

No realtime sync feed: optional future “minimal sync” (if user opts in) will still use only these endpoints (no separate /sync). If disabled (default) all actions remain local except when exporting CSV.

Idempotency: clients MUST send a stable `idempotency_key` (UUID v4) header for all mutating POSTs to prevent duplicate events on retries.

Timezone Handling: all request body timestamps MUST be UTC ISO8601; server echoes `local_offset_sec` to reflect the device-provided offset when relevant.

### Authentication

All API requests require authentication using Bearer tokens in the Authorization header.

```http
Authorization: Bearer <device_token>
```

## 🔐 Authentication

### POST /auth/device

Registers the device and returns a bearer token.

Request:

```json
{
  "device_id": "ios_UDID_hash",
  "platform": "iOS",
  "push_token": "apns_token_optional"
}
```

Response 201:

```json
{
  "device_id": "dev_ab12cd",
  "access_token": "eyJhbGc...",
  "expires_in": 86400
}
```

 
### POST /auth/refresh

Request:

```json
{ "device_id": "dev_ab12cd" }
```

Response 200:

```json
{ "access_token": "eyJhbGc...", "expires_in": 86400 }
```

## 💊 Dosing Endpoints

### POST /doses/take

Record dose1 or dose2.

Request (dose1):

```json
{ "type": "dose1", "at": "2025-09-03T22:45:00Z" }
```

Response 200 (dose1):

```json
{
  "event_id": "evt_x1",
  "type": "dose1",
  "at": "2025-09-03T22:45:00Z",
  "local_offset_sec": -18000,
  "dose2_window": { "min": "2025-09-04T01:15:00Z", "max": "2025-09-04T02:45:00Z" },
  "target_minutes": 165,
  "target_at": "2025-09-04T01:30:00Z",
  "nudge_reason": "baseline"
}
```

Request (dose2):

```json
{ "type": "dose2", "at": "2025-09-04T01:32:00Z" }
```

Response 200 (dose2):

```json
{
  "event_id": "evt_x2",
  "type": "dose2",
  "at": "2025-09-04T01:32:00Z",
  "local_offset_sec": -18000,
  "interval_minutes": 167,
  "within_window": true,
  "remaining_window_minutes": 73
}
```

### POST /doses/skip

Skip dose2.

Request:

```json
{ "type": "dose2", "reason": "felt_alert" }
```

Response 200:

```json
{ "event_id": "evt_skip1", "type": "dose2", "action": "skipped", "reason": "felt_alert" }
```

### POST /doses/snooze

Snooze dose2 target by a fixed 10 minutes (client always uses 10). Disabled when remaining window <15 minutes.

Request:

```json
{ "minutes": 10 }
```

Response 200:

```json
{
  "action": "snoozed",
  "new_target_at": "2025-09-04T01:40:00Z",
  "remaining_window_minutes": 65,
  "snoozes_remaining": 4
}
```

Response 422 (WINDOW_EXCEEDED):

```json
{ "error_code": "WINDOW_EXCEEDED", "window_end": "2025-09-04T02:45:00Z" }
```

Response 422 (SNOOZE_LIMIT):

```json
{ "error_code": "SNOOZE_LIMIT", "message": "Nightly snooze cap reached" }
```

## 📊 Event Logging

### POST /events/log

Log adjunct night events.

Allowed events: `bathroom`, `lights_out`, `wake_final`

Request:

```json
{ "event": "bathroom", "at": "2025-09-04T01:23:00Z" }
```

Response 201:

```json
{ "event_id": "evt_bath1", "event": "bathroom", "at": "2025-09-04T01:23:00Z" }
```

### GET /doses/history

Return recent dose events with lightweight derived metrics.

Query params (optional): `start` (ISO date), `end` (ISO date)

Response 200:

```json
{
  "doses": [
    { "event_id": "evt_x1", "type": "dose1", "at": "2025-09-03T22:45:00Z" },
    { "event_id": "evt_x2", "type": "dose2", "at": "2025-09-04T01:32:00Z", "interval_minutes": 167, "within_window": true }
  ],
  "metrics": {
    "nights": 30,
    "dose2_taken": 28,
    "dose2_skipped": 2,
    "on_time_pct": 94.3,
    "median_interval": 167
  }
}
```

## 📈 Analytics Export

 
### GET /analytics/export

Exports dose events + derived nightly metrics (CSV only).

Query: `start` (ISO date), `end` (ISO date)

CSV columns (current):

```csv
date,dose1_time,dose2_time,interval_minutes,within_window,bathroom_count,natural_wake,waso_minutes
```

 
## ⚙️ Removed: Profile Mutations

Profile endpoints eliminated. Dose2 clamp (150–240) & initial target (default 165) are fixed constants delivered implicitly by client logic after dose1.

 
## 🔌 Device Integration (Client-Only Now)

HealthKit, WHOOP historical import, and Flic button pairing occur locally; no remote device status endpoints remain.

 
## 🔔 Notifications

All notification scheduling done on-device; no preference CRUD API.

 
## 🔗 Deep Links

`dosetap://log?event={dose1|dose2|bathroom|lights_out|wake_final}&at={ISO8601?}`
Validation & effects match corresponding endpoints (window/clamp rules enforced locally before call).

Undo Note: Undo is purely a client-side ephemeral rollback (≤5s). No dedicated `/undo` endpoint exists; clients must simply refrain from sending (or must logically cancel queued) POSTs if user taps Undo before dispatch.

## 🚨 Errors

 
### Envelope

```json
{ "error_code": "WINDOW_EXCEEDED", "message": "Dose 2 outside allowed window", "ts": "2025-09-03T23:00:00Z" }
```

### Codes

| Error Code | HTTP | Meaning |
|------------|------|---------|
| WINDOW_EXCEEDED | 422 | Dose2 take/snooze outside 150–240m clamp |
| DOSE1_REQUIRED | 422 | Dose2 action attempted before dose1 recorded |
| ALREADY_TAKEN | 409 | Duplicate take/skip for dose2 |
| SNOOZE_LIMIT | 422 | Nightly snooze cap reached |
| DEVICE_NOT_REGISTERED | 401 | Invalid or expired device token |
| RATE_LIMIT | 429 | Per-minute request limit exceeded |

## 📦 Rate Limiting (Indicative)

| Category | Limit | Window |
|----------|-------|--------|
| doses (take/skip/snooze) | 10 | 60s |
| events (log) | 30 | 60s |
| history/export | 60 | 60s |
| export (CSV) | 5 | 1h |

Headers: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`.

## 🧪 Test Scenarios (Core)

| Scenario | Expected |
|----------|----------|
| Dose2 at 150m | 200 within_window true |
| Dose2 at 240m | 200 within_window true remaining_window_minutes 0 |
| Dose2 >240m | 422 WINDOW_EXCEEDED |
| Snooze valid pushes inside clamp | 200 new_target_at updated |
| Snooze would exceed 240m | 422 WINDOW_EXCEEDED |
| Snooze after cap | 422 SNOOZE_LIMIT |
| Dose2 before Dose1 | 422 DOSE1_REQUIRED |
| Duplicate take | 409 ALREADY_TAKEN |
| Rate limit spam | 429 RATE_LIMIT |
| Bathroom event logged | 201 event_id present |

## ❌ Removed Surface

- Multi-medication CRUD (all /medications, /refills, /pharmacy*)
- Profile mutation endpoints
- Device status & WHOOP OAuth APIs
- Notification preference APIs
- Aggregated analytics summary (client now derives)

Migration: clients must not rely on any removed paths; attempting calls returns 410 or 404.

## ✅ Current Endpoint Inventory

| Method | Path | Purpose |
|--------|------|---------|
| POST | /auth/device | Register device + token |
| POST | /auth/refresh | Refresh token |
| POST | /doses/take | Record dose1/dose2 |
| POST | /doses/skip | Skip dose2 |
| POST | /doses/snooze | Snooze dose2 target 10m |
| POST | /events/log | Log bathroom/lights_out/wake_final |
| GET | /doses/history | Recent dose history + metrics |
| GET | /analytics/export | CSV export |
