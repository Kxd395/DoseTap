# DoseTap API Specification (XYWAV-Only)

## Overview

This document defines the API endpoints for DoseTap's XYWAV-focused dose timing application. All generic medication endpoints have been removed.

## Base URL

```
Production: https://api.dosetap.app/v1
Development: http://localhost:3000/v1
```

## Authentication

```http
Authorization: Bearer <device_token>
```

## Endpoints

### 1. Dose Management

#### Record Dose Taken

```http
POST /doses/take
```

**Request Body:**
```json
{
  "type": "dose1" | "dose2",
  "timestamp": "2024-12-20T22:45:00Z",
  "meta": {
    "scheduled_time": "2024-12-20T22:45:00Z",
    "delta_minutes": 0,
    "nudge_reason": "light_sleep"
  }
}
```

**Response (200 OK):**
```json
{
  "event_id": "evt_abc123",
  "type": "dose1",
  "timestamp": "2024-12-20T22:45:00Z",
  "next_dose": {
    "type": "dose2",
    "scheduled_at": "2024-12-21T01:30:00Z",
    "window": {
      "min": "2024-12-21T01:15:00Z",
      "max": "2024-12-21T02:45:00Z"
    }
  }
}
```

#### Skip Dose

```http
POST /doses/skip
```

**Request Body:**
```json
{
  "type": "dose2",
  "timestamp": "2024-12-21T01:30:00Z",
  "reason": "felt_alert" | "side_effects" | "other"
}
```

**Response (200 OK):**
```json
{
  "event_id": "evt_def456",
  "type": "dose2",
  "action": "skipped",
  "timestamp": "2024-12-21T01:30:00Z"
}
```

#### Snooze Dose

```http
POST /doses/snooze
```

**Request Body:**
```json
{
  "type": "dose2",
  "snooze_minutes": 10,
  "current_scheduled": "2024-12-21T01:30:00Z"
}
```

**Response (200 OK):**
```json
{
  "event_id": "evt_ghi789",
  "type": "dose2",
  "action": "snoozed",
  "new_scheduled": "2024-12-21T01:40:00Z",
  "within_window": true,
  "window_remaining_minutes": 65
}
```

### 2. Event Logging

#### Log Event

```http
POST /events/log
```

**Request Body:**
```json
{
  "type": "bathroom" | "lights_out" | "wake_final",
  "timestamp": "2024-12-21T01:23:00Z",
  "meta": {
    "note": "optional user note"
  }
}
```

**Response (200 OK):**
```json
{
  "event_id": "evt_jkl012",
  "type": "bathroom",
  "timestamp": "2024-12-21T01:23:00Z"
}
```

### 3. Analytics & History

#### Get Dose History

```http
GET /doses/history
```

**Query Parameters:**
- `start_date`: ISO 8601 date (default: 30 days ago)
- `end_date`: ISO 8601 date (default: today)
- `type`: `dose1` | `dose2` | `all` (default: all)

**Response (200 OK):**
```json
{
  "doses": [
    {
      "event_id": "evt_abc123",
      "type": "dose1",
      "timestamp": "2024-12-20T22:45:00Z",
      "action": "taken"
    },
    {
      "event_id": "evt_def456",
      "type": "dose2",
      "timestamp": "2024-12-21T01:30:00Z",
      "action": "taken",
      "interval_minutes": 165,
      "within_window": true
    }
  ],
  "metrics": {
    "total_doses": 60,
    "doses_taken": 58,
    "doses_skipped": 2,
    "on_time_percentage": 94.8,
    "median_interval_minutes": 167
  }
}
```

#### Get Analytics

```http
GET /analytics/summary
```

**Query Parameters:**
- `period`: `week` | `month` | `90days` (default: week)

**Response (200 OK):**
```json
{
  "period": "week",
  "dose_timing": {
    "median_minutes": 167,
    "min_minutes": 155,
    "max_minutes": 182,
    "on_time_percentage": 94.3,
    "within_window_count": 13,
    "total_dose2_count": 14
  },
  "natural_wake": {
    "percentage": 71.4,
    "nights": 5,
    "total_nights": 7
  },
  "waso_post_dose2": {
    "average_minutes": 12,
    "median_minutes": 10,
    "best_minutes": 7,
    "best_date": "2024-12-18"
  },
  "bathroom_events": {
    "average_per_night": 1.3,
    "before_dose2": 0.8,
    "after_dose2": 0.5
  }
}
```

#### Export CSV

```http
GET /analytics/export
```

**Query Parameters:**
- `start_date`: ISO 8601 date
- `end_date`: ISO 8601 date
- `format`: `csv` (default)

**Response (200 OK):**
```csv
Date,Dose1_Time,Dose2_Time,Interval_Minutes,Within_Window,Bathroom_Count,Natural_Wake,WASO_Minutes
2024-12-20,22:45,01:30,165,true,1,false,15
2024-12-19,22:50,01:42,172,true,2,true,8
```

### 4. Profile & Settings

#### Get XYWAV Profile

```http
GET /profile/xywav
```

**Response (200 OK):**
```json
{
  "dose1_time_local": "22:45",
  "dose2_window_min": 150,
  "dose2_window_max": 240,
  "dose2_default_min": 165,
  "nudge_enabled": true,
  "nudge_step_min": 10,
  "ttfw_median_min": 185,
  "updated_at": "2024-12-20T10:00:00Z"
}
```

#### Update XYWAV Profile

```http
PUT /profile/xywav
```

**Request Body:**
```json
{
  "dose1_time_local": "23:00",
  "dose2_default_min": 170,
  "nudge_enabled": true,
  "nudge_step_min": 15
}
```

**Response (200 OK):**
```json
{
  "message": "Profile updated",
  "profile": {
    "dose1_time_local": "23:00",
    "dose2_window_min": 150,
    "dose2_window_max": 240,
    "dose2_default_min": 170,
    "nudge_enabled": true,
    "nudge_step_min": 15,
    "ttfw_median_min": 185,
    "updated_at": "2024-12-20T15:30:00Z"
  }
}
```

### 5. Device Integration

#### Get Device Status

```http
GET /devices/status
```

**Response (200 OK):**
```json
{
  "healthkit": {
    "connected": true,
    "last_sync": "2024-12-20T15:00:00Z",
    "permissions": ["sleep", "heart_rate", "hrv"]
  },
  "whoop": {
    "connected": false,
    "last_sync": null
  },
  "flic": {
    "connected": true,
    "battery_level": 85,
    "last_event": "2024-12-20T01:23:00Z"
  }
}
```

## URL Scheme Handlers

```
dosetap://log?event=dose1
dosetap://log?event=dose2
dosetap://log?event=bathroom
dosetap://log?event=lights_out
dosetap://log?event=wake_final
```

## Error Responses

### 400 Bad Request
```json
{
  "error": "invalid_request",
  "message": "Dose 2 cannot be scheduled outside 150-240 minute window"
}
```

### 401 Unauthorized
```json
{
  "error": "unauthorized",
  "message": "Invalid or expired token"
}
```

### 422 Unprocessable Entity
```json
{
  "error": "validation_failed",
  "message": "Dose 1 must be taken before Dose 2",
  "details": {
    "last_dose1": "2024-12-19T22:45:00Z"
  }
}
```

### 500 Internal Server Error
```json
{
  "error": "internal_error",
  "message": "An unexpected error occurred",
  "request_id": "req_xyz789"
}
```

## Rate Limiting

- 100 requests per minute per device
- Headers returned:
  - `X-RateLimit-Limit: 100`
  - `X-RateLimit-Remaining: 95`
  - `X-RateLimit-Reset: 1703088000`

## Removed Endpoints (No Longer Available)

The following generic medication endpoints have been removed:
- ❌ `GET /medications`
- ❌ `POST /medications`
- ❌ `PUT /medications/:id`
- ❌ `DELETE /medications/:id`
- ❌ `POST /medications/:id/pause`
- ❌ `POST /medications/:id/resume`
- ❌ `POST /refills/request`
- ❌ `GET /pharmacy/locations`
