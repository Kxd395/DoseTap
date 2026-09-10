# DoseTap questionnaire revision

Version: Proposed revision 1, September 10, 2026
Status: Supplied design proposal, not a shipping specification. The original review changed no application code, medication records, historical answers, tracker states or installed builds.
Delivery scope: The [questionnaire delivery plan](../plans/2026-09-10-questionnaire-delivery-plan.md), DOSETAP-69, qualifies approval, completion/reminder semantics, ownership and sequencing. Consult that plan and current SSOT before implementing this proposal.
Source baseline: Owner-provided reviews of commit `1fc48dd9a4c37627bafdd3c3586c7190e7aca239`, app 0.4.19 (39).

## 1. Decision summary

Remember recurring conditions, reusable symptom definitions, usual sleeping arrangements, equipment, and schedule context. Do not turn yesterday's observations into tonight's answers.

Add sleeping alone/with a partner, share the recurring-symptom library between bedtime and morning, and provide per-section controls for next-night-only or ongoing reuse. Expand the pain editor to support nonpainful sensory symptoms. Repair the documented medication defaults, stale observations, hidden-state calculations, and completion blockers before shipping additional fields.

The supplied owner review is the inventory of current behavior [R1]. The independent findings describe proposed repairs, not implemented fixes [R2]. Everything labeled NEW, REVISE, MOVE, or CONSOLIDATE below is a design proposal. Existing stable field IDs are retained for traceability; new IDs extend their respective ranges. This is a custom tracking questionnaire, not a validated diagnostic instrument or clinical release approval.

## 2. Global answer and persistence rules

### 2.1 Three distinct kinds of information

| Kind | Examples | What happens on the next treatment night |
| --- | --- | --- |
| Persistent reference | User-reported diagnosis, prescribed-regimen reference, usual weekly work plan, equipment available | Remains available with source and last-review date. It is not a new observation or administration. |
| Reusable pattern or setup | Lower-back symptom pattern, foot numbness pattern, usual sleeping companion, room setup | Reappears as a suggestion. It becomes a nightly answer only after an explicit action with a clearly stated scope. |
| Current observation or event | Pain intensity, actual partner presence, last meal, alcohol use, medication taken, therapy use, morning quality | Starts unanswered, or displays an existing record belonging to this same treatment night with its provenance. Never copied from a previous night as fact. |

A treatment night means the app's identified main sleep episode, including daytime sleep after a night shift. Reuse must follow that episode identifier, not midnight or the date a form is opened.

### 2.2 Exact persistence controls

For an eligible setup card:

```text
[ ] Remember this setup for future check-ins
    Reuse: Next treatment night only / Until I turn it off

This saves your usual setup. Each check-in will ask you to confirm it.
```

For an individual symptom:

```text
[ ] Show this symptom again
    Reuse: Next treatment night only / Until I turn it off
    Show in: Bedtime / Morning / Both

This remembers the symptom name and usual details, not today's severity.
```

The default for a newly enabled reuse control is `Next treatment night only`. An explicit `Save as recurring pattern` action selects `Until I turn it off`; it must not silently change the scope of an existing next-night-only selection. Remember the scope once the user deliberately chooses it for that pattern.

Both is the recommended initial display scope for recurring pain or sensory symptoms. The checkbox itself starts unchecked for a new item. Previously saved recurring items retain their configured preference.

Temporary setup selections and long-term patterns must not share a single global remember flag. The checkbox is per card or per symptom, not a blanket permission to reuse every answer.

### 2.3 What the user sees on the next night

```text
Usual setup, not yet confirmed
Partner in the same bed. Fan and blackout curtains.
[Confirm planned setup for this night] [Change]

Recurring symptoms to review
Lower-back discomfort: Not checked
Foot numbness: Not checked
[Review symptoms]
```

Morning uses `Confirm this was the actual setup` rather than treating the bedtime plan as proof. One setup confirmation may cover the visible companion, room, and nonmedical setup fields. It must not confirm medication administration, actual therapy use, symptoms, or safety responses.

A saved symptom appears automatically, avoiding repeated entry. Its nightly presence and severity do not. A `Same as last confirmed` action is permitted only inside a specific symptom review, beside the old date and values, after showing exactly what will be confirmed. There is no blanket `Same as yesterday` action for clinical outcomes.

### 2.4 Missingness and applicability

Store unanswered, explicit No/None, Unsure, Not applicable, and Prefer not to answer distinctly. A collapsed or skipped section remains unassessed. Turning an expansion toggle off must not manufacture a negative response.

If a user explicitly selects `No headache this morning`, current headache details become inactive. Hidden draft values may remain available for undo, but must not be serialized as current symptoms or included in derived burden. Similarly, `Do not include this section` means unassessed, not no symptoms.

Allow check-ins to be saved with unanswered optional items. A saved incomplete check-in is not the same as a fully answered assessment. Save must not require fabricated details; incomplete explicitly started entries need targeted choices to finish, keep as a draft, or remove.

### 2.5 Reuse lifecycle

A next-night-only preference targets the next identified treatment night once that night exists. It can appear at bedtime and morning for that night. Reopening the app, cancelling a draft, crossing midnight, or retrying a save must not consume it twice or roll it to a different night. If the target night is skipped, record that disposition and do not silently extend it indefinitely.

Recurring patterns remain until paused or archived. `Not present tonight` records a negative observation for this night and does not delete the pattern. `Stop showing this` changes the preference and does not assert recovery. Archiving a pattern leaves historical observations intact. Editing a label or usual location must not rewrite old answers.

History forms must not change current recurring preferences by default. Any `Save as a future pattern` action in History must be a separate, explicitly scoped action.

## 3. Revised pre-sleep questionnaire

Preserve the existing three-card structure. Show summary rows for already-recorded events and expand only selected detail. Every new daily response starts unanswered unless an explicit existing record for the same treatment night is being edited.

### Card 1: Tonight's plan, sleeping arrangement, and stress

| ID | Disposition | Exact question or label | Choices and behavior |
| --- | --- | --- | --- |
| PS-01 | MOVE | Bottle and supply records | Keep `Record bottle start` in a clearly labeled independent supply action, accessible from the form. It is not a routine nightly question. Show an independent-save receipt. |
| PS-02 | REVISE | Is this the plan for your next main sleep period? | Show the existing weekly plan, required wake date/time, and following-day obligations. Actions: `Use this plan`, `Change this night only`, `Review weekly schedule`. Label values Planned. Do not change the weekly schedule through a nightly answer. |
| PS-03 | KEEP, fresh | When do you plan to try to sleep? | Now; About 15 minutes; About 30 minutes; About 1 hour; Later; Unsure. This is intention, not actual sleep onset. |
| PS-04 | KEEP | What is keeping you up? | Existing Not tired; Work to do; Social plans; Entertainment; Other. Add Pain or discomfort; Care responsibilities. Optional when Later. |
| PS-41 | NEW | How are you planning to sleep this time? | Alone in the room; With a partner in the same bed; With a partner in the same room, separate beds; With another person or other people; Other arrangement; Unsure; Prefer not to answer. |
| PS-42 | NEW, conditional | Tell us only what is relevant about the shared sleeping space. | For another-person/other arrangement: Same bed; Same room, separate sleeping space; Arrangement changes during the sleep period; Other; Unsure. Optional free text, no person's name required. Do not ask relationship or sexual details. |
| PS-43 | NEW, optional | Will pets share the sleeping space? | No; On the bed; In the room, off the bed; Both or variable; Unsure. Independent of whether another person is present. |
| PS-44 | NEW, optional | Where are you sleeping? | Usual bed at home; Different bed or room at home; Away from home; Other; Prefer not to answer. No precise address or location permission needed. |
| PS-45 | NEW | Remember this sleeping setup for future check-ins | Use the per-card persistence controls in section 2. Store only the chosen setup fields, not a claim about future actual presence. |
| PS-05 | KEEP, fresh | How stressed do you feel right now? | Existing 1 Low through 5 Very High. No preselected value. Unsure and Skip available. |
| PS-06 | REVISE | What is contributing to your stress? | Preserve Work; Family; Relationship; Health; Pain; Sleep; Medication; Environment; Schedule; Financial; Other. Reusable stressor labels may be pinned only through explicit opt-in. Their presence tonight still requires confirmation. |
| PS-07 | KEEP, fresh | How has your stress changed today? | Much Better; Better; About The Same; Worse; Much Worse; Unsure. Optional. |
| PS-08 | KEEP, fresh | Anything to note about stress? | Optional current-night note. Do not copy it into future observations. A separate reference note can be saved only through an explicit action. |

A sleeping-companion answer is context. It must not change dose permissions, mark someone as a trained caregiver, imply monitoring, or establish that assistance is available. Partner attendance is not evidence of safer medication use.

### Card 2: Symptoms, intake review, and medication context

| ID | Disposition | Exact question or label | Choices and behavior |
| --- | --- | --- | --- |
| PS-09 | REVISE | Any pain, numbness, tingling, or other physical symptoms right now? | No symptoms in this group; Review recurring symptoms; Add a symptom; Unsure. This is not a pain-only gate. Do not infer no symptoms from an unopened card. |
| PS-10 | REVISE | Symptoms for this check-in | Independent entries using the shared editor in section 4. A positive sensory symptom does not require positive pain. |
| PS-11 | REVISE | Your recurring symptoms | Show saved active patterns automatically in an unconfirmed state. Actions: Present now; Not present now; Unsure; Edit pattern; Pause future prompts. Same library in morning. |
| PS-12 | REVISE | Any caffeine since your previous main sleep? | Explicit No; Yes; Unsure. For Yes, review or add Coffee; Tea; Soda; Energy drink; Caffeine tablet or supplement; Other. Use a visible review window and logged occurrence times, not an ambiguous midnight reset. |
| PS-13 | REVISE | When was your last caffeine intake? | Confirmed date/time; Estimated date/time or time range; Unknown. No automatic reference-time value counts as confirmed. |
| PS-14 | REVISE | How much was the last item? | Optional beverage volume with explicit fl oz or mL; product count when relevant. Unknown supported. Caffeine mass in mg is a separate optional field. |
| PS-15 | REVISE | Caffeine total in this review window | Show confirmed logged totals by compatible unit, with completeness and estimated/unknown items identified. Optional user estimate; do not infer caffeine mg from beverage ounces without an identified estimate source. |
| PS-16 | REVISE | Any alcohol in the displayed review window, or since your last review? | No; Yes; Unsure. Fresh explicit answer, never remembered as No. Existing logged alcohol remains visible even if the user selects No; flag the inconsistency for review rather than deleting it. |
| PS-17 to PS-19 | REVISE | Alcohol details | Product/type, amount with a clear unit, optional strength, occurrence date/time or estimate/unknown. Preserve source and certainty. Do not fabricate last amount or total from a category. Do not calculate a time when alcohol is declared cleared or medication is declared safe. |
| PS-20 | REVISE | Medication and other product review | Show actual logged events with product, dose/unit, formulation, occurrence time, and source. `No entries logged` does not mean none taken. Actions: Add a missing event; Review usual medication list; Record unsure details. Include an escape hatch for prescription medicines, OTC sleep/cold/allergy/pain products, supplements, nicotine, cannabis, and other products not in the existing catalog. These are history categories, not a statement that their risks are equal. |
| PS-21 | REVISE | Prescribed regimen on file | Read-only reference with product, formulation, once/twice-nightly status as prescribed, amount per administration, units, source, and effective date. `Review regimen` is separate from this questionnaire. Remove the generic questionnaire fallback as an implied prescription. Do not prescribe, titrate, or log administration through a displayed plan. |
| PS-46 | NEW, conditional | Anything new, stopped, or changed since the last medication review? | No changes; Yes; Unsure; Skip. Positive opens the medication reference review. Persistent medication list and actual administrations remain separate. |

The current catalog is not a verified medication reconciliation list or clinically validated prescribing catalog [R1, section 7]. An added free-entry route must preserve exact supplied names and units rather than guess a matching drug. Specific interaction warnings require reviewed medication data, not just a broad product category.

### Card 3: Activity, food, room setup, and optional detail

| ID | Disposition | Exact question or label | Choices and behavior |
| --- | --- | --- | --- |
| PS-22 | KEEP, fresh | What physical activity have you had since your previous main sleep? | None; Light; Moderate; Intense; Unsure. No assigned duration or activity type from the category. |
| PS-23 | KEEP, conditional | What kind of activity? | Walking; Cardio; Strength; Yoga / Mobility; Sports; Physical Labor; Other; Unsure. Multiple actual events may be reviewed instead of forcing one activity. |
| PS-24 to PS-25 | REVISE | Last activity time and duration | Optional date/time, estimate/range, and duration or Unknown. Never fill four hours earlier, or 20/40/60 minutes, as user-confirmed evidence. |
| PS-26 | REVISE | Any naps or unintended dozing since your previous main sleep? | No; Planned naps; Unintended dozing; Both; Unsure. Intentional naps and unintended sleep are distinct. |
| PS-27 to PS-29 | REVISE | Nap and dozing details | Review existing events or add count, duration, and last end time with certainty. Unknown is valid. No automatic count of 1 or inferred end time. Link existing events rather than creating duplicates. |
| PS-30 | REVISE | When did you finish your most recent food or calorie-containing drink? | Show the latest relevant intake event. Actions: Confirm; Add something later; Time unknown; Skip. An enable toggle alone does not confirm a timestamp. |
| PS-31 to PS-33 | KEEP, optional | What was it? | Meal; Snack; Calorie-containing drink; Not specified. High-fat/oily: Yes; No; Unsure. Optional notes, existing 500-character limit. Nutrition and photo details must not block saving a finishing time. |
| PS-47 | NEW, conditional | Anything eaten or drunk after the entry shown? | No; Yes, add it; Unsure. Review is fresh and becomes stale after a later addition or relevant correction. Link to the shared Food & Drink record, not a competing latest-meal store. |
| PS-34 | KEEP, fresh | Screen use in bed before trying to sleep? | None; Briefly; About 30 minutes; 1+ hour; Unsure. Clearly marked as so far/planned at bedtime, not the entire night's actual behavior. |
| PS-35 | REVISE | When did you last use a screen? | Actual/estimated date/time; Unknown. Optional. No inferred 45-minutes-earlier timestamp. |
| PS-36 to PS-38 | REVISE | Room and sleep setup | Preserve temperature Cold/Cool/Comfortable/Warm/Hot; noise Silent/Quiet/Moderate/Noisy; multiselect Eye Mask/Earplugs/White Noise/Fan/Blackout Curtains/Other. Add optional light level Dark/Dim/Bright/Variable/Unsure. Reusable setup stays a suggestion until confirmed for this night. |
| PS-39 | KEEP, fresh | Anything else relevant to this sleep period? | Optional note. Offer a separate `Save as reference note` action only when explicitly requested. |
| PS-40 | REVISE | Remember this room setup for future check-ins | Replace the broad automatic default with section 2 controls. Existing consent/preferences may be retained, but copied values must be labeled suggestions rather than fresh observations. |
| PS-48 | NEW, optional | Any therapy equipment or positioning changes planned for this sleep? | Use usual equipment; Change; Not planned this time; Unsure. Device identity comes from reference setup. This is not proof of overnight use. Optional usual sleep position: Left/Right/Back/Stomach/Elevated/Variable/Unsure. |

Footer: `Save pre-sleep check-in`, `Save draft`, `Skip this check-in`, `Cancel`. A completed save shows the treatment night and what was saved. Draft/skip status must not become a completed set of observations.

## 4. Shared pain and sensory-symptom editor

Replace the pain-only framing with `Recurring symptoms and body discomfort`. Continue to support localized pain without creating a separate competing symptom database.

Numbness, tingling, weakness, and pain can be distinct peripheral-neuropathy symptoms [E3]. This supports separate sensory fields; it does not establish that any particular symptom is neuropathy or identify its cause.

### 4.1 Pattern definition, saved only with explicit permission

| ID | Field | Revised behavior |
| --- | --- | --- |
| PA-10 | Pattern name | Optional user-defined name, for example Lower-back discomfort, Right-foot pain, or Foot numbness / neuropathy symptoms. Required only when needed to distinguish otherwise identical patterns. |
| PA-11 | Diagnosis/reference label | Optional. Attribution: Diagnosed by a clinician, as reported by me; My description or suspected condition; Not sure. Do not infer a diagnosis from sensations. No requirement to label ordinary back or foot symptoms diagnostically. |
| PA-01 | Area | Preserve all existing areas. New entry starts unselected, not Mid Back. Offer Other and Unknown/not sure. |
| PA-02 | Side | Left; Right; Center; Both; Not applicable; Unsure. New entry starts unselected, not Both. |
| PA-04 | Usual sensations | Preserve Aching; Sharp; Shooting; Stabbing; Burning; Throbbing; Cramping; Tightness; Radiating; Pins / Needles; Numbness; Other. Add Electric-shock-like; Sensitivity to touch; Weakness; Unsure. Usual values are suggestions, not automatic current symptoms. |
| PA-05 | Usual pattern | Constant; Comes and goes; Unknown; Not specified. Persist only as a reference descriptor. |
| PA-06 | Pattern note | Optional stable context. Keep it separate from today's note. |
| PA-08 | Reuse | `Show this symptom again` plus Next treatment night only / Until I turn it off; Bedtime / Morning / Both. |
| PA-12 | Library identity and lifecycle | Stable independent pattern ID, status Active/Paused/Archived, creation/revision dates, and last review. Area plus side must not be the unique identity. Two separate problems at the same site can coexist. |

### 4.2 Current observation, always fresh

| ID | Field | Exact choices/behavior |
| --- | --- | --- |
| PA-13 | Is this present right now? | Yes; No; Unsure. Bedtime and morning answered independently. |
| PA-14 | Was it present overnight? | Morning only: Yes; No; Unsure. Can be Yes when current presence is No. Do not require a current symptom to record an overnight symptom that resolved. |
| PA-03 | Pain right now | 0-10 or Unknown; unanswered initially. 0 means explicitly no pain, not no numbness or no symptom. No default 5. |
| PA-15 | Sensory symptom severity right now | Optional separate None/Mild/Moderate/Severe/Unsure for relevant numbness, tingling, or other sensory symptom. Never convert this automatically into pain intensity. |
| PA-16 | What does it feel like this time? | Confirm or change visible usual sensations. Unknown/unsure is allowed. No default Aching. |
| PA-17 | Compared with your usual symptoms | New or different; Better; About the same; Worse; Unsure; No usual baseline. Optional, not a substitute for current presence/intensity. |
| PA-18 | Effect on sleep | Bedtime: None expected; Makes it harder to get comfortable; May delay sleep; Unsure. Morning: Did not affect sleep; Delayed falling asleep; Woke me; Made returning to sleep difficult; Unsure. Morning permits multiple effects. Expected and observed impact are distinct. |
| PA-19 | What affected it or helped? | Optional current-event context: Prolonged standing/work; Activity; Position; Footwear; A treatment or medicine; Other; Unsure. Record use, not recommendations. Link any medication event through its own logger. |
| PA-20 | Current note / overnight severity | Optional note; optional clearly labeled worst overnight pain rating. Do not substitute worst overnight severity for pain right now. |
| PA-07 | Save current entry | Validate only selected and applicable details. Unknown is legitimate. A numbness-only observation saves without inventing pain. An empty editor does not create a default entry. |
| PA-09 | Morning reuse | Use the same library as bedtime. Show separate current-night confirmations and observations. Never copy bedtime intensity into the morning answer. |

Illustrative next-morning view, with invented data:

```text
Lower-back discomfort
Present now? Yes
Pain now: 3/10
Overnight: Present, woke me
[ ] Update my usual pattern details

Foot numbness
Present now? Yes
Pain now: 0/10
Numbness: Moderate
Overnight impact: Unsure

Right-foot pain
Present now? No
[Keep in recurring list] [Pause future prompts]
```

These are three independent observations. None is overwritten because another shares its location. A nonpainful symptom does not inflate a pain summary. A migraine descriptor is not an automatic Extreme intensity.

## 5. Revised morning questionnaire

Use five grouped cards. Keep essential questions visible and optional detail accessible. Existing same-night diary records are shown rather than asked again. A brief flow does not suppress reported symptoms or change missing answers into negatives.

### Card 1: Sleep and waking

| ID | Disposition | Exact question or label | Choices/behavior |
| --- | --- | --- | --- |
| AM-01 | REVISE | Overall, how was this sleep period? | Existing 1-5 sleep-quality scale, with historical quarter-star precision preserved. No starting rating. Do not change scoring precision silently. |
| AM-02 | REVISE | How rested do you feel right now? | Not at all; Slightly; Moderately; Well; Very well; Unsure. No default Moderately. |
| AM-03 | REVISE | How groggy do you feel right now? | None; Mild; Moderate; Severe; Can't function; Unsure. No default Mild. This does not establish the cause of grogginess. |
| WD-05, surfaced here | CONSOLIDATE | When was your final awakening for this main sleep period? | Display or edit the shared diary answer. Allow uncertainty without inventing an exact time. Conflict handling in section 6. |
| AM-11 | KEEP, fresh | What caused your final awakening? | Natural; Alarm; Alarm + Snooze; External; Mixed; Unsure. Optional External detail: Another person; Pet; Noise; Care responsibility; Other. |
| WD-10 to WD-14 | NEW, optional shared detail | Sleep timing details | See section 6. Trying-to-sleep, estimated onset, final awakening, and out-of-bed time remain separate. |
| AM-22 | KEEP, fresh | What do you remember about dreams? | None; Vague; Normal; Vivid; Nightmares; Disturbing; Unsure. Link existing dream quick logs; do not count a summary as another dream event. |

### Card 2: Medication record review

| ID | Disposition | Exact question or label | Choices/behavior |
| --- | --- | --- | --- |
| AM-04 to AM-05 | REVISE, priority | Medication records for this treatment night | Show recorded doses as records, not fresh questions. If absent, show `No record` with default `Leave unchanged`. Actions: `Record a missed tap`, `Record skipped`, `I'm not sure`, `Review an existing record`. No preselected Taken. |
| AM-04 to AM-05, explicit action | REVISE | Record a missed medication tap | Separate confirmation of product, occurrence date/time or permitted uncertainty, amount/unit, and retrospective reason. Show existing prescribed values only as suggestions requiring review. `Record dose` is an explicit medication action with its own receipt. Morning `Save` never infers or creates administration. |
| AM-06 | REVISE | Anything to explain about this dose timing or record? | Optional for any dose; automatically expand only for a flagged timing exception or deliberate late entry. Preserve existing reasons. Do not imply every normal dose was unusual. |
| AM-07 | KEEP, fresh | Why was this dose skipped? | Preserve existing reasons plus `Not part of my prescribed regimen` only as a regimen applicability review, not a skipped administration. Unsure/Skip permitted. |
| AM-08 | KEEP, fresh | Medication record note | Optional. A note does not itself establish administration. |
| AM-13; WD-01 to WD-03 | CONSOLIDATE | What woke you around Dose 2? | Use the shared diary. Add `Another person` consistently to live and reviewed wake choices. Do not create a second morning-only answer store. |
| AM-14 | REVISE | After Dose 2, how long did it seem to take to return to sleep? | Less than 15 min; 15-30 min; 30-60 min; More than 60 min; Did not return to sleep; Unsure. Taken dose only. Confirmed skipped or not part of regimen: Not applicable. Unlogged/uncertain: Applicability unresolved. Never infer use from an answer. |

If the person reports taking a dose but cannot supply a reliable time or amount, preserve the report as unresolved/estimated using an approved schema. Do not invent an exact administration event to satisfy validation. A time-uncertain report must not support precise last-dose timing or a reassurance about driving. Recording what happened remains distinct from recommending what to take.

### Card 3: Recurring symptoms and other physical issues

| ID | Disposition | Exact question or label | Choices/behavior |
| --- | --- | --- | --- |
| AM-35 | REVISE | Physical symptoms during the night or now | Separate group actions: Review recurring symptoms; Pain or sensory symptoms; Headache; Stiffness or soreness; Reflux; Restlessness; Bathroom symptoms; Respiratory/illness symptoms; Other. Explicit `None of these assessed symptoms` is distinct from leaving the group unopened. |
| AM-36 | REVISE | Recurring and new body symptoms | Shared editor in section 4. A reflux-only, urgency-only, or headache-only answer does not require a localized pain entry. |
| AM-37 | REVISE | Headache during the night or now? | Yes; No; Unsure. Conditional current/overnight severity, location, and migraine-like features. Migraine-like is a descriptor, not a severity. New fields have no hidden asserted defaults. |
| AM-38 | KEEP, fresh | Muscle stiffness / muscle soreness | Separate None/Mild/Moderate/Severe/Unsure, with current versus overnight scope. Do not require a pain entry. |
| AM-39 | REVISE | Reflux, restless legs/body restlessness, and bathroom urgency | Preserve separate severity responses. Add optional bathroom trip count or Unknown using existing quick logs as references, not as a presumed complete count. Urgency, actual urination, and bedwetting are distinct. |
| AM-40 | KEEP, fresh | Symptom note | Optional. |
| AM-41 to AM-43 | KEEP, fresh | Nose, throat, cough, sinus, and illness | Preserve existing choices; all start unanswered. Separate feverish feeling from a measured temperature. Offer next-night-only symptom prompts through section 2, without copying today's severity or illness status. |
| AM-50 | NEW, conditional | Did symptoms change between bedtime, overnight, and now? | Display comparable confirmed entries; permit a current answer or optional explanation. Do not require a second redundant score or treat missing observations as improvement. |

### Card 4: Actual sleeping setup, therapy, breathing, and unusual events

| ID | Disposition | Exact question or label | Choices/behavior |
| --- | --- | --- | --- |
| AM-51 | NEW | Was your sleeping arrangement the same as planned? | Yes, confirm the visible arrangement; No, change it; Unsure; Prefer not to answer. If no bedtime plan, use PS-41 to PS-44 choices. Actual presence is fresh. Optional All/Part of sleep period/Unsure. |
| AM-52 | NEW, optional | Did sharing your sleeping space affect your sleep? | No noticeable effect; Helped; Disrupted; Both; Unsure; Not applicable. Conditional details: Snoring/noise from another person; Movement; Different schedules or alarms; Care responsibilities; Pets; Comfort/support; Other. This describes effects on the user's sleep, not symptoms of a partner. |
| AM-53 | NEW, optional | Has someone told you anything about your sleep this time? | Yes; No concerns reported; Not discussed/no observer; Unsure. If Yes: My loud snoring; My breathing pauses or gasping; My movements/kicking; My sleepwalking or unusual behavior; Difficulty waking me; Other. Store as a report relayed by the user unless directly entered by an authorized observer. |
| AM-54 | NEW, fresh | Any breathing concerns that you noticed or were told about? | Yes; No concerns noticed or reported; Unsure. Positive expands self-experienced gasping/choking, reported breathing pauses, other concern, timing, source, and whether ongoing. Absence of an observer must not produce `No breathing problems`. |
| AM-44 | REVISE | What was the actual room and sleep setup? | Confirm/change visible setup. Same exact multiselect aids as bedtime; do not collapse known combinations into Multiple. Optional temperature, noise, light, and position changes. |
| AM-45 | REVISE | Did you use your prescribed sleep therapy during this sleep period? | Yes; No; Unsure; Not applicable. Device identity can be suggested from reference setup, but actual use is fresh. If Yes and device unknown, preserve `Used, device unspecified` visibly instead of hiding inconsistent data. |
| AM-46 | REVISE | How much was the therapy used? | All or nearly all; Part; Briefly; Unsure. Optional estimated hours. Keep machine-reported duration separate. Remove default 100% and the implication that a recalled estimate is device-measured compliance. Optional problems: Removed mask/device; Leak; Discomfort; Congestion; Dryness; Power/equipment problem; Other. |
| AM-47 | REVISE | Sleep-related symptoms or unusual overnight events | Preserve Sleep Paralysis; Hallucinations; Automatic Behavior; Fell Out Of Bed; Confusion On Waking. Add Sleepwalking; Injury or near-fall; Unexpected loss of bladder control; Unusual difficulty waking; Other. Explicit occurrence, unknown, and unassessed states. Do not categorize every event as narcolepsy or a medication reaction. |
| AM-55 | NEW, conditional | What happened, and when? | Self-report/other-person report/device source; approximate timing or Unknown; still happening/resolved/unsure; optional note and action taken. Link existing events to avoid duplication. Clinician-reviewed escalation copy required for concerning responses. |

Why the observer distinction matters: NHLBI identifies snoring, breathing interruptions, and gasping as symptoms that the person may first learn about from someone else [E2]. A person sleeping alone has missing observation opportunity, not a negative breathing assessment. Nothing in these questions diagnoses sleep apnea.

A partner's presence does not establish active monitoring. Do not require their name, assume they consent to notifications, or automatically share the user's answers with them. The app is not an emergency monitoring service.

### Card 5: Functioning, obligations, and optional notes

| ID | Disposition | Exact question or label | Choices/behavior |
| --- | --- | --- | --- |
| AM-15 | REVISE | How long did sleep inertia last after final waking? | None; Less than 5 minutes; 5-15; 15-30; 30-60; More than 1 hour; Still experiencing it; Unsure. No default duration. An ongoing experience is not a completed duration. |
| AM-16 to AM-18 | KEEP, fresh | Mental clarity, mood, and anxiety right now | Preserve the existing named scales and values, without default Clear/Neutral/None. Optional detail. Do not infer causation. |
| AM-19 to AM-20 | KEEP, fresh | Stress right now and since bedtime | Preserve existing values, stressors, trend, and notes. Pinned stressor labels do not automatically assert current stress. |
| AM-21 | KEEP, fresh | Readiness for the day | Existing 1-5 scale, unanswered initially. Optional. |
| AM-09 to AM-10; AM-12; AM-24 to AM-26; WD-04 | CONSOLIDATE | What obligations follow this sleep period? | Use the existing schedule context and explicitly confirmed nightly override. Preserve Off/Work/recovery/transition context as needed, but do not ask duplicate day-type questions or keep conflicting unreviewed copies. Scheduled, self-reported, and confirmed actual contexts remain labeled. |
| AM-23 | REVISE | Additional work and safety detail | Optional expansion. Relevant safety information is not suppressed just because detail is collapsed. |
| AM-56 | NEW, conditional | When do you next plan to drive or perform a hazardous task? | Date/time; No activity planned; Unsure. Distinct from work start, commute duration, required wake, and confidence. Can be collected at bedtime through the same planned obligation record. |
| AM-27 | DE-EMPHASIZE | How confident do you feel about driving? | Optional personal rating only. Never a clearance signal or substitute for time and impairment information. |
| AM-28; WD-06 | CONSOLIDATE prospectively | How sleepy are you right now? | Use the existing timestamped 0-10 diary definition for a new shared observation: 0 Fully alert, 10 Struggling to stay awake. No default 5. Store assessment time. Link the same observation wherever surfaced. Preserve old 1-5 values with their original scale ID; do not silently convert them. |
| AM-29 | KEEP, fresh | Cataplexy symptoms in the relevant period | Existing burden scale, optional and contextually relevant. Clarify the observation period. Do not treat a diagnosis as an event. |
| AM-30 to AM-34 | MOVE | Clinical reference profile | Move diagnosed/suspected sleep conditions, co-medication reference, and genetic report context out of repetitive morning collection. Keep access via `Review profile`. Do not preserve the unsupported `faster processing` assertion as a physiological fact or use genetics to shorten safety timing. Store any supplied report wording with attribution and clinical-review status. |
| AM-48 | KEEP, fresh | Anything else to note or discuss with your clinician? | Optional free text. Separate optional clinician-question flag; no automatic transmission. |
| AM-49 | REPLACE | Manage recurring prompts and usual setup | Replace `Remember last wake-up settings` with section-specific controls. No copying quality, restedness, grogginess, dreams, mood, anxiety, clarity, symptom occurrence, or actual therapy use. |
| AM-57 | NEW, optional later | Any unintended sleep or dozing after waking? | Independent timestamped daytime event, not a rewrite of this morning's check-in. Align with planned DOSETAP-58 rather than creating a second event store. |

Footer: `Save morning check-in`, `Save draft`, `Skip this check-in`, `Cancel`. A successful save shows the treatment night, answer status, and independently saved records. Retried saves are idempotent.

## 6. Wake & Next Day: one shared diary

Keep this as the canonical source for the fields already owned by it. Integrate editors into morning without creating parallel stores [R1, section 6].

| ID | Revised requirement |
| --- | --- |
| WD-01 to WD-02 | Same choices at live confirmation and later review: Natural; Alarm; Another person; Other; Unknown. A wake answer never logs a dose. Legacy Other values remain Other until explicitly corrected. |
| WD-03 | Backup alarm actually set: Yes/No/Unknown. Keep distinct from scheduling intent and wake method. |
| WD-04 | Reference the confirmed following-day context rather than a duplicate independent workday answer. Preserve historical provenance if older values disagree. |
| WD-05 | Final awakening stays distinct from last Health sample, final dose, and getting out of bed. A wake before a later recorded dose is a conflict to review, not automatic proof that the wake is wrong. Permit an explicitly reviewed, plausible sequence without rewriting medication records or forcing a false later wake. |
| WD-06 | A timestamped subjective sleepiness observation. Preserve existing observations and introduce later repeated observations through the planned event stream. If final wake is missing, retain the observation but leave wake-relative elapsed time unresolved under the revised schema. Do not require invented wake time. |
| WD-07 to WD-08 | Reviewed window and Health evidence retain their current purpose and source labels. A reviewed window is not measured sleep. Missing coverage is not zero. |
| WD-09 | `Save diary changes`, `Cancel`, and a dirty-dismiss warning. Remove unsaved-dismissal `Done`. Explain that an independently saved diary remains saved if the outer questionnaire is cancelled. Keep correction reasons and revision history. |
| WD-10, NEW | When did you start trying to sleep? Date/time, estimate, or Unknown. Optional live `Trying to sleep now` is an explicit user action, not an inferred dose-time marker. |
| WD-11, NEW | When did you get into bed for this main sleep period? Optional date/time, estimate, or Unknown. Not equivalent to trying to sleep. |
| WD-12, NEW | When did you get out of bed after final waking? Date/time, estimate, Still in bed, or Unknown. Final waking and out-of-bed time are separate. |
| WD-13, NEW | About how long did falling asleep initially take? Optional estimated duration/range or Unknown. Keep self-estimate separate from Health-estimated onset. Do not force exact precision. |
| WD-14, NEW | Awakenings remembered during the sleep period, excluding final wake. Optional count/estimate/Unknown and optional total awake duration. Clarify whether Dose 2-related waking is included in the displayed summary. Link quick logs without assuming complete capture. |

Maintain the planned event-counting distinctions: one continuous wake episode counts once, including one spanning Dose 2; final waking is separate; split provider samples are not additional awakenings; a quick-log count is not a provider-derived count. Preserve Apple Health stages, quick logs, conflicts, and source coverage [R1, sections 6 and 8].

## 7. Clinical and operational blind spots

### 7.1 Product-specific medication safety, not questionnaire-derived permission

The attachments list several oxybate products but do not establish the user's actual product, formulation, indication, prescribed regimen, or individualized instructions. These details must come from an explicitly reviewed regimen reference, not the software catalog [R1].

As an example of why this matters, the current retrieved XYWAV label contraindicates combination with alcohol or sedative hypnotics, warns about other CNS depressants and respiratory depression, and requires avoiding hazardous activities for at least six hours after taking it. Its administration section also addresses food timing and missed second doses [E1, sections 2.4, 4, 5.1]. These are XYWAV label facts, not a determination about the user's prescription or permission to use a generic rule for every listed product.

Design consequences: collect the actual product, other products taken, food/alcohol timing and uncertainty, actual last dose, and planned driving/hazardous-activity time. A day off may remove a work-specific early-wake warning, but must not disable medication-specific warnings. Neither a partner, a good readiness score, a self-reported fast metabolism, nor a fasting countdown establishes safety. Logging an already-taken late dose remains distinct from telling a person to take one.

No alcohol-clearance countdown, automatic dose adjustment, or blanket `Safe to dose/drive` status is part of this revision. Medication messages and escalation pathways need clinician/pharmacist review before release.

### 7.2 Concerning symptoms need a response path

Do not bury breathing concerns, marked difficulty waking, injuries, sleepwalking, or new/worsening psychiatric symptoms in free text. Add contextual follow-up and clinician-reviewed escalation content. The XYWAV label specifically addresses respiratory effects, depression/suicidality, behavioral reactions, and parasomnias [E1, sections 5.4-5.7]. This does not prove medication causation in an individual report.

Mood already exists in the form. Add an optional `New, worse, or concerning change` route rather than pretending one mood rating assesses psychiatric safety. Any direct safety-screening question needs a defined response pathway and truthful statements about whether anyone monitors or receives the result. Do not deploy an unmonitored alert that implies clinical supervision.

### 7.3 Sleep opportunity and daytime obligations

Keep the weekly work plan as the primary schedule, with the owner's requested weekly verification and an explicit single-night override. Do not repeatedly request facts already on file. A schedule confirmation and a completed sleep diary answer are different actions.

Capture required wake and planned driving separately. Account for work shifts crossing midnight, daylight-saving changes, travel, and daytime main sleep. Display the treatment-night label and local date/time in late and historical check-ins.

### 7.4 Intake timing is more important than forced nutritional detail

Retain last-food finishing time, later snacks/caloric drinks, provenance, and uncertainty. Defer mandatory calories, macros, photos, barcodes, and a full nutrition diary. Reuse familiar food identities if desired, never yesterday's consumption. Keep planned DOSETAP-53/54/55 boundaries rather than presenting an integration as implemented [R1, section 8].

### 7.5 More questions are not automatically better

Keep chronic diagnoses, reference medication lists, equipment ownership, work schedules, and genetic documents in a profile. Keep detailed symptom, device, dream, mood, activity, and environment questions conditional. Do not turn a nightly check-in into a full medical intake.

Optional later additions include a separate fatigue item, position-related discomfort, night sweats, relevant hormonal/cycle context, and validated periodic scales after purpose, licensing, and scoring review. These should not delay the data-integrity fixes or the requested companion/persistence work.

### 7.6 Privacy and interpretation

Companion context, health history, and notes are sensitive. Do not collect names or contact details without a defined user-authorized purpose. No automatic partner notification or clinician sharing. Exports need a preview, category-level exclusion, and clear inclusion of free text only when authorized.

Keep self-report, partner report relayed by the user, device measurement, clinician reference, and derived values distinct. Label within-person associations as associations; the app must not declare a medication, food, partner, or symptom to be the cause of a poor night from correlation alone.

## 8. Priority repairs from the supplied findings

These are source-reported findings at the pinned baseline, not newly reproduced bugs or confirmed causes of the owner's historical incident [R2].

| Finding | Required repair before expansion |
| --- | --- |
| IR-01 | No preselected Taken action for a missing dose. Explicit medication actions only; untouched morning completion leaves the ledger unchanged. |
| IR-03 | Validate the symptom actually selected. Headache-only, reflux-only, urgency-only, stiffness-only, and numbness-only responses can save without fabricated localized pain. |
| IR-05 | Hidden/deselected symptoms cannot affect current serialization, pain burden, History, or exports. Migraine-like features do not establish intensity by themselves. |
| IR-02 | Remove carry-forward of prior-night observations from both saved-settings and previous-check-in fallback paths. Retain only explicitly permitted suggestions and reference setup. |
| IR-04 | Category selection cannot produce confirmed times/amounts. Unknown and estimates must be representable. Repair caffeine volume versus mass semantics without reinterpreting ambiguous legacy values. |
| IR-06 | Predictable Save/Cancel behavior, protected dirty dismissal, and visible independent saves. |
| IR-07 | Return-to-sleep applicability distinguishes taken, skipped, not prescribed for this regimen, and unknown/unlogged. |
| IR-08 | Same named recurring-symptom library at bedtime and morning, with fresh applicability and severity. |

The current dose-plan ranges and medication picker amounts were not clinically validated by the supplied review. Do not treat this document as approval of those controls [R1, sections 2 and 7].

## 9. Implementation contract

### 9.1 Data separation

Use separate records or clearly separated typed domains for:

- Reference profile and prescribed-regimen reference.
- Reusable pattern definitions and reuse preferences.
- Night-specific planned context and confirmed actual observations.
- Independent medication, intake, wake, and daytime events.
- Assessment revisions and saved drafts.

This is a logical separation, not a requirement to introduce competing stores. Reuse the existing canonical stores where they already own the concept.

Each relevant value needs a stable field/record ID, treatment-night association when applicable, assessment phase, occurrence time/range when known, entry time, source, answer status, certainty, confirmation time, schema/scale version, and revision lineage. Pattern references need an ID plus an immutable snapshot/version so a changed template cannot change history.

Suggested field states: unanswered; suggested-unconfirmed; answered; explicitly-unknown; not-applicable; declined. Estimate is a certainty attribute, not a synonym for unconfirmed: a person can explicitly confirm that a value is an estimate. A measured device value is a separate source type.

Known actual event times must not be in the future; planned events may be. Unknown occurrence times remain unknown rather than defaulting to the current clock. Changing the visible diary window must not discard relevant events from a medication-safety review.

Actual event times use an absolute timestamp with the relevant local timezone/offset retained for display and review. Planned local schedules require explicit timezone handling; do not apply naive fixed-hour date arithmetic across daylight-saving transitions.

### 9.2 Save boundaries

Stage ordinary questionnaire edits and their per-card reuse choices together. Save them only through their visible owning action. Where a preference or diary still saves independently, the action must say so and produce a receipt.

Medication and bottle records remain explicit independent actions. `Save morning check-in` must not call an implicit reconciliation path. Record retries use stable identifiers/idempotency protection. Cancel does not silently delete already-saved independent records and must accurately explain what remains.

Dirty dismissal offers Keep editing; Save draft; Discard unsaved changes. Persistence failures retain the draft, user selections, and operation identity. A success receipt must correspond to successful durable persistence, not just modal dismissal.

### 9.3 Migration and analytics

Do not backfill missing new fields as No, Alone, Zero, or Not applicable. Existing unconfirmed/default-origin ambiguity cannot be resolved by assuming the old value was explicitly chosen. Preserve raw historical values, annotate unknown confirmation provenance where appropriate, and expose missingness/source limitations in analysis.

Do not turn historical `Mg`-named beverage-volume values into caffeine mass. Do not numerically reinterpret 1-5 sleepiness as the 0-10 diary scale. Preserve exact historical enum/scale meaning and introduce an explicit version for prospectively changed questions.

Record changes to recurrence separately from symptom changes. A paused prompt is not a resolved condition. A pattern does not count as symptom presence, and an unconfirmed suggestion is excluded from confirmed-observation totals. Show usable observation counts and missingness for each metric.

## 10. Acceptance tests

Use synthetic records. These tests are specified, not executed against the app.

| Test | Scenario | Required result |
| --- | --- | --- |
| AT-01 | Missing Dose 1 and Dose 2; open and save morning without medication actions | Ledger unchanged. |
| AT-02 | Explicit retrospective dose recorded; questionnaire save fails; retry and reopen | Exactly one dose event and one answer identity. Visible independent-save receipt. |
| AT-03 | Extreme prior quality, anxiety, grogginess, and symptoms seeded through each legacy fallback path | Fresh current answers unanswered; no copied occurrence or normal default. |
| AT-04 | Save lower-back and foot patterns, then start the next bedtime | Patterns visible automatically, current presence and intensity unconfirmed. |
| AT-05 | Confirm only foot at morning, with a new intensity | No back-pain assertion; bedtime value and pattern unchanged. |
| AT-06 | Foot numbness present, pain explicitly 0 | Valid sensory observation; no positive pain inferred. |
| AT-07 | Foot symptom occurred overnight but resolved by morning | Overnight Yes and current No retained separately. |
| AT-08 | Two separate patterns share area and side | Neither is overwritten; independent IDs and observations. |
| AT-09 | Reflux-only, headache-only, urgency-only, and stiffness-only check-ins | Each saves without requiring localized pain. |
| AT-10 | Select migraine-like headache, then explicitly deselect headache while mild back pain remains | Headache inactive in current records, summaries, exports, and burden. |
| AT-11 | Only select Coffee, Light exercise, or a nap category | No confirmed time, volume, count, or duration created. |
| AT-12 | Caffeine 12 fl oz and unknown caffeine mg | Volume remains volume; caffeine mass remains unknown in UI/export. |
| AT-13 | Usual partner setup saved, next morning actual sleeping alone | Nightly actual context changes; usual setup remains unless separately updated. |
| AT-14 | Alone, no observer report | Breathing observations remain not observed/unknown, never inferred negative. |
| AT-15 | Partner wakes user for Dose 2 | Same wake method in live view, shared diary, morning, History, and export. No dose logged by selecting wake method. |
| AT-16 | Next-night-only symptom prompt; reopen, cross midnight, retry, and use morning form | Applied to one identified treatment night, not duplicated or prematurely consumed. |
| AT-17 | Mark recurring back symptom absent tonight | Negative current observation; recurring pattern remains available. |
| AT-18 | Pause a pattern; then edit its label | No historical observation changes and no inferred recovery. |
| AT-19 | Dose 2 skipped; then corrected to taken; also test unknown and once-nightly regimen | Correct distinct applicability and review prompts. No invented return-to-sleep response. |
| AT-20 | Therapy equipment on file but usage unanswered | No overnight-use claim and no default 100% use. |
| AT-21 | Save diary independently, then cancel morning | Diary remains; morning draft is not falsely completed; message accurately describes saved items. |
| AT-22 | Change diary answers then tap back/swipe | Dirty-dismiss protection, no silent discarded edits. |
| AT-23 | Later snack added after last-food review | Food review becomes stale; latest intake resolves from canonical events, not copied form values. |
| AT-24 | Day off confirmed, but planned driving exists after a dose | Work-specific wake warning may disappear; medication-specific timing context remains active. No confidence-score clearance. |
| AT-25 | Night shift/daytime sleep, midnight crossing, and daylight-saving transition | Correct episode association, local date/offset display, and elapsed-time calculations. |
| AT-26 | Final awakening before a later recorded dose; or sleepiness entered while wake time unknown | Conflict/unresolved data preserved for review, not a fabricated wake time or silent record rejection. |
| AT-27 | Legacy 1-5 sleepiness and new 0-10 observation both present | Distinct scale provenance; no silent conversion or duplicate observation from multiple views. |
| AT-28 | Save partially answered check-in | Saved incomplete status; optional blanks remain blanks, not normal scores or negatives. |
| AT-29 | Modify a historical answer and open recurring controls | Current preferences unaffected unless a separate future-pattern action is explicitly confirmed. |
| AT-30 | VoiceOver, large text, one-handed use, dark mode, keyboard, interrupted/offline save | Readable labels and state distinctions, reachable actions, retained draft, no fabricated confirmation. |
| AT-31 | Export excludes partner context and free text | Preview and exported content respect selection; other observation provenance remains intact. |
| AT-32 | Clinically concerning response | Approved response pathway appears with truthful monitoring claims; raw report remains saved without automatic diagnosis or causation. |

## 11. Delivery sequence and ownership mapping

First fix IR-01/03/05, then IR-02/04. These are integrity and completion problems, not optional questionnaire enhancements. Align with existing reliability/freshness/unit ownership described in the supplied packet; no live tracker status was checked or changed here.

Next deliver the owner's requested PS-41 to PS-45 companion context and shared PA-08/09/10/12 recurring-symptom behavior, including nonpainful sensory symptoms and individual reuse scopes. This should not depend on nutrition-photo work, new analytics, or a full clinical profile redesign.

Then repair save boundaries and Dose 2 applicability, consolidate duplicate schedule/diary fields, and add the highest-value conditional gaps: actual therapy use, observed breathing/unusual events, and planned driving time. Coordinate with the existing DOSETAP-49/51/52/53/54/57/58/60/61/67 scopes rather than making parallel stores [R1].

Finally perform migration/export checks, accessibility and signed-device acceptance, and clinical review of medication-specific messages. Passing document review is not evidence that a phone build behaves correctly.

## 12. Action log and files

Reviewed the two supplied Markdown reports. Checked current publicly accessible XYWAV labeling and NIH symptom information to bound the medical additions. Created this replacement specification, including field crosswalks, persistence behavior, save semantics, and acceptance tests. No runtime reproduction, source-code edit, clinical approval, tracker write, personal-record access, or app build was performed.

Added file: `docs/review/2026-09-10-dosetap-questionnaire-revision.md`. The original review action log below predates the separate delivery-plan and implementation work.

Unchanged source files:

- `2026-09-10-questionnaire-independent-findings.md`
- `2026-09-10-sleep-questionnaire-review.md`

## 13. Sources and evidence boundaries

[R1] Owner-supplied [collection review packet](2026-09-10-sleep-questionnaire-review.md). Pre-sleep and wake-up collection: owner review packet. Dated September 10, 2026. Source inventory at the pinned app baseline, not a clinical or runtime approval.

[R2] Owner-supplied [independent findings](2026-09-10-questionnaire-independent-findings.md). Independent questionnaire source and flow findings. Dated September 10, 2026. Source-reported IR-01 through IR-08, proposed repairs, and stated limitations.

[E1] DailyMed, Jazz Pharmaceuticals, Inc., XYWAV official U.S. label. Set ID `1e0ae43a-037f-42af-8e23-a0e51d75abe8`, version 16; effective July 1, 2025; publication metadata November 17, 2025; retrieved September 10, 2026. Relevant sections: 2.4, 4, 5.1, 5.4-5.7. Section 4 code `34070-3`; the retrieved 5.1 subsection uses `42229-5`. The label is a product document, not confirmation of the user's prescription. Official source:

```text
https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=1e0ae43a-037f-42af-8e23-a0e51d75abe8
```

[E2] National Heart, Lung, and Blood Institute. Sleep Apnea Symptoms. Updated January 9, 2025; retrieved September 10, 2026. Used for the distinction between self-observed and other-person-reported snoring, interrupted breathing, and gasping, not for diagnosis. Official source:

```text
https://www.nhlbi.nih.gov/health/sleep-apnea/symptoms
```

[E3] National Institute of Diabetes and Digestive and Kidney Diseases. Peripheral Neuropathy. Last reviewed February 2018; retrieved September 10, 2026. Used only for symptom distinctions including numbness, tingling, pain, and weakness. This page's diabetes context does not establish a cause or diagnosis for this user. Official source:

```text
https://www.niddk.nih.gov/health-information/diabetes/overview/preventing-problems/nerve-damage-diabetic-neuropathies/peripheral-neuropathy
```

All field wording, default choices, persistence architecture, prioritization, and acceptance tests in this revision are proposed design decisions. They are not presented as instructions from the supplied reviewers or as requirements of a validated instrument.
