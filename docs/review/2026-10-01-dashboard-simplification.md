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
