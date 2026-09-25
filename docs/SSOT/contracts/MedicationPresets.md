# Medication preset foundation

Date: 2026-09-25
Plane: DOSETAP-74, slices B1/B2
Status: Core contract with independent local ledger/export integration; preset UI remains follow-on work

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
fields are immutable. A new revision cannot change an older value. The value model validates local invariants. The repository transaction enforces
ledger-wide uniqueness, predecessor matching and concurrency as described below.

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

## Independent ledger and export (B2)

Preset revisions and confirmed administrations use separate append-only SQLite
tables, through SessionRepository and EventStorage. They never shadow the legacy
whole-mg medication table or acquire a night/date group. A transaction enforces
one initial revision per preset, an existing same-preset predecessor with no newer
child, nondecreasing revision recording time, and exact embedded-revision matching
for administrations. Stable IDs replay identical content; conflicting reuse fails.
Insert/commit failure rolls back. These internal APIs do not establish UI consent.

The ledger uses canonical sorted-key Codable JSON text with Foundation's default
Date representation (seconds since 2001-01-01 UTC) to preserve subsecond values
and Decimal amounts. Indexed recording/occurrence columns use ISO8601 UTC; reads
check every indexed value against its payload. There is no decode-to-Double
amount adapter. Unreadable or noncanonical records fail export rather than vanish.

Bundle schema5/export3.0 adds required top-level medicationPresetLedger containing
schemaVersion1, presetRevisions and administrations arrays of canonical JSON
strings. It validates IDs, predecessor chains and embedded revision references.
The arrays are independent of dateGroups, including zero-night exports. Original
strings survive timing projection, workbook source inspection and Studio import.
Dedicated workbook sheets show exact quantities as text and known dates as dates;
unknown occurrence stays blank. These records do not enter nighttime dose metrics.

Clear All Data removes administrations before presets. Night deletion/reset and
legacy age-based pruning preserve this ledger; its retention policy must be
exposed before user-facing preset capture. No existing records are backfilled.
The app still has no preset save/log controls; UI duplicate review, audited
corrections/reversals and named groups remain subsequent work.

Next: reviewed Settings/quick-log controls and ledger retention/correction UI.
Keep phone, accessibility,
privacy and release acceptance separate. Non-taken/uncertain outcomes, liquids,
named groups and audited reversals remain follow-on work.

## Saved medication setup (B3a)

Settings offers Saved medication presets separately from legacy picker settings.
Create/revise requires explicit label, ingredient, release profile, oral-solid
components, prescribed instructions, scheduled/as-needed choice and reviewed
effective dates. New categorical choices and amounts start unanswered. Decimal
input uses the displayed locale separator, accepts complete positive decimal
strings only, and rejects unsupported precision rather than rounding.

An unchecked review acknowledgement covers the displayed label and dates. Save
creates only an immutable preset revision, never an administration, dose, alarm,
inventory entry or session. The chain leaf is the editable latest saved revision;
effective dates are displayed as context, not prescribing advice. Older revisions
remain viewable. Equal recording timestamps do not determine revision order.

The first save attempt freezes IDs, contents and recording time. A failed write
retains that command for Retry; Return to editing discards the pending command
and requires fresh review. Read failures hide stale lists and disable creation.
Concurrent revision changes fail rather than overwrite; reopen the latest revision
to resolve them. Cancelling an editor records nothing. Drafts are in-memory only.

Before entry, explain that revisions remain locally until Clear All Data or app
removal; night deletion and age cleanup do not remove them. Exported copies are
separate and are not automatically erased. No individual purge or administration
quick-log action is offered here. Audited administration corrections/reversals
and their capture controls remain B3 follow-on work.
