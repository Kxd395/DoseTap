# Independent medication history and export verification

Date: 2026-09-26 · Plane: DOSETAP-74 · Candidate: 0.4.19 (73)

## Confirmed problem

The owner reported a saved daytime medication missing from History. A scoped,
read-only inspection of the connected phone found build71 and a durable quick-log
record. The copied SQLite database passed quick_check. No phone records were
edited, deleted or relinked. Personal database copies and generated exports stayed
outside the repository; no patient values or identifiers are included here.

History previously presented nighttime sessions only. Independent quick-log rows
had no destination there; saved-preset administrations were reachable only from
Settings preset details. This was a display/navigation gap, not demonstrated loss
of the reported administration. Build72 preset capture and the later core amendment
contract did not repair the main History destination.

## Change

History → Medication history reads all quick-log and saved-preset administrations
through SessionRepository with checked storage reads. It searches medication names,
retains separate source identities, displays occurrence and recording separately,
and keeps unknown occurrence explicit. No night is required. Reads fail visibly;
foregrounding and successful writes refresh the screen. Nighttime Dose 1/2 stay in
session history. Original offset bounds are checked before date formatting.

## Export audit

An isolated copy of the phone database was passed through the existing local
Studio bundle writer and workbook writer. The exact quick-log record ID, amount,
occurrence and recording timestamps matched Medication Log. The generated ZIP
retained the record in insights_bundle.json; ZIP and XLSX CRC checks passed and
the record appeared once in Medication Log. This is source/export evidence, not
proof of a fresh owner-operated share-sheet export or native workbook usability.
The temporary private-input test was removed before commit.

Synthetic regression covers quick-log plus saved-preset records with no night,
unknown occurrence, workbook sheet identity and archive generation. Quick logs
remain in Medication Log (and source evidence); saved-preset administrations remain
in Confirmed Medications. Preset plans themselves are not administration records.
Both ledgers are retained in ZIP insights_bundle.json. No data migration, guessed
deduplication, new dosing action or medication estimate was introduced.

## Acceptance boundaries

Native UI and repository/export regression results, integration state and final
build/install verification are recorded in the DOSETAP-74 workpad. Owner review of
the new History screen and a fresh phone export remain open, as do VoiceOver,
privacy and release acceptance. Audited Edit/Reverse integration remains separate.
