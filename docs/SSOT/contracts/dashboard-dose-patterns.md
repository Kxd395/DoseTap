# Dashboard dose-pattern evidence (DOSETAP-45)

Version 1, September 30, 2026. Pattern review is a patient report for a specific stable observation identity; it never administers medication, creates a dosing session, or changes alarms.

- Canonical administration IDs are deduplicated only when their full evidence agrees. Different IDs at the same time remain distinct and require pair review. Extra doses, conflicting slots/identities, omission plus taken, nonfinite times and nonpositive pairs require review.
- Recorded administration count, explicitly confirmed complete count, historical patient-reported plan and occurrence-time completeness are separate. A check-in or closed session alone never confirms count. An unresolved open session is in progress; a closed unresolved second outcome remains incomplete.
- An explicit complete count may report an administration whose time is unknown; preserve that reported count and keep its interval unavailable. A review that reports fewer administrations than the ledger contains requires review. Reviewed count zero without administration records is a valid no-dose report, never a medication-free claim.
- A single administration has no numerical paired interval. Dose 2 omission, missing outcome, missing occurrence and conflicting evidence have different reason codes. Never substitute skip/record/session-close time or zero for a taken event.
- A versioned metric carries optional value, state, reason and unit. Missing, not applicable, partial and needs-review remain distinct. Numeric values must be finite. Sleep measurement eligibility is independent of paired-dose eligibility.
- Review records retain revision history, recorded time and the exact input fingerprint. Changed source dose evidence invalidates a prior count confirmation until reviewed again. Actual amounts are never copied from plans.

The dashboard adapter reads the review ledgers once per complete refresh and binds each to its stable observation ID. Invalid ledger data retains the previous display and blocks saving until a complete refresh succeeds. Save rereads the current exact local identity, treatment date and canonical dose fingerprint, then applies the caller-reviewed expected revision. Provider-only observations additionally require a current provider snapshot and must still exist as independent observations. Canonical skip evidence contradicted by a review remains needs-review. Only the exact active, nonterminal session can be in progress; morning completion and closure do not confirm a dose count.

Review input fingerprints bind the stable observation identity, treatment date and canonical dose-event evidence. Provider-only fingerprints additionally bind the provider episode evidence; a corrected provider date or sleep evidence cannot silently reuse an earlier count confirmation, even when the provider episode ID stays the same. The shared `DashboardDoseReview.observationFingerprint` function defines this binding for phone and reporting consumers; raw fingerprints are not a sanitized transport field.

An explicit correction after the observation date changes can update the review ledger’s current grouping date only after current observation validation and a new, context-bound review with the prior expected revision and a correction reason. Earlier review revisions remain intact. Replaying the original review, an unchanged fingerprint, a missing reason or a stale expected revision cannot move the grouping date.

Metric construction and JSON decoding enforce the same invariant: available requires a finite value; partial may carry a finite value or remain without a numerical aggregate. Unavailable, not-applicable and needs-review do not carry a numeric value. Contradictory inputs become needs-review with no value, preserving their original reason and unit for diagnosis. An explicitly observed zero remains valid for available or partial data.

## Shared inspection state

Dashboard routes preserve one selected stable observation ID, dose-pattern filter, work-phase filter and work-context basis, context stratum filter, and explicit partial-metric inclusion. Range, timezone, source and reporting as-of remain model-owned. Refresh and filtering never silently replace a selected observation. Each view distinguishes a visible selection, a selection excluded by its current filters/range, and an observation no longer available; clearing selection is explicit. Resetting filters preserves the selected observation and work-context basis. A filter unsupported by a view is disclosed rather than silently applied to a different grain.

## Read-only nearby review transfer

A nearby report may carry a versioned, sanitized local dose-review sidecar. The
producer rechecks exact canonical session identity and the complete current dose
evidence inside its report transaction. Stale, unresolved and provider-only reviews
are omitted. Count, plan, explicit omission, revision and source record IDs remain
separate from administrations; the private source fingerprint never travels.
Missing sidecars mean no review supplied, not zero administrations. The receiving
iPad preserves report source/generation/capture and cannot write the phone ledger.

## Sleep & Dose Pattern consumer

- By date, category comparison and paired-interval modes share the selected provider and sleep definition. Total main-episode sleep is independent of count/spacing; post-Dose-2 sleep requires a usable Dose 2 and compatible Apple Health intervals. Missing values are not points at zero.
- Neutral count symbols are circle/two, square/one, triangle/confirmed zero and diamond/unresolved or review. Categories remain text-labeled; a count view does not inherit the old spacing-reference symbol legend. Comparisons show observed counts, median and middle-50% spread without treatment recommendations.
- Numeric paired spacing and its categorical unpaired companion share the sleep scale, with separate x-axis meanings. Exact selectable tables retain missing sleep and incomplete history. Same-date candidates remain separate; detail navigation and refresh retain observation identity.
- Post-Dose-2 sleep exposes metric state/reason, endpoint basis and covered/elapsed-window minutes. Patient-reported final awakening and provider last observed sleep end remain different comparison strata. Any unmeasured interval is partial; observed all-awake coverage can be zero sleep. Partial values remain inspectable but are excluded from comparison summaries by default, with a visible inclusion choice. Provider main-episode totals do not certify complete reviewed-night coverage.
- A review form captures source fingerprint and expected review revision on opening. Count/plan/omission start unanswered unless an unchanged saved review supplies them. Corrections require a reason; stale or failed writes preserve the editable form and expose failure. Saving a report never fabricates an administration timestamp or amount.
- The live morning flow reads exact-session reviews locally, with provider queries disabled even after saving. It offers unresolved one-log count/plan review, suppresses unchanged complete reports and explicit omissions, and keeps already selected medication actions visible. Historical morning questionnaires do not open this live review or change medication records.
