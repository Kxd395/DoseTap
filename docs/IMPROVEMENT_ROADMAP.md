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


### P1-7: Wake Alarm Naming Mismatch (Semantic Drift)

**Problem:** `AlarmService` uses `dosetap_wake_alarm` and `scheduleWakeAlarm()` but the alarm fires at `dose1 + target minutes` — it's semantically the Dose 2 alarm, not a "wake" alarm. The notification title even says "WAKE UP - Time for Dose 2". This semantic drift invites future bugs.

**Evidence:**
- `AlarmService.swift:20` — `static let wakeAlarm = "dosetap_wake_alarm"`
- `AlarmService.swift:204` — `func scheduleWakeAlarm(at time: Date, dose1Time: Date)`
- `AlarmService.swift:243` — title: "🔔 WAKE UP - Time for Dose 2"
- SSOT `docs/SSOT/README.md:313` — documents the mismatch

**Fix:** Rename: `dosetap_wake_alarm` → `dosetap_dose2_alarm`, `scheduleWakeAlarm` → `scheduleDose2Alarm`, `dosetap_pre_alarm` → `dosetap_dose2_pre_alarm`. Update all callers (5 files). Add terminology contract to SSOT.

**Effort:** S (2-4 hours) — mechanical rename + grep verification

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

**Phase 1 — Safety & Trust ✅ COMPLETE**

All P0 items resolved on `chore/audit-2026-02-15`:

1. ✅ P0-2: Snooze <15m check — all surfaces use `DoseWindowContext.snooze` enum
2. ✅ P0-3: Flic late-dose bypass — blocked with local notification
3. ✅ P0-5: Deep link dose authorization — foreground + unlocked guard
4. ✅ P0-4: DoseActionCoordinator extracted for UI surfaces
5. ✅ P0-6: WHOOP OAuth PKCE migration — client_secret removed
6. ✅ P0-1: WHOOP decorative guards — hardcoded data removed, feature-flag honoured

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
