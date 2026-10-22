# Dashboard provider-access invalidation

Status: implementation contract for DOSETAP-45
Date: 2026-09-30

- Dashboard requests capture an access revision. Preference changes, known HealthKit access loss, WHOOP disconnect and WHOOP account changes advance it before notifying observers. Check this revision after suspension and before publication, alongside generation, range and timezone. Off/on transitions cannot restore an old revision.
- Clear the affected provider's already displayed summaries and query metadata when invalidated. Preserve local dose/diary/event records and the other provider. Provider-only rows disappear when they have no remaining data. Clear integration status until refreshed; never show the old available status as current.
- Re-enabling does not restore old results. A new explicit/normal dashboard refresh is required. Invalidation is subscribed for the model's lifetime, including while its tab is hidden.
- Known loss of HealthKit authorization is conservative invalidation. Apple can conceal read revocation as an empty success; no denied/readable claim can be inferred from an empty query. This change does not add authorization probes or change medication/provider calculations.
- This is a prerequisite to later stale-snapshot retention. No disk cache, provider history extension, WHOOP production enablement or iPad envelope change is delivered here.

Preference writes must use `UserSettingsManager`; direct writes to the integration defaults keys bypass synchronous invalidation and are not allowed in production. The access monitor has no dependency on service or settings singletons.
