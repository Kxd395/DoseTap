# Independent questionnaire source and flow findings

Status: Point-in-time independent code/UX review; proposed fixes, not implemented changes
Date: 2026-09-10
Baseline: `1fc48dd9a4c37627bafdd3c3586c7190e7aca239`, app 0.4.19 (39)
Related: [Complete owner review packet](2026-09-10-sleep-questionnaire-review.md), DOSETAP-68

## Scope and independence

A separate read-only reviewer inspected the current questionnaire views, defaults, persistence and conditional flows while the main agent assembled the neutral inventory. The main agent cross-checked the key source findings. No reviewer changed application code, personal data or medication records. No new simulator or signed-phone reproduction was performed for these findings. This is not external clinical approval or a full repository audit.

P1 means prioritize for reliability, correct data or completion. P2 means flow/consistency work. References below use source line numbers at the pinned baseline; later edits can move them. None establishes the cause of the owner's historical unexpected Dose 2 record or recurring check-in message.

## IR-01: Missing doses default to taken in morning reconciliation

**P1; source-confirmed.** [MorningCheckInViewModelSupport.swift](../../ios/DoseTap/Views/MorningCheckInViewModelSupport.swift), lines 91–98, enables the missing Dose 1 toggle and chooses Taken for missing, unskipped Dose 2. Lines 178–189 provide fallback occurrence times. Lines 103–124 commit selected reconciliation actions; [MorningCheckInViewModel.swift](../../ios/DoseTap/Views/MorningCheckInViewModel.swift), lines 563–574, runs them before saving morning answers.

Impact: completing morning questions can create retrospective medication records from defaults without explicitly selecting Taken. This is a morning-submit path, not evidence of an alarm-triggered auto-log.

Proposed repair: default to unchanged/not logged, require explicit taken selection and time review, and retain intentional retrospective recording. Suggested ownership: DOSETAP-46/67 reliability follow-up; exact implementation scope must be preflighted before changes.

Acceptance: with either dose absent, completing an untouched form leaves the ledger unchanged. Explicit missed-tap recording works. Cancel, failure and retry add no unintended or duplicate dose.

## IR-02: Remembered morning settings contain yesterday's observations

**P1; source-confirmed.** [MorningCheckInViewModel.swift](../../ios/DoseTap/Views/MorningCheckInViewModel.swift), lines 189–204, defaults remembering on. Lines 789–838 restore quality, restedness, grogginess, inertia, dreams, clarity, mood, anxiety, stress, readiness and therapy use/compliance. Fallback lines 871–898 additionally restore symptom and narcolepsy-event answers. [MorningCheckInSections.swift](../../ios/DoseTap/Views/MorningCheckInSections.swift), lines 32–35, describes this as settings/setup.

Impact: yesterday's experience can be saved as today's answer without fresh confirmation.

Proposed repair: remember equipment/reference preferences and reusable symptom patterns separately. Daily answers start unanswered or remain visibly unconfirmed suggestions. Do not rewrite historical answers. Fits the remaining DOSETAP-51 freshness work.

Acceptance: seed an extreme previous morning and test both saved-settings and previous-check-in fallback. Fresh outcomes and symptom occurrence remain unanswered until confirmed; reusable setup remains available.

## IR-03: Non-pain physical symptoms can block completion

**P1; source-confirmed UI gate.** [MorningCheckInClinicalSections.swift](../../ios/DoseTap/Views/MorningCheckInClinicalSections.swift), lines 315–364, collects headache, stiffness, soreness, reflux, restlessness and bathroom urgency in the physical branch. [MorningCheckInSections.swift](../../ios/DoseTap/Views/MorningCheckInSections.swift), lines 58–59 and 94, requires a granular pain entry whenever that branch is on.

Impact: a reflux-only, urgency-only or headache-only morning cannot be submitted without adding pain or disabling the branch. This is a concrete save blocker, not proof it caused the reported phone issue.

Proposed repair: name the branch for its real scope; validate only the selected symptom. Require a complete localized-pain entry only when that entry was actually requested. Suggested follow-up: DOSETAP-67/61 scope review.

Acceptance: headache-only, reflux-only, urgency-only and stiffness-only answers save without fabricated pain. An incomplete, explicitly started pain entry gets targeted guidance.

## IR-04: Category choices create precise-looking time/amount details

**P1; source-confirmed.** [PreSleepLogBodySubstancesCard.swift](../../ios/DoseTap/Views/PreSleepLogBodySubstancesCard.swift), lines 686–688 and 473–475, fills substance times/amounts. [PreSleepLogActivityNapsCard.swift](../../ios/DoseTap/Views/PreSleepLogActivityNapsCard.swift), lines 263–346, fills exercise type/time/duration, nap count/end/duration and screen time. Final validation checks presence, but these automatic values can already satisfy it.

Impact: selecting Coffee, Light exercise or a nap group can save a precise time or amount the user never supplied. The caffeine amounts are beverage ounces, despite legacy property names.

Proposed repair: separate suggested, estimated and confirmed values; permit unknown details rather than forcing invented precision. Fits DOSETAP-51/52.

Acceptance: selecting a category alone does not establish a confirmed timestamp or quantity. Explicitly accepting an estimate preserves its certainty in storage, export and analytics.

## IR-05: Turning headache off leaves hidden migraine state affecting pain burden

**P1; source-confirmed.** [MorningCheckInClinicalSections.swift](../../ios/DoseTap/Views/MorningCheckInClinicalSections.swift), lines 315–329, hides headache fields when off. [MorningCheckInViewModel.swift](../../ios/DoseTap/Views/MorningCheckInViewModel.swift), lines 281–284, returns Extreme for migraine values without checking `hasHeadache`; lines 330–334 serialize those details and derived burden.

Impact: a deselected headache can still cause an extreme pain result.

Proposed repair: gate current serialization/derived values by active symptom selection. A retained hidden draft is acceptable only if it is not counted as current evidence. Suggested follow-up: DOSETAP-61/67 scope review.

Acceptance: select migraine, turn Headache off, keep mild back pain and save. Current answers contain no headache assertion; burden, History and exports reflect active symptoms only.

## IR-06: Done discards wake-diary edits; nested Save commits independently

**P2; source-confirmed mechanics, inferred UX confusion.** [NightOutcomeView.swift](../../ios/DoseTap/Views/NightOutcomeView.swift), line 190, uses Done for cancellation; lines 192 and 296–304 separately save. The morning form opens this nested editor, then can itself be skipped/cancelled.

Impact: Done looks like completion but does not save; cancelling the outer form does not undo the nested Save.

Proposed repair: use Cancel for abandonment, protect dirty dismissal and explain independent diary persistence. Reuse the existing diary, not a duplicate field. Fits DOSETAP-49/47 flow review.

Acceptance: changed answers cannot be silently discarded by Done/back/swipe. Saving the diary then cancelling morning reports accurately what remains saved, without medication/alarm changes.

## IR-07: Return-to-sleep question has no skipped-dose applicability

**P2; source-confirmed.** [MorningCheckInClinicalSections.swift](../../ios/DoseTap/Views/MorningCheckInClinicalSections.swift), lines 51–56, always renders Back To Sleep After Dose 2. [MorningCheckInModels.swift](../../ios/DoseTap/Views/MorningCheckInModels.swift), lines 156–170, offers durations/Never/Unsure but not Not applicable. The answer can be stored without a taken Dose 2.

Impact: a skipped night can acquire an after-dose answer. Never, Unsure and no second dose are different.

Proposed repair: resolve applicability from explicit/recorded dose status without inferring medication use. Corrections should trigger answer review, not invented values. Fits DOSETAP-49/57 semantics review.

Acceptance: confirmed skipped becomes Not applicable; unlogged remains unresolved; taken permits the subjective estimate. Dose correction updates applicability without analytics writing to the medication ledger.

## IR-08: Morning lacks the pre-sleep saved pain-pattern library

**P2; requested consistency gap, not a regression claim.** [MorningCheckInClinicalSections.swift](../../ios/DoseTap/Views/MorningCheckInClinicalSections.swift), lines 263–311, has Add/Edit/Delete only. [MorningCheckInView.swift](../../ios/DoseTap/Views/MorningCheckInView.swift), lines 95–98, does not enable remembering or offer a saved-pattern picker.

Impact: bedtime back/foot patterns cannot be explicitly reused through the morning editor. Copying old observations via IR-02 is not an equivalent safe preference mechanism.

Proposed repair: shared pattern library, with fresh morning intensity and applicability confirmation. Confirm scope with the owner under DOSETAP-61; not yet delivered.

Acceptance: save back/foot patterns at bedtime; next morning select only foot, set a new level and save. No automatic back pain; prior bedtime observations and reusable pattern remain unchanged.

## Recommended next implementation order

1. IR-01 medication-action defaults, then IR-03 completion and IR-05 hidden-state correctness.
2. IR-02/04 freshness, confirmation and unit semantics.
3. IR-06/07 save clarity and applicability.
4. IR-08 consistent pattern reuse after owner feedback.

These are proposed follow-ups against existing ownership, not tracker-state changes or newly completed fixes. The existing build-39 durable-save/retry repairs remain useful within their tested scope. Owner feedback, signed-phone acceptance and independent clinical review remain separate from completion of this documentation work item.
