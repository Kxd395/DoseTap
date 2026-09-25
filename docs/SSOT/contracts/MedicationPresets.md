# Medication preset foundation

Date: 2026-09-25
Plane: DOSETAP-74, slice B1
Status: Core contract; no saved-preset interface or persistence delivery yet

`MedicationPresetRevision` records immutable patient-entered label information,
never clinician verification or proof of administration. Version 1 supports
oral-solid components only: decimal milligrams per tablet/capsule and decimal
unit counts. Liquid concentrations, other mass units and combination ingredients
need an explicit later contract; no implicit conversion or catalog default exists.
Release profile is independent of physical form. Unknown release remains unknown;
Other requires a nonblank entered description. Each component has a UUID, and
duplicate component IDs in one list are rejected.

A revision has stable preset/revision UUIDs, an optional predecessor revision,
label name, single ingredient identity, release profile, components, prescribed
instructions and scheduled/as-needed designation, effective start/optional
exclusive end, and recording timestamp. Source is patient-entered label. All
fields are immutable. A new revision cannot change an older value. Durable
uniqueness, predecessor matching, current-revision selection and concurrency
checks belong to the future repository transaction, not this value model.

Components are scoped to this one ingredient/release profile; each stores its own
physical form, strength and quantity. Totals use checked Decimal multiplication
and addition; NaN, nonpositive values, overflow, underflow and loss of precision
fail instead of producing a rounded or fabricated amount. There is no API to sum
different medications. This validates data representation, not prescribed dosing.

`ConfirmedMedicationAdministration` stores the full revision and independently
confirmed actual components, a stable administration ID, confirmed-at and
recorded-at timestamps, and exact/approximate/unknown occurrence evidence. An
unknown occurrence has no timestamp, timezone or offset. Known occurrences retain
a named timezone and original UTC offset; approximate time is not a range and
cannot establish precise window classification. Occurrence cannot be future to
confirmation, and recording cannot precede confirmation. No clock/default amount
is supplied by the model. A retrospective report may reference a now-inactive
revision; effective dates are context, not a reason to reject reported history.
Offsets are retained as supplied evidence (bounded to plus/minus 18 hours), not
recomputed from a later timezone database. New captures require a recognized
timezone identifier. Historical decoding retains a nonblank identifier even when
the receiving OS does not recognize it; absolute occurrence and offset remain
usable evidence. These model checks do not establish
that a UI obtained consent or that a caller supplied the correct offset.

Both direct construction and JSON decoding validate record invariants and reject
unsupported schema versions; only new capture depends on current timezone-name
recognition. JSON round trips preserve full snapshots.
Serialization here is a domain contract, not a claim about the existing Settings
export. No existing medication row is converted or backfilled. No session,
reminder, inventory, prescription suggestion or clinical score is affected.

Next: durable immutable revisions and actual snapshots through SessionRepository
and EventStorage, transactional retries/corrections, source and workbook export
parity, and reviewed Settings/quick-log controls. Keep phone, accessibility,
privacy and release acceptance separate. Non-taken/uncertain outcomes, liquids,
named groups and audited reversals remain follow-on work.
