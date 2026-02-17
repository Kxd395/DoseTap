# DoseTap Improvement Roadmap

> **Created:** 2026-02-16  
> **Branch:** `chore/audit-2026-02-15`  
> **Context:** Post-audit deep review of WHOOP integration, button states, and design gaps  

---

## Executive Summary

A deep code audit of the running app versus source reveals five critical themes:

1. **WHOOP shows "Connected" but delivers zero real data to any view** — the integration is cosmetic
2. **Dose button logic is duplicated across 4 surfaces with divergent safety behavior** — creating real clinical risk
3. **Deep links can mutate medication state without user authorization** — any app can fire dose URLs
4. **WHOOP OAuth sends client_secret from mobile app without PKCE** — security anti-pattern
5. **Several features are skeleton/placeholder** — Night Review health data is hardcoded, Timeline biometrics are simulated, CloudKit sync is non-functional

---

## ⛔ P0 — Critical (Safety & Integrity)

### ✅ P0-1: WHOOP Data Is Decorative Only — RESOLVED

**Status:** Fixed in commit on `chore/audit-2026-02-15`

**Changes:**
- `NightReviewView.swift` `HealthDataCard`: Removed hardcoded "Recovery: 68%, HRV: 45ms, Sleep Score: 82". WHOOP section now guarded behind `WHOOPService.isEnabled` and shows real connection status or "Not connected".
- `SleepTimelineOverlays.swift` `extractBiometricData()`: Early-returns empty arrays when `!WHOOPService.isEnabled`. Added clear "simulated data" documentation.
- `DashboardModels.swift` `buildIntegrationStates()`: When `!WHOOPService.isEnabled`, shows "Disabled (Feature Flag)" with "Coming in a future update" text instead of misleading "Connected" status.

**Remaining:** When WHOOP is re-enabled (P0-6 PKCE is done), wire `WHOOPDataFetching` fetch methods into views for real data. See P1-1, P1-2, P1-3.

---

### ✅ P0-2: Snooze <15m Check Missing from UI Buttons — RESOLVED

**Status:** Fixed in commit `5948293` on `chore/audit-2026-02-15`

**Changes:** All UI surfaces (CompactDoseButton, DoseButtonsSection) now use `DoseWindowContext.snooze` enum instead of manual `snoozeCount < 3` check, matching Flic's correct behavior.

---

### ✅ P0-3: Flic Button Bypasses Late-Dose Confirmation — RESOLVED

**Status:** Fixed in commit `5948293` on `chore/audit-2026-02-15`

**Changes:** Flic `.closed` and extra-dose paths now block direct persistence. Instead they send a local notification prompting user to open the app for confirmation.

---

### ✅ P0-4: Dose Button Logic Duplicated Across 4 Surfaces — RESOLVED

**Status:** Fixed on `chore/audit-2026-02-15`

**Changes:**
- Created `DoseActionCoordinator.swift` (~230 lines): centralised coordinator handling validation → confirmation routing → persistence → alarm scheduling → event logging → undo registration.
- Wired into **CompactDoseButton** (Tonight tab) and **DoseButtonsSection** (History tab) with legacy fallback when coordinator is nil.
- **FlicButtonService** and **URLRouter** retain independent-but-equivalent safety validation (P0-3 blocks + P0-5 foreground guards). Coordinator available for future consolidation.
- `ActionResult` enum: `.success(message)`, `.needsConfirm(ConfirmationType)`, `.blocked(reason)`
- `ConfirmationType`: `.earlyDose(minutesRemaining)`, `.lateDose`, `.afterSkip`, `.extraDose`

---


### ✅ P0-5: Deep Links Mutate Medication State Without Authorization — RESOLVED

**Status:** Fixed in commit `5948293` on `chore/audit-2026-02-15`

**Changes:** URLRouter now requires `UIApplication.shared.applicationState == .active` and `isProtectedDataAvailable` for all state-changing deep links (dose1, dose2, snooze, skip). Late-dose and extra-dose deep links are blocked with "open app to confirm" feedback.

---

### ✅ P0-6: WHOOP OAuth Uses Client Secret Without PKCE — RESOLVED

**Status:** Fixed on `chore/audit-2026-02-15`

**Changes:**
- Added PKCE support to `WHOOPService.swift`: `generateCodeVerifier()` (32 random bytes → base64url), `codeChallenge(from:)` (SHA256 → base64url).
- `authorize()`: Sends `code_challenge` + `code_challenge_method=S256` in auth URL.
- `exchangeCodeForTokens()`: Sends `code_verifier` instead of `client_secret`.
- `refreshAccessToken()`: Uses `client_id` only — no `client_secret` (public client per PKCE spec).
- Removed `clientSecret` property from service. `SecureConfig.whoopClientSecret` infrastructure retained for potential backend-mediated flow.

**Note:** WHOOP feature remains behind `isEnabled = false` flag. Credential rotation recommended before enabling.

---

## 🔴 P1 — High (Functionality Gaps)

### ✅ P1-1: Night Review Health Data Is Hardcoded — RESOLVED

**Problem:** `HealthDataCard` in Night Review displayed static values ("Recovery: 68%", "HRV: 45ms", "Sleep Score: 82"). Users saw fake data that looked real.

**Resolution:** Removed hardcoded values. Apple Health section now shows "Connect in Settings → Integrations" placeholder until HealthKit is wired. WHOOP section remains gated behind `WHOOPService.isEnabled`.

---

### ✅ P1-2: Timeline Biometric Overlays Are Simulated — RESOLVED

**Problem:** `extractBiometricData(from:)` generated heart rate, respiratory rate, and HRV data using `sin()` and `random()` — not actual WHOOP API data.

**Resolution:**
- `extractBiometricData()` is now `async` and calls real WHOOP APIs:
  - Heart rate: `fetchHeartRateData()` returns actual per-minute HR from WHOOP
  - Respiratory rate: uses WHOOP score-level `respiratoryRate` (best available from API)
  - HRV: uses session-level HRV from recovery merge (per-epoch HRV not available in WHOOP public API)
- Removed all `sin()`/`random()` simulated data generation
- Graceful fallback: empty arrays when WHOOP disabled or API fails
- Call site in `LiveEnhancedTimelineView.loadData()` updated with `await`

---

### ✅ P1-3: DashboardNightAggregate Has No WHOOP Fields — RESOLVED

**Problem:** The night aggregate model had `healthSummary` for HealthKit but no WHOOP fields. Recovery/HRV/strain couldn't appear in Dashboard analytics.

**Resolution:**
- Added `whoopSummary: WHOOPNightSummary?` to `DashboardNightAggregate`
- `totalSleepMinutes` now prefers WHOOP data, falls back to HealthKit
- WHOOP computed properties: `whoopRecoveryScore`, `whoopHRV`, `whoopSleepEfficiency`, `whoopRespiratoryRate`, `whoopDisturbances`, `whoopDeepSleepMinutes`
- `dataCompletenessScore` and `hasAnyData` include WHOOP presence
- `DashboardAnalyticsModel`: added `whoopNights`, `averageWhoopRecovery/HRV/Efficiency/RR`
- `performRefresh` fetches WHOOP sleep + recovery data, merges by session key
- `buildIntegrationStates` shows real WHOOP night count when connected
- `DashboardSleepSnapshotCard`: WHOOP Metrics section with recovery/HRV/efficiency/RR
- `DashboardRecentNightsCard`: per-night recovery badge (color-coded green/orange/red)
- `WHOOPNightSummary` gains `recoveryScore`, `hrvMs`, `restingHeartRate`, `hasValidSleepData`
- Night Review `HealthDataCard` loads real WHOOP data per-session with loading state
- `WHOOPSettingsView`: filters unscored nights, shows recovery/HRV, fixes 0h 0m display

---

### ✅ P1-4: Dose-Sleep Quality Correlation Analytics — RESOLVED

**Problem:** The most valuable insight for XYWAV users — "how does my dose timing affect my sleep quality?" — didn't exist anywhere in the app. The data was there (dose intervals + HealthKit sleep + WHOOP recovery) but nothing correlated them.

**Resolution:** Created `DoseEffectivenessCalculator` — a pure analytics model that:
- Partitions nights into optimal (150-165m), acceptable (166-240m), and non-compliant zones
- Computes zone-level averages: interval, total sleep, deep sleep, recovery, HRV, awakenings
- Calculates compliance rate and pairable nights count
- Detects trend (improving/worsening/stable) comparing recent vs prior interval averages
- Includes `IntervalFormat` enum (`.minutes` → "165m", `.hoursMinutes` → "2:45") so users can choose their preferred display format
- `IntervalFormat` is `Codable`/`Sendable`/`CaseIterable` for persistence in user preferences
- Convenience init from `UnifiedSleepSession` for seamless integration
- 43 Swift Testing tests covering zones, boundaries, averages, trends, and formatting

**Remaining:** Wire into a "Dose Effectiveness" card in Dashboard with chart visualisation.

---

### ⏸️ P1-5: CloudKit Sync Is Non-Functional Skeleton — DEFERRED

**Problem:** Dashboard shows "Cloud Sync · Disabled" with "requires iCloud entitlements" message. `CloudKitSyncService` has a complete implementation (~600 LOC) but the iCloud entitlement is not enabled.

**Decision:** Keep skeleton, defer activation. The code is:
- Well-structured with zone-based sync, change tokens, conflict resolution
- Properly guarded behind `DoseTapCloudSyncEnabled` Info.plist flag (defaults to false)
- Dashboard shows clear "Disabled" status with explanation when inactive
- Added prominent documentation header explaining the deferred state

**To enable later:** Add iCloud entitlement → create CloudKit container → set `DoseTapCloudSyncEnabled=true` in Info.plist → test sync with real iCloud account.

**Blocked by:** Paid Apple Developer Team profile requirement.

---

### ✅ P1-6: NightScoreCalculator Not Surfaced — RESOLVED

**Problem:** `NightScoreCalculator.swift` existed for computing multi-factor night quality scores, but the resulting score didn't appear in any view.

**Resolution:** Added `NightScoreCard` to Night Review with circular score indicator (0-100), colour-coded label (Excellent/Good/Fair/Needs Work), and 4-component breakdown bars (Interval Accuracy 40%, Dose Completeness 25%, Session Logging 20%, Sleep Quality 15%). Calculator registered in SwiftPM Package.swift with 24 unit tests.

---


### ✅ P1-7: Wake Alarm Naming Mismatch (Semantic Drift) — RESOLVED

**Problem:** `AlarmService` used `dosetap_wake_alarm` and `scheduleWakeAlarm()` but the alarm fires for Dose 2, not a wake alarm.

**Resolution:** Renamed across the codebase: `wakeAlarm` → `dose2Alarm`, `scheduleWakeAlarm` → `scheduleDose2Alarm`, `dosetap_wake_alarm` → `dosetap_dose2_alarm`, `dosetap_pre_alarm` → `dosetap_dose2_pre_alarm`. All callers updated in commit `a1da94c`.

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

### ✅ P2-4: DateFormatter Performance — RESOLVED

**Status:** Fixed 2026-02-16 on `chore/audit-2026-02-15`

**Changes:**
- Added `shortWeekday` formatter to `AppFormatters` enum
- Replaced 15+ inline `DateFormatter()` and `ISO8601DateFormatter()` instances with cached static formatters
- `EventStorage.isoFormatter` changed from instance property to computed property returning `AppFormatters.iso8601Fractional`
- Affected files: `SleepPlanCards`, `DataManagementView`, `SessionRepository`, `WHOOPService`, `CSVExporter`, `EventStorage`, `DevelopmentHelper`
- Estimated performance gain: ~750ms saved across multi-view render cycles, 10-15% faster CSV exports

**Validation:** SwiftPM + Xcode builds pass, all 630 tests green.

**Documentation:** `docs/review/dateformatter_performance_fix_2026-02-16.md`

---

### ✅ P2-5: Missing Pull-to-Refresh on Dashboard & History — RESOLVED

**Status:** Already implemented — verified 2026-02-16

**Findings:**
- `DashboardViews.swift` line 96: `.refreshable { model.refresh() }` calls `DashboardModel.refresh(days:)` which cancels stale tasks, fetches sessions from repository, and recomputes HealthKit baselines (if enabled)
- `HistoryViews.swift` line 41: `.refreshable { loadHistory() }` calls `sessionRepo.fetchRecentSessions(days: 7)` and updates UI state

**Resolution:** Pull-to-refresh already works correctly on both views. No changes needed.

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

### ✅ P2-8: No iPad / Landscape Layout — RESOLVED

**Problem:** All views appeared phone-only. Dashboard charts and Timeline would benefit significantly from wider layouts.

**Resolution:**
- `ContentView` checks `horizontalSizeClass`: compact uses existing swipeable `TabView` + `CustomTabBar` (zero regression); regular uses `NavigationSplitView` with sidebar
- New `AdaptiveLayouts.swift`: `isInSplitView` environment key, `AdaptiveSidebarView`, `AdaptiveHStack` helper
- Child tab views (`HistoryView`, `DashboardTabView`, `DetailsView`, `SettingsView`) conditionally skip their `NavigationView` wrapper when inside split view detail column
- `LegacyTonightView` uses `AdaptiveHStack` for side-by-side dose controls + event log on wide screens
- `HistoryView` uses `AdaptiveHStack` for side-by-side calendar + selected day detail on iPad
- `DashboardTabView` already had 2-column grid for iPad (unchanged)
- Tab selection synced via `URLRouter.selectedTab` across both layouts; deep links work identically

**Effort:** L (completed)

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

**Phase 1 — Safety & Trust ✅ COMPLETE**

All P0 items resolved on `chore/audit-2026-02-15`:

1. ✅ P0-2: Snooze <15m check — all surfaces use `DoseWindowContext.snooze` enum
2. ✅ P0-3: Flic late-dose bypass — blocked with local notification
3. ✅ P0-5: Deep link dose authorization — foreground + unlocked guard
4. ✅ P0-4: DoseActionCoordinator extracted for UI surfaces
5. ✅ P0-6: WHOOP OAuth PKCE migration — client_secret removed
6. ✅ P0-1: WHOOP decorative guards — hardcoded data removed, feature-flag honoured

**Phase 2 — WHOOP for Real ✅ COMPLETE**

All WHOOP data integration resolved on `chore/audit-2026-02-15`:

5. ✅ P0-1: WHOOP data wired to Dashboard + Night Review + Timeline
6. ✅ P1-2: Simulated biometrics replaced with real WHOOP API data
7. ✅ P1-3: WHOOP fields added to DashboardNightAggregate + views
8. ✅ P1-6: NightScoreCalculator surfaced in Night Review

**Phase 3 — Analytics & Core ✅ COMPLETE**

9. ✅ P1-4: DoseEffectivenessCalculator + IntervalFormat (43 tests)
10. ✅ P1-7: Wake alarm semantic naming fixed
11. ⏸️ P1-5: CloudKit sync deferred (requires iCloud entitlement)

**Phase 4 — User Value ✅ QUICK WINS COMPLETE**
12. ✅ P2-5: Pull-to-refresh (verified already present)
13. ✅ P2-4: DateFormatter performance (15+ inline instances → cached static)
14. P2-7: Coach Insight Generator visibility (next candidate)
15. P2-1: Widget support

**Phase 5 — Platform Expansion (3-6 weeks)**
16. P2-3: watchOS companion
17. ✅ P2-8: iPad / landscape — NavigationSplitView + adaptive layouts
18. P2-6: History search

---

## Cross-References

- **Audit findings:** `docs/audit/2026-02-15/`
- **WHOOP integration doc:** `docs/WHOOP_INTEGRATION.md`
- **Dose registration architecture:** `docs/review/dose_registration_architecture_2026-02-15.md`
- **Architecture:** `docs/architecture.md`
- **SSOT:** `docs/SSOT/README.md`

---

*Updated: 2026-02-15 | Version: 0.3.3 alpha | All P0 + P1 resolved (P1-5 deferred)*
