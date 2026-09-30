# Physician review contract

Completed visits are patient-reported historical occurrences. Future, cancelled and rescheduled appointments are separate records and cannot reset the completed-visit anchor. Corrections append a revision with identity and recorded-at provenance. Invalid/future completed times fail validation.

Report periods use explicit start-inclusive/end-exclusive instants, a named timezone, a capture cutoff, and a versioned definition. Presets include 7, 28 and 90 calendar days and 6/12 calendar months; since-visit begins at the last completed occurrence, never a booking. Custom bounds must be ordered and cannot extend beyond capture. Missing visit history requires another explicit range.

Physician previews are immutable captured values. Full-period and monthly summaries retain per-metric eligible/available/unknown counts; recent 14/28-day detail complements the full period. Original units, source, instrument/content and derivation versions remain visible; incompatible versions are not pooled. Excluded or serious reports remain in the review detail appendix. Patient notes and questions are unscored; no ESS/KSS/NSS wording or inferred score is provided. Preview does not send data. Sharing requires an explicit action on the captured preview; later corrections create another snapshot.

SQLite `physician_review_records` retains completed-visit revisions and immutable previews. Failed reads block new preview creation; failed transactions publish no success. Reusing an identical revision/snapshot ID is idempotent; a conflicting payload or stale correction fails. Preview export uses protected temporary JSON and reversible formula-safe detail CSV; temporary files are removed when the share sheet closes. The snapshot retains the source-coverage disclosure, app version, query period and timezone. Monthly assessed-day denominators are clipped to the selected part of each month, independently from the full-period denominator.

The printable PDF is rendered from the same immutable report values and source details as preview/JSON/CSV. It paginates long questions and retained review detail without clipping. Unknown-time observations are retained as unplaced detail but cannot enlarge the selected-period eligible denominator.

Portable JSON explicitly names its numeric timestamp epoch (seconds since 2001-01-01T00:00:00Z) and preserves the stored precision. Recent detail uses the last included calendar day for a midnight-exclusive cutoff. Decoded periods and snapshots are revalidated before display or sharing.
