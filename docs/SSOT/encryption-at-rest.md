# Encryption at Rest — Decision Record

Last updated: 2026-02-14
Status: **Decided — iOS Data Protection sufficient for v1**

## Question

Should DoseTap add SQLCipher (or equivalent) database-level encryption to the Core Data SQLite store, or rely on iOS Data Protection?

## Context

DoseTap stores sensitive medication timing data (XYWAV dose times, sleep events, health integrations). The storage layer uses Core Data backed by SQLite on-device. No PHI (Protected Health Information) as defined by HIPAA is stored — the app tracks timing only, not prescriptions, diagnoses, or provider records.

## Decision

**iOS Data Protection is sufficient for v1. SQLCipher is a non-goal for the initial release.**

## Rationale

### What iOS Data Protection already provides

| Protection | Coverage |
|---|---|
| File-level encryption | All app files encrypted with device passcode (AES-256) |
| Access class | `NSFileProtectionCompleteUntilFirstUserAuthentication` (default) — files locked until device unlocked after boot |
| Keychain | OAuth tokens and encryption keys stored in Secure Enclave-backed Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` |
| Backup encryption | App data in iCloud backups is encrypted; iTunes backups can be optionally encrypted |

### What SQLCipher would add

- Column-level encryption of the SQLite database file itself
- Protection against jailbreak + raw file system access
- Protection against forensic tools that can extract raw SQLite from device images
- Defense-in-depth if iOS Data Protection is bypassed

### Why SQLCipher is not needed for v1

1. **Threat model**: The primary threat is a lost/stolen phone. iOS Data Protection + device passcode already mitigates this. A jailbroken device with physical access is an edge case.
2. **Data sensitivity**: Dose timing data is sensitive but not PHI. No diagnosis, provider, or prescription details are stored.
3. **Complexity cost**: SQLCipher requires a third-party dependency, database migration tooling, and testing for performance impact on older devices.
4. **Infrastructure ready**: `DatabaseSecurity.swift` already implements key management (generate, store, rotate, delete) using Keychain. If SQLCipher is needed later, the key infrastructure is in place.

### Future consideration

If any of these conditions change, revisit this decision:

- App begins storing PHI (prescriptions, provider notes, diagnosis)
- Regulatory requirement (HIPAA BAA, SOC 2) mandates database encryption
- CloudKit sync is added (data leaves device → encryption becomes critical)
- User feedback indicates a need for additional security assurance

## Current security controls

| Layer | Implementation | File |
|---|---|---|
| Keychain tokens | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | `SecureConfig.swift`, `KeychainHelper.swift` |
| Key management | 256-bit key generation, Keychain storage, rotation support | `DatabaseSecurity.swift` |
| Secret loading | Env → Keychain → Secrets.swift (debug only); release returns empty | `SecureConfig.swift` |
| Certificate pinning | Leaf + intermediate CA SPKI pins | `CertificatePinning.swift` |
| Mock transport guard | `#if DEBUG` only; CI enforces no mock in production | `MockAPITransport.swift` |

## References

- Apple Data Protection: https://support.apple.com/guide/security/data-protection-overview-secd46de2a1e/web
- SQLCipher: https://www.zetetic.net/sqlcipher/
- `DatabaseSecurity.swift`: `ios/DoseTap/Security/DatabaseSecurity.swift`
- Certificate pinning runbook: `docs/CERTIFICATE_PINNING.md`
