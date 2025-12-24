<!-- Night-First XYWAV ASCII UI v2.0 Specification -->

# DoseTap (XYWAV) — ASCII UI v2.0 (Night‑First)

Version: 2.0 · Status: Draft for agent handoff · Scope: iOS/macOS + watchOS companion

Purpose: Replace generic/boring layout with a focused night‑first experience for XYWAV timing inside the 2.5–4h window. Includes page wireframes, states, and component IDs for implementation and QA.

---


<!-- Night-First XYWAV ASCII UI v2.0 Specification -->

## Legend & Tokens
* [A] Accent action · [P] Primary text · [S] Secondary text · [⚠] Warning · [✔] Success
* Boxes: ┌ ┐ └ ┘ │ ─  · Divider: ─── · Section label: ▸ · Chip: [Label]
* Night palette: Background #0B1220 · Surface #11192A · Card #141F33
* Type scale: Display-XL tabular numerals for timers; Title / Body / Caption
* Key constants: CLAMP = 150–240 min · DEFAULT_D2 = 165 · NUDGE_STEP = 10 or 15
* TestIDs embedded as comments (testid="...")


---

## Global Navigation (App Shell)

## Global Navigation (App Shell)

```

## Global Navigation (App Shell)

```text

```text

* Status strip (top-right): [Lights Out] [Dose 1 Taken 22:47] [Window: 2.5–4h]
* Global FAB (bottom-right on iOS): [+ Bathroom]  testid="fab-bathroom"
* Haptics: medium for primaries; gentle for information; strong for warnings


### A1. Post‑Dose‑1, Pre‑Dose‑2 (default)

```text

```text

### A2. Within ±5m of Target
* Countdown ring pulses softly; TAKE NOW button subtle breathing effect.
* Microcopy → “Ideal moment now (Light stage).”


### A3. Snoozing

```text

```text

* Chips update: [Snooze • 10m remaining]


### A4. Pre‑Dose‑1 (bedtime)

```text

```text

### A5. Post‑Dose‑2 (completed)

```text

```text

* Animated countdown ring pulse ±5m window.
* High contrast mode toggle (Settings) elevates primary/action contrast ≥7:1 (baseline ≥4.5:1).
* Large tap areas ≥48pt; gentle haptics.
* Undo snackbar: dark surface “Taken. Undo (5)” counts down (polite live region, no repetition).


## Open Questions

* Light mode (deferred)
* Extended bathroom event classification (ignored v1)


VoiceOver:

* At −5m: "Dose 2 window closes in five minutes"
* At target: "Dose 2 target now"
* At window end (240m): "Dose 2 window ended"
* Countdown (<15m) updates every 30s (polite)
* Undo snackbar: "Dose logged. Undo available five seconds"
┌─────────────────────────────────────────────────────────────────────────────┐
│  DoseTap ▸ Tonight | Timeline | Insights | Devices | Settings               │  testid="nav-tabs"
└─────────────────────────────────────────────────────────────────────────────┘
```
* Status strip (top-right): [Lights Out] [Dose 1 Taken 22:47] [Window: 2.5–4h]
* Global FAB (bottom-right on iOS): [+ Bathroom]  testid="fab-bathroom"
* Haptics: medium for primaries; gentle for information; strong for warnings

---

## Screen A — TONIGHT (Primary)

### A1. Post‑Dose‑1, Pre‑Dose‑2 (default)
```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Title: Tonight                                                             │
│  Subtitle: We’ll pick your best minute inside 2.5–4h                        │
│                                                                             │
│              ┌─────────────────────────────────────────┐                    │
│              │              COUNTDOWN RING             │                    │
│              │                                         │                    │
│              │           01:12:34  (HH:MM:SS)          │  testid="timer"    │
│              │          Target: 01:45 (t* = 195m)      │  testid="target"   │
│              └─────────────────────────────────────────┘                    │
│                                                                             │
│      ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐          │
│      │  [A] TAKE NOW   │  │  SNOOZE 10m     │  │    SKIP         │          │
│      └─────────────────┘  └─────────────────┘  └─────────────────┘          │
│      testid="btn-take"      testid="btn-snooze"    testid="btn-skip"        │
│                                                                             │
│  ▸ Smart Nudge: Light stage + HR↑ slight; pulled +10m from baseline.        │
│  Chips: [Inside Window] [Nudge +10] [Quiet Mode On]                          │
│  Footer tip: Stay in bed after each dose.                                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

### A2. Within ±5m of Target
* Countdown ring pulses softly; TAKE NOW button subtle breathing effect.
* Microcopy → “Ideal moment now (Light stage).”

### A3. Snoozing
```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Snoozing… Next reminder in 10 minutes [Cancel Snooze] [Take Now]            │
└─────────────────────────────────────────────────────────────────────────────┘
```
* Chips update: [Snooze • 10m remaining]

### A4. Pre‑Dose‑1 (bedtime)
```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Title: Tonight                                                             │
│  Card: Take Dose 1 at bedtime → [TAKE DOSE 1]  [Remind in 5m]               │
│  Note: Dose 2 target will appear after Dose 1.                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### A5. Post‑Dose‑2 (completed)
```
┌─────────────────────────────────────────────────────────────────────────────┐
│  ✔ Done for tonight                                                         │
│  Summary chips: [Dose1→Dose2: 193m] [Inside Window] [Natural Wake? yes]     │
│  CTA: View Timeline →                                                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Screen B — TIMELINE (Night View)
```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Title: Timeline                                                             │
│ Date selector: ◄ Tue, Sep 2 ►  [Today]                                      │
│                                                                             │
│ STAGE BANDS:                                                                │
│  Deep ████████  Light ░░░░░░░  REM ▒▒▒▒▒▒▒  Wake ┄┄┄┄ (time →)              │
│  Markers: ● Dose1 22:47  ● Bathroom 01:03  ★ Target 02:57  ● Dose2 02:55    │
│                                                                             │
│ HR / RR overlay:  HR ────╮╭───  RR ──╮╭─╮─                                  │
│                                                                             │
│ Tap marker bottom sheet:                                                    │
│ ┌───────────────────────────────────────────────────────────────────────┐  │
│ │ Dose 2 @ 02:55 (193m)  Inside window                                   │  │
│ │ Why now: Light stage + HR drift + recent bathroom (−8m)                 │  │
│ │ Immutable record (no edit/delete)                                       │  │
│ └───────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```
* Filters row: [Stages] [HR] [RR] [SpO₂] [Markers]
* Export button (top-right): [CSV]

---

## Screen C — INSIGHTS (N‑of‑One)
```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Title: Insights                                                             │
│                                                                             │
│  ┌─────────────────────────┐  ┌─────────────────────────┐  ┌────────────────┐│
│  │ On‑Time Inside Window   │  │ Dose1→Dose2 Interval    │  │ Natural‑Wake % ││
│  │  86%  (14/16 nights)    │  │  Median 195m (min 162)  │  │  63%           ││
│  └─────────────────────────┘  └─────────────────────────┘  └────────────────┘│
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │ WASO after Dose‑2                                                       │  │
│  │  sparkline ▒▒▒▒▒                                                       │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  Chips: [Phase A Baseline] [Phase B Adaptive] [Compare]                     │
│  CTA row: [Export CSV]  [Mark bad data night]                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Screen D — SETTINGS → XYWAV
```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Title: Settings ▸ XYWAV                                                     │
│                                                                             │
│  Card: Window (read‑only)                                                   │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │ 2.5–4 hours after Dose 1 (Clamp 150–240 min)                           │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  Card: Defaults                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │ • Default Dose‑2 target: 165 min   [Edit]                               │  │
│  │ • Nudge step: 10 min  (options: 10 | 15)                                │  │
│  │ • Snooze: 10 min  (options: 5 | 10 | 15)                                │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  Card: Behavior                                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │ [✓] Adaptive moment detection (Light/REM + HR/RR drift)                 │  │
│  │ [✓] Pull forward after bathroom (−10m)                                  │  │
│  │ [ ] Announce with voice over (On‑device)                                │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  Card: Safety                                                                │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │ • Stays inside 2.5–4h window                                            │  │
│  │ • Stay in bed after each dose                                           │  │
│  │ • Never combine doses                                                   │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Screen E — DEVICES
```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Title: Devices                                                              │
│  Cards:                                                                     │
│   ┌──────────────────────────────┐  ┌──────────────────────────────┐        │
│   │ Apple Health                 │  │ WHOOP                        │        │
│   │ Status: Connected            │  │ Status: Connected            │        │
│   │ Streams: HR, RR, Stages      │  │ Streams: HR, RR, Stages      │        │
│   │ [Manage] [Re‑sync]           │  │ [Manage] [Re‑sync]           │        │
│   └──────────────────────────────┘  └──────────────────────────────┘        │
│   ┌──────────────────────────────┐                                         │
│   │ Flic Button                  │                                         │
│   │ Status: Paired               │                                         │
│   │ Actions: [Lights Out] [Bathroom] [Take Dose]                           │
│   │ [Configure]                                                       │     │
│   └──────────────────────────────┘                                         │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Sheets & Modals
M1. Take Dose (confirmation)
```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Take Dose 2 now?                                                            │
│ [Take] [Cancel]                                                             │
│ Subcopy: You’re inside the window.                                          │
└─────────────────────────────────────────────────────────────────────────────┘
```
M2. Snooze
```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Snooze reminder for: [5m] [10m] [15m] [Cancel]                              │
└─────────────────────────────────────────────────────────────────────────────┘
```
M3. Bathroom Quick Log
```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Bathroom break logged. Next reminder pulled forward 10 min. [Undo]          │
└─────────────────────────────────────────────────────────────────────────────┘
```
M4. Safety Alert
```
┌─────────────────────────────────────────────────────────────────────────────┐
│ ⚠ Outside 2.5–4h window. Take is disabled.                                  │
│ [OK]                                                                         │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## watchOS — Compact Layout
```
┌──────────────────────────────────────────┐
│   01:12:34 To Target                     │
│  ┌────────────────────────────────────┐  │
│  │  TAKE NOW                        │  │  testid="watch-take"
│  └────────────────────────────────────┘  │
│  [Snooze 10m]    [Skip]                  │
│  Footer: Inside window                   │
└──────────────────────────────────────────┘
```
* Swipe left → Timeline mini (markers + last hour band)
* Long‑press → Bathroom quick log

---

## Empty States & Errors
E1. No Devices Connected
```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Connect a data source for better picks. [Connect Apple Health] [Connect WHOOP] │
└─────────────────────────────────────────────────────────────────────────────┘
```
E2. Insufficient same‑night signal
```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Signals are quiet; we’ll use your baseline (center of window).              │
└─────────────────────────────────────────────────────────────────────────────┘
```
E3. Sync error
```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Couldn’t sync HR/RR. We’ll retry in the background. [Retry now]             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Component IDs (QA & Accessibility)
* timer: testid="timer" (aria-live polite, tabular numerals)
* target: testid="target"
* btn-take / btn-snooze / btn-skip
* fab-bathroom
* export: btn-export-csv

---

## Microcopy (Samples)
* Tonight subtitle: “We’ll pick your best minute inside 2.5–4h.”
* Near target: “Ideal moment now (Light stage).”
* Safety card: “Stay in bed after each dose. Never combine doses.”

---

## Visual Polish Notes
* Animated countdown ring pulse ±5m window.
* High contrast mode toggle elevates key actions ≥7:1 (baseline ≥4.5:1).
* Large tap areas ≥48pt; gentle haptics.
* Undo snackbar: dark surface "Taken. Undo (5)" countdown (polite aria-live, single VO announcement).

---

## Acceptance Criteria (UI Only)

1. Tonight: countdown ring + Take/Snooze/Skip + nudge chips.
2. Timeline: stage bands + HR/RR sparklines + marker sheet why-now.
3. Insights: on-time %, interval stats, natural-wake %, WASO sparkline, CSV export.
4. Settings→XYWAV: clamp (read-only) + default target edit + nudge & snooze controls.
5. Devices: manages Health/WHOOP/Flic connect & re-sync.
6. watchOS: large TAKE, Snooze, Skip, mini timeline gesture.

---

## Removed Legacy Elements

* Login / multi-user
* Medication CRUD / lists / refills
* Adherence-by-medication charts
* Provider / pharmacy integrations

---

## Accessibility: VoiceOver & Haptics

* −5m: "Dose 2 window closes in five minutes"
* Target: "Dose 2 target now"
* 240m: "Dose 2 window ended"
* <15m countdown: announce every 30s (polite)
* Undo: "Dose logged. Undo available five seconds"
* watchOS Take hold: hint "Press and hold one second to take Dose 2"

## Open Questions

* Light mode (deferred)
* Extended bathroom event classification (ignored v1)

---

End of v2.0 spec.
