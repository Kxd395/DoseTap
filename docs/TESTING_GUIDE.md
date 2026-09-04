# DoseTap testing guide

Status: Current test and evidence runbook
Last verified: 2026-09-02

Do not keep an evergreen total in this guide. Test files and parameterized cases change often. Discover and record the count from the exact checkout used for a release or audit.

## Test layers

| Layer | Source | What it proves |
| --- | --- | --- |
| DoseCore unit tests | `Tests/DoseCoreTests/` | Deterministic domain, timing, export, diagnostic, networking utility, and policy behavior |
| iOS unit and integration tests | `ios/DoseTapTests/` | Repository, SQLite, export, HealthKit adapters, notifications, navigation, and app-layer behavior |
| iOS UI tests | `ios/DoseTapUITests/` | Simulator-visible launch and interaction flows |
| DoseTap Studio tests | `macos/DoseTapStudio/Tests/` | Import, validation, identity, insights, recommendation, and export behavior |
| Repository guards | `tools/` and CI workflows | Architecture, mutation boundaries, target membership, secrets, docs, and release configuration |
| Manual acceptance | Simulator and signed devices | Real notifications, Apple Health permissions/data, background behavior, accessibility, and owner-observed parity |

An automated pass cannot replace a signed-device, provider, privacy, or owner-observed gate.

## Discover current coverage

```bash
# Enumerate SwiftPM test cases from the current checkout
swift test list

# List tracked test source files
rg --files Tests ios/DoseTapTests ios/DoseTapUITests macos/DoseTapStudio/Tests

# List Xcode targets and schemes
xcodebuild -list -json -project ios/DoseTap.xcodeproj

# List available simulators before choosing a destination
tools/dt-sim list
```

When reporting a result, include the date, commit or dirty-worktree statement, command, destination, passed/failed/skipped counts, and any untested gate.

## DoseCore

Run from the repository root:

```bash
swift build
swift test
```

Focused examples:

```bash
swift test --filter DoseRegistrationPolicyTests
swift test --filter SessionRolloverRegressionTests
swift test --filter TimeCorrectnessTests
swift test --filter MedicationInventoryForecastTests
swift test --filter DiagnosticLoggerTests
```

## iOS app tests

The repository helper defaults to the simulator name in `tools/dt-common.sh`. If that simulator is not installed, select one reported by `tools/dt-sim list` and override it for the command.

```bash
DT_SIMULATOR_NAME="iPhone 17 Pro" tools/dt-test
DT_SIMULATOR_NAME="iPhone 17 Pro" tools/dt-test all
```

Equivalent direct command:

```bash
xcodebuild test \
  -project ios/DoseTap.xcodeproj \
  -scheme DoseTap \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Use a destination that exists on the machine running the test. Do not change product behavior merely to accommodate a missing simulator runtime.

Key app suites currently include storage integration, medication transaction failure injection, session repository behavior, export, Apple Health and API adapters, notifications and timeline, UI state, URL routing, and WHOOP decoding. Discover exact file names rather than copying an old list.

## DoseTap Studio

```bash
swift test --package-path macos/DoseTapStudio
```

Studio fixtures cover clean, shift-work, missing-data, duplicate-event, and contradictory-data imports. Passing fixtures prove the encoded cases only; they do not prove an owner export is complete or source-correct.

## Documentation and repository guards

```bash
bash tools/doc_lint.sh
bash tools/ssot_check.sh
bash tools/check_architecture_boundaries.sh
bash tools/check_dose_state_writes.sh
bash tools/check_legacy_safety_paths.sh
bash tools/check_companion_targets.sh
bash tools/check_repository_hygiene.sh
```

Run `bash tools/release_preflight.sh` for a release candidate. The tagged form has stricter pin and version requirements.

## Time and timezone tests

Time-sensitive code must accept an injected clock or timezone where practical. Cover at least:

- exact 150-minute and 240-minute Dose 2 boundaries;
- snooze cutoff and maximum count;
- midnight crossing without session reassignment;
- the 18:00 dosing-night rollover;
- daylight-saving gaps and repeated hours;
- travel or system timezone changes;
- legacy records with offsets but no named timezone;
- process restart after a committed or failed medication action.

Run the SwiftPM suite in more than one environment timezone when changing grouping logic:

```bash
TZ=UTC swift test
TZ=America/New_York swift test
```

## Manual and signed-device acceptance

Use `docs/PRODUCTION_READINESS_CHECKLIST.md` for release gates. At minimum, medication persistence, notification delivery/reconciliation, Apple Health permission states, same-night screen parity, timezone changes, Clear All Data, export/restore, and accessibility need the evidence class named there.

## Documentation result format

Use this form in a dated audit or Plane comment:

```text
Checkout: <commit plus dirty-worktree scope>
Date: <ISO date and timezone>
Command: <exact command>
Destination: <platform, runtime, device or simulator>
Result: <passed, failed, skipped>
Evidence class: <automated, simulator runtime, signed device, external, owner observed>
Open gates: <what this run did not prove>
```

