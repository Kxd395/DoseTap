# DoseTap Architecture Reference

> **Version:** 0.3.2 alpha | **Updated:** 2026-02-16 | **Branch:** `chore/audit-2026-02-15`

This folder breaks the full architecture into reviewable files by domain.

## Index

| # | File | Domain |
|---|------|--------|
| 00 | [00-overview.md](00-overview.md) | System overview, stats, module graph, tech stack |
| 01 | [01-tab-architecture.md](01-tab-architecture.md) | All 5 tabs, ASCII layouts, breadcrumbs |
| 02 | [02-dose-state-machine.md](02-dose-state-machine.md) | 7 window phases, transitions, display matrix |
| 03 | [03-dose-registration.md](03-dose-registration.md) | All dose flows, surfaces, confirmations, ASCII |
| 04 | [04-session-lifecycle.md](04-session-lifecycle.md) | Session states, rollover, incomplete detection |
| 05 | [05-storage-layer.md](05-storage-layer.md) | SQLite schema, EventStorage, models |
| 06 | [06-services.md](06-services.md) | AlarmService, HealthKit, WHOOP, Flic |
| 07 | [07-api-and-networking.md](07-api-and-networking.md) | APIClient, endpoints, errors, offline queue |
| 08 | [08-functions-by-file.md](08-functions-by-file.md) | Complete function inventory per file |
| 09 | [09-security.md](09-security.md) | Cert pinning, input validation, data redaction |
| 10 | [10-testing.md](10-testing.md) | Test pyramid, test file inventory, patterns |
| 11 | [11-known-issues.md](11-known-issues.md) | Tech debt, open P1s, WHOOP status |

## Quick Stats

- **LOC:** ~52,000 across ~155 Swift files
- **Tests:** 559 SwiftPM + 134 Xcode unit + 12 XCUITest = **705 total**
- **Core module:** 25 platform-free Swift files (DoseCore)
- **Storage:** SQLite (WAL mode, encrypted at rest)
- **Min iOS:** 16.0
