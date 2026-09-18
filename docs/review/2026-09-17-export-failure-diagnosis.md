# Settings export failure diagnosis

Date: 2026-09-17
Tracking: DOSETAP-13 (export), existing DC-07 session-identity gap
Installed candidate: 0.4.19 (59), based on main build 57; build 58 is a separate draft

## Owner report and read-only evidence

The owner supplied a Settings export alert showing `DoseTap.MedicationStorageInjectedFailure error 1` followed by universal free-storage advice, and reported 275 GB used of 512 GB. The screenshot also shows an empty row above Clear All Data.

Owner-authorized USB inspection confirmed installed DoseTap 0.4.19 (57). Only the DoseTap SQLite database and its WAL/SHM companions were copied into a private temporary directory. Queries used SQLite read-only/query-only mode. No app restart, install, record correction, delete or phone write was performed. This is a copied database snapshot, not a guarantee about subsequent phone writes. The local copy passed SQLite integrity_check and uses schema 5. Structural inspection found treatment dates with multiple stable session identities. No personal record payloads, session identifiers or affected dates are reproduced here or in Plane.

The misleading error type is used for real database/read/precondition failures as well as synthetic injection. Its name is not evidence that test injection is enabled. `collectedNightSummary` invokes `nightOutcomeSnapshot`, which invokes the strict editing `historySnapshot`. That rejects a treatment date containing multiple stable identities. The full bundle writer invokes this path for each date. Raw event export can retain those original identities, but the derived summary currently prevents the full archive from being published. This connects a concrete condition in the local copy to a source failure path; no successful owner export is claimed.

## Bounded correction

- Display the failing export step and preserve known storage failure detail/code. Night-summary failures include the treatment date in the on-device alert.
- Show free-space guidance only for a reported database/file-system disk-full error. Identity conflicts receive record-review guidance; unknown failures do not invent a cause or expose arbitrary error payloads.
- Keep raw exception logging private. Keep retry and failed-export cleanup; do not publish a partial archive or change records.
- Remove the standalone Divider inside the Settings Form section, which creates the empty row visible in the screenshot.

This change makes the failure actionable; it does not resolve conflicting session identities or make this owner's export succeed. Do not clear records or relink sessions merely to satisfy the summary reader. No schema or export format changes. The unchanged WHOOP request-metadata helper moved to SettingsHelpers to keep the exporter within its existing architecture size limit.

## Validation and next repair

Synthetic regression creates two session identities on one treatment date, checks the contextual error, confirms source event IDs remain present, and confirms no ZIP is published. Message tests distinguish actual disk-full failures, read failures and unknown errors. Measured results and exact PR/integration state are recorded in the DOSETAP-13 workpad; compilation alone is not test execution.

The next export repair must separate source-record export from edit eligibility: preserve every original session and questionnaire identity, explicitly identify ambiguous derived summaries, and prove archive/Studio fidelity for same-date multiple sessions before changing behavior. This is the existing DC-07 scope, not permission to silently choose a session, discard records, or infer outcomes. Owner export retry on a validated installed build, native alert/layout interaction, accessibility, privacy and release acceptance remain open.

Fresh targeted validation: 20 export tests passed, zero failures/skips, in `/tmp/dosetap-export-alert-tests.xcresult`. This includes the two-identity archive reproduction and message guidance regression. Core validation passed 710 XCTest plus 43 Swift Testing cases. Plane guard passed 15 tests/80 assertions; SSOT/documentation guards and all four build59 configurations passed. Independent source review found no blocking issue.

## Owner-requested phone installation

The owner explicitly requested build59 installation after reviewing the diagnosis. Signed device build and deep/strict signature verification passed for app source `3d561d0b02c0f802a50e09e158e9d6bb726a9df3`. Installation over the existing app succeeded, and an independent device-app query confirmed `com.dosetap.ios` version0.4.19/build59. Database and WAL files remain present. No uninstall, data clearing or clinical-record correction was performed; file presence is not content-equal restore proof.

PR49 remains a draft and main remains build57. The branch project is `DoseTap-export-alert/ios/DoseTap.xcodeproj`; the main project still showing57 is expected. Owner export retry, native alert/layout acceptance, session-conflict repair, accessibility/privacy and release acceptance remain open. Installation metadata does not close those gates.
