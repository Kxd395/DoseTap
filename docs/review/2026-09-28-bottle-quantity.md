# Bottle quantity and prepared-dose tracking — DOSETAP-77

Installed and independently verified phone version: **0.4.19 (84)**. This follows the
[build 82 bottle foundation](2026-09-28-bottle-tracking.md). The separate iPad app
is unchanged. Device, owner, accessibility, privacy and release acceptance remain
separate from source and simulator validation.

## What changes

Tonight → Bottle & supply → **Amounts & preparations** now supports an explicit
starting or reconciled amount for the active bottle. It never assumes an opened
bottle is full. The screen identifies XYWAV 0.5 g/mL; the owner's label and official
product information support a nominal 180 mL / 90 g bottle. Private label photos,
patient names and prescription identifiers are not copied into the repository.

The display leads with estimated grams still in the bottle, then equivalents at
4.5 g per dose and 4.5 g twice nightly. These are named reference amounts, not a
new prescription or an assertion that current Settings contain a versioned dose
plan. One full bottle corresponds to 20 such doses / 10 two-dose nights.

- Record one or two preparations with an explicit amount and mixing time.
  Two preparations commit atomically and each receives its own stable ID.
- Bottle stock decreases once when preparation is confirmed. Preparations remain
  separate from medication outcomes and from the recorded dosing-night count.
- Link a preparation to an existing canonical dose event, or confirm disposal.
  Neither action subtracts bottle contents a second time or creates a dose event.
- Source dose identity, type and occurrence time are checked again at save.
  Duplicate or ambiguous identities cannot be selected. Later changes to a linked
  dose display a review message while retaining the original link snapshot.
- A preparation is unresolved until explicitly linked or discarded. Advancing
  time, skipping a questionnaire or missing a dose log never resolves it.
- Reconciliation keeps its reason and earlier history. Undo corrects the latest
  quantity action for that bottle; dependent entries must be undone first.
  Undo is not evidence that diluted medication was returned to a bottle.
- Write failures keep the form and answers available. Stable submission IDs
  prevent a retry from creating another withdrawal. Concurrent changes fail with
  reload guidance instead of overwriting a newer balance.

The [official XYWAV instructions](https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=1e0ae43a-037f-42af-8e23-a0e51d75abe8)
require mixed doses to be used within 24 hours and otherwise discarded. The UI
shows when that limit is reached, retains the original mixing time, and does not
label an unresolved dose safe for reuse. A historical report beyond the limit
can still be recorded accurately and is flagged for review.

## Ownership and export

Views → SessionRepository → EventStorage → SQLite `supply_state` remains the
single ownership chain. The first quantity write upgrades the supply document to
version 3. Earlier versions remain readable without fabricated quantities. Old
readers reject version 3 rather than silently dropping its evidence; an older app
must not be used to edit this supply document.

Studio ZIP retains the complete `supplyStateJSON`, including fractional dates,
original/recorded times, preparation and dose references, reasons and voids. The
sortable Excel **Bottle & Supply** sheet adds amount, medication volume, source
IDs, dose occurrence and preparation-limit columns. **Source Fields** retains the
complete source. Manual Inventory snapshots remain a distinct collection. The
nearby report carries the source document; this slice adds no iPad quantity UI.

## Validation checkpoint

- Test-first quantity fixtures cover balance replay, atomic insufficient-stock
  failure, explicit zero, duplicate actions and dose allocation, future dates,
  wrong-bottle references, retained-history correction and the 24-hour boundary.
- Full Swift suite passed: 867 DoseCore XCTest, 20 nearby XCTest and 43 Swift
  Testing cases. Build passed.
- 26 native integration tests passed: 14 supply storage, six supply service and
  six Excel/ZIP tests. They cover checked source reads, reload, failed writes,
  no medication creation and source/export parity.
- Unsigned simulator build and all four phone version configurations passed.
  SSOT, documentation, architecture, Plane workflow and whitespace checks passed.
- Normal and largest-text native quantity journeys passed on build 83's unchanged
  interface: baseline, two-dose
  preparation, separate link/discard routes, no duplicate deduction, unchanged
  medication controls, and retained balance/unresolved count after relaunch.
  Compact Tonight/History layout also passed. Test navigation was corrected for
  the composed stepper identifier and offscreen lazy rows; assertions now use
  the visible unresolved count. Normal text was restored after large-text tests.
- The signed final build installed without resetting app data. Independent
  CoreDevice app inventory reports 0.4.19 (84). No owner medication or supply
  records were created for testing. Installation is not owner-flow acceptance.
- Source review checked allocation identity, atomic preparation writes, retry
  idempotency, correction dependencies and separation from medication events.
  Exact feature/main commit and hosted-check evidence live in the pull request
  and the structured DOSETAP-77 workpad.

## Review correction after the build-83 candidate

Automated PR review found that the initial dose-link SQL could overlook a legacy
NULL/date-only row beside a canonical session row. Regression fixtures reproduced
this and event-name alias duplicates. Both supply counts and dose-link candidates
now share one checked date-group projection and the existing canonical event
vocabulary. Ambiguous groups are excluded; unrelated dates remain eligible.
This correction is delivered as build 84, replacing the installed build-83
candidate. No historical records are modified or merged by this lookup.

## Remaining gates and bounds

The owner accepted page opening/readability on build 82; that does not accept this
new quantity flow. Verify real balance/preparation records after restart and in
an exported ZIP/XLSX. Do not create medication events merely for testing.

Unrecorded withdrawals can overstate remaining stock. This estimate is not a
measured bottle level. Split-bottle preparation, partial disposal, automatic
versioned-plan forecasts, order/contact/shipment state and an automatic day-3
notification remain follow-on work. The existing last-bottle and third-recorded-
night notices and independent calendar reminder remain in place. Confirm the
owner's intended day-3 basis and contact lead time before changing that policy.

VoiceOver, actual phone behavior, physical notification delivery, clinical
wording, privacy and release acceptance remain open. DOSETAP-77 stays In Progress.
