# Changelog

All notable changes to DoseTap will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
