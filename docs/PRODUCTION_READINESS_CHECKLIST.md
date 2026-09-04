# DoseTap production readiness checklist

Status: Current release gate; release approval not granted
Last verified: 2026-09-02
Latest audited recommendation: HOLD

This checklist separates local automation from simulator, signed-device, external-service, privacy, and owner-observed acceptance. A green build does not close the stronger gates.

## Evidence sources

- Current SSOT: `docs/SSOT/README.md`
- Latest full audit: `docs/audit/2026-08-31/`
- Latest data-integrity audit: `docs/audit/2026-09-01/`
- CRUD matrix: `docs/audit/2026-09-01/crud-matrix.md`
- Active tracker: `docs/PLANNING.md`
- Per-release procedure: `docs/RELEASE_CHECKLIST.md`

## Automated local gates

Run these against the exact release candidate and retain the command output:

```bash
swift test
bash tools/doc_lint.sh
bash tools/ssot_check.sh
bash tools/check_architecture_boundaries.sh
bash tools/check_dose_state_writes.sh
bash tools/check_legacy_safety_paths.sh
bash tools/check_companion_targets.sh
bash tools/release_preflight.sh
```

Also run the iOS and Studio suites described in `docs/TESTING_GUIDE.md`. Do not copy a historical test total into this file.

## Runtime and simulator gates

- [ ] Dose 1, in-window Dose 2, skip, snooze, undo, and morning reconciliation persist after forced termination and relaunch.
- [ ] A failed SQLite open, statement, or commit never produces success feedback.
- [ ] Missing Dose 2 remains visibly different from skipped, late, and recorded-on-time Dose 2.
- [ ] Dashboard, History, Night Review, and exported data agree for the same fixture nights.
- [ ] Clear All Data handles or truthfully discloses every store in the CRUD matrix.
- [ ] Export and restore compare canonical content, not only row counts.

## Signed-device and owner-observed gates

- [ ] A real Dose 2 registration survives restart and appears in a privacy-filtered diagnostic export.
- [ ] Apple Health grant, denial, Settings change, no-data, and real-data cases are checked on a signed build.
- [ ] Dashboard, History, Night Review, and Apple Health are compared for the same owner-selected night.
- [ ] A real timezone change preserves old-night interpretation and uses the new zone for later records.
- [ ] Notification scheduling, denial recovery, background delivery, and alarm reconciliation are observed on a supported device.
- [ ] Accessibility checks cover VoiceOver, Dynamic Type, contrast, and reduced motion on the release build.

## External and governance gates

- [ ] Plane contains no unresolved P0 release blocker.
- [ ] Required remote CI checks are green for the release commit.
- [ ] Branch protection and required-check names are verified from GitHub at release time.
- [ ] WHOOP live OAuth and data behavior are validated if WHOOP is enabled in the release.
- [ ] CloudKit two-device convergence is validated only for a build that enables the staging sync path.
- [ ] Privacy policy, support page, App Store privacy answers, entitlements, and actual data flows agree for the exact build.
- [ ] Certificate pins are validated from approved release configuration without copying credentials into documentation.

## Current no-go conditions

The latest audit leaves recovery, signed-device dose evidence, Apple Health parity, historical timezone provenance, whole-project clear-all, and lossless restore gates open. The release remains on hold until Plane records evidence for the applicable gates and an owner makes the release decision.
