# Certificate Pinning — Operational Runbook

Last updated: 2026-02-14

## Overview

DoseTap uses SPKI (Subject Public Key Info) SHA-256 pinning for all API connections. This prevents MITM attacks by validating the server's public key hash against a known set.

## Current State

| Item | Value |
|------|-------|
| Primary pin | `sha256/IIRsA4AWjFy9n05ZpJbJxYpwUp6RVoDxdRBT8PmCWw4=` |
| Backup pin (intermediate CA) | `sha256/18tkPyr2nckv4fgo0dhAkaUtJ2hu2831xlO2SKhq8dg=` |
| Pinned domains | `api.dosetap.com`, `auth.dosetap.com` |
| Config source | `DOSETAP_CERT_PINS` env var or Info.plist key |
| Release gate | `tools/validate_release_pins.sh` requires **2 unique** pins |

## Architecture

```
┌─────────────────────────────────────────────────┐
│  App Launch                                     │
│  ┌───────────────────────────────────────────┐  │
│  │ CertificatePinning.forDoseTapAPI()        │  │
│  │  ├── Check DOSETAP_CERT_PINS env var      │  │
│  │  ├── Check Info.plist DOSETAP_CERT_PINS   │  │
│  │  └── If empty: warn in DEBUG, no pinning  │  │
│  └───────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────┐  │
│  │ PinnedURLSessionTransport                 │  │
│  │  └── URLSession with CertificatePinning   │  │
│  │      delegate for TLS handshake           │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
```

Files:
- `ios/Core/CertificatePinning.swift` — Pin loading, URLSession delegate
- `tools/rotate_cert_pins.sh` — Extract pin from live server
- `tools/validate_release_pins.sh` — CI release gate (≥2 unique pins)

## Pin Extraction

```bash
# Extract the current pin from the live server:
bash tools/rotate_cert_pins.sh api.dosetap.com

# Or manually:
openssl s_client -connect api.dosetap.com:443 -servername api.dosetap.com </dev/null 2>/dev/null \
  | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform DER \
  | openssl dgst -sha256 -binary \
  | base64
```

## Rotation Procedure

Rotation requires **zero-downtime overlap**: both old and new pins must be active in the app before the server certificate changes.

### Step 1: Obtain the new pin

```bash
# If the new cert is deployed to a staging server:
bash tools/rotate_cert_pins.sh api-staging.dosetap.com

# If you have the new cert file:
openssl x509 -in new_cert.pem -pubkey -noout \
  | openssl pkey -pubin -outform DER \
  | openssl dgst -sha256 -binary \
  | base64
```

### Step 2: Ship app update with BOTH pins

Set `DOSETAP_CERT_PINS` with comma-separated old + new pins:

```
sha256/IIRsA4AWjFy9n05ZpJbJxYpwUp6RVoDxdRBT8PmCWw4=,sha256/NEW_PIN_BASE64=
```

### Step 3: Wait for adoption

Wait until the vast majority of users have updated to the new app version. Check App Store Connect for adoption metrics.

### Step 4: Deploy new server certificate

Only after the app with both pins is widely adopted.

### Step 5: Remove old pin

In a subsequent app release, remove the old pin from `DOSETAP_CERT_PINS`.

## Deployment Configuration

### GitHub Actions Secrets

Set `DOSETAP_CERT_PINS` as a repository secret:
```
sha256/PIN_A=,sha256/PIN_B=
```

This is used by `ci.yml → release-pinning-check` job (tag-gated).

### Xcode Build Settings

For local development: no pins needed (DEBUG builds skip pinning).

For TestFlight / App Store builds:
1. Add `DOSETAP_CERT_PINS` to the Xcode build environment, or
2. Set it in `Info.plist` under the `DOSETAP_CERT_PINS` key

### Info.plist Example

```xml
<key>DOSETAP_CERT_PINS</key>
<string>sha256/IIRsA4AWjFy9n05ZpJbJxYpwUp6RVoDxdRBT8PmCWw4=,sha256/BACKUP_PIN=</string>
```

## Obtaining the Backup Pin

The backup pin MUST come from a different key than the primary. Options:

1. **Intermediate CA certificate** — pin the issuing CA's public key (survives leaf cert renewal)
2. **Pre-generated backup key** — generate a CSR with a new key pair, extract the SPKI hash, store the private key offline
3. **Next certificate** — when renewing, extract the pin before deploying

### Option 1: Intermediate CA pin (recommended)

```bash
# Get the full chain
openssl s_client -connect api.dosetap.com:443 -servername api.dosetap.com -showcerts </dev/null 2>/dev/null > /tmp/chain.pem

# Extract intermediate (2nd cert in chain)
awk '/BEGIN CERTIFICATE/{n++} n==2' /tmp/chain.pem | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform DER \
  | openssl dgst -sha256 -binary \
  | base64
```

## Failure Modes

| Scenario | Behavior |
|----------|----------|
| No pins configured (DEBUG) | Warning logged, connects via default TLS |
| No pins configured (RELEASE) | `PinnedURLSessionTransport` still created; no pin check (relies on system TLS) |
| Pin mismatch | Connection rejected, `URLSession` cancels with auth error |
| Server cert expired | OS-level TLS failure (before pin check) |
| Release build with <2 pins | `validate_release_pins.sh` blocks CI |

## Validation Checklist

- [ ] `bash tools/rotate_cert_pins.sh api.dosetap.com` returns a valid pin
- [ ] `CONFIGURATION=Release DOSETAP_CERT_PINS="pin1,pin2" bash tools/validate_release_pins.sh` passes
- [ ] CertificatePinningTests all pass (`swift test --filter CertificatePinning`)
- [ ] App connects successfully with pins set in environment
- [ ] App rejects connections when wrong pin is set (manual test)
