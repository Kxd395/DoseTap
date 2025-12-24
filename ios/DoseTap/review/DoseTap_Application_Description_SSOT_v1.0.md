# DoseTap — Application Description & SSOT (v1.0)

**Document Created:** 2025-09-07  
**Last Updated:** 2025-09-07  
**Current App Version:** Pre‑Release (Core scheduling + UI hygiene)  
**Authors/Contributors:** Kevin J. Dial (Primary), AI Copilot (planning & docs)  
**Purpose:** Single Source of Truth (SSOT) for stakeholders, developers, and testers. Aligns product intent, UX, core logic, storage, reminders, and test/acceptance criteria. This version consolidates prior drafts, advice notes, and the current Settings UI stubs.

---

## 0) SSOT-First Workflow (Always run in PRs)
- Update `docs/SSOT/README.md` when **logic, states, thresholds, or errors** change.
- If navigation/contracts change, update `docs/SSOT/navigation.md` and `docs/SSOT/contracts/*`.
- In PR description, **link exact tests** you added/updated.
- Run `tools/ssot_check.sh` (CI gate).

---

## 1) Product Overview

**Scope:** iOS (primary) with planned watchOS extension. DoseTap assists with precise night‑time medication scheduling—optimized for XYWAV-like regimens that require two doses with strict spacing.

**Core invariant:** Dose 2 must occur **150–240 minutes** after Dose 1. Default target: **165m**. Snooze increments **10m**. Snooze disabled when **<15m** remain or after `maxSnoozes` (see config).

**Goals**
- **Night‑first UX:** large, high-contrast controls; minimal cognitive load; dark friendly.
- **Reliability:** debounced event logging; resilient reminders; offline‑safe service façade.
- **Privacy/Trust:** local storage by default; clear destructive actions; consent & transparency.
- **Maintainability:** platform‑free core (`DoseCore`) + thin UI; actor‑based state; time injection for tests.

**Target audience:** Adults managing strict dosing schedules at night.

**Monetization/Distribution (initial):** Free on App Store, no ads. Future **Pro** (one‑time) may unlock analytics/themes.

**Disclaimer (user-facing onboarding):**
- DoseTap assists with organization only; it is **not a medical device**.
- Does not replace advice of your clinician; always follow your prescription.
- Verify schedules/doses as prescribed.

---

## 2) Architecture (Authoritative)

### Modules
- **DoseCore (SwiftPM):** Dosing math/state (`DoseWindowCalculator`, `DoseWindowState`), reminders (`AutoSnoozeRule`, `ReminderScheduler`), storage contract (`EventStore`), rate limiting (`EventRateLimiter`), service façade (`DosingService`), offline queue.
- **DoseTap (App target):** SwiftUI screens, presentation, Settings, integrations UI shells.

### Conventions
- **Platform‑free core** (no SwiftUI/UIKit in `DoseCore`).
- **Actors** for mutable state (`DosingService`, `OfflineQueue`, `EventRateLimiter`).
- **Time injection** (`now: () -> Date`) for deterministic tests (DST, time zone, leap seconds).
- **Errors mapped** via `APIErrorMapper` to `DoseAPIError` (`422_WINDOW_EXCEEDED`, `422_SNOOZE_LIMIT`, `422_DOSE1_REQUIRED`, `409_ALREADY_TAKEN`, `429_RATE_LIMIT`, `401_DEVICE_NOT_REGISTERED`).

### 2.1 Navigation Map & Back‑Title Rules (Authoritative)

Authoritative navigation map (use this in tests, docs, and UX wiring):

Main (Night-First)
 ├─ History
 │    └─ Event Details (note edit)
 └─ Settings
      ├─ Data Storage → (Export History sheet) → Done
      ├─ Notifications
      ├─ Integrations
      │    ├─ Apple Health (authorize modal) → Done
      │    └─ WHOOP (connect modal) → Done
      └─ Privacy & Support (policy / email)

- Back‑title / breadcrumb rule: iOS‑native back, no custom crumb bar.
- From History, back title = Main.
- From Event Details, back title = History.
- From Settings subsections, back title = Settings.
- Dismissal verbs: “Back” for pushes, Done for modals/sheets (Export, Health/WHOOP).
- Accessibility: Each view has an explicit `navigationTitle`; VoiceOver announces “Back to {parent}”.

### Storage Abstraction
- **App‑layer façade:** `DataStorageService` (provides counts, CSV export, clear, location).
- **Core contract:** `EventStore` protocol used in logic/tests.
- **Rule:** `DataStorageService` must satisfy SSOT CSV v1 schema and atomic clear semantics.

---

## 3) Configuration (DoseWindowConfig — SSOT)

```swift
min=150, max=240, nearWindowThresholdMin=15,
defaultTargetMin=165, snoozeStepMin=10, maxSnoozes=<TBD default 3>
```

**Meaning**
- **Active window:** [150, 240] minutes since Dose1.
- **Near‑end threshold:** <15m disables snooze; ring warns.
- **Default target:** 165m display guidance.
- **Snooze:** adds 10m per action; cap = `maxSnoozes`.

All timings are computed in **UTC** internally; UI presents in local time with clear labels.

---

## 4) UI States & Primary Actions (Authoritative Table)

| Phase        | Remaining      | Primary CTA        | Snooze                | Ring Behavior                      | Errors/Notes |
|--------------|----------------:|--------------------|-----------------------|------------------------------------|--------------|
| waiting      | until Dose1     | “Set Dose 1” / Idle| Off                   | Idle                               | –            |
| pre‑active   | <150m since D1  | “Wait”             | Off                   | Counts up to 150m                  | 422_DOSE1_REQUIRED if out‑of‑order |
| **active**   | **150–240m**    | **“Take Dose 2”**  | **On (+10m)**         | Counts down to 240m                | 409_ALREADY_TAKEN guarded |
| near‑end     | <15m left       | “Take Dose 2”      | **Off**               | Warning highlight                  | next miss ⇒ 422_WINDOW_EXCEEDED |
| expired      | >240m           | “Window Missed”    | Off                   | Empty / error state                | 422_WINDOW_EXCEEDED |

**Undo Snackbar:** shows for **15s** (default) after a dose event; undo restores prior state and rolls back storage/logging.

### 4.1 Action Map (Authoritative)

This table maps UI actions to the canonical event written, side‑effects, undo behavior, and errors/tests to assert. Use this as the single source for QA test steps.

| UI Surface | Action (label) | Allowed When | Event written (CSV event_type, source, dose_sequence) | Side‑effects (scheduler, state, haptics) | Undo? | Errors surfaced |
|------------|----------------|--------------|--------------------------------------------------------|-------------------------------------------|-------|----------------|
| Main | Set Dose 1 | Phase: waiting | dose1_taken,user,1 | Start window; schedule Dose 2 notifications | 15s | 429_RATE_LIMIT if double‑tap inside 60s |
| Main | Take Dose 2 | active or near‑end | dose2_taken,user,2 | Cancel pending reminders; finalize session | 15s | 409_ALREADY_TAKEN if repeated |
| Main | Snooze +10m | active and ≥15m left and snoozes < max | none (system action) | Reschedule reminder +10m; increment in‑memory snooze count | No | 422_SNOOZE_LIMIT if at cap; UI disabled <15m |
| Main | Skip | active or near‑end | dose2_skipped,user,2 | Cancel reminders; mark session as missed | 15s | — |
| Main | Bathroom Press | Any time | bathroom,user, | None | 15s | 429_RATE_LIMIT inside 60s |
| Snackbar | Undo | Within 15s of above | undo,user, | Revert prior side‑effects; reschedule if needed | — | — |
| History | Save Note | On details | updates last event's note | Persist text; sanitize for CSV escaping | — | — |
| Settings/Data | Export History (CSV) | Always | — | Present share sheet with events.csv (header always) | — | — |
| Settings/Data | Clear All Data | Always | — | Atomic wipe; verify counts==0; exporter → header‑only | — | Error if any subsystem aborts per policy |
| Settings/Notif | Enable Reminders toggle | Always | — | Register/cancel scheduling; show status | — | — |
| Integrations | Authorize Apple Health | Always | — | Request HealthKit perms; store status | — | — |
| Integrations | Connect WHOOP | Always | — | Launch auth; store status | — | — |

**Notes:**
- CSV header & order are fixed (event_id,event_type,source,occurred_at_utc,local_tz,dose_sequence,note). Exporter always emits header, even when no events.
- Debounce: taps for bathroom and other actions are rate‑limited at 60s unless otherwise specified.

---

## 5) Feature Set (Status & Acceptance)

### 5.1 Dosing Event Tracking — **[Implemented]**
- **Debounce:** repeat “bathroom press” ignored within **60s** (default).  
- **Event types:** `dose1_taken`, `dose2_taken`, `dose2_skipped`, `bathroom`, `undo`.
- **Acceptance:** integration test proves 1st press logged, 2nd within 60s dropped, 3rd at ≥61s logged.

### 5.2 Reminder Scheduling — **[Implemented]**
- **Auto‑Snooze:** if reminder is pending, add **10m** and reschedule when eligible.  
- **Disablement:** auto‑snooze off when `<15m` remain or after `maxSnoozes`.  
- **User toggle “Allow Snoozing”:** controls **user‑initiated** snooze UI only; **system auto‑snooze** still follows SSOT.  
- **Acceptance:** snapshot tests; toggle‑off hides/blocks user snooze; auto‑snooze still applies when eligible.

### 5.3 User Interface (Night‑First) — **[In Progress]**
- Countdown ring (VoiceOver reads “Next dose in H:MM”).  
- Large central action button (“Bathroom Press” → may present as “Record Dose” in locales).  
- **Haptics:** success vs undo distinct patterns.  
- **Undo window:** 15s default, configurable.  
- **Acceptance:** accessibility labels; minimum 44pt touch targets; true‑black backgrounds supported.

### 5.4 History & Export — **[Partial: UI present, schema SSOT v1]**
- History list; tap for details & add **Notes** (free text).  
- **CSV Export** UI (“Export History (CSV)”) wired to `exportToCSV()`.  
- **Acceptance:** `ExporterGoldenTest` compares output with golden fixture; header & field order match SSOT CSV v1.

### 5.5 Integrations — **[UI Shells Implemented / Plumbing Planned]**
- Apple Health: auth screen & status; local‑only processing statement.
- WHOOP: connect/disconnect modal; local‑only statement.
- watchOS: planned button/complications mirroring main CTA.
- **Acceptance:** consent copy present; status indicators reflect stubbed states; plumbing covered in PR‑3.

### 5.6 Build & Hygiene — **[Implemented]**
- Legacy files quarantined (`#if false`).  
- SwiftPM/Xcode parity; CI guard via `tools/ssot_check.sh`.

---

## 6) Screens (Specs)

### 6.1 Splash / First‑Run Onboarding — **[Planned]**
- **Slides:** Welcome → Notifications (why) → Undo demo (15s) → Auto‑snooze explanation → Privacy (local only) → Disclaimer.
- **CTA:** Allow Notifications; proceed to Main.

### 6.2 Main (Night‑First)
- Ring, large CTA, state text, Undo snackbar, gear icon → Settings.
- Pull/refresh calls `ensureScheduled()`.

### 6.3 History
- List with search/filter; tap item → details + note edit; export button.

### 6.4 Settings — **[Implemented: UI v0.1]**
- **Data Storage:** StorageInfo (counts/size/path), **Export History (CSV)**, **Clear All Data** (two‑step destructive).  
- **Notifications:** Enable, default time, **Allow Snoozing** (user control).  
- **Integrations:** Apple Health (authorize), WHOOP (auth sheet).  
- **Privacy & Support:** policy page, support mailto.  
- **Acceptance:** after Clear, counts==0 and export produces header‑only CSV.

### 6.4.1 Settings dismissal (Authoritative)

- Dismissal: Settings is presented in a navigation stack. Users exit via the standard Back button (or Done when a subsection is presented modally).
- Sheets and modal authorizations (Export History share sheet, HealthKit/WHOOP auth) explicitly show a Done/Close button and dismiss to the presenting view.
- Developer/Debug: a "Quit App (Debug)" control may exist under a developer-only screen and must be stripped or disabled in release builds.
- Acceptance: In a release build there is no control that terminates the process; Settings and all modals dismiss only via Back/Done.

---

## 7) CSV Schema — **SSOT CSV v1 (authoritative)**

Header (exact order):
```
event_id,event_type,source,occurred_at_utc,local_tz,dose_sequence,note
```
- `occurred_at_utc`: ISO8601 UTC (`2025-09-07T02:15:23Z`)
- `local_tz`: IANA name (e.g., `America/New_York`)
- `source ∈ {user,watch,flic,system}`
- `event_type ∈ {dose1_taken,dose2_taken,dose2_skipped,bathroom,undo}`
- `dose_sequence`: `1|2` or empty when N/A
- `note`: free text; may be empty

**Exporter Requirements**
- Always include header row.
- Fields are comma‑separated, values CSV‑escaped.
- Deterministic order by `occurred_at_utc` ascending (unless otherwise specified).

---

## 8) Destructive Action Policy (Authoritative)

- **Clear All Data**: two‑step alert; final button label: **“Clear All Data — This cannot be undone.”**  
- Atomic: if any subsystem fails, abort & show error (no partial clears).  
- Post‑clear verification: counts==0; exporter returns header‑only CSV.  
- Future: granular clears (History vs Sessions).

---

## 9) Persistence, Backup & Background Robustness

- **Persistence:** Move to **Core Data / SwiftData** immediately; the in‑memory store is for tests only.
- **Backup/Sync:** Use **NSPersistentCloudKitContainer** to sync to the user’s iCloud (private DB). No third‑party servers.
- **Background:** Evaluate **BGAppRefreshTask** to periodically run `ensureScheduled` overnight.
- **Critical Alerts:** Pursue `com.apple.developer.usernotifications.critical-alerts` entitlement for medication reminders (documentation & justification in App Review notes).

---

## 10) Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Notifications disabled | Missed doses | Detect & show persistent warning; onboarding educates value |
| DND/Focus silences alerts | Missed doses | Critical Alerts entitlement |
| Device migration data loss | Loss of history | Core Data + CloudKit sync |
| Duplicate taps | Bad data | Debounce (60s), Undo window |
| Doc/code drift | Bugs | SSOT CI gate; PR template requires test links |

---

## 11) Test & Acceptance Matrix (must link in PRs)

- **DoseWindowEdgeTests**: exact 150/240 boundaries; DST forward/back.
- **DosingServiceDebounceIntegrationTests**: 60s debounce behavior.
- **AutoSnoozeRuleTests**: applies 10m only when pending & ≥15m remain; respects `maxSnoozes`.
- **ExporterGoldenTest**: CSV matches fixture line‑by‑line.
- **ClearDataFlowTest**: two‑step confirm; counts zero; header‑only CSV.
- **NotificationToggleTests**: enabling/disabling reminders updates scheduled requests.
- **SnoozeToggleTests**: user toggle hides UI; auto‑snooze unaffected.

---

## 12) Names & Form Fields (for tickets/appstore/docs)

- **App Name:** DoseTap  
- **Module:** `DoseCore`  
- **Primary Actor:** `DosingService`  
- **Limiter:** `EventRateLimiter`  
- **Queue:** `OfflineQueue`  
- **Storage façade:** `DataStorageService`  
- **Core contract:** `EventStore`  
- **CSV Schema:** **SSOT CSV v1** (above)  
- **Clear copy:** “Clear All Data — This cannot be undone.”  
- **Toggle labels:** “Enable Reminders”, “Allow Snoozing”

---

## 13) Backlog (prioritized)

- **PR‑2**: Night‑first UI completion (ring + a11y), Undo snackbar, History re‑add, CSV exporter goldens, destructive policy strings, notes on events.
- **PR‑3**: Core Data + CloudKit sync; BGAppRefresh; watchOS button/complications; WHOOP/Health plumbing.
- **PR‑4**: Widgets, localization, Pro‑level analytics/themes.

---

## 14) PR Template (link tests & SSOT)

- What changed (one‑liner)  
- Linked tests (file:line)  
- SSOT docs touched (`README.md`, `navigation.md`, `contracts/*`)  
- Failure modes covered (window edges, snooze disable, API codes)  
- Offline/limiter impact

---

**End of SSOT v1.0**