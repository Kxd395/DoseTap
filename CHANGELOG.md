# Changelog

All notable changes to DoseTap will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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

- Removed hardcoded test counts from docs (architecture.md, README.md, FEATURE_ROADMAP.md)
- Archived historical code review docs to `archive/audits_2025-12-24/`

### Fixed
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
