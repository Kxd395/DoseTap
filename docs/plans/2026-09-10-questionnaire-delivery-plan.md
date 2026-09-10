# Questionnaire revision delivery plan

Date: 2026-09-10
Planning owner: DOSETAP-69. Plane owns live priority and completion.
Implementation baseline: `5e34032207d8410a99587b98922d024143163aa6`, app 0.4.19 (39).
Status: Accepted delivery constraints and staged plan, not a claim that the replacement questionnaire ships.

## Decision

Retain the [supplied revision](../review/2026-09-10-dosetap-questionnaire-revision.md) as design input. This plan qualifies its scope and sequencing. Current behavior remains in [SSOT](../SSOT/README.md); the [collection inventory](../review/2026-09-10-sleep-questionnaire-review.md) and [independent findings](../review/2026-09-10-questionnaire-independent-findings.md) describe the reviewed build, not the future form.

Keep Apple Health sleep detail, quick logs, both questionnaires, explicit Dose 2 wake selection and correction history. Improve integrity and completion before adding questions. Recurring back and foot patterns must remain separate; saving a reusable description must not assert that either symptom occurred tonight.

The first code slice under DOSETAP-67 removes selected-by-default medication reconciliation and tests unchanged-ledger saves. It is not the full independent medication editor, draft system, recurring-symptom redesign or proof that the owner's reminder bug is resolved on a phone.

## Clarifications that govern implementation

### Completion and reminders are separate from answer completeness

The revision's phrase "saved incomplete" must not become another repeated check-in banner. Proposed states:

| Action | Durable meaning | Completion reminder |
| --- | --- | --- |
| Save check-in | User submitted the answered fields; optional fields stay unanswered | Stop for that exact treatment night |
| Save draft | In-progress answers, not a submitted check-in | Resume affordance; any reminder follows an explicit reminder policy |
| Skip check-in | Explicit questionnaire disposition, not a missed medication or negative symptom answer | Stop for that exact treatment night |
| Cancel/discard | No new submission or disposition | Prior durable state remains |
| Failed write | No success state; retain answers and retry identity | Do not falsely mark submitted or skipped |

Persist disposition and completeness separately. A required-field validation error names the field before saving; optional blanks do not block submission. A completion receipt identifies the night and saved action. Draft/skip storage, migration, reminder scheduling and relaunch behavior need tests before these actions ship. They are not implemented by the default repair.

### Identity and timing

- Associate questionnaires and observations with the stable treatment-session identity. A civil night key is grouping, not identity; the provider's primary sleep episode is not a replacement identity.
- Define pre-dose questionnaire and next-night-only preference association explicitly, including naps, shift-work sleep and multiple sessions on one date. Do not consume a one-night preference on opening a form or crossing midnight.
- Keep intended bedtime, reported sleep onset, provider-estimated onset, final awakening, observation end and out-of-bed time distinct. Label source, certainty and derivation version. Elapsed time after a dose is not measured sleep.
- If a dose falls inside a provider-asleep segment, retain a conflict/unresolved onset. Unknown final wake must not force a fabricated time to save sleepiness. Contradictory reports can be retained separately for review, but cannot produce negative or falsely precise derived durations. These require a versioned validation/model change before UI relaxation.

### Recurring symptoms without nightly re-entry

- Use a stable pattern UUID, optional name, location, side and sensations. Two different patterns may share location/side. Preserve old location-keyed observations; do not silently merge them during migration.
- Default the explicit "Save as recurring" action to reuse until paused. Offer next-treatment-night-only as an advanced option. Choose Bedtime, Morning or Both when managing the pattern, not every night.
- Show each enabled pattern automatically, with current presence and intensity unanswered. An explicit "Same as last confirmed" action displays that pattern's prior date/values first. Never bulk-confirm all nightly outcomes.
- Separate present/absent/unsure/unanswered from intensity. Numbness or pins and needles can be present with pain explicitly zero. Overnight occurrence and current morning presence are different observations.
- Pausing a prompt does not mean recovery. Historical editing does not change future preferences without a separate explicit action. Preferences and observations have independent revision histories.

### Medication and independent saves

The target design uses a visibly separate medication-record action with its own reviewed time, amount, session identity, confirmation and receipt. Questionnaire Save must not serve as medication confirmation. Keep retrospective recording available through the existing reviewed History flow.

The first repair only removes implicit selection and preserves untouched ledger evidence. Existing explicitly selected reconciliation remains until the independent action is implemented and verified. Synthetic suggested times and amounts must not be represented as confirmed facts. Unknown occurrence time needs a separate report contract, not a fake exact medication timestamp.

Use the existing dose ledger, shared wake diary, intake history and schedule owners. Do not create duplicate morning-only sources. Independently saved records survive cancelling a questionnaire, with visible wording stating what was already saved. Dirty-dismiss protection must cover back, swipe, navigation and interruption.

### Questions and clinical scope

Keep Natural and Alarm as the prominent mutually exclusive Dose 2 choices; additional options belong under More. Backup alarm remains independent. Add another-person wake only through a versioned cross-screen/export contract, not a local-only enum change.

Companion/pet and planned-versus-actual sleep-location fields are optional proposals, not established owner requirements. Confirm their usefulness and privacy defaults before adding them. No observer is not a negative breathing observation.

Broader medication management conflicts with the current XYWAV-only shipping scope. It requires an explicit product/constitution decision. Expanded clinical-response questions require reviewed wording and response handling before release. This plan does not approve clinical messages, introduce diagnoses, calculate alcohol clearance or provide driving clearance.

## Delivery order and existing owners

Do not reopen DOSETAP-68: it delivered the review packet. DOSETAP-69 owns this scoping record, not completion of the work below. Read each live item before claiming implementation.

| Order | Scope | Existing owner | Required proof |
| --- | --- | --- | --- |
| 1 | IR-01 missing-dose defaults; preserve existing dose evidence on ordinary Save | DOSETAP-67, related DOSETAP-46 | Empty, Dose-1-only, taken/skipped ledgers unchanged; explicit entry still works; failure/retry |
| 2 | IR-03 non-pain symptom save; IR-05 hidden headache state | DOSETAP-61/67 | Headache-only, reflux-only, stiffness-only save; deselection clears only active observation/calculation |
| 3 | IR-02/04 fresh answers and honest units | DOSETAP-51/52 | Every legacy load path; unknown quantities/times remain unknown; no volume-to-mass reinterpretation |
| 4 | IR-06/07 explicit save/dismiss and Dose 2 applicability; submission/draft/skip contract | DOSETAP-67/49, history DOSETAP-47 | Relaunch, independent save then cancel, exact-night reminders, failed writes, corrected dose applicability |
| 5 | Shared recurring patterns, IR-08, nonpainful sensory observations | DOSETAP-61 | Bedtime/morning reuse; UUID migration; same-area coexistence; absent tonight preserves pattern |
| 6 | Dose/sleep/wake markers and independently timed daytime observations | DOSETAP-56/57/58 | Preserve provider stages, source/conflicts/counts; no invented onset; no overwritten repeated observations |
| 7 | Intake review and activity-time readout | DOSETAP-53/54/60 | Later snack invalidates prior review; fresh alcohol status; approved independent activity messaging |
| 8 | Optional companion context, broader clinical additions | Product decision under this plan before new exact item | Demonstrated need, privacy, model ownership and clinical scope agreed first |

Export/history/accessibility are part of each slice, not deferred until the end. DOSETAP-13/45/59 retain export, analytics and clinician-report ownership. The Foodnoms prototype remains separate under DOSETAP-55; no photo/AI subsystem is required for these repairs.

## Data ownership and missing contracts

| Data family | Canonical owner | Required change before new collection ships |
| --- | --- | --- |
| Medication administration | Existing dose ledger | Explicit independent action, session-bound consent; no questionnaire-derived administration |
| Morning answers and completion | Morning storage/submissions | Versioned answer provenance plus durable submission/draft/skip disposition |
| Recurring symptoms | Existing pattern preferences, extended | Stable pattern ID and phase/scope; separate confirmed per-night observations |
| Dose 2 wake/final wake/sleepiness | Shared night-outcome diary | Applicability and missingness; preserve manual/provider distinctions; new enum versioning |
| Repeated daytime observations | Planned independent event stream | Occurrence/assessment/entry times, optional session link and revisions, not diary overwrites |
| Food and drink | Planned shared intake history | Finished/captured/entered times, units and confirmation; later-intake reconciliation |
| Work and planned activity | Work schedule plus separately planned activity record | Schedule is not actual activity; absolute elapsed time and zone provenance |
| Provider sleep and derived metrics | Existing HealthKit evidence/shared timing layer | Reviewed window, coverage, provenance, derivation version and cross-screen parity |

For each new field, specify: stable field ID, question/choices/scale anchors, applicability, unanswered/unknown/explicit-none semantics, source of confirmation, occurrence and entry time, recurrence policy, correction policy, schema migration, History editor, raw export key, redaction and analytic denominator. Add these to the maintained data dictionary before implementing that slice. Historical defaults cannot be relabeled as confirmed answers.

## Acceptance and handoff

### September 10 symptom-repair slice

DOSETAP-67 implements IR-03/05 in build 41: Physical Symptoms no longer requires a separate localized pain entry; disabled headache fields are omitted from newly saved/edited answers and cannot inflate the current burden. Empty localized-pain lists do not save default type/intensity. Existing pain-editor validation and unrelated answers remain intact. The [symptom-repair audit](../audit/2026-09-10-morning-symptom-validation.md) records validation and open gates. Shared recurring morning patterns, broad answer freshness and durable draft/skip states remain separate planned work. This note is delivery evidence, not authority to close DOSETAP-61 or phone acceptance.

### Remaining acceptance

Use the proposal's AT-01 through AT-32 as proposed cases, with the completion clarification above overriding AT-28. Add: submitted-with-blanks stops the exact-night reminder after relaunch; explicit skip does not mutate medication; failed disposition write stays unresolved; same-date distinct sessions cannot share a completion; next-night preference is consumed only by the documented durable action.

Run storage failure/retry, migration round-trip, source-to-screen-to-export checks, offline/interrupted save and large-text/VoiceOver cases for each affected slice. Keep signed-phone, owner, provider and clinical/privacy acceptance open when unobserved. A build number or green CI does not close those gates.

Owner feedback should focus next on recurring-pattern wording and which morning questions are useful. Do not turn that feedback into an obligation to complete every optional field nightly.
