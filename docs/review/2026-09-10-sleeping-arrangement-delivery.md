# Sleeping arrangement: field guide and delivery record

Work item: DOSETAP-70. Version: 0.4.19 (44).

The owner asked for planned sleeping setup on pre-sleep page 3 and actual setup in morning check-in. This is a focused addition to the existing questionnaires, not the full replacement questionnaire proposed in the independent review.

## Pre-sleep page 3

These questions appear before exercise and naps, without opening "Add more details".

| Question | Choices |
| --- | --- |
| Who will share the sleeping space? | Alone in the room; Partner in the same bed; Partner in the room, separate beds; Another person or other people; Other arrangement; Unsure; Prefer not to answer |
| How is the space shared? | Same bed; Same room, separate sleeping spaces; Changes during the sleep period; Other; Unsure. Shown only for another person/people or another arrangement. |
| Pets in the sleeping space | No pets; On the bed; In the room, off the bed; Both or variable; Unsure |
| Where are you sleeping? | Usual bed at home; Different bed or room at home; Away from home; Other; Prefer not to answer |

Every choice starts as Not recorded and can be cleared. No names or addresses are requested. Changing to Alone clears an inapplicable shared-space detail, but does not clear an independently entered pet or location answer.

"Save as usual setup" saves a separate local preference. "Use usual sleeping setup" fills unanswered fields without replacing choices already made for this night. Forgetting the usual setup does not delete history or this night's answers. History editors do not offer these preference actions. Finish the questionnaire to save the night's plan; saving a preference alone does not submit it.

"Use room setup" now reveals page 3 and shows feedback. It preserves the existing temperature/noise/sleep-aid reuse behavior under Add more details. It does not infer a new sleeping arrangement or morning outcome from the previous night.

## Morning check-in

| Question | Choices |
| --- | --- |
| Was your sleeping arrangement the same as planned? | Same as planned; Different / enter actual setup; Unsure; Prefer not to answer; Not recorded |
| What was your actual sleeping setup? | The same arrangement, shared-space, pets and location fields, shown when Different is selected |
| Did sharing the sleeping space affect your sleep? | No noticeable effect; Helped; Disrupted; Both; Unsure; Not applicable; Not recorded |
| What helped or disrupted sleep? | Snoring or noise; Movement; Different schedules or alarms; Care responsibilities; Pets; Comfort or support; Other. Multiple selections, shown only for Helped, Disrupted or Both. |

Same as planned is available only when this exact session has a nonempty, completed pre-sleep plan. The displayed plan is saved as a snapshot with the morning answer. Without a plan, a person can enter actual setup or leave it unknown. No response is selected automatically. No new medication events, alarm actions, session timing estimates or health permissions are inferred from these answers.

If pre-sleep was saved before a session existed and no Dose 1 was logged, its date-placeholder plan can still be found when the treatment date identifies exactly one session. An explicit blank/skipped plan or an ambiguous date does not use that fallback. The lookup does not rewrite the original records.

## Persistence and reporting

Pre-sleep source JSON uses `sleepingSetup`; morning environment JSON uses `sleepingContext`, independently of the older room-environment toggle. Normalized question keys are `pre.sleeping_setup.v1` and `sleeping_context.v1`. New submissions have questionnaire version `pre_night.v3.2026-09-10` or `morning.v3.2026-09-10`; existing records are not backfilled. No SQL migration is needed.

History uses the existing reviewed correction path. Existing source/normalized exports and Studio raw-payload inspection include the fields. This slice adds no correlation score or new dashboard comparison. Usual preferences are not clinical events and do not turn CSV export into a complete backup. Sleeping context is sensitive even without names; release/privacy review remains an explicit gate.

## Validation status

Validation covers the following paths; Plane DOSETAP-70 records the final run IDs and integration state.

- Core: 699 XCTest and 43 Swift Testing cases passed, including missing-versus-unknown, conditional fields, explicit confirmation and preservation of the plan.
- App persistence: new tests cover exact-session matching, completed-plan eligibility, source/normalized exports, morning save/reopen/change, saved-plan snapshots, preference separation and failed-write retry. Existing repository/export regressions are also run.
- Simulator interaction: page-3 selections and usual setup; Tonight save/reopen; History cancel/confirm/save/restart/correction; and the existing bottle-opening regression. Largest-text journeys use a separate simulator and restore normal text afterward.
- Studio: 70 tests executed, 3 skipped, no failures. This is existing import/reporting regression coverage, not a signed-phone-to-Studio transfer claim.
- Repository: Swift build/tests, unsigned simulator build, SSOT guard, all four app/staging build identities, Plane workflow guard and whitespace check.

Off-screen ImageRenderer output was rejected as visual evidence because it does not render these native controls. Native simulator screenshots and interactions are used instead. An interrupted shared-build test was retried in an isolated DerivedData folder; interrupted attempts are not passing evidence.

Still open: signed-phone installation and owner-observed pre-sleep/morning save/reopen acceptance for build 44, VoiceOver review, and privacy/release acceptance for sensitive sleeping context. A source change or passing automated test alone does not close those gates. No phone installation or complete-backup validation is claimed.
