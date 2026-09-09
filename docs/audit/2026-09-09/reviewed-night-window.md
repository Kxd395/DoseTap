# Reviewed night window entry

Date: 2026-09-09
Baseline: `97aff2793a72c41fe72a432e45c7d8c07e592878`, shipping checkout `DoseTap-main`.
Scope: DOSETAP-56 third slice. Candidate 0.4.19 (35). DOSETAP-57 remains Todo.

## Changes

The existing Wake & Next Day diary stores an optional reviewed observation window. Its versioned value includes stable session identity, absolute start/end, explicit user-review source, review time, entry timezone and that zone's offsets at both bounds. The zone describes date entry, not independently observed travel location. A window is neither measured sleep nor final awakening.

The editor requires fresh confirmation for added or changed bounds. Recorded Dose 1/final-wake dates may suggest a draft; absent end information stays unresolved rather than expanding to the current clock. Cancelling writes nothing. Unchanged windows retain their review metadata. Correcting or clearing a saved window needs a reason and retains the previous answer in the existing revision chain.

The existing transaction and stale-snapshot checks apply, including matching session identity. Other diary answers and explicit Dose 2 wake answers preserve the window. A discovered backdated-entry edge case now rejects an incoming wake-answer timestamp that would invalidate already reviewed answers, rolling the pending dose and answer back together. No review timestamp is silently moved forward.

Raw submissions and revisions use the existing export path. The collected-night JSON and CSV now include the window's fields; Studio reads/writes them and includes them in existing reports. Safe Studio reports redact window timestamps and entry-zone/offset metadata. There is no new schema/table, medication history, questionnaire, provider import or computed sleep total.

## Validation

Synthetic fixtures only; no owner sleep data was examined. Commands ran with candidate changes plus the two preserved unrelated Xcode edits.

- Test-first signals: new core/window/export tests failed before their types/fields existed, then passed. Six window tests cover old JSON, missing fields, round trips, invalid/future/non-finite bounds, unsupported provenance/version, corrections/removal and the repeated DST hour.
- `swift build -q`; `TZ=UTC swift test -q`; `TZ=America/New_York swift test -q`: passed, each timezone 670 XCTest plus 43 Swift Testing cases. Logs: `/tmp/dosetap56-window-final-utc.log`, `/tmp/dosetap56-window-final-ny.log`.
- iOS simulator: 120 tests passed across `MedicationMutationTransactionTests`, `DoseActionCoordinatorClockTests`, `HealthKitProviderTests`, `DashboardAnalyticsAuditTests`, `ExportIntegrityTests` and `ExportImportRoundTripTests`. Includes SQLite reopen, failed commit, stale snapshot, wrong-session rejection, retained removal revisions, no medication projection change, raw JSON/CSV export, and preservation during retrospective wake entry. `/tmp/dosetap56-window-final-green.xcresult`.
- The entry-time edge case first failed with a committed invalid diary and subsequently unreadable answers. The guard passes the regression without inventing timestamps. Red result: `/tmp/dosetap56-window-entry-red.xcresult`.
- Studio initially retained a stale build manifest that omitted the new shared source. `swift test --package-path macos/DoseTapStudio --disable-build-manifest-caching` refreshed it without deleting caches/artifacts. The normal `swift test --package-path macos/DoseTapStudio` then passed: 69 executed, 66 passed, three optional fixture/visual skips, zero failures. `/tmp/dosetap56-window-studio-final.log`.
- App-version readback agrees across both configurations of DoseTap and DoseTapStaging: 0.4.19 (35). Core and iOS builds passed; the pre-commit hook also builds generic iOS Simulator with signing disabled.
- UI runtime: `DoseTapUITests/testReviewedNightWindow()` passed on iPhone 17 Pro Max / iOS 26.5. It checks unconfirmed/cancelled entry, explicit save, restart readback, reason-required removal and unchanged recorded Dose 2. Three screenshot attachments were inspected for labels, date/time bounds, confirmation and saved state. `/tmp/dosetap56-window-ui-retry.xcresult`. The initial long selector selected zero tests and is not counted; the shortened test name with explicit `()` selector ran one case.
- Plane workflow (10 tests / 64 assertions), SSOT, docs, architecture, dose-state writes, legacy safety paths, repository hygiene, companion-target and whitespace guards passed. No untracked-file-only whitespace check is substituted for the full commit-range check.

Targeted app command: `xcodebuild test -project ios/DoseTap.xcodeproj -scheme DoseTap -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath /tmp/dosetap56-derived -parallel-testing-enabled NO` with the six suite selectors above and `CODE_SIGNING_ALLOWED=NO`.

## Remaining integration and acceptance

The bounded HealthKit query is still not connected to a screen or export calculation. Existing primary-episode sleep summaries remain unchanged. Saved windows must be rechecked against raw provider provenance/conflicts, overlapping sessions/naps, missing data, provider edits/deletions and corrected dose times before driving treatment-night totals. Window entry does not resolve these conflicts. DOSETAP-57's dose-to-sleep/return markers and completed awakening counts remain unimplemented.

Signed-device import, permission/readiness semantics, entry during travel/DST, accessibility and owner-observed parity remain open. No phone installation is claimed. Historical unexpected Dose 2 investigation and medication/alarm/persistence, backup/restore, privacy and release gates remain independent.

## Preservation and tracking

Only app build-number hunks are included from the Xcode project; unrelated object-order and UI-test scheme edits remain excluded. The preserved feature checkout and historical branches are untouched. Plane DOSETAP-56 stays In Progress with exact workpad write/readback required at closeout. GitHub review/checks and merge state belong to the PR and final Plane workpad; local results alone do not establish them.
