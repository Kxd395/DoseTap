# CloudKit Go-Live Checklist

This runbook is for the point when Apple Developer CloudKit capability propagation finishes and DoseTap can validate real iCloud sync.

## Scope

- App target: `DoseTap`
- Bundle ID: `com.dosetap.ios`
- CloudKit container: `iCloud.com.dosetap.ios`
- Current sync implementation: dashboard-driven private-database sync for session summary, sleep events, dose events, and morning check-ins

## 1. Local Preflight

Run the local config check before touching a device:

```bash
./tools/check_cloudkit_readiness.sh
```

Expected result:

- `Debug` and `Release` both report `DoseTap/DoseTap.entitlements`
- `Debug` and `Release` both report `INFOPLIST_KEY_DoseTapCloudSyncEnabled = YES`
- Entitlements report container `iCloud.com.dosetap.ios`

## 2. Apple-Side Readiness

Verify these in the Apple Developer portal and Xcode signing UI:

1. The `com.dosetap.ios` App ID has iCloud capability enabled.
2. The CloudKit container `iCloud.com.dosetap.ios` exists and is attached to the App ID.
3. The device test account is signed into iCloud.
4. The Team used by Xcode matches the App ID owner.

If propagation only started on March 8, 2026, do not treat failures before March 10, 2026 as conclusive.

## 3. Build And Install

Install a Debug build to a physical device:

```bash
xcodebuild -project ios/DoseTap.xcodeproj -scheme DoseTap -configuration Debug -destination 'platform=iOS,name=<Device Name>' build
```

Then confirm the signed app includes CloudKit entitlements:

```bash
APP_PATH="$(find ~/Library/Developer/Xcode/DerivedData -path '*Build/Products/Debug-iphoneos/DoseTap.app' -print -quit)"
codesign -d --entitlements :- "$APP_PATH"
```

Expected entitlements in the signed app:

- `com.apple.developer.icloud-container-identifiers`
- `com.apple.developer.icloud-services` with `CloudKit`

## 4. Runtime Validation

Use two real devices on the same iCloud account.

On device A:

1. Launch DoseTap.
2. Log Dose 1.
3. Log at least one sleep event.
4. Save a morning check-in.
5. Trigger dashboard sync.

On device B:

1. Launch DoseTap.
2. Trigger dashboard sync.
3. Confirm the same session appears with matching dose data, sleep events, and morning check-in state.

Expected current behavior:

- These entities should sync: session summary, `sleep_events`, `dose_events`, `morning_checkins`
- These entities are not yet included in CloudKit upload and should be treated as known gaps: `pre_sleep_logs`, `checkin_submissions`, `medication_events`, `sleep_sessions`, `current_session`

## 5. SQLite Parity Checks

On simulator or device container, compare row counts and sample session keys:

```bash
APP_DATA="$(xcrun simctl get_app_container booted com.dosetap.ios data)"
DB_PATH="$(find "$APP_DATA" -name '*.sqlite' | head -n 1)"
sqlite3 "$DB_PATH" "SELECT 'sleep_events', COUNT(*) FROM sleep_events
UNION ALL SELECT 'dose_events', COUNT(*) FROM dose_events
UNION ALL SELECT 'morning_checkins', COUNT(*) FROM morning_checkins
UNION ALL SELECT 'pre_sleep_logs', COUNT(*) FROM pre_sleep_logs
UNION ALL SELECT 'checkin_submissions', COUNT(*) FROM checkin_submissions
UNION ALL SELECT 'medication_events', COUNT(*) FROM medication_events;"
```

Check for discoverability blind spots:

```bash
sqlite3 "$DB_PATH" "SELECT DISTINCT session_date FROM morning_checkins
EXCEPT
SELECT session_date FROM sleep_sessions
UNION
SELECT session_date FROM dose_events
UNION
SELECT session_date FROM sleep_events;"
```

Any non-empty result means storage contains session data that the current recent-session discovery path can miss.

## 6. Known Failure Modes To Watch

- Build says cloud sync disabled: `DoseTapCloudSyncEnabled` is off in build settings or wrong target/scheme is installed.
- Signed app lacks CloudKit entitlements: signing profile or target entitlements are wrong.
- Sync completes but data classes are missing on the second device: expected today for `pre_sleep_logs`, `checkin_submissions`, `medication_events`, `sleep_sessions`, `current_session`.
- Duplicate logical Dose 2 after multi-device offline use: expected risk with current UUID-keyed conflict handling.

## 7. Exit Criteria

Treat CloudKit setup as ready only when all are true:

1. Local readiness script passes.
2. Signed Debug app shows CloudKit entitlements on device build output.
3. Two-device sync succeeds for dose events, sleep events, and morning check-ins.
4. No unexpected missing rows appear in the synced entity set.
5. Known unsynced entities are documented as remaining scope, not mistaken as data loss.
