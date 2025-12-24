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

**Requirements**: Xcode 15+, iOS 17 SDK

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

- ✅ 136 unit tests passing
- ✅ Core window logic complete
- ✅ SQLite persistence
- 🔄 watchOS companion (UI only, not integrated)
- 📋 Phase 2: Health Dashboard (planned)

## License

Proprietary.
