# 08 — Testing, Observability, and Security

## Validation Gates

Required before any rebuild release candidate:

```bash
swift build -q
swift test -q
xcodebuild build -project ios/DoseTap.xcodeproj -scheme DoseTap -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Also required when relevant:

- Xcode unit tests.
- XCUITests for critical paths.
- Multi-timezone SwiftPM tests.
- Device tests for notifications, HealthKit, Watch, widgets, Flic, and WHOOP.
- Secret scan.
- Privacy manifest validation.
- Export/support bundle redaction tests.

## Test Matrix

| Category | Required Coverage |
| --- | --- |
| Unit | Dose windows, session keys, registration policy, calculators, data redaction, migration mappers. |
| Integration | Repository/store adapters, HealthKit mock, WHOOP mock, notification scheduling, URLRouter, AppIntents. |
| UI | Tonight core flow, morning check-in, history edits, dashboard data states, settings/integrations. |
| Device | Notifications, critical/time-sensitive fallback, HealthKit permissions, widgets, watch, Flic. |
| Load | One year and three years of nightly data, exports, dashboard aggregate build, migration. |
| Edge | DST, timezone change mid-session, app kill/relaunch, duplicate action retries, offline sync, iCloud sign-out. |
| Security | Secrets, log redaction, SQL injection, URL scheme abuse, token storage, support bundle redaction. |

## Observability Requirements

Every session-impacting action should produce structured diagnostics:

- `correlation_id`
- `session_id`
- `session_date`
- `action_source`
- `event_type`
- `policy_decision`
- `storage_version`
- `app_version`
- `timezone`
- `result`
- `error_category` when failed

Sensitive data rules:

- No access tokens.
- No refresh tokens.
- No OAuth codes.
- No raw notes unless user explicitly exports them.
- No full device identifiers.
- No unredacted health payloads in standard logs.

## Diagnostic Events to Add or Verify

- Migration started/completed/failed/rolled back.
- Storage adapter selected.
- Sync enabled/disabled.
- Sync conflict detected/resolved.
- Integration authorization changed.
- Widget state refreshed/stale.
- Watch action received/rejected/persisted.
- Dose policy blocked/requires confirmation/allowed.
- Export generated/redacted.

## Security Baseline

Minimum controls:

- Keychain for tokens.
- App Group storage minimized to derived widget/watch state.
- Local database protected by iOS Data Protection.
- SQL statements parameterized.
- Remote API clients rate-limited and retry-bounded.
- Certificate pinning reviewed for maintainability.
- No client secrets in mobile binary.
- Branch protection and CI gates on main.
