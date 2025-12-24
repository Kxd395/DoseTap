# DoseTap – XYWAV Dose Timing (Night‑First)

Minimalist assistant focused solely on taking XYWAV Dose 2 at a safe, personalized minute—nothing extra.

## 🎯 Core Promise
Help you hit Dose 2 inside the 150–240 minute window (default target 165m) with the least cognitive friction possible at 3 AM.

## 🌟 Principles
 
* Single task only (Dose 2 timing)
* Safety clamp always (never >240m or <150m from Dose 1)
* Local‑first (events on device)
* Optional minimal sync (off by default; sends only event type + UTC + offset + device id)
* Undo protection (5s after Dose1 / Dose2 take / skip)
* Accessibility-first (large targets, high contrast option ≥7:1, VoiceOver cues −5m/target/end, haptics, watch hold‑to‑confirm)
* Transparent future adaptive logic (explain the “why”)—but still bounded

## 🛠 Night Flow (Condensed)

1. Log Dose 1 (sets window + initial target 165m)
2. Countdown ring + status chips (Inside Window / Nudge +10)
3. Optional Snooze 10m while ≥15m remains
4. Take or Skip Dose 2 (Undo 5s window)
5. (Optional) Mark bathroom / lights_out / wake_final
6. Morning: view adherence stats or export CSV

## 📦 Event Types

* dose1
* dose2_taken (derives interval + within_window)
* dose2_skipped
* snooze (duration=10m fixed v1)
* bathroom
* lights_out
* wake_final

All include: utc_ts, local_offset_sec, idempotency_key, device_id* (device_id only transmitted if minimal sync enabled).

## 🔄 Undo Semantics
5‑second snackbar after Dose1 / Dose2 take / Dose2 skip. Reverts local state and cancels queued network call if still pending. After expiry events are immutable (no edit/delete UI anywhere).

## 🔒 Privacy & Minimal Sync
Default: full offline. Enabling minimal sync contributes only de‑identified timing metadata (no HR, no sleep stages, no personal profile). You can keep it disabled indefinitely.

## 📊 CSV Export (Manual Only)
Columns: date,dose1_time_utc,dose2_time_utc,dose_interval_min,within_window,bathroom_count,natural_wake,waso_minutes
Triggered from Tonight / Insights / Settings (single code path). No automatic background exports.

## 🚀 Differentiators

1. Ruthless scope (only XYWAV two‑dose timing)
2. Immutable history (except brief undo window)
3. Clamp transparency (target + window always visible)
4. Accessible by default (contrast, VoiceOver schedule, reduced motion)
5. Local reasoning; adaptive future remains explainable & bounded

## 🧪 Reliability Posture

* Idempotent event insertion using locally generated UUIDs
* Offline queue flushes preserving order
* DST & timezone travel preserve elapsed mins from Dose1 baseline
* Snooze disabled when <15m remaining

## 🔮 Future (Clearly Marked)

* Optional adaptive planner (Thompson Sampling across {165,180,195,210,225})
* Local-only evaluation mode vs minimal sync crowd statistics
* Additional accessibility preferences (larger haptics granularity)

## 🛑 Out of Scope (Removed)

* Multi‑med management / refills / pharmacy
* Provider or caregiver portals
* Continuous dashboards & trend charts
* Automatic cloud sync of physiological data

## 📞 Support
Lightweight in‑app FAQ; no multi-tier support model.

## ▶ Onboarding Call to Action
“Enable Health permissions, tap Dose 1, and we’ll handle the timing math.”

*DoseTap — Focus the night on correct timing, not clutter.*
