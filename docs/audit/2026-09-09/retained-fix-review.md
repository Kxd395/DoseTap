# Retained branch review

Status: Partial review with tested recovery; remaining gates are in Plane
Date: 2026-09-09
Plane: DOSETAP-63; new Timeline correctness finding: DOSETAP-64
Baseline: `ae7373a7fe892a02125ada44ee57e0fc2f10e8a5`

## Result

Do not merge either retained branch wholesale. The smaller iOS-fix branch's relevant implementation paths have current replacements. Recover its three sync regression scenarios against today's repository and SQLite implementation. Keep the larger timeline branch until its remaining questionnaire and UI patches have a documented disposition.

No production Swift, medication policy, database schema, alarm, or installed-phone behavior changes in this slice. The existing Xcode project and UI-test scheme edits were not made by this review and are excluded from its commit.

## Five-commit iOS-fix branch

Tip: `269981483ece091effc0944ac1fc3158dc69babb`.

After the source comparison and passing recovered tests, the local branch label was retired. Its exact tip is preserved under local annotated tag `archive/2026-09-09/ios-fix-suite`. This previously local-only history was not uploaded to GitHub. The archive tag is local preservation, not an off-device backup.

| Old commit | Reviewed intent | Disposition against the baseline |
| --- | --- | --- |
| `1af6e7e` | Event input normalization, sync API compatibility, old Timeline compiler decomposition, time-picker helper, outdated UI signatures | The whitelist in `Security/InputValidator.swift` is already lowercase. Current sleep inserts use `normalizeStoredEventType` in `SessionRepositorySync.swift`; repository alias tests exist. The old FullApp Timeline and legacy tab implementation are absent from the current app tree. `SleepPlanDetailView.swift` already owns `TimePickerSheetRow`. Do not restore removed scaffolding. |
| `09f1f2b` | Sync IDs/delete replay, outbound tombstones, shared tab selection | Current `SessionRepositorySync.swift` upserts by explicit ID and suppresses outbound tombstones on inbound delete. `EventStorage+Maintenance.swift` uses transactional SQLite tombstones, not the old UserDefaults queue. Current `ContentView.swift` binds compact and regular navigation to `URLRouter.selectedTab`. Recover the three old regression scenarios, not the old persistence implementation. |
| `31600bd` | Recorded metrics in Full Review | Current `Views/Timeline/TimelineReviewViews.swift` and capture support already include `ReviewKeyMetricsCard`. Content and calculations are not identical; a discovered correctness defect is DOSETAP-64, not grounds for restoring the older card. |
| `c2c7de7` | Two-column Full Review metrics | Current `ReviewKeyMetricsCard` already arranges its main tiles in two columns. No layout code copied and no fresh visual acceptance claimed. |
| `2699814` | Disable parallel Xcode CI tests | Current `.github/workflows/ci.yml` passes `-parallel-testing-enabled NO`; main already contains replacement commit `7804b5d`. No CI patch needed. |

Recovered tests use fixed occurrence times and isolated in-memory storage. They verify explicit-ID replacement without duplicates, idempotent inbound dose deletion that preserves another record, and inbound morning deletion that clears its normalized submission. None may create an outbound deletion tombstone.

The initial adaptation failed four assertions: the suite's shared store retained tombstones after its legacy clear helper, and the morning fixture had no matching session identity. The fixtures were corrected to isolated SQLite stores and a real repository-created session. Production behavior was not altered to make the tests pass.

## Four-commit timeline branch

Tip: `5795bc8d8419720d31b8b46ff3192194ecc30e0f`.

| Old commit | Scope | Disposition / remaining review |
| --- | --- | --- |
| `16e9d36` | Comprehensive export plus questionnaire/UI/audit work | Current export uses the maintained `SettingsStudioExport.swift`, storage exports and versioned collected-night projection. Do not substitute the old V2 exporter or import generated output. Remaining questionnaire/UI deltas need per-feature comparison. |
| `a2be58d` | Audit artifacts and privacy manifest | A current `PrivacyInfo.xcprivacy` exists. Old generated artifacts and private-looking sample exports are not salvage candidates. No claim of fresh privacy acceptance. |
| `ae4e7f1` | SQLite-only consolidation and event normalization | Current storage is SQLite with repository mutation ownership; obsolete Core Data adapters are not the current persistence path. Current normalization is already used by repository sleep-event writes. Remaining UI changes are not yet exhaustively reviewed. |
| `5795bc8` | Deterministic legacy date-ID migration | Current `EventStorage+Schema.swift` owns this migration, uses a database-scoped migration ledger and updates dependent rows. Do not transplant the old public `DoseCore` hash helper or change existing identities. A dedicated migration comparison is still required before retiring this branch. |

This branch changes hundreds of paths including generated build outputs. This report is a bounded source review, not a claim that every changed line or historical export has been audited. Keep the branch reachable.

## Local Xcode edits

- Parsing HEAD and working `project.pbxproj` with `plutil` and comparing JSON objects returned equality. The observed diff only reorders entries; no build object, target membership, or setting differs semantically.
- `DoseTapUITests.xcscheme` moves `MacroExpansion` before `Testables` and removes explicit `parallelizable="NO"`. Absence is not proof that parallel testing is enabled. Preserve it outside this commit; retain explicit serial execution in validation commands. A deliberate scheme-policy change needs its own review and UI-test evidence.
- These findings do not authorize discarding either pre-existing edit or the original dirty checkout.

## New finding before structural refactoring

`ReviewKeyMetricsCard` currently computes estimated awake minutes as bathroom count multiplied by five and classifies timing from already-rounded interval minutes. It also marks a Dose-1-only record Off-Window. These are source-reviewed inconsistencies with the observation and absolute-time contracts. DOSETAP-64 records exact boundary, missingness, source/coverage and Review/capture acceptance cases. This slice does not fix or visually reproduce them.

## Organization assessment

See [the staged organization and coding-standards plan](../../architecture/14-organization-and-coding-standards-plan.md). Existing architecture and documentation guards pass, but that does not prove all prose or metric behavior is correct. This review removed a stale duplicated table-count/schema-version claim from the SSOT overview; the field-level schema documents remain authoritative alongside executable schema.

## Validation

Checkout includes the two pre-existing Xcode edits, plus this slice's tests and documentation.

- `swift build -q`: passed.
- Plane workflow, documentation lint, SSOT, architecture boundaries, dose-write, legacy-safety, repository-hygiene and `git diff --check`: passed. Informational dangling Git objects were not deleted.
- `swift test -q`: 655 XCTest tests and 43 Swift Testing tests passed.
- `DT_SIMULATOR_NAME='iPhone 17 Pro' tools/dt-test targeted -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO`: final run passed 100 tests, zero failures, on iOS 26.5; includes the three recovered scenarios. Xcode built the app and test targets as part of this run.
- Local evidence: `/tmp/dosetap63.zphybF/`; successful result bundle: `repository-tests-isolated.xcresult`. Temporary artifacts are not durable backups.
- Fresh physical-device, UI-layout, hosted CloudKit round-trip, and release acceptance were not performed. CloudKit is still a staging-only capability.

## Remaining DOSETAP-63 gates

1. Finish the larger timeline branch's questionnaire/UI and migration comparison before archiving it.
2. Resolve the pre-existing UI-test scheme policy separately, with exact UI-test evidence if changed.
3. Preserve existing worktrees and ignored/uncommitted contents; folder retirement requires its own inventory and preservation plan.

No clean-checkout or signed-phone acceptance is inferred from this run.
