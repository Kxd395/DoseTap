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

## Physical morning alignment verification and presentation follow-up

Signed build 95 was installed, independently inventoried and launched through iPhone Mirroring. Read-only inspection of an actual dose pair spanning midnight showed the following morning's saved Work Night answer on that same previous-night observation. Work Night and Into Work Block filters displayed distinct square and triangle markers. Reviewed work remained separately Unknown when no reviewed association existed. No dose, check-in or provider association was edited.

Physical Overview scrolling and Zoom in/Reset worked. The zoom check exposed out-of-domain marks drawing outside the plot, and the actual single-dose minute annotations were absent despite the simulator fixture. Build 96 clips marks to the plot and places single-dose minute labels explicitly in the inspection overlay; label hit testing is disabled so point selection remains available. This is a display correction only. Physical pinch, pointer hover, VoiceOver, all-night association accuracy and owner acceptance remain open; iPad Dashboard 10 launch remains deferred.

Build 96 final verification: 34 focused native tests and the existing single-dose/tap/zoom/reset/work-filter UI journey passed. The enabled precommit hook built the generic simulator target; Plane workflow 15/80, docs, all four version configurations and whitespace checks passed. Signed 0.4.19 (96) passed codesign, installed over the existing app, was independently inventoried and launched through Mirroring; its running process matched the newly installed bundle container. Actual phone pixels showed single-dose minute labels, bounded zoomed marks and successful Reset. The phone was left at the full-range Apple Health/Morning check-in/All night types sleep-spacing view. These scoped observations do not close the remaining owner/provider/accessibility/release gates.

## Zoom navigation and overlapping records — build 97

Owner review rejected build96 zoom usability: no panning existed, and absent a selected night the viewport used the midpoint. The viewport now has independent display focus, continuous pinch updates, bounded drag panning and accessible left/right/up/down controls. Initial button zoom focuses the selected night; later selection does not jump the viewport. Reset and source/filter changes restore the complete range. A range label makes viewport movement observable.

A scatter coordinate represents spacing and recorded sleep, not a calendar date. Distinct nights may share exact coordinates; single-dose nights intentionally share the zero category. Nearby point taps open a dated, scrollable chooser with exact spacing/sleep values and stable observation identities. Coordinates are preserved, with no jitter or source-data rewrite.

Read-only source audit confirmed canonical comparison rows reject ambiguous replay identity and local snapshot reads use repository transactions. Export serializes frozen view inputs and is not imported back into chart storage. This does not certify every current phone record or provider association; aggregate population and overlap are separate from individual identity/accuracy acceptance.

Native validation passed 27 focused tests covering bounded pan math, invalid geometry, coincident distinct records, morning identity and production dose-pattern/database paths. The first UI attempt inherited a display-fixture argument and did not reach the requested repository fixture; the corrected test removes that argument and retains all actual overlap/viewport/drag assertions. The stalled first test runner was stopped after its failure; its log is preserved.

The next UI run reached the overlap chooser and zoom but exposed chart gestures intercepting the scroll margin. Plot interaction is now restricted to the actual plot hit area, with drag-start bounds checked; scrolling outside that area remains available. The final normal-size test declares its text size explicitly rather than inheriting a prior largest-text preference. Both failed runs remain diagnostic evidence, not passes.

The final UI journey passed using the production repository/provider overlap fixture: two exact-coordinate nights remained separate in the chooser, selecting one and zooming worked, the directional control changed the displayed range, an actual chart drag changed it again, and Reset restored the view. Scroll-margin navigation reached the controls without intercepting the plot. Result: `/tmp/dosetap97-ui-bounded.log`, `Test-DoseTapUITests-2026.10.02_08-19-07--0400.xcresult`.

Build97 signed/device verification passed: codesign, installation, independent version inventory and launch. Actual phone refresh populated the chart. A tapped cluster opened different dated nights with different exact spacing/sleep values; selecting a record and zooming worked. A physical Mirroring drag changed both viewport ranges, the right-arrow control changed the horizontal range, outer dashboard scrolling worked while zoomed, and Reset restored the full range. No dose, check-in, provider association or export file was modified during inspection. Actual pinch, VoiceOver and owner usefulness acceptance remain separate open gates. Installation and source checkpoints are retained in ignored local evidence.
