# Independent daytime diary

- One stable observation ID owns append-only revisions; a retry of an identical revision is idempotent, while a reused revision ID with changed data fails. Corrections name their predecessor and reason; stale concurrent corrections fail.
- Instrument `dosetap.custom-current-sleepiness`, version 1, English content `custom-0-10-v1` is separate from morning/night ratings and KSS/ESS/NSS. No score is preselected. Answered requires an integer 0–10; incomplete, unsure and skipped have no score. No conversion or clinical score is calculated.
- Assessed-at is the time explicitly recorded for the observation; recorded-at is submission time. Current entries use the actual rating time, even after a delayed prompt. Remembered entries are explicitly retrospective. UTC instants, named timezone and matching offset are preserved. The custom current diary has a point recall window, not a borrowed licensed-scale recall period.
- Optional activity, work setting and explicitly reported coping purpose remain independent. Coping actions require Yes. Notes are limited to 2,000 characters and are never included in diagnostic logs.
- Every observation is independent of nighttime sessions. Saving, correcting and reading never records medication, changes dose alarms or creates a night. Failed reads block editing; failed writes keep the exact revision for retry and never show success.
- SQLite stores original and corrected payloads; readback validates all payloads and revision chains. Clear All Data removes this ledger. Reports consume current revisions while preserving original provenance.
- Routine reminders, prompt history, linked event-interval review, formal instruments and physical-device/owner/privacy acceptance remain separate work.
