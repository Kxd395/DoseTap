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

No remaining quantity or dose count is inferred from elapsed nights, a planned
amount, or an empty allocation ledger. Explain that estimated doses remaining
requires confirmed quantity and consumption; that quantity-based follow-on remains
open. Preparation versus administration and split-bottle doses are not conflated.

Source truth remains one versioned SQLite supply document through
Views -> SessionRepository -> EventStorage. Commands preserve legacy records,
validate counts/identities/times, and publish success only after a durable write.
New fields are optional when reading older version-1 documents; the first tracking
command writes version 2 so older apps reject rather than erase the new records. Settings supply JSON and
Studio ZIP/Excel retain the source document and field-level evidence. This is not
a promise of full-app restore. No cloud or pharmacy integration.

Export retains exact source dates in optional `supplyStateJSON`, with
`supplyStateEncoding` equal to `json-date-seconds-since-2001-v1`. The outer bundle
still uses its existing timestamp convention. A conditional Bottle & Supply sheet
and Source Fields expose receipts, openings, reminder revisions and void history.
Inventory/manual snapshots remain separate. Invalid persisted supply fails the
export rather than silently omitting it.
