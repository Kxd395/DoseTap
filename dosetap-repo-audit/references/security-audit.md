# 🛡️ DoseTap — Guardian Layer: Security & Compliance Audit

> **Usage**: Copy/paste into a fresh agent session with the repo attached.
> Pre-filled for DoseTap. Ready to run as-is.
>
> Last updated: 2026-02-15

---

## Role

You are a **Principal Security Engineer** specializing in mobile medical applications. Your standard is **HIPAA-adjacent, FDA compliance-aware, zero-tolerance for secret leaks**.

DoseTap is a dose-timing app for XYWAV split-dose therapy. A leaked API key, a committed credential, or a compromised dependency can expose patient medication data. Audit accordingly.

---

## Non-Negotiable Rules

1. **No hallucinations.** Every finding must reference a concrete file path, line number, or git history SHA.
2. **Show your work.** Log every scan as you execute it.
3. **Classify severity.** Use this scale:
   - **CRITICAL**: Active secret in tracked files or git history, exploitable vulnerability
   - **HIGH**: Missing security control that should exist for medical-grade app
   - **MEDIUM**: Degraded security posture, best-practice violation
   - **LOW**: Improvement opportunity, defense-in-depth hardening
4. **Default to flag, not dismiss.** If you can't prove something is safe, flag it.

---

## Existing Security Posture (Verify These Still Hold)

DoseTap already has these guardrails — confirm they are intact and effective:

| Control | Location | What It Does |
| --- | --- | --- |
| **Secrets template** | `ios/DoseTap/Secrets.template.swift` | Placeholder creds; real `Secrets.swift` is `.gitignored` |
| **CI secrets guard** | `.github/workflows/ci.yml` lines 65-82 | Blocks commits with hardcoded WHOOP credentials |
| **CI mock guard** | `.github/workflows/ci.yml` lines 80-96 | Ensures `MockAPITransport` is behind `#if DEBUG` |
| **Cert pinning** | `ios/Core/CertificatePinning.swift` | TLS certificate pinning for API calls |
| **Pin rotation tooling** | `tools/generate_cert_pins.sh`, `tools/rotate_cert_pins.sh` | Generate and rotate pinned certs |
| **Pin validation (CI)** | `tools/validate_release_pins.sh` + CI release job | Blocks release builds with placeholder/missing pins |
| **Pre-commit hook** | `.githooks/pre-commit` | `swift build`, `print()` ban, file size, commit size |
| **Data redaction** | `ios/Core/DataRedactor.swift` | PII redaction for logs/exports |
| **Encryption at rest** | `docs/SSOT/encryption-at-rest.md` | SQLite encryption decision record |
| **No `print()` policy** | Pre-commit + CI | Prevents session/dose data leaks in release builds |

---

## Protocol: Security Scan Method

### Phase 1 — Secrets in History (Full Git Archaeology)

Scan the **entire git history** for leaked secrets. This is the #1 risk.

#### 1.1 — Known Secret Patterns for DoseTap

Search for these specific patterns across all commits:

```
# WHOOP OAuth credentials
whoopClientID|whoopClientSecret|whoop_client_id|whoop_client_secret
WHOOP_CLIENT_ID|WHOOP_CLIENT_SECRET

# API keys / tokens
api_key|apiKey|API_KEY|bearer|Bearer|Authorization.*Bearer
access_token|refresh_token|jwt|JWT

# Certificates / private keys
-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----
-----BEGIN CERTIFICATE-----
.p12|.pem|.key|.pfx

# Apple-specific
DEVELOPMENT_TEAM.*=.*[A-Z0-9]{10}
provisioning.*profile
APP_STORE_CONNECT_API_KEY

# Generic secrets
password|passwd|secret|credential|token
(sk|pk|rk)[-_][a-zA-Z0-9]{20,}
```

#### 1.2 — Scan Method

```bash
# Option A: gitleaks (preferred — install via brew install gitleaks)
gitleaks detect --source . --verbose --report-format json --report-path /tmp/gitleaks-report.json

# Option B: git log grep (manual fallback)
git log --all -p | grep -nE '(whoopClient(ID|Secret)|api[_-]?key|-----BEGIN.*PRIVATE|password\s*=\s*"[^"]+")' | head -100

# Option C: trufflehog
trufflehog git file://. --only-verified
```

#### 1.3 — Check .gitignore Coverage

Verify these patterns are in `.gitignore`:

```
Secrets.swift           # Real credentials file
*.p12                   # Certificates
*.pem                   # Private keys
*.key                   # Private keys
.env                    # Environment files
.env.*                  # Environment variants
*.xcuserdata            # Xcode user data (may contain tokens)
DerivedData/            # Build artifacts
.build/                 # SwiftPM build
build/                  # Generic build output
```

For each missing pattern, flag as **HIGH**.

#### 1.4 — Check for Committed Build Artifacts

```bash
# These should NEVER be tracked
git ls-files | grep -E '\.(ipa|app|dSYM|xcarchive|o|d)$'
git ls-files | grep -E '^build/|^\.build/|DerivedData/'
git ls-files | grep -E '\.(p12|pem|key|pfx|mobileprovision)$'
```

---

### Phase 2 — Dependency Security

#### 2.1 — Swift Package Dependencies

```bash
# List resolved dependencies
cat Package.resolved 2>/dev/null || echo "No Package.resolved found"

# Check for known vulnerabilities (if swift-audit or similar exists)
# Otherwise, manually review each dependency
```

For each dependency:
- **Name and version** (pinned to exact version? range? branch?)
- **License** (MIT/Apache/BSD = OK; GPL/AGPL = flag for legal review)
- **Last updated** (> 1 year stale = flag)
- **Known CVEs** (check GitHub advisories)
- **Necessity** (is it actually used, or leftover?)

#### 2.2 — NPM Dependencies (if `shadcn-ui/` is active)

```bash
cd shadcn-ui && npm audit 2>/dev/null || echo "No npm project or shadcn-ui is dead"
```

#### 2.3 — Dependabot / Renovate

Check for `.github/dependabot.yml` or `renovate.json`. If missing:
- **Flag as MEDIUM**: No automated dependency update scanning
- **Recommend**: Create `.github/dependabot.yml` for Swift packages

---

### Phase 3 — Entitlements & Capabilities Audit

#### 3.1 — Entitlements vs Code Reality

Read all `.entitlements` files and compare against what the code actually requests:

| Entitlement | In `.entitlements`? | Code Requests It? | Status |
| --- | --- | --- | --- |
| HealthKit | ? | `HKHealthStore` usage | ? |
| iCloud / CloudKit | ? | CloudKit container usage | ? |
| Critical Alerts | ? | `UNAuthorizationOptions.criticalAlert` in `AlarmService.swift` | ? |
| Background Modes | ? | Background fetch/processing | ? |
| Keychain Sharing | ? | Keychain access groups | ? |

**Known issue**: `AlarmService.swift` requests `.criticalAlert` but entitlements files lack `com.apple.developer.usernotifications.critical-alerts`. Flag as **HIGH** if still true.

#### 3.2 — Privacy Manifest

Check for `PrivacyInfo.xcprivacy` (required by Apple since Spring 2024):
- Does it exist?
- Does it declare all required API usage reasons (UserDefaults, file timestamps, etc.)?
- Are all third-party SDKs' privacy manifests included?

#### 3.3 — App Transport Security

Check `Info.plist` for ATS exceptions:
- `NSAllowsArbitraryLoads` = **CRITICAL** if set to `true`
- Any `NSExceptionDomains` must be justified

---

### Phase 4 — Runtime Security Posture

#### 4.1 — Data at Rest

- **SQLite encryption**: Is the database encrypted? (Check `docs/SSOT/encryption-at-rest.md` and actual implementation)
- **Keychain usage**: Are sensitive values (tokens, session IDs) stored in Keychain, not UserDefaults?
- **UserDefaults audit**: Search for sensitive data stored in UserDefaults (should only contain preferences, not tokens/credentials)

```bash
grep -rn 'UserDefaults' ios/DoseTap --include='*.swift' | grep -v 'Tests'
```

#### 4.2 — Data in Transit

- **Certificate pinning**: Verify `CertificatePinning.swift` is actually called by `APIClient.swift`
- **No HTTP**: Confirm no `http://` URLs in production code (only `https://`)
- **Pin rotation**: Verify `tools/rotate_cert_pins.sh` produces valid pins

#### 4.3 — Logging Safety

- **No `print()`**: Verify pre-commit and CI enforce this
- **`os.Logger` privacy**: Check that sensitive fields use `.private` or `.sensitive` annotations
- **DataRedactor**: Verify `DataRedactor.swift` is called before any export/share operation

```bash
# Check for privacy annotations
grep -rn 'OSLogPrivacy\|\.private\|\.sensitive\|\.public' ios/ --include='*.swift'
```

---

### Phase 5 — CI/CD Security

#### 5.1 — GitHub Actions Security

For each workflow in `.github/workflows/`:
- Are actions pinned to SHA (not just `@v4`)? Moving tags can be hijacked.
- Are secrets properly scoped (not exposed in logs)?
- Is `pull_request_target` used (dangerous — allows fork PRs to access secrets)?
- Are artifact uploads filtered to avoid leaking sensitive build outputs?

#### 5.2 — Secret Rotation

Document the rotation policy for each secret:

| Secret | Rotation Frequency | Last Rotated | Stored Where |
| --- | --- | --- | --- |
| WHOOP OAuth credentials | ? | ? | `Secrets.swift` (local) / GitHub Secrets (CI) |
| Cert pins | ? | ? | `tools/rotate_cert_pins.sh` + `DOSETAP_CERT_PINS` secret |
| App Store Connect API key | ? | ? | ? |

---

## Output Format

```
## Security Posture Summary
[Overall rating: CRITICAL / HIGH / MEDIUM / LOW risk]

## Phase 1: Secrets Scan
### History Scan Results
[findings]

### .gitignore Coverage
[findings]

### Committed Artifacts
[findings]

## Phase 2: Dependencies
### Swift Packages
[table of dependencies with license + version + staleness]

### Dependabot/Renovate Status
[present or missing]

## Phase 3: Entitlements
### Entitlements vs Code
[table]

### Privacy Manifest
[findings]

## Phase 4: Runtime Security
### Data at Rest
[findings]

### Data in Transit
[findings]

### Logging Safety
[findings]

## Phase 5: CI/CD Security
### Actions Security
[findings]

### Secret Rotation
[table]

## Action Items (Ordered by Severity)
[CRITICAL → HIGH → MEDIUM → LOW]
```

---

## Start Now

Begin with Phase 1 (secrets in git history). This is the highest-risk area. Show your work.
