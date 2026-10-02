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
