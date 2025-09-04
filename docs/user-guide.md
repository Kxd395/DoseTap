# DoseTap User Guide (XYWAV-Only)

This guide covers the minimal, night‑first XYWAV workflow: log Dose 1, adapt + take (or snooze / skip) Dose 2 inside the regulatory clamp (150–240 min, default target 165), log adjunct events (bathroom, lights_out, wake_final), review recent history, and export data.

## 1. Install & Device Registration

* Platform: iOS (watchOS companion optional). No web / Android.
* Install from TestFlight / App Store.
* First launch → allow notifications (critical). Deny = reduced reliability.
* Device registration happens silently on first foreground (POST /auth/device). Failure shows a red banner: “Offline – actions will queue”.

## 2. Tonight Screen Basics

Single dark screen (high contrast toggle in Settings). Core elements:

```text
┌──────────────────────────────────────────────┐
│ Countdown Ring  (HH:MM:SS to target)         │
│ Target: 01:30 (165m)  Window: 150–240m       │
│                                              │
│ [TAKE NOW]  [SNOOZE 10m]  [SKIP]             │
│ Chip Row: [Inside Window] [Nudge +10]        │
│ Undo Snackbar (when active): “Taken. Undo (5)”│
└──────────────────────────────────────────────┘
```

States:

* Pre-Dose1: “Log Dose 1” card instead of ring.
* Near Target (±5m): subtle pulse + microcopy “Ideal moment now”.
* <15m Remaining: Snooze disabled; Take button label morphs to “Take Before Window Ends (MM:SS)”.
* Window Ended (>240m): Dose2 cluster hidden; message “Dose 2 window closed.” Skip remains for record clarity.

Undo:

* Appears for 5 seconds after Dose1, Dose2 Take, or Dose2 Skip.
* Tapping Undo cancels the local staged event (and network call if still queued).

Offline Behavior:

* Actions queue with a [Queued] chip. They flush automatically when connectivity returns.

Accessibility Cues (VoiceOver & Haptics):

* −5m to target: “Dose 2 window closes in five minutes.” (polite)
* At target: “Dose 2 target now.”
* At window end: “Dose 2 window ended.”
* Countdown (<15m): updates every 30s (polite, not interrupting user input).

High Contrast Mode: Increases button contrast (≥7:1) and adds persistent focus ring for Take.

Minimal Optional Sync:

* Disabled by default. If enabled in advanced settings, only event type + UTC timestamp + timezone offset + random device_id are transmitted (no health metrics, no personal identifiers).

CSV Export Schema:

```csv
date,dose1_time_utc,dose2_time_utc,dose_interval_min,within_window,bathroom_count,natural_wake,waso_minutes
```
Export is manual via the Export button (Tonight / Insights / Settings all route to same function). File not retained after share unless you save it.


## 18. Troubleshooting

| Symptom | Likely Cause | Resolution |
|---------|--------------|-----------|
| Snooze disabled early | Remaining <15m | Take or skip now |
| Take 2 button grey | No Dose1 event | Log Dose1 |
| “Window closed” after tapping Take | >240m elapsed | Skip remains available for record clarity |
| Bathroom not counted | Deep link early terminated | Relaunch app; ensure network or allow queue |
| Export empty | Date range outside recorded nights | Adjust range |

## 19. Privacy & Data Scope

Only the following event types leave the device: dose1, dose2, dose2_skip, dose2_snooze, adjunct events (bathroom/lights_out/wake_final). No profile, pharmacy, or other medication details are collected.

## 20. Support

Email: [support@dosetap.com](mailto:support@dosetap.com) (include app version + export sample if reporting interval issues).

---
Always follow your prescriber’s instructions. DoseTap does not alter dosing— it only helps you respect the required interval.

End of Guide
