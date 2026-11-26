# Dashboard simplification — October 1, 2026

Tracker: DOSETAP-45. Candidate: 0.4.19 (91). Owner acceptance remains open.

## Decision

The owner authorized a simpler dashboard after build90 remained unsatisfactory.
Keep current records, source/correctness protections and the build90 performance
changes. Replace the crowded landing presentation; do not reset to build88 or
rewrite Git history. Build88/main fac445c is the design comparison baseline;
its 84-commit difference from phone89 includes much more than visual changes.

## Presentation

Overview now contains two whole-period counts, a dose-spacing dot chart, and
three direct actions: Review records, Explore patterns, Prepare a visit.
The chart shows up to14 most recent valid pairs from the selected period, with
its count/subset disclosed. It uses the existing exact-interval projection;
missing pairs are omitted and no line joins gaps. Dots do not imply treatment
effectiveness or a recommended interval. Original source identity and detailed
inspection remain in Session Replay.

Detailed summary metrics, WHOOP, sleep, trends and comparisons remain available
through the existing routes. Analysis filters no longer appear on Overview or
Trends where they do not apply. Records starts with recent nights before source
coverage/inventory. Provider errors scroll with Overview; source/range details
expand on demand. Accessibility text grows normally, with a compact first metric
in landscape. No stored data, medication behavior, provider query, or dosing
calculation changes are included.

## Validation and delivery

Evidence: `.build/dashboard-simplification-evidence/`.
Initial normal and maximum-text overview tests passed with inspected screenshots.
Core:1191 XCTest plus43 Swift Testing passed. Combined navigation/appearance,
repository guards, generic simulator build and signed device delivery are tracked
in that evidence directory; final results follow below.

Plane initially refused connections because Docker Desktop was stopped. Starting
the existing runtime brought its existing Plane containers back automatically;
the proxy remains bound to127.0.0.1:3301. No image pull, volume reset, stack
reconfiguration or data deletion was performed. ExactDOSETAP-45 preflight then
succeeded: InProgress/high. Tracker acceptance remains separate from installation.

## Scroll regression discovered during validation

The new navigation test reproduced an app hang after returning from Records and scrolling to Explore. DoseTap consumed about99% CPU; a three-second sample showed the main thread repeatedly in SwiftUI lazy-stack layout. The owned simulator test was interrupted and its app terminated, without reset/uninstall. Overview contains a bounded set of cards, so its LazyVStack was replaced with VStack. The same test must pass before phone delivery; the sample and interrupted artifact are retained.

The corrected combined UI run passed all four selected journeys, including the
previously hanging return/scroll path, range retention across Records/Replay,
empty history, normal/max text portrait/landscape and night-mode chart interaction.
Artifact: `home-scroll-fixed.xcresult`. The empty state keeps Records reachable
and does not draw a zero-valued chart. Required guards and core tests passed.

Screenshot review also caught a stale dark header after switching to Light. The dashboard now explicitly sets its control background, navigation background and toolbar color scheme from the current appearance. Theme-switch verification follows this correction.

Theme verification passed both selected journeys (`theme-final-ui.xcresult`).
The final Light screenshot was inspected: the header and content now use the same
appearance. The normal overview fits its summary, full chart and Records action;
maximum-text landscape fits the first complete metric and allows scrolling.
Application commits: `f7ebe9c`, `6e20741`, `f530113`. Normal enabled hooks passed
SwiftPM and generic simulator arm64/x86_64 builds for each commit. The core suite
and workflow/SSOT/version91/architecture/dose-write/legacy/companion/hygiene/doc
checks passed. The failed scroll artifact remains diagnostic evidence, not a pass.

## Signed phone delivery

Installed0.4.19(91), bundle `com.dosetap.ios`, without uninstall/reset on the paired
iPhone15 Pro Max. Independent inventory confirmed91, launch succeeded, and an
independent process inventory confirmedPID57699. Signed application source:
`f530113f1bee879bf721f6f02ed795e36cf85b69`. ExecutableSHA256:
`99d0b0199b13918bad4dd1cace3080e0c56c5a16f9f5e1da2e282c368acf2db1`.
Strict/deep signature verification passed. The original ignored local configuration
was used for signing and the recovery template restored afterward.

Receipts: `phone91-artifact.json`, `phone91-install.log`,
`phone91-installed-apps.json`, `phone91-launch.json`, `phone91-processes.json`.
Physical installation/launch does not establish actual-record consistency, perceived
speed, VoiceOver, live providers, privacy or owner acceptance. No PR/push/merge or
iPad launch was performed. Main and the paused dashboard/iPad checkout remain
unchanged. Next: owner phone review, then focused integration against the pending
feature head with affected checks; investigate any remaining specific slow action
using a device trace rather than expanding the dashboard again.
