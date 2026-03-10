# Unified Severity Mapping

All findings across every audit phase MUST use this scale. Non-negotiable.

| Severity | Label | Definition (DoseTap-Specific) |
| --- | --- | --- |
| **P0** | CRITICAL | Patient safety impact: dose timing incorrect, alarm not delivered, data loss/corruption, session state inconsistency, leaked credentials with real exposure |
| **P1** | HIGH | Feature broken for a specific channel (e.g., Flic works but alarms don't fire), notification system broken, security control missing with real exposure |
| **P2** | MEDIUM | Missing feature, degraded UX, permission handling gap, reproducibility drift, missing automation that will cause regressions |
| **P3** | LOW | Code smell, dead code, missing docs, cosmetic issues, small maintainability wins |

## Examples

| Severity | Example Finding |
| --- | --- |
| P0 | Dose window math wrong, orphan alarms after session delete, API key in git history |
| P1 | Flic button → no alarms scheduled, notification ID mismatch, `macos-latest` floating runner |
| P2 | No permission recovery, no Dependabot, no code coverage tracking |
| P3 | Dead `alarm_tone.caf` check, stale archive contents, TODO comments |
