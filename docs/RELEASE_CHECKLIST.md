# Release Checklist

Status: Current per-release runbook
Last verified: 2026-09-02

Use this checklist before tagging any release. Every item must pass.

## Quick Start — Automated Preflight

Run the automated preflight script to verify all gate-able items at once:

```bash
bash tools/release_preflight.sh v1.2.3
```

The tagged form is strict: missing or invalid `DOSETAP_CERT_PINS` blocks the
preflight. Untagged runs are local dry runs and only warn when pins are missing.

This checks tag format, app version/build settings, documentation lifecycle,
SSOT integrity, medication and export boundaries, tracked-secret rules,
certificate pin configuration, mock transport confinement, CHANGELOG state,
and the SwiftPM build and tests. The same script runs on CI for tag pushes.

## Automated (CI must be green)

- [ ] Documentation checks — `tools/doc_lint.sh` and `tools/ssot_check.sh` pass
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
- [ ] **Snooze** — Tap snooze while more than 15m remains, confirm the configured duration is applied, and verify it is disabled near close or at the configured limit; defaults are 10m and 3 snoozes
- [ ] **Skip** — Skip Dose 2, confirm session ends cleanly, verify next night starts fresh
- [ ] **Undo** — Take dose, immediately undo within 5s window, confirm state reverts

### Data Integrity

- [ ] **Export** — Export from Settings, open the files, verify manifest/schema compatibility, and compare owner-selected records and source labels
- [ ] **Support bundle** — Generate a support bundle and verify the documented privacy filter; do not assume the bundle is anonymous without inspection
- [ ] **Session persistence** — Force-quit app mid-session, relaunch, verify state restored correctly

### Edge Cases

- [ ] **Offline mode** — Enable airplane mode, record a dose, force-quit, and verify the committed local state survives relaunch; medication actions must not enter the network queue
- [ ] **DST and timezone** — Run deterministic gap/repeated-hour tests and complete the physical timezone evidence required by the applicable release gate
- [ ] **Rate limit** — Rapid-tap a Quick Log event and verify its configured cooldown; the current Bathroom default is 30 seconds

## Final Sign-off

- [ ] Version and build numbers bumped in Xcode project
- [ ] `bash tools/check_app_version.sh` passes
- [ ] CHANGELOG.md updated with release notes
- [ ] Tag created: `git tag -a vX.Y.Z -m "Release X.Y.Z"`
- [ ] Archive uploaded to App Store Connect (if production release)

---

**Release approved by:** _______________  
**Date:** _______________
