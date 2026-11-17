# Bottle quantity and prepared-dose tracking — DOSETAP-77

Installed phone: **0.4.19 (86)**, independently verified through CoreDevice. Automated quantity checks passed; hosted checks and merge are tracked in PR #73. This follows the
[build 82 bottle foundation](2026-09-28-bottle-tracking.md). The separate iPad app
is unchanged. Device, owner, accessibility, privacy and release acceptance remain
separate from source and simulator validation.

## What changes

Tonight → Bottle & supply → **Amounts & preparations** now supports an explicit
starting or reconciled amount for the active bottle. Build 86 initializes 90 g
when the user explicitly confirms starting a new full XYWAV bottle. Existing
openings are not retroactively filled. The screen identifies XYWAV 0.5 g/mL; the owner's label and official
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
- Full Swift suite passed: 872 DoseCore XCTest, 20 nearby XCTest and 43 Swift
  Testing cases. Build passed.
- 26 native integration tests passed: 14 supply storage, six supply service and
  six Excel/ZIP tests. They cover checked source reads, reload, failed writes,
  no medication creation and source/export parity.
- Unsigned simulator build and all four phone version configurations passed.
  SSOT, documentation, architecture, Plane workflow and whitespace checks passed.
- Seven build-86 native journeys passed: normal and largest-text quantity flows,
  full-opening/undo, confirmed unlinked balance and restart, and compact
  Tonight/History reachability. Automatic 90 g initialization, displayed 4.5 g,
  two-dose withdrawal to 81 g, separate link/discard actions and retained balance
  were checked. Test scrolling was adjusted for the full-bottle form and lazy
  rows at large text; normal text was restored. Native screenshots were inspected.
  Results: `Test-DoseTapUITests-2026.09.28_19-37-39--0400.xcresult` contains four
  passing journeys; the corrected large-text journey passed in
  `Test-DoseTapUITests-2026.09.28_19-42-50--0400.xcresult`. Both existing
  pre-sleep bottle/reminder entry-point journeys also passed against the unified
  route, bringing the final native total to seven.
- The signed final build installed without resetting app data. Independent
  CoreDevice app inventory reports 0.4.19 (86). No synthetic owner records were created.
  One owner-confirmed current balance was saved through the normal mirrored app
  form and verified after reopening and installing build 86. Unopened stock stays
  unknown. This bounded check does not accept the remaining preparation/export flow.
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
This correction was delivered as build 84, replacing the installed build-83
candidate; builds 85 and 86 retain it. No historical records are modified or
merged by this lookup.

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

## Owner-reported Tonight visibility gap

After build84 installation, the owner reported seeing only the nights-since-opening
information. Source inspection confirmed that Tonight omitted a missing balance
and only showed dose equivalents when a balance existed. Build85 puts grams and
reference dose/night equivalents on that card, always displays unopened-stock
status, and provides a direct amount setup/review route. The supply card follows the
compact dosing control so the amount detail does not displace the normal-text
dose action. The page remains scrollable for supply and weekly information. Missing amounts and stock
are explicitly not recorded; elapsed nights never invent consumption. Read errors
remain unavailable with retry. All three final native checks passed, including missing-quantity visibility,
gram/dose/bottle values on Tonight, direct quantity navigation, relaunch persistence
and compact Tonight/History reachability. Native screenshots were inspected;
normal text was restored. Earlier attempts exposed duplicate accessibility
identifiers and an obsolete one-screen-fit assumption; both were corrected. The
final successful result is Test-DoseTapUITests-2026.09.28_19-16-01--0400.xcresult. The supplied image was unrelated to DoseTap
and was not treated as app evidence.

## Owner clarification: standard full bottles and current elapsed-night count

The owner requested automatic quantities for a new full bottle. Build86 confirms
the standard XYWAV180mL/90g opening and starting baseline in one atomic write.
Retrying the action does not refill a partially used bottle. A preparation starts
with the confirmed4.5g amount displayed, editable before explicit save. An unused
opening can be undone together with its automatic baseline; later quantity actions
must be corrected first. No dose event is created.

Elapsed-night counts remain separate from confirmed withdrawals. A confirmed
90g opening with ten4.5g withdrawals leaves45g (ten reference doses/five two-dose
night equivalents). This example requires confirmed quantities; five elapsed
nights alone is insufficient. A current-bottle correction is a dated balance
reconciliation and never creates historical medication events. Build 86 is installed;
quantity validation passed; hosted review and merge state are recorded in PR #73.

The physical-phone balance entry also exposed an unknown-stock display defect:
a quantity-only document upgrade could show zero unopened bottles. The projection
now keeps stock unknown until a receipt has actually been recorded. Every
new-bottle route shares the full-bottle flow; an opening without a receipt does
not invent a shipment or stock count. Quantity and supply pages refresh after
saves, and openings with quantity history route to retained-history corrections.
