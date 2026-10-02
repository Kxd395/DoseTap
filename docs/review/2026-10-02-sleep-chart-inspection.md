# Sleep chart inspection — 2026-10-02

Implementation branch: `feat/sleep-chart-inspection`, based on recovery checkpoint `ac4e07b` and phone93 source `5540cc3`. Preserved feature and paused integration worktrees remain separate.

## Delivered behavior

- Overview Sleep vs spacing and Trends Interval vs Sleep share canonical replay comparisons, exact observation selection and one chart component.
- Confirmed single-dose nights with recorded sleep occupy a zero category, with a distinct teal marker, a `1` and sleep minutes. No zero-minute interval is written or exported. Unknown count and missing sleep stay unplotted.
- Square means confirmed work before sleep, circle means off, diamond means unknown. Planned shifts alone do not establish work. Both views share the work filter; global pairing counts retain their period/source denominator.
- Spacing colors stay blue within 150–240 minutes, lavender below, amber above; single dose uses teal. Markers are larger, outlined and enlarged on selection. Night Mode retains the existing warm filter. Color is descriptive, not a treatment rating.
- Horizontal grid divisions are 25 minutes, with 12.5-minute subdivisions. Sleep grid divisions are 25 minutes. Labels adapt to zoom, with bounded tick generation.
- Tap, accessible point controls and pointer hover inspect source sleep, spacing, date and work status. Overlapping points offer exact candidate identities. Source values retain fractional precision; summary labels use up to two decimals.
- Pinch and accessible Zoom in/out/Reset change display domains only, around the selected night. Source/row/filter changes reset zoom. Record, relationship, dose and export data are unchanged.

## Validation and acceptance boundaries

Native focused tests cover numeric boundaries, exact fractional values, confirmed single versus unknown, zero sleep, finite domains, grid subdivisions and bounded ticks, zoom focus, canonical dose review and production provider pairing. SwiftPM core checks and repository guards are separate from rendered UI evidence.

UI journeys use synthetic repository/provider evidence. Physical phone 94 installation, inventory and launch are recorded in the ignored `.build/chart-inspection-evidence` directory when performed. Simulator evidence does not establish owner acceptance of individual actual-night associations.

Physical pinch/hover, VoiceOver usability, real-phone chart responsiveness and per-night provider accuracy remain owner/device gates. Pointer hover requires a pointer; a finger on an iPhone does not hover. Physical iPad Dashboard 10 launch stays explicitly deferred. Existing provider/privacy/reminder/release gates on DOSETAP-45 remain open.

Verified automated results: 29 focused native tests; 2 synthetic UI journeys (normal dark palette and largest-text Night Mode); 1,191 XCTest core tests plus 43 Swift Testing tests. Plane workflow 15 tests/80 assertions, SSOT, architecture, version 94 across four phone/staging configurations, docs and whitespace checks passed.

Signed 0.4.19 (94) passed codesign verification, installed over the existing phone app, was independently inventoried as build94 and launched successfully. The first transport connection reset; retry succeeded. Actual chart pixels and touch acceptance remain separate evidence.

## Morning context alignment correction — build 95

The chart previously read only reviewed shift associations, while the exact night already contained the saved morning `timingContextJson.nightType`. This ignored Work Night, Off Night and Into/Out block answers; reviewed phases were also intentionally reduced to preceding-work/off/unknown. The saved phone diagnostic copy confirmed the reported categories existed. It is a snapshot, not a fresh phone read; records without an exact session link and duplicate morning groups require review. Private diagnostic counts remain in local ignored evidence.

The chart now defaults to Morning check-in context: square work, circle off, upward triangle into block, downward triangle out, hexagon recovery, diamond unsure/unknown. Into/Out retain their original labels. First-night-off remains an independent positive report in point details. Reviewed shifts remain selectable separately; a morning report never creates attendance, block membership or actual shift times. Shared work-phase filters still use reviewed shifts and are labeled when active.

The projection requires an unambiguous exact session ID and treatment date plus a finite report timestamp no later than the dashboard cutoff. The morning clock date never reassigns a record to another night. Chart marker/filter/detail and CSV freeze the same projected category and morning ID/timestamp. Missing, malformed, future, mismatched or ambiguous evidence remains unknown/review.

34 focused native tests passed, including real in-memory SQLite saves and production refresh of D1 before midnight, D2 after midnight and the following morning check-in. A historical edit changes the context on the same stable observation and preserves its 180-minute pair and dose rows. Existing reviewed-work freshness/identity tests still pass.

Three distinct simulator UI journeys passed: exact reported Into/Out context and filtering, reviewed-shift single-dose/zoom/filter journey, and the largest-text Night Mode journey. Initial largest-text automated scrolling failed reachability; the final test uses the scroll margin and adaptive direction, retains visible/hittable assertions, and passes actual point/control taps. Screenshots and failure/readback evidence remain in the ignored local evidence directory.
