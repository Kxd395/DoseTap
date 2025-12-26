# DoseTap

**XYWAV-Only Medication Manager**

DoseTap helps patients manage XYWAV's strict timing requirements: Dose 2 must be 150–240 minutes after Dose 1.

## 📖 Single Source of Truth

> **[`docs/SSOT/README.md`](docs/SSOT/README.md)** — Canonical specification
>
> If code differs from the SSOT, the code is wrong.
> All numeric constants live in [`docs/SSOT/constants.json`](docs/SSOT/constants.json).

## Quick Start

```bash
# Build core logic + run tests
swift build
swift test

# Open iOS app in Xcode
open ios/DoseTap/DoseTap.xcodeproj
```

**Requirements:**
- **Deployment target:** iOS 16.0 (app runs on iOS 16+ devices)
- **Build requires:** Xcode 15+ with iOS 17 SDK

## Documentation Map

| Document | Purpose |
|----------|---------|
| [`docs/SSOT/README.md`](docs/SSOT/README.md) | **Canonical spec** — states, thresholds, contracts |
| [`docs/SSOT/constants.json`](docs/SSOT/constants.json) | Machine-readable constants |
| [`docs/SSOT/contracts/`](docs/SSOT/contracts/) | API schema, data dictionary, product guarantees |
| [`docs/PRODUCT_DESCRIPTION.md`](docs/PRODUCT_DESCRIPTION.md) | What the app does |
| [`docs/architecture.md`](docs/architecture.md) | Code structure (SwiftPM + SQLite) |

## Contributing

1. **Read the SSOT first** — behavior is defined there, not in code comments
2. Update SSOT if changing behavior, thresholds, or state logic
3. Add/update tests in `Tests/DoseCoreTests/`
4. Run `swift test` before PR

**Security**: WHOOP tokens → Keychain only. Never commit secrets.

## Current Status

- ✅ **Tests**: See CI for current counts (SwiftPM + Xcode)
- ✅ Core window logic complete
- ✅ SQLite persistence (unified via SessionRepository)
- ✅ Sleep Environment tracking
- ✅ CSV export with SSOT v1 format
- ✅ PII redaction for support bundles
- ✅ **Storage Unified** — Split brain eliminated (v2.12.0)
- ⏸️ **watchOS companion** — Phase 2 placeholder (see below)
- 🔄 Phase 2: Health Dashboard (planned)

## Docs Truth Table

| Status | Features |
|--------|----------|
| ✅ **Implemented** | Dose window logic (150-240m), SQLite persistence, SessionRepository facade, Sleep event logging, CSV export, Support bundles |
| ✅ **Enforced** | Storage boundary: Views → SessionRepository only (CI guard) |
| 🔄 **Planned** | Cloud API sync, watchOS companion, Health Dashboard, WHOOP data visualization |
| 📋 **Spec Ready** | Medication logger (Adderall/XR), Stimulant tracking |
| ⛔ **Banned** | SQLiteStorage (use SessionRepository), Direct EventStorage access from Views |
| ⚠️ **Legacy** | CoreData references (unused), JSON file storage (migrated) |

> See [`docs/SSOT/README.md`](docs/SSOT/README.md) for authoritative feature status.

### watchOS Status

The `watchos/DoseTapWatch/` folder contains **placeholder UI code only**. Full watchOS integration is planned for Phase 2 and will include:

- WatchConnectivity sync with iOS app
- Dose timing notifications
- Complication support

**Current state**: Builds but not functionally connected to iOS app or DoseCore.

## License

Proprietary.
