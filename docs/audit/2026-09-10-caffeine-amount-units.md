# Caffeine amount units

Date: 2026-09-10
Status: Implementation and local validation; signed-device acceptance remains open
Tracker: DOSETAP-52; morning missingness follow-up remains DOSETAP-51
Candidate: 0.4.19 (43)

## Changed behavior

The pre-sleep form records beverage volume in US fluid ounces separately from caffeine mass in milligrams. Last intake and daily totals are optional independent fields. Fractions and explicit zero survive saving; blank is not zero. The source selector applies to all entered amounts and starts as user-reported for manual entries. No conversion or medication adjustment is calculated.

Selecting Coffee no longer supplies an intake time or quantity. The old Boolean adapter no longer invents a current time or 95-unit caffeine amount. Existing raw amounts are preserved with unverified units because old UI and adapter paths used different meanings. Merely opening an old record does not convert it. Explicit corrections use the existing history path.

New normalized submissions, History text/CSV and the shared manual/scheduled Studio writer use the versioned record or clearly marked legacy fields. Studio retains old archives without converting their Mg-named values and flags unverified legacy units. New saves reject unsupported versions, non-finite/negative quantities and answered totals below the corresponding last amount, leaving the original saved record intact.

No medication, alarm, Apple Health, pain-pattern or morning-table behavior changed. The questionnaire delivery plan now spells out the coordinated morning nullable-answer migration: SQLite, both record models, normalized answers, History, Dashboard denominators, exports, Studio and UI must move together.

## Validation scope

- Red regression: five assertions failed before the repair, reproducing duplicate-unit normalized output and the fabricated Boolean-adapter amount/time.
- DoseCore: 684 XCTest and 43 Swift Testing cases passed, including fractional/zero/missing values, source round-trip, invalid totals and unsupported versions.
- iOS: 419 app tests passed on iPhone 17 Pro simulator, including storage reopen, rejected edits and the Studio JSON writer.
- Studio: 70 tests discovered, zero failures, two optional visual previews skipped. The actual generated iOS archive was extracted and imported with `DOSETAP_IOS_EXPORT_FIXTURE`; 12.5 US fl oz, explicit 0 mg, label-reported source and raw legacy 95 remained distinct. The old/new amount-reader test also passed.
- Simulator UI: caffeine selection, blank fields, deselection and explicit None passed. Visual review found a truncated placeholder; it was shortened to Unknown and the smoke path rerun.
- Build identity, Plane workflow, documentation/SSOT, architecture, dose-write, legacy-safety, check-in-export and Studio-export guards passed. Generic unsigned simulator build passed.

The archive readback and final UI proof are recorded in the Plane workpad. One incremental UI rerun omitted the new field checks in its trace and is not accepted as proof; a separate temporary build directory was used for the current-code check. Local logs use `/tmp/dosetap-caffeine-*`; they are machine-local evidence, not distributed test fixtures.

## Open acceptance

Signed-phone entry/save/reopen/restart, owner review, VoiceOver and largest Dynamic Type remain open. The simulator smoke check is not full questionnaire navigation coverage. Older Studio versions ignore the additive record; use the matching reader for its amounts. Full backup/restore is not established. Other substance/activity inferred defaults and true unanswered morning observations remain planned work, not completed by this slice.
