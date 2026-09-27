# Nearby Apple Health sleep evidence delivery

Date: 2026-09-27. Plane: DOSETAP-76, In Progress.
Installed and independently inventory-verified: iPhone 0.4.19 (81), separate
iPad Dashboard 0.1.0 (9). Both apps launched successfully. Owner acceptance remains open.

The owner asked to continue the dashboard overhaul. All post-merge workflows for
previous main `a5978b4` passed on live readback. This slice delivers the bounded
Apple Health evidence prerequisite, not the complete Dose 2 sleep analysis.

## Behavior

- Phone Settings → Connect iPad Dashboard offers **Include recent Apple Health
  sleep**, off initially and scoped to the current screen/connection. Opening does
  not query Health. Starting with it enabled requires the existing integration
  preference and prepares the last 30 elapsed days before advertising.
- Original stages, UUIDs, boundaries and allowed source/device metadata survive
  transfer. Range, completion and phone timezone are separate from SQLite capture.
  Empty successful reads are not proof of no sleep or permission. Query failure
  does not silently omit provider evidence; the owner can explicitly opt out.
- A 10,001-result query detects a 10,000-sample limit without silent truncation.
  The existing encoded 32 MiB bound remains. Leaving, backgrounding, cancelling or
  changing the choice fences late results. Repeated refresh in one connection uses
  the visibly dated prepared evidence; reconnect to refresh the provider query.
- iPad **Apple Health evidence** presents the query scope, counts and calendar-day
  stage bars in the phone timezone. It retains original interval times and source
  inspection. Chart rendering is capped at 500 intervals with an explicit notice;
  the full selected-day list and reporting payload remain intact. Overlapping
  sources are not summed and gaps are not converted to awake time.
- Complete provider validation runs before cache replacement and on reopening.
  Unknown versions, malformed packets and invalid/conflicting sample identities
  cannot replace the last good report. Legacy provider-unavailable reports remain
  readable. The Connection version label now uses the installed bundle metadata.
- No clinical SQLite, dose, alarm, provider-store, CloudKit or server writes occur.
  Existing Studio ZIP/Excel schemas are unchanged. WHOOP remains unavailable.

## Validation

- New Core tests were written first and failed before the packet type existed.
  Final SwiftPM: 848 DoseCore XCTest, 20 nearby XCTest and 43 Swift Testing passed.
  `/tmp/dosetap-provider-core-tests.log`.
- Phone: 3 preparation tests and 7 snapshot-storage tests passed, including opt-out,
  disabled preference, failure, successful-empty and late-result cancellation.
  28 HealthKit adapter tests passed. `/tmp/dosetap-provider-phone-tests.log` and
  `/tmp/dosetap-provider-health-tests.log`.
- Native phone publisher test passed and its screenshot confirms the initial off
  switch. iPad: 9 cache tests and 4 native UI journeys passed, including the new
  normal/largest-text stage/source inspection and existing dashboard paths.
  Native screenshots were inspected, not offscreen renderings. Artifacts:
  `/tmp/dosetap-provider-phone-screens`, `/tmp/dosetap-provider-ipad-screens`.
- Both simulator and signed device builds passed. Phone version check passed all
  four configurations at 81; iPad generated Debug/Release builds use 9.
- Plane workflow (15 tests/80 assertions), SSOT, documentation and whitespace checks
  passed. Installation, hosted review and integration require their own readbacks;
  the live PR and Plane workpad record results after this document's checkpoint.

## Remaining gates and next slice

Actual phone Health permission/empty/failure states, large real-history preparation,
phone-to-iPad sample/byte/source parity, reconnection, VoiceOver, privacy/security
and owner/release acceptance remain open. No owner acceptance was inferred from
"proceed" or from the older quoted builds 79/7 prompt.

Next: reviewed per-night source consensus and Dose 2 awakening → dose → observed
return to sleep, preserving unknown gaps, conflicts and endpoint basis. WHOOP is
separate work. The broader work/pain/food/environment/daytime comparisons remain
in the [inventory](2026-09-26-dashboard-data-comparison-inventory.md).

## Hosted validation follow-up

PR #71 initially found that the largest-text UI test assumed the Medications
sidebar item was already visible. It now uses the existing sidebar scrolling
helper before tapping. This is a test-only navigation correction; installed app
binaries and build numbers are unchanged. Hosted rerun results and integration
are recorded in the live PR and Plane workpad.
