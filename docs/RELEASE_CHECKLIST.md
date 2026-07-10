# Release Checklist

Use this checklist before tagging any release. Every item must pass.

## Quick Start — Automated Preflight

Run the automated preflight script to verify all gate-able items at once:

```bash
bash tools/release_preflight.sh v1.2.3
```

The tagged form is strict: missing or invalid `DOSETAP_CERT_PINS` blocks the
preflight. Untagged runs are local dry runs and only warn when pins are missing.

This checks: tag format, app version/build settings, SSOT integrity, no tracked
secrets, no hardcoded credentials, certificate pin validation, mock transport
confinement, CHANGELOG updated, SwiftPM build + tests. The same script runs on CI
for tag pushes.

## Automated (CI must be green)

- [ ] `ssot-lint` — SSOT integrity check passes (no drift between docs and code)
- [ ] `swiftpm-tests` — All DoseCore unit tests pass (see CI output for current count)
- [ ] `xcode-tests` — All SessionRepository and app-level tests pass
- [ ] `release-pin-script-tests` — Pin validation script regression checks pass
- [ ] `release-pinning-check` — (tag builds only) Release preflight + real pin validation + Release build
- [ ] `app-version-check` - `bash tools/check_app_version.sh` passes for `DoseTap` and `DoseTapStaging`
- [ ] Secret scanning — No `Secrets.swift` tracked, no hardcoded credentials in source
- [ ] Mock transport guard — `MockAPITransport` confined to `#if DEBUG`

## Manual Verification

### Dose Safety Flows

- [ ] **Dose 1 happy path** — Tap "Take Dose 1", confirm haptic + visual feedback, verify dose1 state persists after app restart
- [ ] **Dose 2 window** — Wait until window opens (or mock time), confirm Dose 2 button enabled, verify window math (150–240m range)
- [ ] **Missed Dose 2 alarm recovery** - Let the alarm grace period expire, verify Dose 2 is marked skipped, then confirm `Record Dose 2 (Late)` remains available before and after Wake Final. Review the warning, record the actual dose, and verify the skip clears after relaunch.
- [ ] **Snooze** — Tap snooze while >15m remaining, confirm 10m added, verify snooze disabled when <15m or after 3 snoozes
- [ ] **Skip** — Skip Dose 2, confirm the dose outcome is recorded while the session remains open for morning closeout, then verify the next night starts fresh after closure
- [ ] **Undo** — Take dose, immediately undo within 5s window, confirm state reverts

### Data Integrity

- [ ] **Export CSV** — Export from History, open CSV, verify columns match schema, spot-check 3 rows
- [ ] **Support bundle** — Generate support bundle, verify it contains anonymized data (no PII leak)
- [ ] **Session persistence** — Force-quit app mid-session, relaunch, verify state restored correctly

### Edge Cases

- [ ] **Offline mode** — Enable airplane mode, take dose, verify queued, disable airplane mode, verify synced
- [ ] **DST transition** — If near DST change, verify window math handles timezone shift (or add to next release)
- [ ] **Rate limit** — Rapid-tap bathroom event, verify debounce (60s cooldown)

## Final Sign-off

- [ ] Version and build numbers bumped in Xcode project
- [ ] `bash tools/check_app_version.sh` passes
- [ ] CHANGELOG.md updated with release notes
- [ ] Tag created: `git tag -a vX.Y.Z -m "Release X.Y.Z"`
- [ ] Archive uploaded to App Store Connect (if production release)

---

**Release approved by:** _______________  
**Date:** _______________
