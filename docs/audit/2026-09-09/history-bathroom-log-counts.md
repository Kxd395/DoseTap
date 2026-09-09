# History bathroom-log correction

Status: Implementation and local validation; integration and phone acceptance tracked in DOSETAP-65
Date: 2026-09-09, America/New_York
Baseline: main `d6ee21e`; candidate 0.4.19 (32)

## Scope

The legacy History calculator multiplied each bathroom event by five minutes and averaged only nights with bathroom entries. That value was not measured awake duration. The shared History and recorded-night trend card now shows total bathroom logs, the number of nights with logs, and the number of recorded nights included. Canonical bathroom types contribute; water, noise and other events do not. No history and zero logged entries remain separate. An explanation states that missing entries do not establish absence of awakening.

The range is up to 14 most recent recorded night keys, not necessarily consecutive calendar nights. The header now names recorded nights; the Review title is Recorded-Night Trends. Compact History retains four columns at standard text size. Accessibility sizes use one column, with complete spoken labels and wrapping explanations. Repository changes refresh the read-only summary.

Source events, medication, alarms, Apple Health imports and provider-derived awake-duration exports are unchanged. The reference scan found legitimate `wasoMinutes` variables in SettingsStudioExport and Studio's report builder; those provider-derived fields were deliberately preserved. No migration is required. Other legacy dose/interval calculations are outside this issue.

## Validation

- Tests were written before the summary type. The first run failed because that type did not yet exist.
- `swift build -q` and `swift test -q`: passed, 655 XCTest and 43 Swift Testing cases. Log: `/tmp/dosetap65-core.log`.
- Focused Xcode suite: six tests passed, zero failures, on iPhone 17 Pro Max / iOS 26.5. Command: `xcodebuild test -project ios/DoseTap.xcodeproj -scheme DoseTap -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath /tmp/dosetap65 -parallel-testing-enabled NO -only-testing:DoseTapTests/HistoryBathroomLogTests CODE_SIGNING_ALLOWED=NO`. Bundle: `/tmp/dosetap65-verified.xcresult`.
- Cases cover empty history, zero logs with recorded nights, canonical names, multiple logs, gaps between night keys, repository recalculation after deletion, range limits, retained source rows, and standard/accessibility detailed/compact raster capture. The initial capture fixture assigned published values directly; rendering refreshed them from storage. The corrected test uses an isolated in-memory repository and verifies the actual refresh path.
- All four card renderings were visually inspected. Values and explanations are legible; standard History retains one four-metric row.
- Two simulator UI tests passed with zero failures: `testHistoryBathroomInsightsCountsAndCapture` and `testCompactLayoutTonightFitsAndHistoryUsesOneMetricRow`. Bundle: `/tmp/dosetap65-ui.xcresult`. History's populated and empty states, the four-metric row, and generated Review capture/Copy were inspected. The display-only fixture creates no source rows; it is not evidence about the owner's phone data.
- Plane workflow, SSOT, documentation, architecture, dose-write, legacy-safety, repository-hygiene, app-version and whitespace checks passed. App and staging Debug/Release all report build 32.

## Preservation and open acceptance

Only four build values are included from the Xcode project. With those intended values excluded, the pre-existing project/scheme diff retains SHA256 `66a71c1a98f267d3e31b14e591610ec3d0ab7fcc6fd0a2db00910cf06494749f`. Existing scheme edits are not part of this change.

Hosted checks and merge readback belong in the verified Plane workpad. Signed-phone History, Review/capture and VoiceOver acceptance remain open. Local and hosted automation do not close medication-reliability, provider, privacy or release gates.
