# Changelog

All notable changes to DoseTap will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.3] - 2026-06-12

### Fixed

- **P0 Tonight home state resolver**
  - Added a single resolved home presentation state for Tonight so the screen chooses the primary workflow before rendering secondary sections.
  - Stopped the screenshot state from showing a separate "Ready for Dose 1 / Tap below to start" status card alongside the actual Dose 1 button.
  - Gated "Wake Up & End Session" to the closeout workflow instead of showing it as a peer action while Dose 1 is ready.
  - Kept previous incomplete check-ins non-blocking unless they affect the current session identity, rollover, or dose state.
  - Removed the Settings tab's separate runtime color-scheme override so all main tabs follow the app shell theme.
  - Extended the tab split-brain CI guard to reject direct tab-level `settings.colorScheme` ownership.
  - Updated compact Timeline, History, Dashboard, and Settings tab roots from `NavigationView` to `NavigationStack` for consistent iOS 16 navigation behavior.
  - Made pre-sleep and morning check-in carry-forward default on for new entries.
  - Changed pre-sleep "Use last" to copy the latest completed pre-sleep check, carry time-of-day fields onto the new night, and drop one-off freeform notes.
  - Made new morning check-ins fall back to the latest prior morning check-in when no explicit saved template exists, while avoiding stale dose-reconciliation reasons.

### Changed

- Bumped `DoseTap` and `DoseTapStaging` to version `0.4.3` build `5`.

## [0.4.2] - 2026-06-12

### Fixed

- **P0 dose sequence persistence**
  - Blocked Dose 2 persistence unless an active canonical Dose 1 exists.
  - Recovered persisted Dose 2 without Dose 1 by quarantining the active session with `invalid_dose_state` instead of crashing on launch.
  - Made Dose 1 undo clear dependent Dose 2, extra dose, skip, snooze, and alarm state.

- **P0 snooze split-brain prevention**
  - Made snooze persistence fail closed unless an active Dose 1 session is still open.
  - Changed snooze coordination to commit repository state before alarm rescheduling and roll back repository state if alarm scheduling fails.
  - Added persisted snooze invariants so snooze-only active state is detected and recovered.

### Changed

- Bumped `DoseTap` and `DoseTapStaging` to version `0.4.2` build `4`.

## [0.4.1] - 2026-06-12

### Fixed

- **P0 dose action feedback**
  - Added shared dose action result presentation for success, blocked, and confirmation coordinator results.
  - Wired `CompactDoseButton` and `DoseButtonsSection` so blocked Dose 2, snooze, skip, and override results are no longer silently ignored.
  - Added focused app tests for dose action result presentation.

- **CloudKit readiness validation**
  - Fixed the zsh readiness gate by avoiding the reserved `status` variable name.
  - Made release preflight print app-version checker progress and use the longer build-settings timeout needed by Xcode.
  - Raised the default build-settings watchdog to 240 seconds after local Xcode reads exceeded 120 seconds.
  - Made tagged release preflight fail when `DOSETAP_CERT_PINS` is unset instead of reporting a warning-only pass.

- **Sleep event mapping**
  - Canonicalized Brief Wake aliases to `wake_temp` at the repository boundary and in the legacy storage migration.
  - Fixed the doc lint schema-version gate so missing schema versions no longer pass as blank matches.

- **Migration state hardening**
  - Added a SQLite `schema_migrations` ledger for one-time data migrations while preserving existing UserDefaults flags for current installs.
  - Bumped SQLite `user_version` to `1` and added a regression test that storage initialization applies it.
  - Replaced duplicate-column-error based additive migrations with explicit column-exists checks.

### Changed

- **Dose command composition**
  - Moved dose core, coordinator, undo, URL router, Flic, and notification snooze wiring into `AppContainer`.
  - Bumped `DoseTap` and `DoseTapStaging` to version `0.4.1` build `3`.

## [0.4.0] - 2026-06-12

### Added

- **Build identity enforcement**
  - Set `DoseTap` and `DoseTapStaging` app targets to version `0.4.0` build `2`.
  - Added `tools/check_app_version.sh` to validate app/staging Debug and Release version/build consistency.
  - Wired app version/build validation into release preflight, CI, PR checklist, and the Linear workflow handoff standard.

- **Planner turnover control for Tonight UI**
  - Added `After check-in, show upcoming night` setting in Night Schedule.
  - Added `plannerSessionKey(for:)` path to keep planner-facing screens consistent after morning check-in.
  - Added regression tests for planner key behavior with toggle on/off.

- **Weekly workday sleep setup flow**
  - Added quick "workday/off-day" weekly schedule template controls.
  - Added setup-wizard entry point to configure weekly workday patterns.

- **Forensic Improvements to Diagnostic Logging (v2.15.0)** - Aviation-grade forensic hardening
  - Per-session `seq` counter for event ordering under timestamp collision
  - `constants_hash` on terminal events (`session.completed`, `timezone.changed`) for drift detection
  - `invariant.violation` event type for "should never happen" conditions
  - `logInvariantViolation(name:reason:sessionId:)` convenience method
  - Session trace reading guide: `docs/HOW_TO_READ_A_SESSION_TRACE.md`
  - Documented `session_id` semantic freeze (grouping key, not unique identifier)
  - Documented `errors.jsonl` as lens for triage, not evidence

- **Diagnostic Logging System (v2.14.0)** - Session-scoped diagnostic logging for debugging and support
  - DiagnosticEvent enum mirroring SSOT state names exactly
  - DiagnosticLogger actor with JSONL file output
  - Session metadata (meta.json) with device/app context
  - **Tier 1 Critical Events:** App lifecycle, timezone changes, notification delivery, undo flow
  - **Tier 2 Session Context Events:** Sleep event logging, pre-sleep log, morning check-in
  - Phase transition logging at edges only (window.opened, nearClose, expired)
  - SessionTraceExporter in Settings → Export Session Diagnostics
  - Local export only, no cloud upload, no health data
  - 14-day retention with automatic pruning
  - Documentation: `docs/DIAGNOSTIC_LOGGING.md`
  - Implementation: `ios/Core/DiagnosticEvent.swift`, `ios/Core/DiagnosticLogger.swift`
  - SSOT contract: Every log MUST have session_id, views MAY NOT call logger

- **Night Mode theme** - Circadian-friendly red light mode eliminating all blue wavelengths for nighttime medication checks
  - Three theme options: Light, Dark, Night Mode (red light)
  - Global red color filter (`.colorMultiply()`) removes blue light exposure
  - Persistent theme selection via UserDefaults
  - Theme picker in Settings → Appearance section
  - Medical benefit: Protects melatonin production during 2-4 AM dose checks
  - Documentation: `docs/NIGHT_MODE.md`
  - Implementation: `ios/DoseTap/Theme/AppTheme.swift`, `ios/DoseTap/Views/ThemeSettingsView.swift`

- HealthKitProviding protocol for test isolation (GAP A)
- TimeCorrectnessTests: 14 tests for 6 PM boundary, DST, timezone edge cases (GAP B)
- ExportIntegrityTests: 6 tests for row counts and secrets redaction (GAP C)
- SSOT regression guards preventing stored dose state (GAP D)
- Dynamic test count references in documentation (GAP E)

### Changed

- **Audit branch stabilization and refactor pass**
  - Split oversized dashboard, setup, pre-sleep, history, timeline, night-review, and morning-check-in files into coherent modules.
  - Split `SessionRepository` and `EventStorage` extensions by concern, and quarantined deferred CloudKit plus legacy Core Data compatibility paths under explicit legacy naming.
  - Clarified build-product boundaries with `DoseTap.Local.entitlements`, `DoseTap.Cloud.entitlements`, and staging-only CloudKit validation guidance.
  - Added App Store submission artifacts including privacy manifest, support/privacy surfaces, and release-preflight hardening.

- **Theme-stable schedule time pickers**
  - Replaced compact schedule DatePickers with sheet-based wheel pickers in Settings, Setup Wizard, and Weekly Schedule.
  - Prevents light/dark/night-specific rendering differences for sleep schedule controls.

- **Tonight surface consistency**
  - Aligned remaining planner-facing views (timeline, quick log, night review, pre-sleep nap summary) to planner key behavior after check-in.

- Repository cleanup: Archived dated audit reports to `docs/archive/`
- Archived WHOOP OAuth test scripts to `archive/tools_whoop/`
- Moved historical audit files to `archive/audits_2026-01/`
- Deleted build artifacts and test logs from root directory
- Moved unused ContentView variants to `ios/DoseTap/legacy/`

- Removed hardcoded test counts from docs (architecture.md, README.md, FEATURE_ROADMAP.md)
- Archived historical code review docs to `archive/audits_2025-12-24/`

### Fixed
- **Release validation reachability** - `ci.yml` now runs on `v*` tag pushes so the existing release-pinning validation job can execute for tagged builds.
- **Bounded Xcode build-setting reads** - `check_app_version.sh` and `check_cloudkit_readiness.sh` use watchdogs around `xcodebuild -showBuildSettings` so automation fails cleanly instead of hanging.

- **Local-vs-staging product boundary drift**
  - Removed dead setup-wizard cloud-sync preference.
  - Hid the manual CloudKit sync action in the local-first shipping target.
  - Updated live docs/runbooks so CloudKit validation points at `DoseTapStaging`, not the shipping app target.

- **P1: Notification ID mismatch** — Unified `SessionRepository.sessionNotificationIdentifiers` with `AlarmService.NotificationID` (`dosetap_*` prefix). Previously 6 cancel call sites used IDs that had zero overlap with what AlarmService actually schedules, leaving orphan notifications.
- **P1: Flic alarm parity** — `FlicButtonService` dose 1 path now schedules wake alarm + dose 2 reminders; dose 2 / skip paths now cancel all alarms. Previously Flic dose actions had no alarm side effects.
- **P2: Critical alerts capability gating** — Added `canUseCriticalAlerts` guard in `AlarmService` that checks both `UserSettingsManager.criticalAlertsEnabled` and an Info.plist `CriticalAlertsCapabilityEnabled` flag. Notifications gracefully fall back to `.timeSensitive` when the Apple entitlement is not yet approved. Entitlement key is added to `.entitlements` files only after Apple approval.
- **P2: Notification permission recovery** — `SettingsView` now detects iOS `.denied` authorization when user enables notifications, resets the toggle, and offers a button to open iOS Settings. Previously permission denial was a one-shot dead end.
- **P2: Channel parity for dose actions** — URLRouter, History `DoseButtonsSection`, and CompactDoseButton now all cancel alarms on dose 2 / skip / late override. Post-skip dose 2 override enabled across all surfaces (was UI-only).
- **P2: Extra dose via deep link** — URLRouter `dose2` path now supports extra dose (dose 3+) when dose 2 is already taken.
- **P3: Alarm sound fallback** — Removed dead `alarm_tone.caf` lookup; alarm sound now uses system sound fallback directly.
- Foreign key enforcement in SQLite (`PRAGMA foreign_keys = ON`)
- HealthKitService syntax error preventing compilation
- Missing source file references in Xcode project

## [0.1.0] - 2025-12-24

### Added
- Initial DoseCore SwiftPM package with dose window calculations
- SessionRepository for managing dose sessions
- EventStorage with SQLite backend
- 262 SwiftPM tests (DoseCoreTests)
- 32 Xcode tests (DoseTapTests)
- SSOT documentation in `docs/SSOT/`
- CI workflow with SwiftPM and Xcode test jobs
