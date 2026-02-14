# WHOOP Integration — Production Readiness

Last updated: 2026-02-14

## Current State

| Item | Status |
|------|--------|
| OAuth 2.0 flow | ✅ Implemented (ASWebAuthenticationSession) |
| Token management | ✅ Keychain storage + auto-refresh |
| API client | ✅ Sleep, recovery, cycle, heart rate |
| Retry/resilience | ✅ Exponential backoff, 429/5xx retries |
| Logging | ✅ os.Logger (no print) |
| Feature flag | 🔒 `WHOOPService.isEnabled = false` |
| Credentials | ❌ Need WHOOP developer app registration |
| E2E testing | ❌ Blocked on credentials |

## Files

| File | Purpose | Lines |
|------|---------|-------|
| `WHOOPService.swift` | OAuth, tokens, API client, keychain | ~470 |
| `WHOOPDataFetching.swift` | Sleep/recovery/cycle/HR data | ~480 |
| `WHOOPSettingsView.swift` | Connect/disconnect UI | ~280 |
| `SleepTimelineOverlays.swift` | Timeline integration | ext |

## Enablement Steps

### 1. Register WHOOP Developer App
- Go to https://developer-dashboard.whoop.com
- Create a new application
- Set redirect URI to `dosetap://whoop-callback`
- Note the Client ID and Client Secret
- Required scopes: `read:recovery`, `read:sleep`, `read:cycles`, `read:profile`

### 2. Configure Credentials
Add to `ios/DoseTap/Secrets.swift` (`.gitignore`d):
```swift
enum Secrets {
    static let whoopClientID = "your-client-id"
    static let whoopClientSecret = "your-client-secret"
    static let whoopRedirectURI = "dosetap://whoop-callback"
}
```

Or set environment variables:
```bash
DOSETAP_WHOOP_CLIENT_ID=...
DOSETAP_WHOOP_CLIENT_SECRET=...
DOSETAP_WHOOP_REDIRECT_URI=dosetap://whoop-callback
```

### 3. Enable Feature Flag
In `WHOOPService.swift`, change:
```swift
static let isEnabled: Bool = true
```

### 4. Test Checklist
- [ ] OAuth flow completes (authorize → callback → token exchange)
- [ ] Token refresh works after expiry
- [ ] Sleep data fetches correctly for last 14 nights
- [ ] Recovery data maps to DoseTap sleep sessions
- [ ] 401 triggers clean disconnect (not crash)
- [ ] 429 rate limit triggers retry with backoff
- [ ] 5xx server errors retry up to 2 times
- [ ] Airplane mode → queue or graceful error
- [ ] Disconnect clears all keychain tokens
- [ ] Re-authorize after disconnect works cleanly

### 5. Privacy Considerations
- WHOOP sleep/recovery data is health data — ensure `NSHealthShareUsageDescription` covers it
- Token stored in Keychain (iOS Data Protection automatic)
- No WHOOP data logged at `.info` or higher (use `.debug` for API responses)
- User profile (name, email) is only stored in memory, not persisted

## Architecture

```
┌──────────────────────────────────┐
│  WHOOPSettingsView               │
│  ┌────────────────────────────┐  │
│  │ Connect / Disconnect       │  │
│  └─────────────┬──────────────┘  │
│                │                 │
│  ┌─────────────▼──────────────┐  │
│  │ WHOOPService (@MainActor)  │  │
│  │ ├── authorize()            │  │
│  │ ├── apiRequest() + retry   │  │
│  │ ├── refreshTokenIfNeeded() │  │
│  │ └── Keychain storage       │  │
│  └─────────────┬──────────────┘  │
│                │                 │
│  ┌─────────────▼──────────────┐  │
│  │ WHOOPDataFetching (ext)    │  │
│  │ ├── fetchSleepData()       │  │
│  │ ├── fetchRecoveryData()    │  │
│  │ ├── fetchCycleData()       │  │
│  │ └── fetchHeartRateData()   │  │
│  └────────────────────────────┘  │
└──────────────────────────────────┘
```
