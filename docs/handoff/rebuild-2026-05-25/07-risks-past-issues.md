# 07 — Risks and Past Issues

## Historical Critical Risks

Older audits identify serious issues. Some may already be fixed in current HEAD, but the rebuild must verify rather than assume.

| Risk | Historical Source | Required Rebuild Action |
| --- | --- | --- |
| WHOOP client secrets in git history | `docs/audit/2026-02-15/findings.md` | Rotate credentials, verify no live secrets in HEAD, run secret scan, decide whether history purge is still required. |
| Secret on HEAD in archive docs | Audit findings SEC-003 | Verify current archive state and redact/purge if still present. |
| Missing sensitive patterns in `.gitignore` | Audit findings SEC-004 | Re-check `.gitignore`; add missing patterns for keys, certs, env files, provisioning, and generated secrets. |
| Notification ID mismatch | Audit and changelog | Keep regression tests for schedule/cancel ID parity. |
| Flic alarm parity | Audit and changelog | Test Flic dose/skip paths against alarm schedule/cancel expectations. |
| Deep links mutating state without authorization | Improvement roadmap | Keep foreground/protected-data checks and confirmation requirements. |
| Fake/simulated health data | Improvement roadmap | Add tests preventing simulated values from appearing as real data. |
| CloudKit ghost entitlement | Audit and docs | Separate local shipping target from staging CloudKit target. |

## Current High-Risk Areas

### Dose Registration Channel Parity

Risk: app UI, history, deep link, Flic, Siri, watch, and widget paths diverge.

Control:

- One policy.
- One mutation use case.
- Channel-specific confirmation adapters only.
- Tests for every channel.

### Timezone and DST

Risk: sessions cross midnight and DST; naive date grouping corrupts history.

Control:

- Preserve `SessionKey` behavior.
- Use fixed clock injection.
- Run tests in multiple timezones.

### Storage Migration

Risk: data loss during rewrite.

Control:

- Shadow migration.
- Row-count and checksum validation.
- Encrypted backup.
- Rollback flag.
- No destructive delete in first release.

### Health Data Privacy

Risk: sensitive medication/sleep data leaks through logs, exports, support bundles, or third-party integrations.

Control:

- Redaction tests.
- Structured privacy levels.
- No plaintext tokens.
- User-controlled export.

### Dashboard Overclaiming

Risk: small sample sizes create misleading conclusions.

Control:

- Sample-size gates.
- Data completeness warnings.
- Observational wording only.

## Required Security Checks

- Secret scan on full working tree.
- Hardcoded token/key scan.
- URL scheme abuse review.
- SQL injection review for all raw SQLite calls.
- Keychain access group review.
- App Group data minimization.
- Privacy manifest and Info.plist permission string review.
- Export/support bundle redaction tests.
