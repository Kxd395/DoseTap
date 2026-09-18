# Settings export failure diagnosis

Date: 2026-09-17
Tracking: DOSETAP-13 (export), existing DC-07 session-identity gap
Current repair candidate: 0.4.19 (60); build 59 is the prior diagnostic candidate. Build 58 remains a separate pain-entry draft.

## Owner report and read-only evidence

The owner supplied a Settings export alert showing `DoseTap.MedicationStorageInjectedFailure error 1` followed by universal free-storage advice, and reported 275 GB used of 512 GB. The screenshot also shows an empty row above Clear All Data.

Owner-authorized USB inspection confirmed installed DoseTap 0.4.19 (57). Only the DoseTap SQLite database and its WAL/SHM companions were copied into a private temporary directory. Queries used SQLite read-only/query-only mode. No app restart, install, record correction, delete or phone write was performed. This is a copied database snapshot, not a guarantee about subsequent phone writes. The local copy passed SQLite integrity_check and uses schema 5. Structural inspection found treatment dates with multiple stable session identities. No personal record payloads, session identifiers or affected dates are reproduced here or in Plane.

The misleading error type is used for real database/read/precondition failures as well as synthetic injection. Its name is not evidence that test injection is enabled. `collectedNightSummary` invokes `nightOutcomeSnapshot`, which invokes the strict editing `historySnapshot`. That rejects a treatment date containing multiple stable identities. The full bundle writer invokes this path for each date. Raw event export can retain those original identities, but the derived summary currently prevents the full archive from being published. This connects a concrete condition in the local copy to a source failure path; no successful owner export is claimed.

## Build 59: diagnostic correction

- Display the failing export step and preserve known storage failure detail/code. Night-summary failures include the treatment date in the on-device alert.
- Show free-space guidance only for a reported database/file-system disk-full error. Identity conflicts receive record-review guidance; unknown failures do not invent a cause or expose arbitrary error payloads.
- Keep raw exception logging private. Keep retry and failed-export cleanup; do not publish a partial archive or change records.
- Remove the standalone Divider inside the Settings Form section, which creates the empty row visible in the screenshot.

This change makes the failure actionable; it does not resolve conflicting session identities or make this owner's export succeed. Do not clear records or relink sessions merely to satisfy the summary reader. No schema or export format changes. The unchanged WHOOP request-metadata helper moved to SettingsHelpers to keep the exporter within its existing architecture size limit.

## Build 59 validation and subsequent repair

Synthetic regression creates two session identities on one treatment date, checks the contextual error, confirms source event IDs remain present, and confirms no ZIP is published. Message tests distinguish actual disk-full failures, read failures and unknown errors. Measured results and exact PR/integration state are recorded in the DOSETAP-13 workpad; compilation alone is not test execution.

The next export repair must separate source-record export from edit eligibility: preserve every original session and questionnaire identity, explicitly identify ambiguous derived summaries, and prove archive/Studio fidelity for same-date multiple sessions before changing behavior. This is the existing DC-07 scope, not permission to silently choose a session, discard records, or infer outcomes. Owner export retry on a validated installed build, native alert/layout interaction, accessibility, privacy and release acceptance remain open.

Fresh targeted validation: 20 export tests passed, zero failures/skips, in `/tmp/dosetap-export-alert-tests.xcresult`. This includes the two-identity archive reproduction and message guidance regression. Core validation passed 710 XCTest plus 43 Swift Testing cases. Plane guard passed 15 tests/80 assertions; SSOT/documentation guards and all four build59 configurations passed. Independent source review found no blocking issue.

## Owner-requested phone installation

The owner explicitly requested build59 installation after reviewing the diagnosis. Signed device build and deep/strict signature verification passed for app source `3d561d0b02c0f802a50e09e158e9d6bb726a9df3`. Installation over the existing app succeeded, and an independent device-app query confirmed `com.dosetap.ios` version0.4.19/build59. Database and WAL files remain present. No uninstall, data clearing or clinical-record correction was performed; file presence is not content-equal restore proof.

PR49 remains a draft and main remains build57. The branch project is `DoseTap-export-alert/ios/DoseTap.xcodeproj`; the main project still showing57 is expected. Owner export retry, native alert/layout acceptance, session-conflict repair, accessibility/privacy and release acceptance remain open. Installation metadata does not close those gates.


## Build 60: preserve conflicting records without selecting a session

The owner retried build 59 and confirmed the contextual identity-precondition failure.
The export path now performs checked source reads independently of the editing guard.
Every original dose/sleep event remains in the source CSV and JSON. Original session
metadata, pre-sleep rows, morning rows and normalized submissions are additionally
retained as typed SQLite columns, including unknown JSON keys and exact timestamp text.
Null, empty text, numeric zero and binary values remain distinct.

A date with multiple stable identities, an identity spanning dates, or competing
source questionnaires is marked `raw_only`. Its combined dose times, selected
questionnaires, alarm/context summary and collected-night metrics are unavailable.
It contributes no row to the derived sessions/collected-night CSVs and no analytic
session in matching Studio. Valid dates continue normally. Real SQLite/read failures
still prevent archive publication; no record is repaired, deleted or relinked.

Export 2.8 uses schema 3 with `dateGroups` at the root. Older Studio requires the old
`sessions` key, so an intact new archive fails decoding before analytics are published.
A numeric schema bump alone would not stop the old importer from pairing events across
identities. Updated Studio reads schema 3 plus legacy schema 1/2, rejects contradictory
root layouts, and retains original imported bundle bytes. Use matching Studio for these
archives; standalone source CSVs do not carry the identity-safety contract.

Validation evidence so far:

- Core: 710 XCTest and 43 Swift Testing cases passed.
- Expanded iOS run: 188 synthetic/repository/export tests plus one private local-copy
  replay passed, with no failures or skips. This includes production ZIP creation,
  source-row equality before/after, unchanged edit rejection, a clean control night,
  future questionnaire payload retention and a pre-sleep link crossing dates.
- The owner-authorized database copy successfully produced a complete local ZIP.
  Checked source arrays and events were unchanged. The original phone database was
  not opened for writing. Private inputs, output and temporary replay code remain
  outside committed evidence; this replay is not an owner phone export or restore test.
- All four DoseTap/DoseTapStaging Debug/Release configurations report 0.4.19 (60).
- Matching Studio: 86 tests executed, 3 skipped, no failures, including the actual
  synthetic iOS ZIP round trip and rejection by the legacy required-layout decoder.
- Strict archive checks passed for both the synthetic ZIP and private-copy output;
  159 auditor fixtures plus ZIP input passed. A discovered validator false positive
  now correctly requires the physical-symptom payload for bathroom urgency without
  inventing a required timing-context payload. Existing informational gaps remain.
- Signed build/signature, Plane workflow, architecture, medication-write boundary,
  documentation/SSOT and whitespace checks passed. Source review found the old
  consumer hazard; the schema-3 boundary resolved that finding.

The structured DOSETAP-13 workpad records final Studio/archive validation, signed
installation, commit/PR state and readback. Owner export through the actual share sheet,
provider-enriched phone parity, accessibility, privacy/release acceptance and tested
backup/restore remain separate gates. Identity reconciliation remains review work;
a successful archive does not prove the underlying conflicting nights are resolved.
