# Dashboard evidence review delivery

Status: Installed; hosted integration pending; DOSETAP-45 and DOSETAP-76 remain In Progress.
Date: 2026-09-26. Installed: iPhone 0.4.19 (79), separate iPad Dashboard 0.1.0 (7).

The owner requested a whole-dashboard overhaul, including better use of collected
information. The [collection/comparison inventory](2026-09-26-dashboard-data-comparison-inventory.md)
maps supported fields, source ownership, current visibility and remaining work.
This bounded slice addresses readability, dose-spacing correctness and explicit
diary outcomes; it does not complete the whole overhaul.

## Changes

- Phone: observed theme-aware dashboard palette keeps values and chart marks
  bright through the existing Night Mode filter. Normal Light/Dark colors remain.
  Labeled symbols supplement color. The interval scatter legend identifies the
  built-in 150–240 minute inclusive reference, not a historical prescription or
  treatment-effectiveness rating. Range and selected chart survive theme changes.
- Phone: equal/reversed selected dose timestamps remain recorded but are excluded
  from spacing summaries, reference counts and plots. A visible interval-review
  count and recent-night wording preserve the distinction from missing outcomes.
- iPad: Wake & sleepiness workspace shows timed explicit diary ratings, reported
  final wake, source IDs and unavailable/excluded reasons. Matches require the
  same durable identity on both actual dose rows and the validated diary, within
  one immutable snapshot generation. No lifecycle guess fills missing identity.
- Elapsed Dose 2 → reported final wake is wall-clock time, not observed sleep.
  Post-wake sleepiness has its own denominator and requires an assessment after
  both Dose 2 and reported final wake. Zero ratings and zero elapsed remain valid
  when explicitly reported; absent answers are not zero. Detail times include
  seconds; summary duration rounding is disclosed.
- Matched comparison plots show diary sleepiness against dose spacing or elapsed
  Dose 2 to reported final wake. Point selection opens exact evidence; constant
  ratings are explicitly described as unable to distinguish outcomes. A report
  generation change closes the old inspector to prevent stale detail.
- Canonical diary decoding now requires the complete versioned record and typed
  revisions. Invalid reviewed windows stay unavailable; undated source rows are
  counted separately without inventing a second date for a valid identity.
- iPad adds a 14-day range. Chart points, readable diary rows and exclusion counts
  complement the existing dose trends, distributions, monthly summaries,
  medication calendar records, questionnaire coverage and report contents.

## Validation evidence

- Phone regression first reproduced the zero-pair bug with eight failed assertions;
  after correction all 23 DashboardAnalyticsAuditTests passed, including positive
  subminute and repeated-hour DST fixtures. Source times remained unchanged.
- Core: 840 DoseCore XCTest + 20 Nearby XCTest + 43 Swift Testing cases passed.
  Eleven new diary tests cover identity, chronology, conflicts, missingness,
  post-capture records, midnight/DST and independent metric denominators.
- Independent review found no calculation/cache blocker and caught the exact-time
  wording issue; diary detail now displays seconds and summary rounding is labeled.
- Native phone large-text/landscape and Night Mode theme/legend journeys passed.
  Phone artifacts: `/tmp/dosetap-dashboard79-ui.log` (large text) and
  `/tmp/dosetap-dashboard79-ui-retry.log` (Night Mode). The initial Night Mode
  test hit a picker beneath the navigation bar; the corrected native scroll path
  passed. Its stalled Xcode diagnostics process was ended without resetting data.
- iPad: all eight cache tests and both native journeys passed from isolated
  `/tmp/dosetap-ipad7-exact-build`, including largest text, comparison selection,
  exact matched-record detail and retained missingness. An earlier incremental
  run used an older navigation path; it is superseded by this fresh verification.
  Log: `/tmp/dosetap-ipad7-exact-tests.log`; native screenshot attachments:
  `/tmp/dosetap-ipad7-exact-screens`. Rendered normal/large text and detail inspected.
- Signed builds and installation passed. Device application inventories independently
  reported phone 0.4.19 (79) and separate iPad Dashboard 0.1.0 (7). The existing
  full DoseTap app on iPad stays 0.4.19 (76). No uninstall/reset was performed.
  Evidence: `/tmp/dosetap-phone79-apps.json`, `/tmp/dosetap-ipad7-apps.json`.
  Both launch attempts were denied because devices were locked; physical visual,
  owner usability and real-report parity acceptance remain open.
- Phone build/version check passed all four configurations; iPad Debug and Release
  settings both read 0.1.0 (7). Plane workflow (15 tests/80 assertions), SSOT,
  documentation and whitespace checks passed.
- Independent source review found and resolved stale inspector and time-precision
  issues. Final review found no remaining actionable issue in this bounded patch.
- Both Plane workpads were applied and exactly read back as In Progress during
  implementation. PR #69 canonical validation fixes are included in this branch;
  PR #70 contains this evidence-review slice. Hosted checks and normal protected
  integration are pending and must not be inferred from local validation.

## Remaining acceptance and next work

The next analytic prerequisite is bounded provider evidence transfer with query
status, original sample identity, coverage and reviewed sleep boundaries. Then
expose Dose 2 awakening → dose → return-to-sleep with gaps/conflicts, followed by
work-transition, symptom, food, environment and daytime-medication comparisons.
The current nearby report still has no Apple Health/WHOOP measurements.

Whole-overhaul usefulness, real report parity, VoiceOver, physical-device behavior,
private-server readiness, privacy/security and release acceptance remain open.
No clinical write, alarm behavior, dose advice, CloudKit upload, medication-time
relink, or historical-answer backfill is introduced by this slice. Duplicate/skip
policy alignment and historical medication-window evidence remain separate work.
