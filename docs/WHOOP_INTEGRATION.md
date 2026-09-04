# WHOOP integration status and validation plan

Status: Implemented code path; production enablement and live end-to-end validation open
Last verified against code and WHOOP documentation: 2026-09-02

## Current implementation

| Capability | Code-backed status | Remaining gate |
| --- | --- | --- |
| OAuth UI | `ASWebAuthenticationSession` with state verification and PKCE | Live consent and callback run with an approved WHOOP app |
| OAuth state | Generated as an eight-character URL-safe value | Verify against the live service during E2E testing |
| Token storage | Keychain-backed access and refresh tokens | Signed-build lifecycle and disconnect inspection |
| Refresh | One serialized in-flight refresh; requests `offline` scope | Live rotation, expiry, and concurrent-request run |
| Data API | Sleep, recovery, cycle, and heart-rate collection requests | Real-account completeness and no-data behavior |
| Pagination | Follows collection `next_token` through the `nextToken` request parameter | Live multi-page dataset |
| Resilience | One refresh after 401 plus bounded 429 and 5xx retry behavior | Live rate-limit and outage behavior |
| UI enablement | Dynamic local flag changes on connect and disconnect | Owner-observed Settings and Dashboard flow |
| Production credentials | Not complete | A native binary cannot keep a client secret confidential; approve a server-side exchange or another reviewed design |

Main source files:

- `ios/DoseTap/WHOOPService.swift`
- `ios/DoseTap/WHOOPDataFetching.swift`
- `ios/DoseTap/WHOOPSettingsView.swift`
- `ios/DoseTap/SleepTimelineOverlays.swift`
- `ios/DoseTap/Views/Dashboard/`

## External contract

Current WHOOP documentation states that user data access uses OAuth 2.0, self-generated state is eight characters, the `offline` scope provides refresh tokens, and token requests use a client ID and client secret. Collection endpoints expose `nextToken` pagination.

- [WHOOP OAuth documentation](https://developer.whoop.com/docs/developing/oauth/)
- [WHOOP API reference](https://developer.whoop.com/api/)

Recheck those pages before a release. External documentation can change independently of this repository.

## Local development configuration

Register the exact redirect URI `dosetap://whoop/callback` in the WHOOP Developer Dashboard. Request only the scopes the enabled UI needs. The current code expects `offline`, `read:recovery`, `read:sleep`, `read:cycles`, and `read:profile`.

Local secrets may be supplied through ignored development configuration supported by `SecureConfig`. Never commit, print, paste into Plane, or include actual values in a support bundle.

Production must not ship a reusable WHOOP client secret in source, Info.plist, a build setting, or another extractable client asset. Production enablement requires a reviewed token-exchange boundary, exact data-flow map, privacy disclosure, retention policy, outage behavior, and revocation flow.

## Data presentation contract

- Apple Health and WHOOP remain separate named sources.
- A WHOOP value must not silently replace an Apple Health value under a generic label.
- Missing or unscored provider data remains missing; do not invent a zero or carry forward an old value.
- Night matching must preserve canonical DoseTap session identity and provider time provenance.
- Provider profile and health payloads must not enter diagnostic logs.

## Required live validation

- [ ] Authorization succeeds and returns to `dosetap://whoop/callback`.
- [ ] Wrong or replayed state is rejected.
- [ ] Access-token expiry triggers one serialized refresh without disconnecting concurrent reads.
- [ ] Rotated refresh tokens replace old tokens safely.
- [ ] Sleep, recovery, cycle, and heart-rate collections traverse more than one page.
- [ ] Unscored, missing, 401, 429, 5xx, offline, and revoked-access states produce clear non-stale UI.
- [ ] Disconnect removes DoseTap-owned WHOOP credentials and cached connection state.
- [ ] Dashboard, History, Night Review, and export identify WHOOP as the source for the same night.
- [ ] Privacy policy and App Store disclosures match the exact enabled data flow.

Until these gates pass, describe WHOOP as implemented but not production-validated.
