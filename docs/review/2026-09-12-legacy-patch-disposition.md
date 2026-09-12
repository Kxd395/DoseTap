# Retained legacy patch disposition

Status: Source-review decision; Plane owns completion and acceptance
Date: 2026-09-12
Tracking: DOSETAP-63
Reviewed shipping baseline: `00f5675f04d4e2a396279050c76226737c3ae73a`, 0.4.19 (53).

## Decision and preservation boundary

The reviewed legacy patches do not justify a source transplant into this baseline. Keep their histories reachable as reference; keep the shipping project and UI-test scheme policy unchanged. Do not merge or copy the original dirty checkout, generated builds, old exports, unrelated tooling or private drafts. This completes a patch-disposition decision, not a claim that every historical proposal shipped or every data path is accepted.

The original `/Volumes/Developer/projects/DoseTap`, shipping `/Volumes/Developer/projects/DoseTap-main`, retained integration worktree and ignored content remain preserved. No branch, tag, worktree or private file is deleted, renamed or published by this review. Checkout retirement is not proposed; it would require its own inventory and preservation plan.

This record supplements the [September 9 retained-fix review](../audit/2026-09-09/retained-fix-review.md), retaining its dated test evidence and superseding only its pending questionnaire/UI/migration comparison and undecided scheme-policy wording. Current migration and presentation concerns discovered below stay with the existing implementation owners.

## Exact retained histories

The prior iOS-fix history is preserved by local annotated tag `archive/2026-09-09/ios-fix-suite`, whose dereferenced commit is `269981483ece091effc0944ac1fc3158dc69babb`. The tag is local preservation, not an off-device backup. Its five commits remain classified by the earlier review:

| Exact commit | Disposition |
| --- | --- |
| `1af6e7ef290a71205f8e837f4a4206d08d4a582b` | Current event normalization and extracted views supersede old compiler/UI scaffolding. |
| `09f1f2bca40f407d7cc328a4875df0ba74ce5545` | Current ID-based sync and transactional tombstones supersede old implementation; three useful regression scenarios were recovered. |
| `31600bde10516c4111f847a327f8e59ffa520b0d` | Current Full Review metrics supersede the older card; correctness is separately owned by DOSETAP-64/57. |
| `c2c7de76310f57988d9a2883b06dee7590c5fcfb` | Current review card already has two-column metrics; no old layout copied. |
| `269981483ece091effc0944ac1fc3158dc69babb` | Explicit serial Xcode CI testing is already present. |

The recovery merged through PR #12 at `1927dbd76605a456955acb469464802f637e27fa`. Current `SessionRepositoryTests.swift` still contains the explicit-ID replacement, idempotent inbound dose deletion and inbound morning/submission deletion scenarios. Their previous passing run is historical evidence, not rerun here.

Both local `003-timeline-refinements` and `origin/003-timeline-refinements` resolve to `5795bc8d8419720d31b8b46ff3192194ecc30e0f`. Four commits absent from shipping ancestry were inspected individually; ancestry alone did not determine their disposition.

| Exact commit | Disposition against build 53 |
| --- | --- |
| `16e9d3644c4d80348edd22f0cca95582c703ffed` | Export, questionnaire and UI intents have maintained replacements or incompatible design alternatives, detailed below. No production hunk selected for extraction. Generated outputs stay unimported; the unrelated photo/video `tools/sidecar-ledger` remains reference history outside DoseTap's shipping scope. |
| `a2be58d5afe9e35c2fb781f8ec45437a11a7613d` | Dated audit artifacts are historical evidence, not current contracts. Current privacy manifest supersedes the old manifest: it includes empty tracking domains and uses `NSPrivacyAccessedAPITypeReasons`, where the old file used `NSPrivacyAccessedAPIReasons`. Do not restore it or infer fresh privacy acceptance. |
| `ae4e7f1f47d294831f10dc2e53190159a121f0b8` | Repository/SQLite ownership and canonical event handling supersede the old persistence adapters. Its duplicate-medication purge and date-only loader must not replace current identity-aware paths. One live-list consistency question remains a current-code follow-up, not a transplant candidate. |
| `5795bc8d8419720d31b8b46ff3192194ecc30e0f` | Current private storage migration, SQLite ledger and failure handling supersede the old process-wide migration flags and unchecked statements. The old public UUID algorithm would generate different identities and must not be restored. |

## Questionnaire, export and UI comparison

| Retained intent | Current evidence and decision |
| --- | --- |
| Comprehensive V2 export and richer date discovery | `SettingsStudioExport.swift`, `Storage/EventStorage+Exports.swift` and `SessionRepositoryQueries.swift` own current reports and checked reads. Builds 52/53 preserve inventory/medication and event provenance. The old mixed-section CSV and capped reads are not replacements; DOSETAP-13/39 retain wider export/backup acceptance. |
| Pre-sleep single-page V2 and Use Last | Current `Views/PreSleepLogView.swift` has reviewed page navigation, save errors and room-only fill without overwriting answers. The old V2 overwrote room choices and copied nightly screen answers; its summary action expanded a section without actually scrolling. Do not replace the current form with it. A different page layout is a design alternative, not an unmerged correctness fix. |
| Independent pain detail and wake pain delta | Current `StorageModels.PainEntry`, pre-sleep pain editor and `MorningCheckInClinicalSections.swift` retain independent area, side, intensity, sensations, pattern and notes. The old model shared one overall intensity across locations, wrote separate pain snapshots outside the questionnaire transaction, converted coarse categories into numeric levels and adjusted wake intensity from a delta. Those semantics are not valid replacements. Radiation/primary-area and delta UI are retained design input, not claimed implemented; DOSETAP-61 owns broader symptom-model decisions. |
| Morning V2 End Night, skip and optional disruptions | Current `MorningCheckInViewModel.submit` waits for `saveMorningCheckIn`, retains failed answers and avoids reapplying committed reconciliation. The old form directly wrote `wake_survey` and pain events, separately closed the session, defaulted unanswered pain/awakening values to zero/none and contained an unimplemented Use Last action. Do not restore its save/skip workflow. Durable partial drafts remain DOSETAP-67; awakening definitions remain DOSETAP-57. |
| Event aliases and dose feedback | Current `EventType.swift` and repository writes normalize aliases; Brief Wake is `wake_temp`, not the old patch's `brief_wake`. Current coordinator medication feedback uses `persist: false`, and quick logging rejects medication vocabulary. Saved button IDs are preference identity and must not be rewritten from labels just to normalize occurrence types. |
| Timeline, History dates, theme and merged dose view | Current `DetailsView`, extracted History/Timeline views, `ContentView` theme owner and `MergedNightTimelineCard` supply the maintained UI. The merged Review card derives doses separately from sleep logs. Its legacy chart uses an explicit selected night; reviewed dose/sleep evidence is a separate path. Old calendar-date labels and layout alternatives do not justify restoring the removed FullApp Timeline or silently changing treatment-night semantics. |
| Active Core Data removal and settings scaffolding | Both current app targets use Sources phase `J01`. Retained `DevelopmentHelper`, `TimeZoneMonitor`, `LegacyPersistentStore`, `LegacyCSVExporter`, `LegacyJSONMigrator` and `SupportBundleExport` files have references but no Sources membership. They are excluded retained files, not deleted code. Current setup UI handles the explicit staging CloudKit capability; obsolete settings/inventory/action-notification copies are not restored. |

The current pain and sleeping-context source-to-normalized/export regressions are in `SessionRepositoryTests.swift` and `SleepingSetupIntegrationTests.swift`; current event export identity checks are in `ExportTests.swift`. Reviewing those tests establishes their encoded cases and ownership, not a new execution result or complete historical-format migration guarantee.

## Migration comparison and current follow-ups

`EventStorage+Schema.swift` runs the canonicalization, UUID and deduplication steps through `runSchemaMigration`. Mutation and database-scoped ledger changes commit together; failures roll back. The old implementation used UserDefaults flags and ignored individual SQLite failures. Current duplicate cleanup preserves an unmatched medication-like sleep row; the old blanket purge did not.

The current private deterministic UUID helper sets version/variant bits and emits lowercase; the old global `deterministicSessionUUID(for:)` in `ios/Core/SessionKey.swift` copied hash bytes directly and emitted uppercase. They can produce different identities for the same date. No existing ID is rewritten and no old helper is recovered.

Existing `MedicationMutationTransactionTests.swift` cases `testRestoredDatabaseRunsMigrationsDespitePreferencesFromAnotherDatabase` and `testFailedMigrationDoesNotAdvanceLedgerAndRetriesAfterReopen` exercise database-scoped execution, alias/UUID results, matched versus unmatched dose rows and rollback/retry. The old commit added three helper assertions, not comprehensive migration acceptance.

Two source-reviewed questions remain outside this patch-recovery decision:

- **DOSETAP-39 primary owner; related DOSETAP-42:** UUID migration covers eight tables, but its fetch/update list omits newer `checkin_submissions`, `symptom_command_log` and `symptom_summaries` session IDs. The existing migration fixtures do not seed all those dependencies. Reproduce a restored legacy database with linked rows before deciding a repair. This is an identified coverage/ownership gap, not a reproduced owner-data failure. The old patch covers fewer tables and supplies no fix. Current timestamp-based deduplication also remains subject to wider record-preservation acceptance.
- **DOSETAP-39 primary owner; related DOSETAP-45:** the live generic event list reloads sleep rows only (`EventLogger.loadEventsFromStorage`), while immediate medication feedback can add an in-memory row. Dose summaries and Review derive dose rows independently. Verify intended live-list/count behavior across refresh/restart using stable session identities. The old date-only dose/sleep merge is not safe to copy; this review does not claim a reproduced screen failure or medication loss.

These are implementation follow-ups for primary owner DOSETAP-39, with DOSETAP-42/45 as related scopes. Closing DOSETAP-63 must not close them or turn missing evidence into an accepted result.

## Local Xcode disposition

Read-only `plutil` object comparison of shipping HEAD and protected working `project.pbxproj` returned exact equality across **383 objects**. Only serialization order differs; no target membership, build value or object changed semantically. Keep the protected local bytes intact and exclude the reordering from integration.

The protected UI-test scheme moves `MacroExpansion` before `Testables` and removes `parallelizable="NO"`. XML comparison after ignoring element order and that one attribute returned equality. Missing the attribute does not prove parallel testing is enabled.

**Policy: retain the committed explicit serial UI-test setting and use `-parallel-testing-enabled NO` for validation.** Current `.github/workflows/ci.yml` already passes that flag. Do not promote the local attribute removal or reorder as housekeeping. Because this review changes no scheme, project or test execution behavior, it does not require a new UI journey to validate a scheme modification. Future deliberate policy changes need their own exact UI-test evidence.

Protected shipping-file readback at this baseline:

| File | Working SHA-256 |
| --- | --- |
| `ios/DoseTap.xcodeproj/project.pbxproj` | `83eb6c7db19edb0c7a73fd15a71302088d07d0a0e7e07a43a918f21fca15dcec` |
| `ios/DoseTap.xcodeproj/xcshareddata/xcschemes/DoseTapUITests.xcscheme` | `564bf513c30866021d36503c0c51011969fa6223c0630dd0c9894ad454fe5e7a` |

The untracked icon folder remains outside this review. No private draft or historical export contents are copied into this record.

## Validation and closure criteria

Fresh evidence here is exact Plane preflight, Git/ref/source comparison, parsed project/XML comparison and documentation validation. No app build, simulator test, physical install, provider query, owner-data inspection or privacy review was run for this documentation decision. App identity remains 0.4.19 (53).

`bash tools/doc_lint.sh`, `bash tools/ssot_check.sh`, `bash tools/check_plane_workflow.sh` (15 tests, 80 assertions) and `git diff --check` passed for this documentation change.

DOSETAP-63's review can close after independent review accepts these per-patch dispositions, documentation guards pass, the two current-code questions are recorded with primary owner DOSETAP-39, and structured closeout plus exact Plane readback succeeds. The issue need not remain open merely to preserve reachable history or unchanged local files. Device, migration/restore, UI, privacy and release acceptance remain with their owning items; repository deletion and wholesale integration remain unauthorized by this record.
