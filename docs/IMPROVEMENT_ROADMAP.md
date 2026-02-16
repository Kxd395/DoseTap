# DoseTap Improvement Roadmap

> **Created:** 2026-02-16  
> **Branch:** `chore/audit-2026-02-15`  
> **Context:** Post-audit deep review of WHOOP integration, button states, and design gaps  

---

## Executive Summary

A deep code audit of the running app versus source reveals three critical themes:

1. **WHOOP shows "Connected" but delivers zero real data to any view** — the integration is cosmetic
2. **Dose button logic is duplicated across 4 surfaces with divergent safety behavior** — creating real clinical risk
3. **Several features are skeleton/placeholder** — Night Review health data is hardcoded, Timeline biometrics are simulated, CloudKit sync is non-functional

---

## ⛔ P0 — Critical (Safety & Integrity)

### P0-1: WHOOP Data Is Decorative Only

**Problem:** Dashboard shows "WHOOP · Connected" with a green dot (visible in the screenshot), but NO actual WHOOP data (recovery, strain, HRV, sleep score) flows to any view.

| Surface | What Happens | Evidence |
|---------|-------------|----------|
| **Dashboard** | Integration status card only — shows "Connected" string, no metrics | `DashboardModels.swift:735-746` — only builds status text |
| **Timeline** | Calls `fetchRecentSleep()` then generates **SIMULATED** data via `sin()` curves | `SleepTimelineOverlays.swift:361-394` — comment: "For now, create sample data" |
| **Night Review** | Shows **HARDCODED** values: "Recovery: 68%", "HRV: 45ms", "Sleep Score: 82" | `NightReviewView.swift:607-615` — TODO comment present |
| **DashboardNightAggregate** | Has `healthSummary` (HealthKit) but **no WHOOP fields at all** | `DashboardModels.swift:60-97` — struct definition |

**Fix:** Either wire `WHOOPDataFetching` (which has 7 real fetch functions built) into `DashboardNightAggregate` and views, or remove the "Connected" status entirely to avoid misleading users.

**Effort:** M (3-5 days) — fetching infrastructure exists, needs view plumbing + per-night storage

---

### P0-2: Snooze <15m Check Missing from UI Buttons

**Problem:** The SSOT states "Snooze disabled when <15m remain" but both `CompactDoseButton` and `DoseButtonsSection` only check `snoozeCount < 3`. The Flic path correctly uses `DoseWindowContext.snooze` which enforces both limits.

**Evidence:**
- Tonight: `snoozeEnabled = (core.currentStatus == .active || core.currentStatus == .nearClose) && core.snoozeCount < 3` — **no time check** (`CompactDoseButton.swift:223`)
- History: identical logic (`HistoryViews.swift:1049`)
- Flic: `guard case .snoozeEnabled = context.snooze` — **correctly checks both** (`FlicButtonService.swift:297`)

**Fix:** Replace the manual boolean with `DoseWindowContext.snooze` enum check in all button views.

**Effort:** S (1-2 hours)

---

### P0-3: Flic Button Bypasses Late-Dose Confirmation

**Problem:** When status is `.closed`, the Flic button logs Dose 2 directly with only a haptic warning. The Tonight UI correctly shows an alert requiring explicit "Take Dose 2 Anyway" confirmation. Same issue for extra-dose (3rd dose) path.

**Evidence:**
- Flic `.closed`: `sessionRepository.saveDose2(timestamp: now)` + `provideHapticFeedback(.warning)` — no confirmation (`FlicButtonService.swift:233-247`)
- Flic extra-dose: `sessionRepository.saveDose2(timestamp: now, isExtraDose: true)` — no safety dialog (`FlicButtonService.swift:261`)
- Tonight `.closed`: Shows `showWindowExpiredOverride` alert requiring destructive button tap (`CompactDoseButton.swift:38-43`)

**Fix:** Either block late/extra doses from Flic entirely, or queue a local notification asking user to confirm via the app UI before persisting.

**Effort:** S (2-4 hours)

---

### P0-4: Dose Button Logic Duplicated Across 4 Surfaces

**Problem:** Nearly identical dose registration logic exists in 4 places with subtle but important differences:

| Surface | File | EventLogger | Undo | Alarm Schedule | Extra Dose Warning | Theme Colors | Late Confirm |
|---------|------|:-----------:|:----:|:--------------:|:-----------------:|:------------:|:------------:|
| **Tonight** (CompactDoseButton) | `CompactDoseButton.swift` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **History** (DoseButtonsSection) | `HistoryViews.swift:931` | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| **Flic** (FlicButtonService) | `FlicButtonService.swift` | ❌ | ❌ | ✅ | ❌ | N/A | ❌ |
| **Deep Link** (URLRouter) | `URLRouter.swift` | ❌ | ❌ | ❌ | ❌ | N/A | ❌ |

**Fix:** Extract a unified `DoseActionCoordinator` that all 4 surfaces call. This coordinator handles: validation → confirmation routing → persistence → alarm scheduling → event logging → undo registration.

**Effort:** L (3-5 days) — architectural refactor touching 4 files + tests

---

## 🔴 P1 — High (Functionality Gaps)

### P1-1: Night Review Health Data Is Hardcoded

**Problem:** `HealthDataCard` in Night Review displays static values ("Recovery: 68%", "HRV: 45ms", "Sleep Score: 82") with a TODO comment. Users see fake data that looks real.

**File:** `NightReviewView.swift:586-615`

**Fix:** Wire `HealthKitService.fetchSleepSummary(for:)` and `WHOOPService.fetchSleepForNight(_:)` into the card, or hide the card entirely when no real data exists.

**Effort:** M (2-3 days)

---

### P1-2: Timeline Biometric Overlays Are Simulated

**Problem:** `extractBiometricData(from:)` generates heart rate, respiratory rate, and HRV data using mathematical functions (`sin()`, `random()`), not actual WHOOP API data. The comment explicitly says "In a real implementation, this would come from the WHOOP sleep stages endpoint."

**File:** `SleepTimelineOverlays.swift:354-394`

**Fix:** Replace with `WHOOPDataFetching.fetchHeartRateData()` and `fetchSleepStages()` calls. The endpoints already exist.

**Effort:** M (2-3 days)

---

### P1-3: DashboardNightAggregate Has No WHOOP Fields

**Problem:** The night aggregate model that powers all Dashboard analytics has `healthSummary` for HealthKit data but absolutely no fields for WHOOP metrics. Even when WHOOP is connected, recovery/strain/HRV can't appear in trend charts.

**Fix:** Add `whoopSummary: WHOOPNightSummary?` to `DashboardNightAggregate` and populate during `refreshData()`. Add WHOOP metric cards/charts to Dashboard.

**Effort:** L (3-5 days) — model change + view work + trend chart integration

---

### P1-4: No Dose-Sleep Quality Correlation View

**Problem:** The most valuable insight for XYWAV users — "how does my dose timing affect my sleep quality?" — doesn't exist anywhere in the app. The data is there (dose intervals + HealthKit sleep + WHOOP recovery) but no view correlates them.

**Fix:** Add a "Dose Effectiveness" card to Dashboard showing scatter plot: X=interval minutes, Y=sleep quality metrics. Highlight optimal timing zone (150-165m) vs outliers.

**Effort:** L (5-7 days) — new view + analytics model + chart

---

### P1-5: CloudKit Sync Is Non-Functional Skeleton

**Problem:** Dashboard shows "Cloud Sync · Disabled" with "requires iCloud entitlements" message. The `CloudKitSyncService` has a full implementation (~600 LOC) but the iCloud entitlement is not enabled in the project.

**Fix:** Decide: enable iCloud entitlement and test sync, or remove the skeleton to avoid confusion.

**Effort:** M (3-5 days) if enabling, S (1 day) if removing

---

### P1-6: NightScoreCalculator Not Surfaced

**Problem:** `NightScoreCalculator.swift` exists for computing multi-factor night quality scores, but the resulting score doesn't appear in any view (Night Review, Dashboard, or History).

**Fix:** Add a "Night Score" badge/card to Night Review and as a column in Dashboard trend charts.

**Effort:** S (1-2 days)

---

## 🟡 P2 — Medium (UX & Polish)

### P2-1: No Widget Support

**Problem:** No WidgetKit integration. Users can't see dose status, countdown, or next action from the Lock Screen or Home Screen — they must open the app.

**Fix:** Add a WidgetKit target with: (1) lock screen countdown widget, (2) home screen dose status widget, (3) StandBy mode large widget.

**Effort:** L (5-7 days)

---

### P2-2: No Siri Shortcuts / AppIntents

**Problem:** `URLRouter` handles deep links but there's no `AppIntents` framework integration. Users can't say "Hey Siri, take my first dose" or create Shortcuts automations.

**Fix:** Add `AppIntent` conformances for: TakeDose1, TakeDose2, LogEvent, CheckDoseStatus. Register as Shortcuts.

**Effort:** M (3-5 days)

---

### P2-3: No watchOS Companion

**Problem:** `watchos/` directory exists with only assets. No WatchKit app. For a dose timer app, wrist access is extremely valuable — users often take doses in bed.

**Fix:** Create a minimal watchOS target: dose status complication + "Take Dose" button + countdown.

**Effort:** XL (2-3 weeks)

---

### P2-4: DateFormatter Performance

**Problem:** Multiple views create new `DateFormatter` instances inline on every render. DateFormatter initialization is expensive (~50ms per instance).

**Evidence:** Found 15+ instances of `DateFormatter()` in view bodies and non-static contexts across `SettingsView`, `TonightView`, `DiagnosticExportView`, `EditDoseTimeView`, and others.

**Fix:** Move all formatters to `static let` properties on their containing types or a shared `Formatters` enum.

**Effort:** S (2-3 hours)

---

### P2-5: Missing Pull-to-Refresh on Dashboard & History

**Problem:** Dashboard and History don't have pull-to-refresh. Users must switch tabs or relaunch to see updated data.

**Fix:** Add `.refreshable { await model.refreshData() }` to both views.

**Effort:** XS (30 minutes)

---

### P2-6: No History Search

**Problem:** Users with months of data (screenshot shows 114 nights) can't search for specific sessions, events, or dates.

**Fix:** Add a search bar to History with filtering by date range, event type, and dose status.

**Effort:** M (2-3 days)

---

### P2-7: Coach Insight Generator Visibility

**Problem:** `CoachInsightGenerator.swift` exists for generating AI-style narrative summaries but it's unclear if it's surfaced to users in any prominent way.

**Fix:** Audit usage and either promote to a visible "Night Coach" card in Night Review/Dashboard, or remove dead code.

**Effort:** S (1-2 days)

---

### P2-8: No iPad / Landscape Layout

**Problem:** All views appear to be phone-only. Dashboard charts and Timeline would benefit significantly from wider layouts.

**Fix:** Add `NavigationSplitView` for iPad and landscape-aware layouts for chart views.

**Effort:** L (5-7 days)

---

## 🟢 P3 — Low (Nice to Have)

| # | Improvement | Effort |
|---|------------|--------|
| 1 | Add haptic feedback to all dose buttons (Tonight has it, History doesn't) | XS |
| 2 | Add confirmation sound when dose is logged (accessibility) | XS |
| 3 | Show WHOOP connection status in Tonight tab header | XS |
| 4 | Add "time since last event" badges on QuickLog buttons | S |
| 5 | Add swipe-to-delete on History event rows | S |
| 6 | Add session comparison view (compare two nights side-by-side) | M |
| 7 | Add data export scheduling (weekly auto-export to Files) | M |
| 8 | Add medication interaction warnings based on dosing amounts | L |
| 9 | Dark mode audit — verify all custom colors in both modes | S |
| 10 | Add animation to dose window countdown (progress ring) | M |

---

## Effort Legend

| Size | Time | Description |
|------|------|-------------|
| **XS** | < 1 hour | Config change or one-liner |
| **S** | 1-4 hours | Single file, focused fix |
| **M** | 1-5 days | Multi-file, moderate complexity |
| **L** | 3-7 days | Architectural, many files |
| **XL** | 1-3 weeks | New target or major feature |

---

## Recommended Priority Order

**Phase 1 — Safety & Trust (1-2 weeks)**
1. P0-2: Fix snooze <15m check in UI buttons
2. P0-3: Fix Flic late-dose bypass
3. P0-4: Extract DoseActionCoordinator (unifies all 4 surfaces)
4. P1-1: Remove hardcoded health data from Night Review

**Phase 2 — WHOOP for Real (2-3 weeks)**
5. P0-1: Wire WHOOP data to Dashboard + Night Review + Timeline
6. P1-2: Replace simulated biometric overlays with real data
7. P1-3: Add WHOOP fields to DashboardNightAggregate
8. P1-6: Surface NightScoreCalculator

**Phase 3 — User Value (2-4 weeks)**
9. P1-4: Dose-sleep quality correlation view
10. P2-1: Widget support
11. P2-2: Siri Shortcuts / AppIntents
12. P2-5: Pull-to-refresh
13. P2-4: DateFormatter performance

**Phase 4 — Platform Expansion (3-6 weeks)**
14. P2-3: watchOS companion
15. P2-8: iPad / landscape
16. P1-5: CloudKit sync decision
17. P2-6: History search

---

## Cross-References

- **Audit findings:** `docs/audit/2026-02-15/`
- **WHOOP integration doc:** `docs/WHOOP_INTEGRATION.md`
- **Dose registration architecture:** `docs/review/dose_registration_architecture_2026-02-15.md`
- **Architecture:** `docs/architecture.md`
- **SSOT:** `docs/SSOT/README.md`

---

*Generated: 2026-02-16 | Version: 0.3.2 alpha*
