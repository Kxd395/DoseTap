# WHOOP export request status

Date: 2026-09-12. Status: locally validated delivery; reviewed integration is tracked in [PR #43](https://github.com/Kxd395/DoseTap/pull/43).
Baseline: merged [PR #42](https://github.com/Kxd395/DoseTap/pull/42), `352d874a053a0e5617593b2f967d1914529d69c0`, app **0.4.19 (54)**.
Candidate: **0.4.19 (55)**; Studio export **2.7**, schema **2**. All four DoseTap/DoseTapStaging Debug/Release configurations report this identity.
Tracking: DOSETAP-13 primary; related DOSETAP-56 and DOSETAP-39. Their acceptance remains open.

## Bounded contract

This continues [DC-05](../audit/2026-09-12/collection-store-export-audit.md) after the [Health missingness repair](2026-09-12-health-export-missingness-delivery.md). The [SSOT](../SSOT/README.md) and [data dictionary](../SSOT/contracts/DataDictionary.md) define optional root `whoopEnrichment` request evidence for manual Settings exports.

Independent sleep/recovery statuses distinguish `not_attempted`, `completed` and `failed`. Attempted UTC query bounds, optional returned-record counts and an eligible-night count describe the request. Completed zero records is different from failure; these counts are neither exported-night counts nor measurement denominators. Eligibility retains the existing scored, non-nap filter and precedes per-date selection.

Successful sleep retrieval remains usable if recovery fails. Sleep failure leaves recovery not attempted. Cancellation aborts export; it must not produce a successful partial archive. Disabled integration, disabled preference, disconnected account, no sessions and invalid range retain explicit not-attempted reasons.

Warnings use fixed messages without embedding raw server errors. Studio retains optional metadata, unknown future status strings and original archive bytes. Unknown strings are not success. Older and local/scheduled archives may omit the field; absence means not captured. The existing local-snapshot warning still identifies that provider enrichment was not fetched.

Strict archive validation distinguishes explained missing WHOOP summaries from malformed or contradictory metadata. Positive eligible counts without exported summaries remain a strict failure. Fetch evidence does not establish permission, full coverage or per-night availability.

There is no SQL migration, historical rewrite, medication/alarm action, consent change or sleep-episode/source-selection change. Same-date episode selection remains separate. This reporting archive is not a complete backup.

## Validation and integration

| Evidence | Result |
| --- | --- |
| Request regression | Existing behavior reproduced failures; 14 focused service tests then passed, including partial recovery, counts, overlapping requests and cancellation |
| Production writer | Missing status and swallowed cancellation reproduced; final nine writer tests passed in the full iOS suite. Invalid treatment dates still reject before a valid archive can be produced |
| Core | 710 XCTest plus 43 Swift Testing cases passed |
| iOS integration | 491 tests passed, zero failures/skips; unsigned iPhone 17 Pro simulator build, iOS 26.5 |
| Studio | 80 tests executed with all five retained iOS archive fixtures, two optional native-preview skips, zero failures |
| Strict archive checks | 136 generated cases plus ZIP passed; actual partial-recovery folder and ZIP passed with expected empty-inventory advisory |
| Native Studio | Imported the generated archive, verified source build 55/export 2.7, retained WHOOP sleep, missing recovery and the fixed warning in the existing Export view |
| Source review | Independent service/export, Studio and validator review; cancellation publication gap corrected and reviewed clear |

The model extraction keeps `InsightBundleModels.swift` below its architecture ceiling without changing the DTO. Final CI also caught the exporter ceiling after cancellation hardening; removing redundant method annotations preserves its enclosing `@MainActor` isolation and restores the guard without raising its limit. All seven writer regressions, the signed build and codesign verification passed again after that cleanup. Repository guards cover SSOT, documentation, Plane workflow (15 tests/80 assertions), dose writes, legacy safety, architecture, repository hygiene, tab ownership, companion targets and whitespace. They do not establish whole-project reader consistency.

Local evidence is under `.build/audits/2026-09-12-whoop-export-status/`: `ios-reviewed-full-summary.json`, `ios-reviewed-full.log`, review red/final writer logs, service red/green logs, `studio-all-fixtures.log`, strict folder/ZIP logs, `app-version.log`, and native `native-studio-warning.png`/`.txt`. The final iOS result bundle is `/tmp/dosetap-whoop-full.xcresult`; fixture location is recorded in `/tmp/dosetap-whoop-export-fixture-path.txt`. Temporary evidence may expire; this record and the exact Plane workpads are durable evidence summaries.

PR review also identified two edge cases: recovery warnings must only claim retained WHOOP sleep when an exported session contains it, and a positive eligible count without exported WHOOP summaries must fail strict validation even when consent flags are false or absent. Both have regression coverage, including empty/filtered results and an eligible intervening night outside the exported session population. Sleep selection is unchanged. The fallback explicitly names WHOOP so it does not deny Apple Health sleep in the same archive. All nine writer tests passed after the final wording qualification.

Signed generic iOS build and deep/strict codesign verification passed. The retained candidate is `/tmp/dosetap-whoop-export-signed-build/Build/Products/Debug-iphoneos/DoseTap.app`; `signed-artifact.json` records identity and executable SHA-256. This run did not install it on a phone.

Implementation commits are `b2da06b` (service/status contract and Studio decoding), `0c5930e` (strict validation) and `4fd27c7b7f54500b2818058d8962f14f60e54d1a` (Settings writer/cancellation and model extraction). [PR #43](https://github.com/Kxd395/DoseTap/pull/43) is the reviewed integration reference; its merge/check history and the DOSETAP-13/56/39 workpads hold exact hosted/main closeout evidence. This local validation record does not substitute for those readbacks.

The shipping checkout's pre-existing project/scheme edits and icon drafts are protected. Only the four reviewed build-number values advance in the project file; those unrelated changes are excluded from this PR.

## Remaining acceptance

- Owner-authorized phone Settings export through Files/share into Studio using actual WHOOP records, including usable sleep with unavailable recovery.
- Live provider permissions, disconnection, empty results, failures and cancellation; provider revision/deletion reconciliation and durable provenance.
- Same-date session/episode ambiguity, reviewed-window adoption, source parity and broader snapshot/reader consistency. Apple Health query-error detail remains separate.
- Scheduled/background export acceptance, complete backup/restore coverage, VoiceOver/accessibility, privacy/security and release acceptance.

The next acceptance step after validation is a real-record provider/export comparison. Synthetic tests or merged code do not close these gates or DOSETAP-13/56/39.
