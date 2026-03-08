# Apple Dev CLI Setup

Date: 2026-03-08

This repo now includes lightweight Apple developer CLI helpers:

- `dt-build`
- `dt-test`
- `dt-sim`
- `dt-device`
- `dt-cloudkit-check`

## Commands

```bash
dt-build sim
dt-build device

dt-test
dt-test all

dt-sim list
dt-sim boot
dt-sim open
dt-sim shutdown-all

dt-device list
dt-device install /path/to/DoseTap.app <device-id>

dt-cloudkit-check
```

## Defaults

- Project: `ios/DoseTap.xcodeproj`
- Scheme: `DoseTap`
- Configuration: `Debug`
- Default simulator destination for tests: `platform=iOS Simulator,name=iPhone 16`

You can override these per shell session:

```bash
export DT_SCHEME="DoseTap"
export DT_CONFIGURATION="Debug"
export DT_SIMULATOR_NAME="iPhone 16"
export DT_TEST_DESTINATION="platform=iOS Simulator,name=iPhone 16"
```

## Shell Integration

`~/.zshrc` now adds this repo's `tools/` directory to `PATH` when the repo exists at:

`/Volumes/Developer/projects/DoseTap`
