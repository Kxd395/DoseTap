# 04 — Integrations and Data

## Integration Principles

- Integrations are additive. The app must remain useful with every integration disabled.
- Integration data must never be faked. If data is missing, show missing-data states.
- Tokens and identifiers must never be logged in plaintext.
- Integration failures must be user-visible when they affect decisions, and diagnostic-only when they do not.
- Each integration needs a mock service for tests and previews.

## HealthKit

Required scope:

- Sleep analysis.
- Heart rate.
- Respiratory rate.
- HRV SDNN.
- Resting heart rate.

Implementation notes:

- Keep preference and authorization separate.
- Support re-authorization after reinstall or permission changes.
- Handle partial permission grants.
- Cache derived nightly summaries locally with source timestamps.
- Never block dose logging on HealthKit availability.

Acceptance criteria:

- Permission denied does not crash or clear user intent silently.
- Revoked permission shows a recoverable settings state.
- Imported data is linked by session key/time range with timezone-safe logic.

## WHOOP

Current source includes OAuth/token/API client files and production-readiness docs. Rebuild must verify the current implementation against real WHOOP developer credentials.

Required before enabling:

- PKCE OAuth verified with WHOOP.
- No client secret embedded in mobile app.
- Token refresh and disconnect tested.
- 401, 429, 5xx, offline, and malformed response behavior tested.
- Dashboard and timeline only show real WHOOP data.
- Data provenance shown as WHOOP, HealthKit, manual, or unavailable.

Rollback:

- Feature flag disables WHOOP UI and background fetch.
- Disconnect clears Keychain tokens.
- Cached WHOOP-derived summaries are marked stale or removed based on user choice.

## Flic Button

Flic is high-risk because it can mutate medication state from outside the main UI.

Rules:

- Flic must call the same dose registration policy as Tonight.
- Late dose, after-skip dose, and extra dose require explicit confirmation.
- If confirmation cannot be shown, Flic must create a notification/open-app prompt instead of persisting the dose.
- All Flic actions must be logged with source `flic`.

## Widgets

Recommended scope:

- Display current phase, next action, countdown, and last sync/update time.
- Avoid direct mutating dose actions until confirmation UX is proven.
- Use App Group storage only for minimal derived state, not the full medical record.
- Widget stale state must be obvious.

## Apple Watch

Recommended scope:

- Dose status.
- Confirmed dose logging.
- Snooze where policy allows.
- Quick sleep events.
- Haptic reminders.

Storage dependency:

- Watch support should be built after sync/shared-state architecture is selected.
- Watch actions must be idempotent and conflict-tested with phone actions.

## Siri and Shortcuts

Recommended scope:

- Check dose status.
- Log non-dose sleep events.
- Open app to dose confirmation.

Avoid:

- Silent dose 1 or dose 2 mutation from voice unless Apple interaction and app policy provide explicit confirmation.

## Exports and Support Bundles

Required:

- CSV export by date range.
- Diagnostic session trace export.
- Redacted support bundle.
- Schema version and app version in export metadata.
- Redaction tests for tokens, secrets, notes where excluded, email, and device identifiers.
