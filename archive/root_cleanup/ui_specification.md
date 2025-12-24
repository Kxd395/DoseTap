# DoseTap UI Specification - Night-First Design

## Design System

### Color Palette (Dark Mode Default)

```css
/* Base Colors */
--color-base: #0B1220;      /* Ink black background */
--color-surface: #11192A;   /* Elevated surface */
--color-card: #141F33;      /* Card background (6-8% elevation) */

/* Action Colors */
--color-accent: #22D3EE;    /* Cyan-teal for primary actions */
--color-positive: #34D399;  /* Success/take actions */
--color-warning: #F59E0B;   /* Snooze/caution */
--color-danger: #EF4444;    /* Skip/critical */

/* Text Colors */
--color-text-primary: #F9FAFB;
--color-text-secondary: #9CA3AF;
--color-text-muted: #6B7280;
```

### Typography

```css
/* UI Font Stack */
--font-ui: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;

/* Display Numbers */
--font-display: 'SF Pro Rounded', -apple-system-ui-rounded, system-ui;

/* Font Sizes */
--text-xs: 0.75rem;    /* 12px */
--text-sm: 0.875rem;   /* 14px */
--text-base: 1rem;     /* 16px */
--text-lg: 1.125rem;   /* 18px */
--text-xl: 1.25rem;    /* 20px */
--text-2xl: 1.5rem;    /* 24px */
--text-3xl: 1.875rem;  /* 30px */
--text-4xl: 2.25rem;   /* 36px */
--text-5xl: 3rem;      /* 48px */
--text-6xl: 3.75rem;   /* 60px */
```

## Screen Layouts

### 1. Tonight Screen (Primary)

```
┌─────────────────────────────────┐
│        TONIGHT                   │
│                                  │
│     ┌───────────────┐           │
│     │               │           │
│     │   02:47:23    │           │ <- Countdown (--text-6xl, tabular)
│     │               │           │
│     │  ◯━━━━━━━━━◯  │           │ <- Ring progress
│     └───────────────┘           │
│                                  │
│  "Dose 2 in light sleep"        │ <- Microcopy (--text-sm)
│  "We'll never go outside        │
│   2.5-4 hours"                  │
│                                  │
│ ┌─────────────────────────────┐ │
│ │       TAKE DOSE 2           │ │ <- Primary (--color-accent)
│ └─────────────────────────────┘ │
│                                  │
│ ┌──────────┐  ┌──────────────┐ │
│ │ SNOOZE   │  │    SKIP      │ │ <- Secondary actions
│ │  10 MIN  │  │              │ │
│ └──────────┘  └──────────────┘ │
└─────────────────────────────────┘

Component IDs:
- testid="countdown-timer"
- testid="countdown-ring"
- testid="btn-take"
- testid="btn-snooze"
- testid="btn-skip"
```

### 2. Timeline Screen

```
┌─────────────────────────────────┐
│        TIMELINE                  │
│                                  │
│  Tonight · Dec 20               │
│                                  │
│ ┌─────────────────────────────┐ │
│ │ 10PM    2AM    6AM          │ │
│ │ ━━━━━━━━━━━━━━━━━━━━━━━━━━ │ │
│ │ ████░░░░████░░░░░░████░░░░ │ │ <- Sleep stages
│ │ ～～～～～～～～～～～～～～～ │ │ <- HR/RR overlay
│ │  ↓D1    ↓B    ↓D2          │ │ <- Event markers
│ └─────────────────────────────┘ │
│                                  │
│ Legend:                         │
│ ■ Deep  ░ Light  ▓ REM         │
│                                  │
│ Events:                         │
│ • Dose 1: 10:45 PM             │
│ • Bathroom: 1:23 AM            │
│ • Dose 2: 2:30 AM (165 min)    │
│                                  │
│ [View Previous Night]           │
└─────────────────────────────────┘

Component IDs:
- testid="timeline-view"
- testid="sleep-stages"
- testid="event-markers"
```

### 3. Insights Screen

```
┌─────────────────────────────────┐
│        INSIGHTS                  │
│                                  │
│ ┌─────────────────────────────┐ │
│ │ Dose Timing                 │ │
│ │ Median: 167 min             │ │
│ │ Range: 155-182 min          │ │
│ │ On-time: 94%                │ │
│ └─────────────────────────────┘ │
│                                  │
│ ┌─────────────────────────────┐ │
│ │ Natural Wake                │ │
│ │ This week: 71%              │ │
│ │ Trend: ↑ +5%                │ │
│ └─────────────────────────────┘ │
│                                  │
│ ┌─────────────────────────────┐ │
│ │ WASO Post-Dose 2            │ │
│ │ Average: 12 min             │ │
│ │ Best: 7 min (Dec 18)        │ │
│ └─────────────────────────────┘ │
│                                  │
│ [Export CSV]                    │
└─────────────────────────────────┘

Component IDs:
- testid="insights-cards"
- testid="metric-dose-timing"
- testid="metric-natural-wake"
- testid="metric-waso"
- testid="btn-export-csv"
```

### 4. Settings → XYWAV

```
┌─────────────────────────────────┐
│     SETTINGS → XYWAV            │
│                                  │
│ Dose 2 Window                   │
│ ┌─────────────────────────────┐ │
│ │ Min: 150 min (2.5 hours)    │ │
│ │ Max: 240 min (4.0 hours)    │ │
│ │ Default: 165 min            │ │
│ └─────────────────────────────┘ │
│                                  │
│ Adaptive Nudging                │
│ ┌─────────────────────────────┐ │
│ │ [✓] Enable smart timing     │ │
│ │ Step size: 10 min           │ │
│ │ TTFW baseline: 185 min      │ │
│ └─────────────────────────────┘ │
│                                  │
│ Notifications                   │
│ ┌─────────────────────────────┐ │
│ │ [✓] Dose 2 reminder         │ │
│ │ [✓] Critical alerts         │ │
│ │ Sound: Gentle Chime         │ │
│ └─────────────────────────────┘ │
└─────────────────────────────────┘

Component IDs:
- testid="settings-xywav"
- testid="input-window-min"
- testid="input-window-max"
- testid="input-default"
- testid="toggle-nudging"
```

### 5. WatchOS Layout

```
┌──────────────┐
│   02:47:23   │ <- Large countdown
│              │
│ ┌──────────┐ │
│ │   TAKE   │ │ <- Full width
│ │  DOSE 2  │ │    green button
│ └──────────┘ │
│              │
│ ┌──────────┐ │
│ │  SNOOZE  │ │ <- Yellow
│ │  10 MIN  │ │
│ └──────────┘ │
│              │
│ ┌──────────┐ │
│ │   SKIP   │ │ <- Red
│ └──────────┘ │
└──────────────┘

Haptic Feedback:
- Take: Success haptic
- Snooze: Warning haptic
- Skip: Notification haptic
```

## Component States

### Button States

```css
/* Primary Button (Take) */
.btn-primary {
  background: var(--color-accent);
  color: var(--color-base);
  font-weight: 600;
  font-size: var(--text-lg);
  padding: 1rem 2rem;
  border-radius: 0.75rem;
}

.btn-primary:active {
  transform: scale(0.98);
  background: color-mix(in srgb, var(--color-accent) 80%, white);
}

/* Secondary Buttons */
.btn-snooze {
  background: var(--color-warning);
}

.btn-skip {
  background: transparent;
  border: 2px solid var(--color-danger);
  color: var(--color-danger);
}
```

### Countdown Ring Animation

```css
@keyframes pulse-ring {
  0%, 100% { opacity: 0.6; transform: scale(1); }
  50% { opacity: 1; transform: scale(1.02); }
}

.countdown-ring.warning {
  animation: pulse-ring 2s ease-in-out infinite;
}
```

## Empty States

### No Dose 1 Taken
```
"Take your first dose to start tonight's schedule"
[RECORD DOSE 1]
```

### Timeline - No Data
```
"No sleep data available yet.
Connect your devices in Settings."
[GO TO DEVICES]
```

## Error States

### Notification Permission Denied
```
"⚠️ Notifications disabled
You won't receive Dose 2 reminders.
[ENABLE IN SETTINGS]"
```

### HealthKit Disconnected
```
"❌ HealthKit connection lost
Adaptive timing unavailable.
[RECONNECT]"
```

## Accessibility

- All interactive elements min 44x44pt
- Color contrast ratios ≥ 4.5:1 for normal text
- VoiceOver labels for all actions
- Dynamic Type support
- Reduce Motion: disable ring animations

## Testing IDs Reference

```javascript
// Primary actions
testid="btn-take"
testid="btn-snooze"
testid="btn-skip"

// Navigation
testid="tab-tonight"
testid="tab-timeline"
testid="tab-insights"
testid="tab-devices"
testid="tab-settings"

// Key components
testid="countdown-timer"
testid="countdown-ring"
testid="timeline-view"
testid="insights-cards"
testid="settings-xywav"

// Metrics
testid="metric-dose-timing"
testid="metric-natural-wake"
testid="metric-waso"
```
