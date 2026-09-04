# DoseTap

DoseTap is a local-first iOS app that helps patients manage two-dose nighttime medication timing and track sleep-related events.

## Core Behavior

- Dose 1 starts the session. Dose 2 uses the configured timing window. Early recording retains its explicit confirmation; after the window closes, users can record an occurrence already taken or explicitly mark it missed.
- Late Dose 2 stays Dose 2 (with a late flag). Extra dose starts at dose index 3+ only.
- Sessions are closed by morning check-in completion, not midnight. Fallbacks: prep-time soft rollover and missed check-in cutoff.
- Sleep events (bathroom, lights out, brief wake, etc.) are logged and attached to the active session.
- Nap tracking exists as "Nap Start" and "Nap End" events, paired in History.

## Data Retention

- All data is stored locally in SQLite.
- Deleting the app deletes the sandbox and all data.
- Manual CSV export is available in Settings.
- Shipping builds are local-first. CloudKit sync is limited to the `DoseTapStaging` validation target and is not active in the shipping `DoseTap` target.

## HealthKit

- Integration reads sleep analysis plus heart rate, respiratory rate, HRV SDNN, and resting heart rate.
- Preference is stored in `UserSettingsManager.healthKitEnabled`.
- Authorization is checked via `HealthKitService.isAuthorized` and may need re-grant after reinstall.

## Quick Start

```bash
# Build core logic + run tests
swift build
swift test

# Open iOS app in Xcode
open ios/DoseTap.xcodeproj
```

### Local development without signing

For day-to-day work you don't need a valid signing cert:

- Run on **iPhone Simulator** with the **Debug** build configuration
  (Product → Scheme → Edit Scheme → Run → Info → Build Configuration: Debug)
- Command line:

  ```bash
  xcodebuild build \
    -project ios/DoseTap.xcodeproj -scheme DoseTap \
    -destination 'generic/platform=iOS Simulator' \
    CODE_SIGNING_ALLOWED=NO
  ```

Signing is only required for physical devices, archive builds, and TestFlight.
If Xcode shows "Unable to process request - PLA Update available", sign in at
<https://developer.apple.com/account> and accept the latest Program License Agreement.

## Documentation

- Documentation lifecycle and authority: `docs/README.md`
- Current behavior SSOT: `docs/SSOT/README.md`
- Current work and Plane ownership: `docs/PLANNING.md`
- Agent workflow and verified Plane closeout: `AGENTS.md`, `.agents/plane-workflow.yml`, and `WORKFLOW.md`
- Architecture: `docs/architecture/README.md`
- Testing and release evidence: `docs/TESTING_GUIDE.md` and `docs/PRODUCTION_READINESS_CHECKLIST.md`
- Historical evidence and superseded plans: `docs/archive/`

## License

Proprietary.
