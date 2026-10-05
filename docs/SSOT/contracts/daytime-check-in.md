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

## Derived daytime context

Context calculation version 1 consumes the immutable observation, a validated work-context document, an explicit planned/confirmed basis, a medication/content reference timeline and one captured as-of instant. Matching uses exact half-open shift intervals, never night phase or inferred weekdays. Shift position/cardinality, timezone, duration, local shift start and first/middle/final third form descriptive work sampling strata; stable occurrence and revision IDs remain provenance rather than splitting otherwise comparable dates. Unknown or ambiguous work evidence remains separate. Explicit diary Off work means only the reported setting at assessment, never confirmation of an entire off day.

Medication strata come from the shared context timeline and remain patient-entered label references, not verified prescriptions or evidence of administration. Missing reference context stays observation-specific. Recalculation names current source revisions without editing the submitted response; report consumers freeze these derived values at their capture time. A context-free descriptive analysis is labeled unadjusted and does not claim matched work/medication conditions.

Historical medication timezone identifiers can remain recorded even when the current OS no longer recognizes them; no local date is invented in that case. Source calendar dates require a recognized source zone. Nap links always preserve their validated saved calendar date and timezone.

## Shared dashboard presentation

The Dashboard daytime route captures the published reporting range, as-of instant, reporting timezone and exact reviewed custom/visit bounds. Updating, unpublished or mismatched selection is unavailable rather than silently replaced with an independent default. Daytime observations use civil-date bounds through that capture, not the 18:00 treatment-night grouping; night dose/work-phase filters do not filter independent observations. History retains its deliberately independent period selection.

Only revisions recorded by the captured as-of time participate. A correction saved later cannot replace an earlier report's source observation. Raw points remain visible when contextual reads fail, with an explicit unavailable-context state and no matched comparisons. The focal point chart precedes secondary filters, spans the selected period explicitly, and permits selecting an actual stored sample; empty space and gaps never generate interpolated observations.

The shared main-wake source reader accepts only validated `NightOutcomeDiary.finalWakeAt` tied to the strict history snapshot's stable session ID. Its semantic revision fingerprints that ID and reported wake instant, so unrelated rating edits do not invalidate a wake anchor. Captured reads use the latest recorded revision at or before as-of; a cleared wake is absent. Nap endpoints, session closure, provider endpoints and questionnaire submission time never substitute for a reported main wake.

Chart selection uses a spatial tap so vertical gestures continue scrolling the list. Axis/legend type is bounded at XXX Large to retain readable dates within the plot; the exact observation table and inspection text retain the requested accessibility text size. Compact chart bounds have an exact timestamp/capture readout in the period disclosure.

### Retained daytime inspection
Dashboard owns daytime selection, overlap candidates, entry-origin and setting filters outside captured-data view recreation. Refresh, range/basis changes and navigation retain the exact observation ID. Missing, filtered and outside-period records show explicit retained-selection status; they do not select a replacement. Coincident or equally close actual points require a candidate choice. The chart also offers nearby timestamps within an eight-point horizontal marker radius, converted through the current chart domain, so visually overlapping marks remain inspectable without changing their actual coordinates. Previous/next follow deterministic actual-time/ID order only from a visible selected record. Reset selection and reset filters are separate actions. Chart/table mark the same selected ID; unanswered rows are inspectable in the table without inventing a plot value.

### Source-bound wake-relative context
A saved explicit main-wake source link or a scheduled prompt's saved main-wake anchor identifies the only eligible source. No reference is not-linked; unreadable references or a cleared exact source remain unavailable. Conflicting references remain ambiguous. Corrections recalculate against the same stable source ID while retaining original/current fingerprints; a wake after assessment stays unresolved. Exact elapsed seconds are retained. Descriptive definition 1 groups by half-open one-hour bands [0,3600), [3600,7200), etc., alongside protocol/work/clock/content strata; these are not clinical thresholds or physiological labels. Semantic source revision determines matched/changed status because prompt anchor times are millisecond-normalized; exact elapsed uses the current source Date and the original saved time remains provenance.

### Explicit existing-source selection and wake comparisons
- The optional source picker selects existing eligible naps, actual medication administrations, or explicitly reported main wakes; it never creates another source event or infers an effect. Preserve source ID/revision, semantic evidence, actual/unknown time precision and original nap day/timezone. Overlapping, unresolved duplicate or stale-source naps require review before linking.
- New observation links are revalidated inside the observation transaction; missing, changed or unreadable evidence rolls back the write and retains the draft. Identical committed retries and response corrections preserve historical source snapshots. Nested nap reads join the existing transaction without committing it.
- Wake comparison resolves only an explicit saved main-wake link or the original prompt anchor with matching prompt/schedule identity. Freeze source reads at the capture, retain original and current provenance and exact elapsed seconds, and never substitute a nearby wake, nap, provider endpoint or session-close time. The versioned descriptive one-hour bands remain separate from protocol/work/clock/content strata.

## Quick daily entry

The current-moment entry starts unanswered and presents direct 0–10 rating buttons
with 44-point minimum targets, a selected-state label and accessible values.
Rating then Save is sufficient. Optional context, retrospective controls, source
links and interval review are collapsed behind Add details; collapsing them never
erases a draft. No prior rating is carried forward. Unsure, skipped and incomplete
remain distinct. Correction retains its original observation time and reason.
A durable save triggers reminder reconciliation so a current observation can
satisfy its randomized window without editing its sampling origin.
