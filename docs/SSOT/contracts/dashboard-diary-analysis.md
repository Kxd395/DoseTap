# Dashboard diary analysis v1

The iPad may plot matched post-wake sleepiness against positive dose spacing or
elapsed Dose 2 to reported final wake. Use only the matched fields from this
calculator, show the independent matched count, retain a table/point detail, and
state when all ratings are identical. Plotting is descriptive: no trend fit,
causal claim, optimal interval, medication recommendation or efficacy score.

Read-only projection from one validated nearby snapshot. No provider queries,
clinical writes, inferred sleep duration, or prescribed-window classification.

Dose and questionnaire projections are constructed from the same snapshot;
source ID, revision sequence and capture time accompany the result. A dose join
requires the same treatment date and exact nonempty, non-date-placeholder identity
on both actual dose rows and the outcome record. Lifecycle identity cannot repair
NULL dose context. Existing conflict and cross-date identity rules still apply.

Valid stored sleepiness (integer 0–10, including zero) and its explicit assessment
time remain diary observations even when a dose join is unavailable. Reported
final wake remains a reported instant, not observed sleep end. Unavailable or
conflicting diary fields remain absent; unknown values never become zero.

Elapsed from Dose 2 to reported final wake requires a unique positive dose pair
and final wake at or after Dose 2. Equal instants yield zero elapsed minutes;
this does not mean zero sleep. Matched sleepiness additionally requires a final
wake and assessment at or after both Dose 2 and final wake. Missing final wake
leaves the raw timed rating visible but excludes it from the post-wake summary.
All observations must be finite and no later than recorded time and capture.

Each metric has its own eligible count, median and exclusion-reason counts over
the caller's selected questionnaire dates. Reasons use deterministic precedence:
missing/unavailable diary, missing/unusable pair, unavailable identity, identity
mismatch, missing final wake, final wake before Dose 2, then missing timed rating
or assessment before the relevant endpoints. These are evidence exclusions, not
clinical judgments. Missing diary dates are not inferred for expected nights.
Natural/alarm group comparisons and provider sleep analytics are deferred.
