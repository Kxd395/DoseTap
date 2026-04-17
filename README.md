# DoseTap

DoseTap is a local-first iOS app that helps patients manage two-dose nighttime medication timing and track sleep-related events.

## Core Behavior

- Dose 1 starts the session. Dose 2 is allowed within the window or by explicit early/late override.
- Late Dose 2 stays Dose 2 (with a late flag). Extra dose starts at dose index 3+ only.
- Sessions are closed by morning check-in completion, not midnight. Fallbacks: prep-time soft rollover and missed check-in cutoff.
- Sleep events (bathroom, lights out, brief wake, etc.) are logged and attached to the active session.
- Nap tracking exists as "Nap Start" and "Nap End" events, paired in History.

## Data Retention

- All data is stored locally in SQLite.
- Deleting the app deletes the sandbox and all data.
- Manual CSV export is available in Settings.
- Cloud sync is not implemented.

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

- SSOT (authoritative behavior): `docs/SSOT/README.md`
- Database schema: `docs/DATABASE_SCHEMA.md`
- Data dictionary: `docs/SSOT/contracts/DataDictionary.md`
- Diagnostic logging: `docs/DIAGNOSTIC_LOGGING.md`
- Testing guide: `docs/TESTING_GUIDE.md`
- Symphony monitoring setup: `WORKFLOW.md` and `docs/SYMPHONY_SETUP.md`

## License

Proprietary.
