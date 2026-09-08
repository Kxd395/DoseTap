# Shared page headers and controls

Status: implementation and bounded simulator verification; signed-device and owner acceptance remain open.

## Scope

DOSETAP-43. The owner prefers the compact native style of Timeline, Dashboard, and Settings and requested the same capture/settings access on all five tabs. Build 0.4.19 (25) gives Tonight, Timeline, History, Dashboard, and Settings the same toolbar contract: appearance at the leading edge, page title in the middle, and current-page capture at the trailing edge. Compact titles replace Tonight's custom DoseTap banner and History's expanded title. Tonight retains the session date below its header.

History retains Add/Correct. Dashboard retains refresh and the build-dependent cloud sync action. Timeline has current-page capture in Live and Review, including empty states; the existing review-summary capture moves into Review content. Appearance remains one shared preference, including the existing automatic Night Mode and manual-override behavior. No medication, alarm, persistence, calculation, or questionnaire behavior is changed.

## Verification record

- The new shared-header regression failed against build 24 because Tonight had no native navigation header (`/tmp/dosetap-shared-controls-before.log`).
- An intermediate run passed the all-tab capture, largest-text header, and compact Tonight/History checks. The appearance test initially selected the new toolbar shortcut instead of the Theme settings row. A specific `settings-theme` identifier removes that ambiguity (`/tmp/dosetap-shared-controls-after.log`).
- The first seven-test run passed six tests, including automatic Night Mode and manual override across restart. The new cross-tab appearance test exposed Timeline returning without its navigation bar. A second run reproduced it after waiting ten seconds, ruling out the original short assertion timing (`/tmp/dosetap-shared-controls-final.log`, `/tmp/dosetap-shared-theme-recheck.log`). Root pages now explicitly request a visible navigation bar. A subsequent isolated attempt suffered a test-runner exit before completing its navigation journey; it is not a pass (`/tmp/dosetap-shared-theme-visible.log`).
- Simulator screenshots for all five native headers, Timeline Review, and the five capture previews were visually inspected. History's editor, Dashboard's refresh action, and the common controls remain distinguishable. The attachment manifest is `/tmp/dosetap-shared-controls-proof/manifest.json`.
- Swift build and tests passed: 655 XCTest tests and 43 Swift Testing checks (`/tmp/dosetap-shared-controls-core.log`).
- The final seven-test run passed with zero failures, including two complete cross-tab Night Mode cycles with headers present, capture in all five tabs and both Timeline modes, Tonight fit, History's metric row, largest-text reachability, and automatic appearance/restart behavior (`/tmp/dosetap-shared-controls-verified.log`). Result bundle: `/tmp/dosetap-header-ui/Logs/Test/Test-DoseTapUITests-2026.09.08_17-43-23--0400.xcresult`.
- The final unsigned DoseTap simulator build passed (`/tmp/dosetap-shared-controls-build-final.log`). The built Info.plist reads 0.4.19 (25). Plane workflow, SSOT integrity, architecture boundary, dose-state write-path, documentation lint, app-version, and whitespace checks passed. Both targets and both app configurations identify as 0.4.19 (25).

## Boundaries and remaining acceptance

This is a shared-header/control update, not a redesign of every content card or a capture-rendering rewrite. Full-page previews show material/blur artifacts around some native controls, particularly Timeline's segmented picker and History's filters; capture-rendering polish remains open. The existing capture engine can fall back to a visible-window image. Preview opening does not prove every long-page export is complete. No image was shared externally or saved to Photos during these tests.

Owner review on the signed phone, smaller phones, iPad, landscape, complete VoiceOver/larger-text acceptance, and prior alarm/security/provider/release gates remain open. A clean full final-revision UI-suite run is separate from the bounded header tests; the earlier History questionnaire scrolling failure remains unexplained. No phone installation is claimed.

The pre-existing project-file ordering edits and UI-test scheme changes remain local and excluded. Only the four app build-number changes are included from the Xcode project file.
