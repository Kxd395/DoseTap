# Reviewed dose/sleep metrics v1

DOSETAP-57 bounded consumer of the DOSETAP-56 reviewed-night projection. Derivation: `reviewed_dose_sleep_v1`. The [measurement addendum](../../plans/2026-09-09-sleep-timing-calculation-addendum.md) remains the broader design contract.

The separate [awakening-count implementation contract](reviewed-awakening-counts.md) defines the next slice. Its counts and consumer migration are not implemented by the duration/inspection behavior documented here.

## Inputs and ownership

Use canonical explicit dose events and the fresh, locally revalidated `ReviewedNightSleepProjection` from the repository loader. Preserve the reviewed window, its stable session identity, generation time, projection/evidence versions and original evidence alongside results. No medication, questionnaire, provider or preference writes occur. Local changes, disabled Health access, cancellation, failed reads, changed bounds and stale asynchronous results invalidate the entire displayed result using the existing loader/view lifecycle. Refresh queries can remove prior observations; no cached successful metric survives an unsuccessful refresh.

WHOOP stage aggregates, manual quick-log taps, alarm callbacks and final-wake estimates are not interval evidence for this first consumer. Apple Health consensus may include multiple Health source apps; its raw provenance remains with the checked evidence, not a claimed new public export.

## Durations and boundary rules

| Metric | Required observed boundaries |
| --- | --- |
| Dose 1 to initial sleep | One explicit Dose 1 at/before the first observed awake→asleep transition; uninterrupted observed awake coverage from window start to that initial onset |
| Awakening to Dose 2 | An observed asleep→awake transition starting the awake band containing Dose 2 |
| Dose 2 to return to sleep | That same awake episode and an immediately adjacent observed return to asleep |
| Whole Dose 2 awakening | The same awakening and return, never a sum across disconnected episodes |

Use absolute elapsed seconds and retain exact endpoints; do not repair ordering by adding a day. Bands are half-open. An explicit dose exactly at an observed return is associated with the immediately preceding awake episode and can yield zero post-dose delay. One second after return is already-asleep conflict. A dose exactly at observed awakening can yield zero pre-dose delay. Continuous asleep coverage across a dose is a conflict, never zero latency.

Initial asleep coverage already in progress at the reviewed start does not establish initial onset. Earlier sleep before Dose 1 is a conflict rather than permission to select a later sleep block. Any unknown/conflicting prefix prevents identifying the initial sleep, even with high overall coverage. For Dose 2, an awake band without preceding observed sleep cannot establish an overnight awakening. A known awakening before Dose 2 can retain a valid pre-dose duration when its eventual return is missing; post-dose/whole values remain missing. Gaps or conflicts between Dose 2 and a candidate return block those values. Unrelated gaps elsewhere do not erase a locally resolved Dose 2 episode.

## Representation and presentation

Each metric has `available`, `missing` or `conflict` status; a machine-readable reason when unavailable; optional absolute start/end and elapsed seconds only when available. Reasons distinguish missing dose, invalid dose records, invalid projection, already asleep, boundary gap, conflicting evidence, missing initial onset, missing awakening and missing return. Retain endpoint source (`recordedDose` or `appleHealthConsensus`), session identity, generation time and derivation versions in the result. Numeric zero is reserved for a resolved exact boundary. Positive durations below one second display as `<1 sec`, never rounded to zero. Endpoint labels identify the display timezone and per-endpoint abbreviation.

Show all four rows under the optional reviewed Apple Health coverage check, with human-readable missing/conflict reasons. The containing view shows source, coverage and checked time; available rows expose both endpoint times. No SQL migration, automatic backfill, new collection, dashboard average, export/Studio metric adoption or awakening-count display is included in this slice. Existing manual evidence and all quick logs remain intact.

## Required evidence

Core tests cover 8 minutes awake before Dose 2 + 14 after = 22 total; exact and ±1-second boundaries; missing/skipped doses; conflicting/duplicate/reversed dose records; stage splits and reordered samples; already-asleep coverage; missing initial onset; missing return; known-zero versus missing; partial coverage and local boundary gaps/conflicts; corrected dose/provider deletion refresh; absolute time across midnight/DST. Loader integration verifies the same snapshot supplies doses and provider bands and that stale/failed results have no metrics. Native simulator evidence exercises available and unavailable rows; physical/provider, owner-observed and accessibility acceptance remain open unless separately recorded.

## Timeline selected-night inspection (build 48)

Timeline Review offers Check dose and sleep timing and Review night window. The check is read-only and uses the same repository loader as Wake & Next Day. Missing or invalid saved bounds require review; the chart range is never silently saved as a reviewed window. The existing stage chart remains separate and unchanged.

A resolved awakening displays observed awake start, recorded Dose 2, and observed return (or an explicit missing return). Existing four metric rows retain their strict missingness/conflict semantics. Matching quick logs are timed context only, not interval boundaries or inferred causes. Original Health samples touching the episode boundaries are inspectable with stage, original timestamps, source app and available device metadata. When no episode resolves, inspect the reviewed window's samples without claiming a match. No alarm-event history is invented or implied complete.

Clearing or refreshing immediately removes the old result. Night switches, local repository changes, Health preference changes, disappearance and backgrounding invalidate pending requests. A late response cannot replace another night's result. Results are not included in the existing capture/share path, persisted, or exported by this slice. Provider edits require another check; query time is visible. No initial-onset rule, HRV model, legacy normalization, dose record, alarm, questionnaire or preference is changed.
