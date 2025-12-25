# Release Checklist

Use this checklist before tagging any release. Every item must pass.

## Automated (CI must be green)

- [ ] `ssot-lint` — SSOT integrity check passes (no drift between docs and code)
- [ ] `swiftpm-tests` — All 207+ DoseCore unit tests pass
- [ ] `xcode-tests` — All SessionRepository and app-level tests pass

## Manual Verification

### Dose Safety Flows

- [ ] **Dose 1 happy path** — Tap "Take Dose 1", confirm haptic + visual feedback, verify dose1 state persists after app restart
- [ ] **Dose 2 window** — Wait until window opens (or mock time), confirm Dose 2 button enabled, verify window math (150–240m range)
- [ ] **Snooze** — Tap snooze while >15m remaining, confirm 10m added, verify snooze disabled when <15m or after 3 snoozes
- [ ] **Skip** — Skip Dose 2, confirm session ends cleanly, verify next night starts fresh
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

- [ ] Version number bumped in Xcode project
- [ ] CHANGELOG.md updated with release notes
- [ ] Tag created: `git tag -a vX.Y.Z -m "Release X.Y.Z"`
- [ ] Archive uploaded to App Store Connect (if production release)

---

**Release approved by:** _______________  
**Date:** _______________
