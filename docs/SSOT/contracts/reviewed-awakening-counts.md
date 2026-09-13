# Reviewed awakening counts: implementation contract

Status: Defined for the next DOSETAP-57 implementation; no count calculator or UI delivered by this document
Date: 2026-09-12
Proposed derivation identifier: `reviewed_awakening_count_v1`

This refines the accepted [sleep measurement addendum](../../plans/2026-09-09-sleep-timing-calculation-addendum.md). The existing [dose/sleep durations and Timeline inspection](reviewed-dose-sleep-metrics.md) remain implemented behavior. This contract defines a separate count of **observed wake-and-return episodes within a reviewed window**, not all physiological awakenings or a medication-effectiveness measure. Owner measurement-contract acceptance remains open.

## Inputs and source ownership

Use the current `ReviewedNightSleepProjection` from the existing checked repository loader, together with the canonical dose snapshot from that same check. For the manual/provider comparison below, the future checked result must also expose the optional `NightOutcomeDiary.finalWakeAt` and its existing outcome submission/revision provenance, decoded from the same matching `outcomeJSON` snapshot already rechecked by the loader. Preserve missing values/provenance as absent; do not query another night or read a separate current preference. The current `ReviewedNightSleepResult` does not expose this manual-wake input, so extending that typed result is an explicit implementation prerequisite, not existing behavior. Any change to the source outcome invalidates the count/comparison just as it invalidates the existing provider check.

Preserve stable session identity, reviewed absolute bounds, generation time, projection/evidence/count derivation versions and original evidence. A calendar date, open-session lifetime, planned wake time or chart extent cannot supply reviewed bounds.

The first implementation consumes Apple Health consensus bands only. WHOOP disturbance totals, questionnaire awakening buckets, brief-wake/bathroom logs, alarm delivery and dose taps cannot supply sleep transitions. Apple Health may contain samples from several source apps; retain the checked snapshot's source detail. Do not add source-app counts together or choose a source merely because it produces fewer awakenings. WHOOP aggregates remain separate unless a future reviewed interval contract establishes compatible boundaries.

The calculator is read-only and platform independent. Views use the repository loader; it owns the coherent local/provider snapshot. The current loader rejects invalid/contradictory dose evidence at local assessment before querying Health. Preserve that fail-closed boundary: pure provider-count independence does not authorize UI to bypass a `needsReview` assessment or reuse an old projection. Any future decoupled provider-only review needs separate design and validation. No new medication ledger, SQL table, questionnaire answer, provider write, recurring preference or alarm action is part of counting. Refresh, cancellation, failed reads and local/provider corrections follow the existing invalidation contract; a previously successful count cannot survive a failed refresh as current evidence.

## What counts once

1. Use finite, ordered, half-open bands `[start,end)` already clipped to the reviewed window. Validate that they partition the window without overlaps or omitted gaps. Reject invalid/mismatched projections; do not patch their dates or silently drop malformed bands.
2. Coalesce exactly adjacent bands of the same resolved state. Stage changes, repeated samples, source labels and sample boundaries do not split a continuous awake band. Preserve raw observations alongside the projection.
3. One **completed episode** is a maximal awake band with an immediately adjacent resolved asleep band on both sides: `asleep → awake → asleep`. Its awake start and return are the two transition instants. Count it once, regardless of its length or whether Dose 2 occurs inside it.
4. Do not bridge an unmeasured or conflicting band, however brief. A gap is not an awake interval, a return, or evidence of one continuous episode. The current consensus policy can leave conflicting sleep stages unmeasured; the counter must not override that policy.
5. Introduce no minimum awake/sleep duration, smoothing tolerance or rounding threshold in v1. A positive resolved band qualifies under the same boundary rules. Preserve absolute precision; display rounding never decides membership. Any later duration rule requires a new version and separate review.

An asleep band already present at the window start can support a later awakening. It does not establish initial sleep onset or repair a missing Dose 1-to-sleep duration. A fully observed all-awake window has zero completed wake-and-return episodes, accompanied by **No sleep observed in this window**; it does not establish normal sleep or zero physiological awakenings.

## Incomplete evidence and final waking

Keep incomplete awake bands inspectable with independently present start/return evidence:

| Boundaries around the awake band | Classification |
| --- | --- |
| Asleep immediately before and after | Completed wake-and-return episode |
| Asleep before; window end, gap or conflict after | Awakening observed; return not observed |
| Window start, gap or conflict before; asleep after | Return observed; awakening start not observed |
| Neither boundary observed | Awake coverage without a resolved awakening or return |

These incomplete bands are not additional completed episodes. Do not describe their count as the number of missed awakenings. Two awake bands separated by a gap may be portions of the same episode; their relationship remains unknown.

Trailing `asleep → awake → window end` is an awakening without an observed return. It is excluded from the completed count even when awake coverage reaches the window end. The window end is an observation boundary, not proof that the person stayed awake afterward. Keep a provider final-wake estimate, explicit manual final wake, and out-of-bed time separately labeled. Do not turn a terminal band into a confirmed final-wake answer or use an answer to invent provider sleep.

Manual final wake before later observed sleep requires visible review. Provider episode facts can remain inspectable, but a combined whole-night interpretation and aggregate eligibility stay unresolved until the disagreement is addressed. Do not clip away later sleep or rewrite either source to force agreement. A separately identified overlapping nap/window conflict continues to block the existing loader's checked result.

## Whole-window count versus observed portions

The proposed result must distinguish the following concepts; these are logical fields, not an implemented archive schema:

| Value | Required semantics |
| --- | --- |
| `observedCompletedEpisodeCount` and episode list | Number of locally complete sequences found in usable bands, including when evidence elsewhere is partial; count absent for invalid projection or no resolved asleep/awake evidence |
| `wholeWindowCount` | Optional exact count of these observed sequences across the full reviewed window; present only for valid, fully classified, conflict-free coverage |
| `status` and reasons | `available`, `partial`, `missing` or `conflict`; distinguish no classified evidence, window gap, source conflict and invalid projection |
| Coverage | Reviewed duration, resolved asleep/awake duration, unmeasured duration and conflict duration; conflict is a subset of unmeasured, never added twice |
| Incomplete boundaries | Original awake band endpoints plus separate observed-start/observed-return flags and reasons; do not fill missing transition times |

Precedence for whole-window status is invalid/unresolved conflict → `conflict`; no resolved asleep/awake coverage → `missing`; any other unmeasured coverage → `partial`; otherwise → `available`. Invalid projections produce no episode list or observed count. A valid projection containing localized source conflicts may retain locally resolved episodes. Whole-window count is absent in the first three states. An empty successful query is missing, not pending sync or zero. Pending sync requires an actual in-flight operation.

A complete window with no completed episodes can carry numeric zero, including when sleep spans the entire window or a terminal awakening has no return. In those cases label exactly what was observed. A partial window with no locally completed episode must say **No complete episode observed; total unavailable**, not display a bare zero. Nonzero partial evidence can say **2 observed wake-and-return episodes · total unavailable because coverage has gaps**. Complete-window wording still describes provider observations, not undetected brief awakenings.

## Dose 2 membership

Medication timing uses the explicit actual occurrence, never the alarm target, recording timestamp or check-in time. Missing, skipped, unknown-time or invalid Dose 2 cannot be substituted with another event. They leave Dose 2 subsets unavailable while an otherwise usable provider-only count remains independent.

- **Episodes starting at or after Dose 2:** completed episodes with `awakeStart >= dose2`. For an exact subset total, require complete conflict-free coverage from Dose 2 through the reviewed end. Inspect evidence before Dose 2 only when needed to establish the awakening boundary of a band whose awake start equals Dose 2. A dose inside an earlier awake band or exactly at its return does not make that episode eligible for this subset; an earlier gap affecting that separate association must not erase an otherwise resolved later subset. Apply the same available/partial/missing/conflict distinctions to the relevant range and any required predecessor boundary.
- **Episode spanning Dose 2:** `awakeStart < dose2 < return`. Show it separately; its onset predates Dose 2, so it does not also enter the starting-at-or-after subset.
- **Dose exactly at awake start:** the episode enters the starting-at-or-after subset. Label the dose association as an exact-start match, not an additional spanning episode.
- **Dose exactly at observed return:** retain the existing duration contract's association with the preceding episode and genuine zero post-dose delay. Label an exact-return match; this episode does not enter the starting-at-or-after subset or a strict spanning subset.
- **Dose within continuous asleep coverage:** no associated awake episode. Preserve the duration conflict; do not invent an awakening or zero return delay. Later completed episodes can still contribute to a separately usable post-dose subset.

Association details and subset counts are different views of the same episodes, not values to add together. An incomplete Dose 2 awakening can retain the existing valid pre-dose duration; it contributes no completed episode until its adjacent return is observed. If approximate timing cannot establish boundary order, Dose 2 membership is unresolved. Do not force an exact-time classification from display precision.

## Display, aggregation and export adoption

The first display belongs with the reviewed check and its checked time, reviewed range, source, coverage and existing four duration rows. Use **Observed wake-and-return episodes**, **Starting at or after Dose 2**, and a separate **Awake episode around Dose 2** detail. Preserve Apple Health stage bands and every quick log. A timed bathroom/alarm log can provide context but cannot prove the cause or full duration of an awake episode.

For an eventual mean/median, use one fresh result per stable session identity and the same derivation/source/window population. Each metric gets its own usable denominator. Report included sessions and exclusions for missing, partial, conflicting, no-observed-sleep and unresolved manual-final-wake disagreement. Require observed sleep for sleep-night comparisons; an all-awake window's valid zero remains a review fact but is excluded from that comparison. Dose 2 comparisons additionally require a usable taken-dose occurrence and resolved membership; a confirmed skip is not an unknown wake type. Work/off groups require their separately reviewed schedule contract. Never average log counts, WHOOP disturbances and reviewed Health episodes together.

Existing `healthKit.wakeCount`, WHOOP disturbance counts and old numeric archives keep their original meanings. The new metric requires a distinct additive versioned representation with status/reasons, bounds, generation time, coverage, episode endpoints and per-metric denominators. Absence in older archives means not captured. Recompute current results after corrections; saved reports retain their generation/version context. Define privacy/redaction and strict writer/Studio validation before exporting the new representation. Do not silently relabel a legacy number or imply full backup/recovery.

## Required implementation fixtures

These are acceptance specifications, **not tests run by this documentation slice**. `S`, `A`, `U`, `C` mean resolved asleep, awake, unmeasured and conflict; adjacent letters have touching endpoints unless stated otherwise.

| Input / change | Required result |
| --- | --- |
| `S A S`; wake 02:40, Dose 2 02:48, return 03:02 | One completed episode, zero starting at/after Dose 2, one spanning match; existing durations 8 + 14 = 22 minutes |
| Split that awake band into adjacent source samples; duplicate/reorder raw samples | Same one episode after projection, unchanged endpoints and count |
| `S A S A S`, Dose 2 at the second awake start | Two total; one starting at/after Dose 2; exact-start match; no strict spanning match |
| Dose exactly at return, and one second either side | Exact-return association with zero delay; before belongs to spanning episode; after is already-asleep conflict, never an extra count |
| `S A U S`, `S U A S`, or `S A C S` | No completed episode across that boundary; preserve incomplete evidence and missing/partial/conflict reason |
| `U S A S` with an unrelated earlier gap | One locally completed episode; whole total absent; a fully observed post-dose range can have its own usable subset |
| `U A S A S`, Dose 2 inside the first awake band, classified coverage thereafter | Later completed episode gives a usable starting-at-or-after subset of one; first band is excluded despite its unresolved awakening start |
| `S U A S`, Dose 2 exactly at awake-band start | Predecessor gap leaves awakening start unresolved; exact subset unavailable, not a confirmed post-dose awakening or zero |
| `S A` through window end | Zero completed episodes for complete coverage; one observed awakening without return; no automatic final-wake confirmation |
| `A S` from window start | Initial awake band contributes no awakening; zero completed episodes for complete coverage |
| Fully observed `S`, or fully observed `A` | Zero completed episodes with distinct sleep/all-awake explanations; no initial onset inferred from left clipping |
| Empty query; in-bed/unknown-only observations; invalid bounds/bands | Missing or conflict as applicable; whole count absent, no fabricated zero |
| Long-separated sleep blocks with a fully observed awake interval between | One completed episode; no 90-minute cluster truncation inside reviewed bounds |
| Several quick logs inside one awake band | Still one completed episode; retain all logs, no inferred cause |
| Missing/skipped Dose 2; dose time unknown | Pure calculator preserves usable provider-only facts; dependent dose subsets unavailable with distinct reasons; no new unknown-time storage state is introduced |
| Duplicate/reversed taken records | Existing loader returns needsReview without querying/publishing counts; no stale projection reuse or implicit decoupling |
| Manual final wake before later sleep; overlapping nap/window | Review conflict; no silent clipping or aggregate inclusion |
| Midnight, DST repeated hour, travel | Absolute ordering/count unchanged; display zone/offset labels remain explicit |
| Source deletion/correction, dose edit, window edit, night switch or late callback | Invalidate and recompute from one fresh matching snapshot; no stale count publication or medication/alarm writes |
| New archive, old archive, malformed/future count version; redacted report | Exact writer/import/report semantics; missing stays missing; unsupported values are not silently interpreted as v1 |

## Delivery sequence and open gates

1. Implement the pure versioned calculator and failing-first core fixtures for the rules above. Extend the checked loader result with the same-snapshot optional manual final wake and available outcome provenance; test missing values, edits/removal, wrong identities and stale callbacks. Reuse the existing projection and dose validation; do not replace the working duration calculator.
2. Wire the existing loader and one reviewed UI surface with native normal/large-text evidence, followed by VoiceOver and owner-night/provider comparison. Inspect exact endpoints and raw source evidence on the same night.
3. Adopt the shared result in remaining charts, History, dashboard and Settings/Studio with explicit legacy labels, writer/import parity and privacy review. Keep cross-consumer acceptance open until all intended surfaces agree.

This documentation closes the missing engineering definition only. Implementation, owner approval of measurement wording, signed-phone/provider parity, full accessibility, privacy/security and release acceptance remain open in Plane. No build increment is required for these documents; the verified source baseline is 0.4.19 (55).
