# Apple Dev CLI Setup

Status: Current local-development runbook
Last verified: 2026-09-02

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
- Repository fallback simulator: `iPhone 16`

The fallback simulator was not installed on the workstation used for the 2026-09-02 documentation audit. Run `dt-sim list` and set `DT_SIMULATOR_NAME` or `DT_TEST_DESTINATION` to an installed device. Documentation must not treat one workstation's installed simulator list as a project guarantee.

You can override these per shell session:

```bash
export DT_SCHEME="DoseTap"
export DT_CONFIGURATION="Debug"
export DT_SIMULATOR_NAME="iPhone 16"
export DT_TEST_DESTINATION="platform=iOS Simulator,name=iPhone 16"
```

## Shell Integration

If your shell configuration adds this repository's `tools/` directory to `PATH`, the short command names above are available. Otherwise, call them as `tools/dt-build`, `tools/dt-test`, and so on from the repository root.

The working copy used for this verification was at:

`/Volumes/Developer/projects/DoseTap`
