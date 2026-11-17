# Storage integrity and CI follow-up — 2026-09-29

Implementation baseline: upstream `main`, `99914e4e77a0a0655e0c6a41383a5a274c39b91f`.
Branch: `fix/storage-integrity-ci`.
Checkout: `/Volumes/Developer/projects/DoseTap-integrity-hardening`.
Plane scope: bounded DOSETAP-39 reset/initialization work, DOSETAP-20 CI guard/Studio coverage, and DOSETAP-8 representative safety UI coverage. These items retain broader acceptance gates.

## Changes

- Local SQLite reset now checks one transaction. Failed preflight, BEGIN, deletion or COMMIT cannot clear repository state, preferences or reminder intent. A failed rollback disables the handle. Successful reset has separate system-alarm and pending/delivered notification readback; unverified cleanup is reported without undoing a committed deletion.
- Schema initialization checks schema inspection, backfills, named operations, ledger rows and version reads/writes. The entire initialization commits together. Legacy columns precede indexes, failed initialization closes the handle, and future versions are refused without source/schema mutation.
- The inventory guard recognizes the storage-owned dashboard snapshot and checked `inventoryExportRecords()` accessor. Its regression harness rejects five invalid source paths.
- A separate workflow invokes the explicit iPhone UI scheme, exports six synthetic iOS archives, and supplies them to the full Studio suite. The required archive round trips cannot be skipped. Fixture extraction rejects ambiguous/missing archives, unsafe paths, symlinks, duplicate members and excessive expansion.

## Local validation

- `swift build -q` and `swift test -q`: passed; 872 XCTest cases and 43 Swift Testing cases.
- Full iOS `DoseTap` scheme: 581 tests passed on the explicit iPhone 17 Pro / iOS 26.5 simulator, with a finalized result bundle. New schema failure tests cover rejected backfills, normalization, ledger entries, COMMIT/ROLLBACK, legacy columns and future-schema refusal.
- Reset and system-alarm focused run: 31 tests passed. Real trigger rejection and injected failures preserve session/reminder state; retry and reopen checks passed.
- `DoseTapUITests` scheme: four selected safety UI tests passed (Dose 1 no-alarm review, Dose 2 cancel/background/explicit-save, quick log before each dose). This local run preceded the schema commit; hosted CI will repeat the same four cases against the final PR head.
- CI export runner: all six selected exporter tests executed and passed. Archives were also extracted from the full iOS result bundle and tested with Studio.
- Studio: 92 tests executed, 90 passed, two optional native preview tests skipped. Required collected and raw-only iOS archive round trips passed; all six provider/source fixtures were supplied.
- Fixture handoff regression suite: six tests passed. Inventory guard and its five negative regression cases passed. ShellCheck and workflow YAML parsing passed.
- Plane workflow, SSOT, documentation, architecture and whitespace checks passed. Repository pre-commit SwiftPM and app simulator build checks passed.

Evidence is retained under `.build/audits/2026-09-29-integrity/` in the implementation checkout, including `migration-final.xcresult`, `safety-ui.xcresult`, CI exporter results, synthetic archives, Studio logs and guard logs. These are local verification artifacts and are ignored by Git. Hosted check results belong to the PR, rather than this static document.

## Open gates

- Owner/merge acceptance and hosted checks against the final PR head; no merge, tag or deployment is included.
- Signed-phone reset failure/recovery UX, real system-alarm cancellation, background/restart behavior, actual-record export/import and accessibility acceptance.
- Whole-project CRUD and content-equal backup/restore, linked-record legacy UUID migration coverage, staging/external-store cleanup and the earlier DOSETAP-39 owner/provider/privacy gates.
- Broader DOSETAP-8 onboarding, alarm/skip/snooze and signed-device safety acceptance; the four selected UI cases are representative coverage.
- Broader DOSETAP-20 CI consolidation and required-check policy. New job definitions do not automatically change branch protection.
- Historical credential revocation/sealed review remains under DOSETAP-1/DOSETAP-4/DOSETAP-46. This work does not verify revocation, rewrite history or close privacy/provider/release acceptance.

The preserved feature checkout and the dirty local main checkout were not changed or recommitted. Generated `Secrets.swift` uses the existing credential-free template; the ignored Plane credential source remains in the preserved checkout.
