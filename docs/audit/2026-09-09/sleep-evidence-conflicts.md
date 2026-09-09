# Bounded sleep evidence and conflicts

Date: 2026-09-09
Plane: DOSETAP-56, In Progress
Baseline: `a3cceb8`, shipping checkout `/Volumes/Developer/projects/DoseTap-main`
Candidate: 0.4.19 (36), `feat/sleep-evidence-conflicts`

## Change

The new bounded sleep query retains original sample bounds, UUID, raw category, source revision, optional device description and provider timezone before normalization. Query receipt time is separate. No device hardware identifiers or arbitrary metadata are copied. Raw evidence stays in the returned snapshot; it is not a persisted source ledger or a new export.

`SleepEvidenceResolution` applies a versioned consensus policy inside explicit half-open bounds. Unspecified-asleep plus one detailed stage can agree. Sleep/awake disagreement, disagreement between detailed stages, or known classification overlapping an unknown category remains unresolved. In-bed records supply context only. Conflict time is part of unmeasured time; it cannot increase sleep or awake totals. Supporting sample IDs accompany each slice.

The coverage-only bounded query delegates to this resolver. Legacy primary-episode charts, final-wake fields, post-Dose-2 estimates, exports, questionnaires, medication records and alarms keep their current behavior. No screen invokes the new bounded query yet.

## Validation

- Test-first signal: core tests failed before the new types existed (`/tmp/dosetap56-evidence-red.log`); app tests failed on missing adapter APIs (`/tmp/dosetap56-evidence-adapter-red.xcresult`).
- `swift build -q`, then `TZ=UTC swift test -q` and `TZ=America/New_York swift test -q`: each passed 677 XCTest and 43 Swift Testing cases. Seven new core cases cover conflict exclusion, duplicate/reordered samples, unknown/in-bed data, zero versus unavailable, gaps/clipping, invalid samples, source round-trip, fresh-snapshot deletion and repeated DST hour.
- Build 36 iPhone 17 Pro Max simulator: 122 tests passed across HealthKitProviderTests, MedicationMutationTransactionTests, DoseActionCoordinatorClockTests, DashboardAnalyticsAuditTests, ExportIntegrityTests and ExportImportRoundTripTests. Result: `/tmp/dosetap56-evidence-build36.xcresult`. Adapter cases verify unclipped sample provenance and unchanged legacy summary behavior.
- Studio: `swift test --package-path macos/DoseTapStudio --disable-build-manifest-caching` passed 66 tests; three optional fixture/visual tests skipped. Manifest caching was disabled to discover the new root-package source without deleting build artifacts.
- Plane workflow (10 tests, 64 assertions), SSOT, documentation, architecture, dose-write, legacy-safety, repository-hygiene and companion-target guards passed. `git diff --check` passed. All four app configurations and built simulator bundle report build 36.
- No UI changed; no new visual or signed-phone proof is claimed. Hosted CI/review and merge evidence belong in the PR and verified Plane workpad after they complete.

## Remaining gates and next implementation

1. Validate a saved window against current dose records, overlapping reviewed sessions and incomplete/overlapping naps before querying it as a treatment night.
2. Define durable provider revision/deletion reconciliation and privacy-aware report provenance. A fresh query recomputes from its returned observations; this does not prove anchored-import or persisted-deletion behavior.
3. Use the rich conflict result, not its coverage-only projection, when integrating Timeline, History, Dashboard and export/Studio. Preserve source disagreements and missing boundary evidence.
4. DOSETAP-57 remains responsible for dose-to-sleep/return markers and completed awakening counts. This prerequisite does not deliver those features.
5. Signed-device HealthKit permissions/import, real-data parity, accessibility, historical unexpected Dose 2 investigation, medication/alarm device acceptance and full backup/restore remain independent gates.

## Source check

The adapter follows Apple's [HKSourceRevision contract](https://developer.apple.com/documentation/healthkit/hksourcerevision) and [timezone metadata definition](https://developer.apple.com/documentation/healthkit/hkmetadatakeytimezone), checked during this run alongside the installed HealthKit headers. Source metadata is provenance, not a device-accuracy score. Provider timezone is the supplied sample metadata, not independently verified travel location.

Only task-owned files and four build-number hunks are intended for commit. The pre-existing Xcode project ordering and UI-test scheme edits remain uncommitted and preserved; the separate original checkout is untouched.
