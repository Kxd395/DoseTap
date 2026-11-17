# Next app improvements after build 65

Date: September 24, 2026
Status: Bounded review and proposed sequence; no new feature acceptance
Baseline: main build 64 plus the DOSETAP-72 build-65 candidate
Evidence: native simulator Tonight/Timeline captures, compiled source review,
and live Plane readback of DOSETAP-43/45/48/57/58. This is not a full-app or
owner-phone acceptance review.

## Recommendation

Prioritize Night Mode readability and action states under the existing
DOSETAP-43 layout work, preserving DOSETAP-48 automatic appearance behavior.
Then deliver the DOSETAP-45 work/off sleep summary. Follow with DOSETAP-58
independently timed daytime observations. Do not add a composite sleep score.

## Demonstrated usability findings

Final DOSETAP-72 native captures show a readable primary-color Wait Ns label,
but adjacent elements remain visually dim:

- Selected Tonight/Timeline tabs are dark teal and less prominent than other tabs.
- The blue Bathroom icon is nearly black; available Water and recent-log text
  are also dim.
- Purple Pre-Sleep Check and Next Action headings are hard to read.
- Compact quick-log labels use fixed 8–9-point fonts, requiring a separate large-text pass.

`ios/DoseTap/Theme/AppTheme.swift` multiplies the full screen by
`(1.0, 0.4, 0.3)`, while the tab bar and event/card views retain their ordinary
blue, green and purple colors. The source and captures support a display issue.
They do not establish the cause of the owner's earlier intermittent untappable
controls. DOSETAP-72 remains open for real-night recurrence acceptance.

## Next bounded implementation

Cover Tonight, Timeline Live and their shared tab bar:

1. Use readable Night Mode foregrounds for enabled event icons, recent-log labels,
   selected tabs, Pre-Sleep and Next Action headings. Preserve the warm appearance.
2. Distinguish available actions, per-event Wait Ns cooldowns, failed saves and
   medication-window waiting with text and accessible state, not color alone.
3. Keep a visible non-color indication of the selected tab and its accessibility
   selected trait. Preserve existing navigation and open editor state.
4. Review compact labels at normal and maximum text sizes. Verify complete
   controls remain reachable, with no accidental duplicate clinical writes.
5. Preserve automatic start/end/override rules, dose confirmation, alarm behavior,
   cooldown settings and repository persistence. Do not replace the root view
   subtree merely to switch appearance.
6. Describe Night Mode as a warm, dim appearance. The current source comment
   claiming no blue wavelengths does not match its nonzero blue multiplier;
   this review makes no sleep-benefit claim.

Validation must inspect native rendered contrast and exercise ready, waiting,
ready-after-background and failed-save/retry states. Switch appearance while an
editor is open. VoiceOver and owner-phone readability remain explicit gates.

## Next feature addition: work/off sleep summary

DOSETAP-45 is high priority and In Progress. Use the existing workbook summary
contract as the calculation reference for 7-, 14- and 30-day windows. Display
before a confirmed workday, before a confirmed day off, and work status unknown.
Show mean/median, measurement definition, provider, usable counts and missing or
excluded records. Schedule estimates and legacy night labels stay separate.

The existing local Studio increment must be adapted selectively: current main
already has stronger schema-3 identity and raw-evidence handling. The older
panel's latest-resolved-date anchor differs from the workbook's latest-exported-
date anchor and hides excluded dates from coverage. Define one shared date-window
and denominator contract before adding a second conflicting display. The iPhone
Dashboard is the owner's everyday destination; Studio and Excel should reconcile
with its definitions, without combining providers or inventing missing sleep.

Do not infer coming off or going into a work block from a single ambiguous
Work Night label. Actual shift timing or confirmed before/after-work evidence
needs its own collection contract.

## Following collection slice

DOSETAP-58 remains Todo. The current night diary has one editable sleepiness
rating and assessment time. A later daytime assessment must become a new timed
observation, not overwrite the earlier one. Define event identity, occurrence
and entry times, missing versus zero, History correction and export preservation
before implementing the new flow. Existing saved room/pain preferences cannot
silently confirm today's symptoms or outcomes.

DOSETAP-57 already has dose/sleep markers and interval inspection. Awakening
counts still need implementation against the reviewed episode/missingness
contract; a new count must not be inferred from bathroom-log totals.

## Tracker and acceptance

This document does not change issue states or claim the proposed slices shipped.
DOSETAP-43/45/48/57 are In Progress; DOSETAP-58 is Todo at this readback.
Older workpad no-merge wording is historical evidence, not current source truth.
Merged code, simulator checks and installation are separate from owner,
accessibility, provider, privacy and release acceptance.
