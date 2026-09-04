# 01 — Current State Inventory

## Application Shape

DoseTap is currently a Swift/iOS codebase with a mixed SwiftPM + Xcode structure.

| Area | Current Location | Notes |
| --- | --- | --- |
| Core domain logic | `ios/Core/` | Platform-free Swift, includes dose windows, models, API queue, diagnostics, redaction, certificate pinning, recommendation and score calculators. |
| iOS app | `ios/DoseTap/` | SwiftUI app target with views, services, settings, storage, theme, integrations, and composition root. |
| Storage | `ios/DoseTap/Storage/` | SQLite-backed local storage with `EventStorage` and `SessionRepository` extensions by concern. |
| Tests | `Tests/DoseCoreTests/`, `ios/DoseTapTests/`, `ios/DoseTapUITests/` | Current testing guide documents SwiftPM, Xcode unit, and UI test gates. |
| Specs | `specs/` | Spec Kit-style plans for repo review, CloudKit sync, and manual dose entry. |
| Docs | `docs/` | SSOT, architecture, schema, audit, testing, privacy, release, and roadmap docs. |
| watchOS | `watchos/` | Source exists; target activation and parity need verification. |
| Widget | `ios/DoseTap/Widget/` | Widget source exists; target entitlement and Xcode project state need verification. |

## Current Core Behavior

Authoritative behavior lives in `docs/SSOT/README.md`.

- Dose 1 starts the active medication session.
- Dose 2 clinical window is 150-240 minutes after Dose 1.
- Default target interval is 165 minutes.
- Late Dose 2 remains Dose 2 with late metadata; it must not become dose index 3.
- Extra dose starts only at dose index 3+.
- Morning check-in closes the active session.
- Session grouping rolls over at 6 PM local time by default.
- Sleep events attach to the active session.
- Nap tracking is currently event-pair based: `Nap Start` and `Nap End`.
- Undo window defaults to 5 seconds for dose/event actions.

## Current Storage

Authoritative schema lives in `docs/DATABASE_SCHEMA.md`.

Existing tables include:

- `sleep_events`
- `dose_events`
- `current_session`
- `sleep_sessions`
- `pre_sleep_logs`
- `morning_checkins`
- `medication_events`

Storage is local SQLite. README states Cloud sync is not implemented in the shipping app. Current source also contains deferred CloudKit-related code and cloud entitlements, so the rebuild must explicitly separate local shipping, staging CloudKit validation, and future sync.

## Current Integrations

| Integration | Current Evidence | Rebuild Posture |
| --- | --- | --- |
| HealthKit | `HealthKitService.swift`, `HealthKitProviding.swift`, `HealthKitSettingsView.swift` | Keep, expand carefully, and distinguish user preference from system authorization. |
| WHOOP | `WHOOPService.swift`, `WHOOPDataFetching.swift`, `WHOOPSettingsView.swift`, `docs/WHOOP_INTEGRATION.md` | Keep only if credentials, PKCE flow, rate limits, and real-device E2E tests are ready. Never display simulated biometric data as real. |
| Flic | `FlicButtonService.swift` | Keep behind channel-parity tests and explicit confirmation rules for late/extra dose paths. |
| Siri/AppIntents | `ios/DoseTap/Intents/DoseTapIntents.swift` | Keep for read-only status and safe sleep-event logging; dose mutations require policy review. |
| Widgets | `ios/DoseTap/Widget/` | Keep for status/countdown; activation requires target, App Group, and stale-state tests. |
| URL schemes | `URLRouter.swift` | Keep but require foreground/protected-data gating for state mutation. |
| CSV export | `CSVExporter`, `EventStorage+Exports`, settings/export views | Keep; exports are essential for user control and support. |

## Documentation Drift Warning

Some older docs and audits conflict with current source. Examples:

- Historical audit files list missing privacy manifest, but `ios/DoseTap/PrivacyInfo.xcprivacy` exists on current HEAD.
- Older feature triage says WHOOP/watch/widgets are planned or partial, while current source contains WHOOP data fetching, widget, watch, and AppIntents files.
- Current README still says Cloud sync is not implemented, while deferred CloudKit code and entitlements exist.

Required rebuild action: create a fresh `CURRENT_STATE_AUDIT.md` before implementation and mark each older finding as `verified-open`, `resolved`, `obsolete`, or `needs-runtime-test`.
