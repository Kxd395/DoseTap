# Changelog

All notable changes to DoseTap will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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
