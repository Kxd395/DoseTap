# Sleep and naps

Version 1, DOSETAP-45. Nap review is independent of medication, main wake, alarms and session lifecycle. Each episode has a stable ID, append-only reviewed revisions and explicit planned/unplanned/unknown status. Legacy timer events remain source records; ambiguous or incomplete pairs stay unresolved.

Rest-window elapsed minutes, patient-estimated asleep minutes and provider-observed asleep minutes are separate measures. Duration-only reports have a reviewed calendar date but no invented clock position. Estimated duration is attributed to the episode start date, never proportionally allocated across midnight. Timed rest windows may be clipped for a selected local day; 23/25-hour DST days are labeled calendar days. Episode counts use the start date and count once.

Day review distinguishes unreviewed, partial, all naps reviewed and explicitly no naps. Confirmed no naps with any episode evidence is a conflict, not zero. Overlapping independently identified episodes require review and are excluded from duration totals until explicitly reconciled as the same episode. Manual and provider observations checked for the same reviewed episode share one ID and never add two counts or combine estimates with measured sleep.

Provider checks use the existing sleep-evidence resolver inside the explicit reviewed nap window. Unknown/conflicting time remains unknown; no sleep stages or nap episodes are inferred from totals. Results are transient, checked against current local records and provider access, and invalidated on source change. Main reviewed-window coverage uses the existing reviewed-night loader and stays distinct from nap windows and primary-episode totals.

Charts, exact table and CSV derive from one selected-range projection with explicit source/definition/as-of and missing/overlap counts. Revisions preserve prior inputs. Clear All includes this ledger; exports include raw review records. No unscheduled medication action occurs.

Optional benefit is an explicitly entered custom 0–10 self-report (0 no benefit, 10 greatest perceived benefit), never a default, named instrument or clinical score. Nap-end-to-dose intervals require a selected actual administration record, matching durable dose-session identity, known actual nap end and ordered finite occurrence timestamps; no proximity pairing or dosing recommendation is generated.

A reviewed timer association stores the SHA-256 digest of the exact source snapshot reviewed. Changed or missing source events mark the derived episode as requiring review, invalidate completed-day evidence, and exclude its duration/provider interval until explicitly re-reviewed. The derived flag is not persisted as a new source record. Removing a source association requires an explicit reason.

The local `nap_diary` singleton stores a validated append-only ledger with revision compare-and-swap in a checked SQLite transaction. A failed or malformed read is an error, never an empty diary. Payload dates use Foundation seconds since 2001; raw snapshot/archive transport preserves that encoding. No provider result is persisted in the diary.

`SessionRepository.reviewedNapEpisodes(asOf:defaultTimeZoneID:)` is the shared local reader. It reconstructs timer evidence from one raw marker snapshot in each persisted episode's original timezone, so travel alone does not invalidate its source digest. New, unreviewed timer episodes use the requested default timezone. Consumers must preserve `sourceNeedsReview`, duplicate association and unknown boundaries instead of creating replacement nap records.
