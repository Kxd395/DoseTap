# DoseTap – Product Spec & Presentation Pack

**One‑liner:** Tap once for Dose 1. Inside the **2.5–4 h** window, we remind you at a minute you’re likely to surface, then tap again for Dose 2. Bathroom/Out‑of‑Bed events help the timing model. All data stays on‑device by default.

## Problem → Opportunity
Split‑dose XYWAV at ~3 AM is easy to miss or mishandle. Phones are bright and slow. We replace screens with one tactile button and an adaptive reminder that never leaves the **2.5–4 h** label window.

## Solution
- **Hardware button (Flic 2)** → URL scheme → app logs events and schedules reminders.
- **Adaptive placement:** baseline = median Time‑to‑First‑Wake (TTFW) from Health/WHOOP history; same‑night nudges ±10–15 min; **hard clamp 150–240 min**.

## Architecture
- iOS SwiftUI app + watchOS companion.
- HealthKit: Sleep Analysis (stages), HR/HRV/RR (optional), Medications read (optional).
- WHOOP API v2: sleep & cycles history via OAuth.
- Local storage: Core Data / or JSON for MVP. CSV export.

## Events (codes)
`dose1`, `dose2`, `bathroom`, `lights_out`, `wake_final`, `snooze`

## MVP
- URL handler: `dosetap://log?event=...`
- Reminder: default 165 min; clamp [150, 240].
- Watch: three big buttons; haptic confirms.
- Insights: average Dose1→Dose2 interval, natural vs. alarm nights.

## Limitations & Mitigations
- iOS background: keep the Flic app running (don’t force‑quit).
- WHOOP latency: use for **history**, not live staging.
- HealthKit variability: rely on multi‑night baselines, small same‑night nudges.

## Roadmap
- v0.1 Tonight‑ready slice
- v0.2 HealthKit baseline & nudges
- v0.3 WHOOP history personalization
- v0.4 Insights + CSV export

## Action Plan (Weeks)
- **Week 0:** URL scheme, notifications, 165‑min default
- **Week 1:** HealthKit sleep read + baseline; Snooze 10m
- **Week 2:** WHOOP OAuth + 30‑night import; Insights v1
- **Week 3:** Polish, slides, demo

## Success Metrics
- % Dose 2 on‑time (inside 2.5–4 h)
- % natural‑wake vs alarm nights
- Missed Dose 2 per week
