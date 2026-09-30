# Independent daytime diary

- One stable observation ID owns append-only revisions; a retry of an identical revision is idempotent, while a reused revision ID with changed data fails. Corrections name their predecessor and reason; stale concurrent corrections fail.
- Instrument `dosetap.custom-current-sleepiness`, version 1, English content `custom-0-10-v1` is separate from morning/night ratings and KSS/ESS/NSS. No score is preselected. Answered requires an integer 0–10; incomplete, unsure and skipped have no score. No conversion or clinical score is calculated.
- Assessed-at is the time explicitly recorded for the observation; recorded-at is submission time. Current entries use the actual rating time, even after a delayed prompt. Remembered entries are explicitly retrospective. UTC instants, named timezone and matching offset are preserved. The custom current diary has a point recall window, not a borrowed licensed-scale recall period.
- Optional activity, work setting and explicitly reported coping purpose remain independent. Coping actions require Yes. Notes are limited to 2,000 characters and are never included in diagnostic logs.
- Every observation is independent of nighttime sessions. Saving, correcting and reading never records medication, changes dose alarms or creates a night. Failed reads block editing; failed writes keep the exact revision for retry and never show success.
- SQLite stores original and corrected payloads; readback validates all payloads and revision chains. Clear All Data removes this ledger. Reports consume current revisions while preserving original provenance.
- Routine reminders, prompt history, formal instruments and physical-device/owner/privacy acceptance remain separate work.

## Explicit daytime events and interval review

- A separately identified daytime event records reported unplanned sleep, interrupted activity, struggling to stay awake or an unclear event. Struggling is not counted as sleep. Approximate times are labeled; unknown duration remains absent. No medication/night record is created.
- A check-in may review an explicit start/end interval as none reported, events reported, unsure or not reviewed. Event references are unique existing IDs; reviewing or reusing a reference never inserts another event. Missing/partial review is not a symptom-free day.
- Corrections preserve event identity and original evidence. Reporting counts current event IDs once, separately from reviewed intervals and observed days. No extrapolated monthly burden or full-day percentage is derived.

- Explicit nearby reporting snapshots include both independent ledgers in `daytimeDiary` as original source rows with all revisions. Consumers validate payloads and use current revisions; legacy morning/night ratings remain separate instruments. This transport does not include provider-owned health data.

## Descriptive daytime trends

Independent observations can be filtered by scheduled, discretionary, symptom-triggered or retrospective origin. Trend points use actual assessment times with no connecting state curve. Comparable groups keep six-hour local-clock bands, source timezone, work setting, instrument and origin separate; distributions and medians disclose sample and distinct-day counts. Review-submission dates do not claim full-day monitoring. Event counts come from distinct current event IDs, never linked-review counts or inferred ratings.

Scheduled entries preserve an optional immutable sampling-protocol ID supplied from the prompt schedule. Different protocols do not pool; a legacy scheduled entry with unknown protocol remains an individual prompt group. Reminder intention/anchor and actual assessment times remain separate.

Coverage unions explicit definite review intervals clipped to the report period. Dates touched by a reviewed interval and fully covered calendar days are separate; partial/uncertain review never implies a symptom-free whole day. Midnight and DST use the declared reporting timezone. Review-submission dates are separate metadata, not substitutes for interval coverage.

Report callers may request a half-open period with `includesEnd: false`; exact midnight end boundaries exclude the next date and its samples while preserving a review interval that covers the complete preceding day. Kind and coping totals count independent events and observation responses, respectively; unanswered coping stays explicit and repeated responses are never converted to unique events.

## Explicit related-source references

An observation may preserve up to 32 explicitly selected existing nap, medication-administration or main-wake references. Each reference keeps the source kind and stable ID, an optional durable revision ID, a SHA-256 semantic evidence key, original source event IDs, original calendar date/timezone when present, optional actual timestamp bounds, timestamp quality, and selection time. Legacy source revisions or boundaries remain absent; projection-generated UUIDs must not be stored as durable revisions. An estimated sleep duration is never converted into a clock boundary.

Selecting a reference does not insert another event or infer a temporal pairing. Duplicate references and reused same-kind underlying event IDs are rejected. References are immutable through response corrections and survive source changes as historical evidence; current source availability/mismatch is a separately derived state. New reference selection must validate current source evidence, exclude unresolved duplicate/changed-source nap candidates, and preserve unknown occurrence times. Work context remains a versioned derivation from the actual assessment and explicit saved shifts; no weekday inference or absent-record Off classification.
