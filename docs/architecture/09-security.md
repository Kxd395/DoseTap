# 09 — Security

## Defense Layers

```text
┌─────────────────────────────────────────────┐
│ Layer 1: Input Validation                    │
│  InputValidator — whitelist event names,    │
│  sanitize text, validate deep links         │
├─────────────────────────────────────────────┤
│ Layer 2: Transport Security                  │
│  CertificatePinning — SHA-256 SPKI pins,   │
│  domain-scoped, no fallback in production   │
├─────────────────────────────────────────────┤
│ Layer 3: Data at Rest                        │
│  DatabaseSecurity — file protection,        │
│  EncryptedEventStorage — SQLCipher-compat   │
├─────────────────────────────────────────────┤
│ Layer 4: Data Redaction                      │
│  DataRedactor — PII removal for exports,    │
│  SecureLogger — redacted logging            │
├─────────────────────────────────────────────┤
│ Layer 5: Logging Privacy                     │
│  os.Logger with OSLogPrivacy annotations    │
│  No print() in production code              │
└─────────────────────────────────────────────┘
```

## Input Validation

File: `ios/DoseTap/Security/InputValidator.swift` (337 lines)

### Event Name Whitelist

```swift
static let validEventTypes: Set<String> = [
    // Physical
    "bathroom", "water", "snack",
    // Sleep Cycle
    "lightsout", "lights_out", "waketemp", "wake_temp",
    "inbed", "in_bed", "wake_final", "wakefinal",
    "wake", "wake_up", "wakeup",
    "nap start", "nap end", "nap_start", "nap_end",
    // Mental
    "anxiety", "restless", "dream", "heartracing", "heart_racing",
    // Environment
    "noise", "temperature", "temp", "pain",
    // Dose Events (internal)
    "dose1", "dose2", "dose2_skipped", "snooze", "extra_dose"
]
```

### Validation Functions

```text
validateEventName(_:) → String?
  Input → lowercase → trim → whitelist check → sanitized or nil

sanitizeText(_:maxLength:) → String?
  Input → trim → length check (max 500) → strip control chars

validateDeepLinkURL(_:) → Bool
  Check scheme, host, path against known routes

validateDoseTimestamp(_:) → Bool
  Reject future dates, dates > 24h old

validateSessionDate(_:) → Bool
  Format check "YYYY-MM-DD"
```

## Certificate Pinning

File: `ios/Core/CertificatePinning.swift` (251 lines)

```text
Pin format: SHA-256 of SPKI (Subject Public Key Info)
Domains: api.dosetap.com, auth.dosetap.com
Fallback: NEVER in production (DEBUG only)

Pin sources (priority):
  1. ENV: DOSETAP_CERT_PINS
  2. Info.plist: DOSETAP_CERT_PINS

Generation command:
  openssl x509 -in cert.pem -pubkey -noout |
  openssl pkey -pubin -outform DER |
  openssl dgst -sha256 -binary | base64
```

### URLSession Delegate

```swift
func urlSession(_:didReceive challenge:completionHandler:)
  ├── Extract server certificate chain
  ├── Compute SHA-256 of each cert's SPKI
  ├── Check against pinnedHashes
  ├── Match? → .useCredential
  └── No match? → .cancelAuthenticationChallenge
```

## Data Redaction

File: `ios/Core/DataRedactor.swift` (234 lines)

```text
Redaction types:
  ├── Emails    → [REDACTED_EMAIL]
  ├── UUIDs     → HASH_<first8chars>
  ├── IP addrs  → [REDACTED_IP]
  └── Names     → [REDACTED]

Configs:
  ├── .default  — hash IDs, remove emails+names
  └── .minimal  — hash IDs only
```

Used in: support bundle export, diagnostic export, error logging.

## Database Security

File: `ios/DoseTap/Security/DatabaseSecurity.swift`

```text
File protection: .completeUntilFirstUserAuthentication
  - Data accessible after first unlock
  - Protected when device locked (before first unlock after restart)

Integrity checks:
  - PRAGMA integrity_check on open
  - PRAGMA foreign_key_check

Encryption:
  - EncryptedEventStorage wraps EventStorage
  - SQLCipher-compatible API
  - Key stored in Keychain
```

## Secure Logging

File: `ios/DoseTap/Security/SecureLogger.swift`

```text
All logging via os.Logger:
  - .public for non-sensitive data (event types, counts)
  - .private for PII (timestamps, session IDs, user data)

Production builds:
  - .private values appear as <private> in Console.app
  - No print() allowed (enforced by linter)
```

## OAuth Security (WHOOP)

```text
PKCE (Proof Key for Code Exchange):
  ├── code_verifier: 43-128 char random string
  ├── code_challenge: SHA256(code_verifier) base64url
  └── Prevents authorization code interception

client_secret: Stored in SecureConfig, not hardcoded
redirect_uri: Custom URL scheme dosetap://whoop/callback
```

## Deep Link Security

```text
URL validation chain:
  1. URLRouter.handle(_:) checks scheme == "dosetap"
  2. InputValidator.validateDeepLinkURL(_:) checks host
  3. Event names validated against whitelist
  4. Notes sanitized (length, characters)
  5. Timestamps validated (not future, not stale)
```
