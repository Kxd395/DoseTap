# Local bottle tracking

DOSETAP-77, owner-authorized 2026-09-28 extension to the earlier reminder-only scope.

This bounded slice records reported receipts and explicit bottle openings locally.
The usual receipt count is three, editable before confirmation. Receiving bottles
never records medication or automatically replaces an open bottle. Starting a
tracked bottle explicitly replaces the current bottle for display; it does not
claim the previous bottle was empty. Legacy timestamp-only openings remain intact
and are not assigned to a shipment by inference. Entries may represent only the
unopened portion of a delivery, not its total shipment count. Already-open unlinked
bottles do not receive stock-based notices; a direct calendar-reminder route is
available while explicit current-bottle adoption remains a follow-on.

The display separates tracked unopened bottles, the active opening date, and
recorded dosing nights since opening. A dosing night is a distinct stored treatment
date with canonical taken nighttime events in the opening-to-now interval. Skips,
snoozes and independent daytime medications do not count. Missing or conflicting
identity data is disclosed and excluded, and a failed read is unavailable, not zero.
This temporal count is not proof that a particular bottle supplied each dose.

When no tracked unopened bottles remain, show a last-tracked-bottle notice. On the
third recorded dosing night since that opening, emphasize the owner-requested
contact reminder. This is an in-app notice, not proof of pharmacy contact, approval,
ordering or shipping. Existing explicitly saved calendar notification stays
independent and available as a fallback. No medication alarm changes.

## Confirmed quantity and preparations (DOSETAP-77)

Quantity tracking is opt-in per bottle, including an existing unlinked opening.
An explicit XYWAV 0.5 g/mL baseline records the amount still IN the bottle, excluding
already-prepared doses. A full 180 mL bottle is nominally 90 g; a 4.5 g reference
dose is 9 mL. Nothing initializes a full balance from an opening or a photograph.
The estimate is baseline minus confirmed preparations since that baseline. Grams
are stored as integer milligrams; dilution water is excluded. Reference-dose
counts are equivalents, not a prescribing instruction or a count of taken doses.

Each preparation has its own ID, bottle ID, amount, mixing time and recorded-at.
The capture explicitly asks when the medication was mixed with water.
Preparing two doses explicitly creates two records in one durable write. A
preparation can be linked to an existing canonical taken-dose record, or explicitly
marked discarded. Neither action deducts bottle stock again. Supply actions never
create, correct or cancel medication events or medication alarms. Deleted/changed
linked dose evidence is flagged for review, not silently substituted. One dose
cannot consume multiple preparations in this slice; split-bottle allocation remains
open. Prepared-but-unresolved is not proof of a skipped dose or available medication.

The quantity ledger preserves corrections by voiding the latest applicable action;
undoing a preparation is a correction of an erroneous entry, not returning mixed
medicine to the bottle. Dependent actions must be undone first. Reconciliation
baselines keep earlier evidence and require an explicit reason. Backdated changes
must not reorder inventory history. Failed writes preserve inputs and expose retry.

XYWAV diluted-dose instructions require use within 24 hours after mixing and
otherwise disposal. The UI shows the original preparation time and elapsed-limit
review state; it never recommends taking, auto-carries a dose into tomorrow, or
records disposal based on a timer. Reported historical use beyond the limit remains
recordable through the medication ledger and can be linked with a review warning.
Official source checked 2026-09-28:
https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=1e0ae43a-037f-42af-8e23-a0e51d75abe8

Doses/nights are estimates from confirmed quantity entries only. Missing withdrawals
can overstate stock and are disclosed. Night equivalents use an explicitly labeled
4.5 g twice-nightly reference, not an inferred historical prescription. Existing
night-count contact notices stay independent; automatic quantity-triggered alerts
and pharmacy contact remain outside this slice.

Source truth remains one versioned SQLite supply document through
Views -> SessionRepository -> EventStorage. Commands preserve legacy records,
validate counts/identities/times, and publish success only after a durable write.
New fields are optional when reading older version-1 documents; the first tracking
receipt/opening command writes at least version 2 so older apps reject rather than erase the new records. Settings supply JSON and
Studio ZIP/Excel retain the source document and field-level evidence. This is not
a promise of full-app restore. No cloud or pharmacy integration.

Export retains exact source dates in optional `supplyStateJSON`, with
`supplyStateEncoding` equal to `json-date-seconds-since-2001-v1`. The outer bundle
still uses its existing timestamp convention. A conditional Bottle & Supply sheet
and Source Fields expose receipts, openings, reminder revisions and void history.
Inventory/manual snapshots remain separate. Invalid persisted supply fails the
export rather than silently omitting it.

Quantity commands write supply version 3 with optional `quantityEntries`; older readers reject rather than strip the ledger. No SQL migration or historical backfill. Studio ZIP, supply backup, Source Fields and Bottle & Supply retain every quantity entry and dose-link snapshot.
