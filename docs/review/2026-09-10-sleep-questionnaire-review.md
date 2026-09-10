# Pre-sleep and wake-up collection: owner review packet

Status: Point-in-time source inventory and proposed review questions; not a release approval
Date: 2026-09-10
Source baseline: `1fc48dd9a4c37627bafdd3c3586c7190e7aca239`, app 0.4.19 (39)
Tracker: [DOSETAP-68](http://plane.localhost:3301/dark-water-drones/browse/DOSETAP-68/)

## How to use this document

This packet inventories the current iPhone pre-sleep and morning forms, the shared pain editor, and the separate Wake & Next Day editor. It includes choices, defaults, conditional questions, save boundaries and planned work. These are source-code observations, not proof of what is installed on your phone. No personal health records were used, and this documentation changes no app behavior.

Use the stable IDs in the first column when giving feedback: for example, “PA-03: I want to adjust my foot pain without changing my back pain.” Read the inventory first if you want an unprompted review. The [independent findings](2026-09-10-questionnaire-independent-findings.md) are separate so they do not have to influence your first impressions.

- **Current:** reachable in the reviewed source. This does not mean all device/release checks are complete.
- **Conditional:** appears after a selection, toggle or expansion.
- **Legacy:** retained model/history data, not necessarily a current question.
- **Planned:** in an existing Plane work item; not a promise it is installed.
- **Review proposal:** a question or suggested change from this review, not yet implemented or approved.

“Blank” means no answer in a fresh form before carry-forward or automatic detail filling. “None,” “Unknown,” “Unsure,” “Not applicable” and an unanswered field are different. A control displaying a default does not establish that the person chose it. Numeric medication ranges below reproduce UI controls only; they are not dosing recommendations or confirmation that the catalog is clinically correct.

## 1. Current flows and save boundaries

| Flow | Current sequence | What completion means |
| --- | --- | --- |
| Pre-sleep, tonight | Card 1 timing/stress → Card 2 pain/substances/medications/dose plan → Card 3 exercise/naps/food/details. Swipe or Back/Next. | Final **Done** saves through the parent callback. Existing answers use **Save**. A save error keeps the form open. **Skip for tonight** is a skip action, not a completed answer set. |
| Pre-sleep, History | Same questionnaire for the selected treatment night; live plan/setup controls are limited. | **Review** returns a draft to the History correction flow. **Cancel** abandons that questionnaire draft. Existing source answers are not fresh-night defaults. |
| Morning, live | Quality/restedness/grogginess → dose confirmation → night context → functioning → optional work/clinical context → symptoms → environment/therapy/narcolepsy → notes/preferences → Complete. | **Complete Check-In** first processes dose reconciliation, then saves morning answers. These are separate writes. **Skip** dismisses without the normal submit path. |
| Morning, History | Same answer collection, without live medication reconciliation or remembered-settings loading for a new historical form. | **Review History Answers** returns a draft to the History review flow. The questionnaire does not add doses or close tonight's session. |
| Wake & Next Day | Open from the Dose 2 wake review button in morning/History; edit the shared nightly diary. | Its **Save** writes independently. Its current **Done** button only dismisses; it does not save edits. Cancelling the outer morning form does not undo an already saved diary. |

Other independent saves: bottle-opening confirmation, live medication logging, saved pain-pattern preferences and live sleep-plan overrides are not all deferred until questionnaire completion. Review these boundaries before assuming that Cancel reverses everything on the screen.

## 2. Pre-sleep: all current questions

Most categorical questions begin blank. Positive substance/activity choices can automatically populate their detail fields; see section 5. “More details” is an expansion, not a separate form.

### Card 1: timing and stress

| ID | Field | Choices / input | Initial state and condition |
| --- | --- | --- | --- |
| PS-01 | Started a new bottle? | Opens **New bottle**: Started on date/time, **Record bottle start**, Cancel. | Optional; date initially now, no future date. Saves an independent supply record on confirmation, even if pre-sleep is skipped. The last recorded opening is shown. |
| PS-02 | Sleep-plan context | Wake by, in-bed target, wind-down target, expected minutes. **Just for tonight** toggle reveals a Wake by hour/minute picker and **Reset to schedule**; when off, shows Typical Week baseline. | Planned schedule, not observed sleep. Toggle/picker changes save through the plan store immediately, independently of questionnaire Save. Not the History-night answer. |
| PS-03 | When do you plan to sleep? | Now; ~15 min; ~30 min; ~1 hour; Later. | Blank. This is intention, not measured sleep onset. |
| PS-04 | Why later? | Not tired; Work to do; Social plans; Entertainment; Other. | Conditional on Later; blank. |
| PS-05 | Stress level right now? | 1 Low; 2 Mild; 3 Medium; 4 High; 5 Very High. | Blank; five selectable buttons, despite the shared component's “Slider” name. |
| PS-06 | Current stressors? | Multi-select Work; Family; Relationship; Health; Pain; Sleep; Medication; Environment; Schedule; Financial; Other. | Appears when a stress level/detail exists. Empty selection initially. |
| PS-07 | Stress trend today? | Much Better; Better; About The Same; Worse; Much Worse. | Same condition; blank. |
| PS-08 | Stress notes | Free text: what is driving it, what helped or worsened. | Same condition; optional. |

### Card 2: pain, substances, medication and plan

| ID | Field | Choices / input | Initial state and condition |
| --- | --- | --- | --- |
| PS-09 | Body pain right now? | None; Mild; Moderate; Severe. | Blank. A positive selection requires at least one granular pain entry before final save. |
| PS-10 | Separate pain entries | Add Pain Entry / Add another pain; edit or delete each entry. | Each has its own location, side, intensity and sensations. Full inventory in section 3. |
| PS-11 | Saved pain patterns | Use tonight; Forget; remember/update a current pain pattern. | Live pre-sleep only. Reusing opens an editor to review tonight's level. Preference changes are separate from saving tonight's answers. |
| PS-12 | Caffeine / stimulants today | Multi-select Coffee; Tea; Soda; Energy Drink. **No caffeine today** and **Clear answer** are distinct actions. | Blank is “Not recorded.” An older “Multiple” aggregate can remain preserved until exact sources are reselected. Not a medication dose record. |
| PS-13 | Last caffeine intake time | Time picker. | Shown for positive intake. Can be auto-filled from the form's reference time. |
| PS-14 | Last drink size | 2–48 **beverage oz**, step 2. | Positive intake; suggested quantity is automatically filled. This is not caffeine mass. |
| PS-15 | Caffeine beverage total today | At least last-drink size, up to 96 **oz**, step 4. | Positive intake; total cannot be below last amount. Storage property names still end in `Mg`; DOSETAP-52 owns the unit repair. |
| PS-16 | Alcohol today? | None; 1 drink; 2–3 drinks; 4+ drinks. | Blank initially; positive choices reveal PS-17–19. This inventory does not endorse medication use after alcohol. |
| PS-17 | Last alcohol drink time | Time picker. | Positive intake; can be auto-filled from reference time. |
| PS-18 | Last alcohol amount | 0.5–8 drinks, step 0.5. | Positive intake; auto-filled category-based amount. The UI does not collect beverage strength here. |
| PS-19 | Alcohol daily total | At least last amount, up to 20 drinks, step 0.5. | Positive intake; total must not be below last amount. |
| PS-20 | Medications today | List of independently logged medications: name, amount, time, notes; Add/Log Medication and delete actions. | Empty list says no entries logged, not confirmed no medication use. Add/delete controls are restricted in History. See section 7 for the picker catalog. |
| PS-21 | Tonight's dose plan | Total nightly plan 500–20,000 mg, step 250. Split presets 50/50, 55/45, 60/40, 40/60; Dose 1 percentage slider 30–70%, step 1. Displays both calculated amounts. | Displays existing plan or catalog-derived fallback (currently 9,000 mg total, 50/50). Plan values can prefill morning reconciliation. A displayed plan is not an administration. Current warning copy appears above 4,500 mg for either planned dose and above 9,000 mg total. Clinical appropriateness and explicit-confirmation semantics need separate review. |

### Card 3: activity, naps, food and optional detail

| ID | Field | Choices / input | Initial state and condition |
| --- | --- | --- | --- |
| PS-22 | Exercise today? | None; Light; Moderate; Intense. | Blank. Positive choices reveal PS-23–25 and fill defaults. |
| PS-23 | Exercise type | Walking; Cardio; Strength; Yoga / Mobility; Sports; Physical Labor; Other. | Positive exercise. Suggested type varies by intensity. |
| PS-24 | Last exercise time | Time picker. | Positive exercise; inferred default approximately four hours before reference time. |
| PS-25 | Exercise duration | 5–600 minutes, step 5. | Positive exercise; defaults Light 20, Moderate 40, Intense 60 minutes. |
| PS-26 | Nap today? | No nap; <30 min; 30–60 min; >1 hour. | Blank. Positive choices reveal PS-27–29. |
| PS-27 | Nap count | 1–6, step 1. | Default 1 after positive selection. Not a provider-derived awakening count. |
| PS-28 | Total nap time | 5–360 minutes, step 5. | Defaults 20, 45 or 90 minutes for the three positive duration groups. |
| PS-29 | Last nap ended | Time picker. | Inferred default approximately six hours before reference time. No individual nap start/end pairs in this questionnaire. |
| PS-30 | Record last food | On/off; Finished at date and time. | Off/no entry initially. Enabling creates a time to review. Date is bounded by current or History reference time. Includes later snacks/caloric drinks, not just dinner. |
| PS-31 | Food type | Not specified; Meal; Snack; Calorie-containing drink. | Conditional on PS-30. Optional classification. |
| PS-32 | High-fat or oily? | Unsure; No; Yes. | Conditional on PS-30. Unsure retains an unknown value. |
| PS-33 | Food notes | Optional text, up to 500 characters. | Conditional on PS-30. Earlier legacy late-meal category can be displayed separately; it is not an exact finishing time. |
| PS-34 | Screens in bed | None; Briefly; ~30 min; 1+ hour. | Inside More details; blank. |
| PS-35 | Screens last used | Time picker. | Positive screen use; inferred default approximately 45 minutes before reference time. |
| PS-36 | Room temperature | Cold; Cool; Comfortable; Warm; Hot. | More details. Blank or remembered room setup. |
| PS-37 | Noise level | Silent; Quiet; Moderate; Noisy. | More details. Blank or remembered room setup. This is environment, not an individual noise awakening. |
| PS-38 | Sleep aids / setup | Multi-select Eye Mask; Earplugs; White Noise; Fan; Blackout Curtains; Clear. | More details; may be remembered. Clear stores no aids; older “Multiple” can remain preserved. |
| PS-39 | General notes | Optional free text. | More details. A visual line limit is not a confirmed storage character limit. |
| PS-40 | Remember room setup / Use room setup | On/off preference; manual use action. | Live form only; remembering defaults on. Reuses only room temperature, noise and sleep-aid setup into unanswered fields. It does not copy prior food, alcohol, caffeine or pain observations. |

The last-food section contains existing medication-label wording. This packet is a review of that UI, not a fresh clinical validation. Planned alcohol/caloric-drink handling needs its own reviewed wording; no fasting, alcohol-clearance or “safe to dose” conclusion should be inferred from an unanswered field.

## 3. Shared granular pain editor

Use this to review your example: one back entry with its own level and throbbing/tightness, plus a separate foot entry with its own level and pins/needles/numbness. The current editor has no separate diagnosis field called “neuropathy”; sensations and optional notes can describe the experience without establishing a diagnosis.

| ID | Field | Current selections / behavior |
| --- | --- | --- |
| PA-01 | Area | One area per entry: Head / Face; Neck; Upper Back; Mid Back; Lower Back; Shoulder; Arm / Elbow; Wrist / Hand; Chest / Ribs; Abdomen; Hip / Glute; Knee; Ankle / Foot; Other. A new editor starts with Mid Back selected. |
| PA-02 | Side | Left; Right; Center; Both; N/A. New editor defaults Both. |
| PA-03 | Intensity | Integer 0–10. New editor defaults 5; an existing/reused entry supplies its own value to review. |
| PA-04 | Sensations | Multi-select Aching; Sharp; Shooting; Stabbing; Burning; Throbbing; Cramping; Tightness; Radiating; Pins / Needles; Numbness; Other. New editor defaults Aching. At least one is required. |
| PA-05 | Pattern | Not set; Constant; Comes and goes; Unknown. |
| PA-06 | Notes | Optional free text. Review whether a named recurring condition belongs here or needs a separate user-defined label. |
| PA-07 | Save / Cancel | At least one area and sensation are needed. Saved entries are keyed by area and side; another entry with the same key replaces/updates it, rather than representing two distinct conditions at the identical site. |
| PA-08 | Remember for future nights | Available in live pre-sleep; default off in a new editor. Saves reusable setup separately. “Use tonight” still requires reviewing tonight's intensity and saving the questionnaire. |
| PA-09 | Morning reuse | Morning supports separate Add/Edit/Delete entries, but does not expose the pre-sleep saved-pattern library. Reusing that library with a fresh morning level is a review proposal, not current functionality. |

## 4. Morning: all current questions

The main form is one scrollable page, not a verified five-question-only flow. Defaults below describe a new view model before remembered settings or an existing answer overrides them. Many current fields have no unanswered option. Remembered settings can replace these defaults with prior-night experiences; see section 5 and IR-02.

### Quick ratings, dose review and night context

| ID | Field | Current choices / input | Base default / condition |
| --- | --- | --- | --- |
| AM-01 | Sleep quality | 1–5 stars, quarter-star increments. | 3. |
| AM-02 | How rested do you feel? | Not at all; Slightly; Moderately; Well; Very well. | Moderately. |
| AM-03 | Morning grogginess | None; Mild; Moderate; Severe; Can't function. | Mild. Categorical, not the proposed 0–10 scale. |
| AM-04 | Dose 1 confirmation | Existing record shown; when absent: “I took Dose 1 but missed the tap” toggle, occurrence date/time and amount 250–20,000 mg in 250 mg steps. | **Missing Dose 1 currently defaults the toggle on.** Time/amount are supplied from existing context or fallback. This can write medication on Complete. |
| AM-05 | Dose 2 confirmation | Existing record shown; when absent: Leave as-is / Taken / Skipped. Taken exposes occurrence date/time and amount 250–20,000 mg in 250 mg steps. | **Missing, unskipped Dose 2 currently defaults Taken.** Already skipped uses Skipped; already recorded uses Leave as-is. Do not treat missing data as proof of taking a dose. |
| AM-06 | Why Dose 2 was early, late or unusual | Forgot To Tap; Fell Asleep; Alarm Issue; Intentionally Waited; Ate Too Late; Felt Too Sedated; Pain Or Discomfort; Schedule Conflict; Other; Unsure. | Unsure. Shown whenever effective Dose 2 status is Taken, including an ordinary recorded dose, despite the unusual-dose wording. |
| AM-07 | Why Dose 2 was skipped | Slept Through; Alarm Issue; Ate Too Late; Side-Effect Concern; Felt Too Sedated; Pain Or Discomfort; Schedule Conflict; Chose To Skip; Other; Unsure. | Unsure. Conditional on skipped status. |
| AM-08 | Dose 2 reason notes | Optional free text. | Shown with the relevant reason flow. |
| AM-09 | Night type | Off Night; Work Night; Into Work Block; Out Of Work Block; Recovery Night; Unsure. | Unsure. |
| AM-10 | First night off after a work block | On/off. | Off. Separate from night-type selection. |
| AM-11 | How did you wake? | Natural; Alarm; Alarm + Snooze; External; Mixed; Unsure. | Unsure. This is final morning waking, not Dose 2 waking. |
| AM-12 | Next-day demand | Off Day; Normal Day; 12h Shift; 13h Shift; Long Drive; Travel; Recovery Day; Unsure. | Unsure. |
| AM-13 | What woke you for Dose 2? | Opens the shared **Wake & Next Day** editor, WD-01 onward. | Uses the same diary as Dose 2/History, not the older six-choice enum retained in morning model code. |
| AM-14 | Back to sleep after Dose 2 | <15 min; 15–30 min; 30–60 min; >60 min; Never; Unsure. | Unsure. Subjective bucket, not Apple Health latency. Currently shown even if Dose 2 was skipped/not logged; no separate Not applicable choice. |

### Morning functioning

| ID | Field | Current choices / input | Base default |
| --- | --- | --- | --- |
| AM-15 | Sleep inertia duration | <5 minutes; 5–15; 15–30; 30–60; >1 hour. | 5–15 minutes. |
| AM-16 | Mental clarity | 1–5 integer slider, Foggy → Clear. | 5. |
| AM-17 | Mood | Very Low; Low; Neutral; Good; Great. | Neutral. |
| AM-18 | Anxiety | None; Mild; Moderate; High; Severe. | None. |
| AM-19 | Stress level | 1 Low; 2 Mild; 3 Medium; 4 High; 5 Very High. | Blank. |
| AM-20 | Current stressors / trend / notes | Same eleven stressors and five trends as PS-06/07; trend asks **Since Bedtime**; optional free text. | Conditional on stress details; empty/blank initially. |
| AM-21 | Readiness for the day | 1–5 integer slider, Barely → Ready. | 3. |
| AM-22 | Dream recall | None; Vague; Normal; Vivid; Nightmares; Disturbing. | None. Distinct from an overnight Dream quick log. |

### Work/safety and clinical reference, each behind its own opt-in toggle

| ID | Field | Current choices / input | Base default / condition |
| --- | --- | --- | --- |
| AM-23 | Add work / safety context | On/off. | Off; enables AM-24–29. |
| AM-24 | What set your wake requirement? | Self-Selected; Work; Commute; Family / Care; Medical; Travel; Other; Unsure. | Unsure. |
| AM-25 | Next shift window / next required wake | Separate Record toggles; shift start and end date/time; required wake date/time. | Toggles off; initial date values now. Planned obligations, not observations. |
| AM-26 | Commute burden | 0–240 minutes, step 5. | 0. This is not a planned driving start time. |
| AM-27 | Driving confidence | 1–5, Not safe → Confident. | 3. Personal rating; cannot establish driving fitness. |
| AM-28 | Daytime sleepiness | 1–5, Alert → Very sleepy. | 3. Separate from the timestamped 0–10 diary in WD-06. Do not combine scales. |
| AM-29 | Cataplexy burden | None; Mild; Moderate; Severe; Unsure. | Unsure. |
| AM-30 | Add clinical reference context | On/off. | Off; enables AM-31–34. |
| AM-31 | Diagnosed or relevant sleep disorders | Multi-select Narcolepsy; Insomnia; Obstructive Sleep Apnea; Restless Legs / PLMD; Circadian Disorder; Shift-Work Disorder; Parasomnia; Idiopathic Hypersomnia; Other. | Empty. The wording mixes diagnosed and relevant; review whether those should be separate. |
| AM-32 | Sleep-disorder notes / co-medication notes | Two optional free-text fields for severity/treatment and medication/device context. | Empty. Notes are not proof of a medication administration. |
| AM-33 | Genetic-context assertions | “DNA / pharmacogenomic report suggests faster processing”; “Clinician has reviewed this genetic context” on/off toggles. | Both off. Existing wording to review, not this packet's interpretation of a genetic report. |
| AM-34 | Pharmacogenomic notes | Optional report wording/context. | Empty. Consider whether sensitive long-term reference information belongs in every morning form. |

### Symptoms, environment and therapy

| ID | Field | Current choices / input | Base default / condition |
| --- | --- | --- | --- |
| AM-35 | Any Issues? | Physical Pain and Sick/Respiratory branch toggles. | Both off; each reveals its branch. |
| AM-36 | Pain detail by area + side | Same PA-01–07 granular entries; Add, Edit, Delete. | Empty. **Current submit validation requires a pain entry whenever the physical branch is on**, even for another symptom alone. |
| AM-37 | Headache | Toggle; severity None / Mild / Moderate / Severe / Migraine; location Forehead / Temples / Back of Head / Behind Eyes / All Over / One Side; Migraine-like toggle. | Headache off; hidden defaults Mild, Forehead, migraine off. Hidden-state behavior needs review (IR-05). |
| AM-38 | Muscle stiffness / muscle soreness | Two separate None / Mild / Moderate / Severe answers. | Both None. |
| AM-39 | Reflux / heartburn; restless legs / body restlessness; bathroom urgency overnight | Three separate None / Mild / Moderate / Severe / Extreme / Unsure answers. | Each Unsure. Urgency is not a bathroom-trip count. |
| AM-40 | Pain notes | Optional free text. | Empty. |
| AM-41 | Nose / throat | Nose: None / Stuffy Nose / Runny Nose / Stuffy & Runny. Throat: Normal / Dry / Sore / Scratchy. | Respiratory branch; None and Normal. |
| AM-42 | Cough / sinus pressure | Cough: None / Dry Cough / Productive. Sinus: None / Mild / Moderate / Severe. | Respiratory branch; both None. |
| AM-43 | Illness | Feeling feverish toggle; No / Coming down with something / Actively sick / Recovering; notes. | Respiratory branch; feverish off, No, notes empty. |
| AM-44 | Sleep Environment | Expand, then Add room/setup details toggle. Room and noise choices match PS-36/37. Sleep aids is a **single** selection: None / Eye Mask / Earplugs / White Noise / Fan / Blackout Curtains / Multiple; notes. | Collapsed, toggle off. Hidden defaults Comfortable / Quiet / None. Unlike pre-sleep, exact aid combinations are not collected here. |
| AM-45 | Sleep Therapy Device | Expand, then Used Sleep Therapy Device toggle. Choices CPAP; BiPAP; APAP (Auto); Oxygen Concentrator; Oral Appliance; Positional Therapy; Other. | Collapsed, toggle off; underlying device None is excluded from selectable positive choices. Current completion does not require picking a device after enabling use, so true usage can be saved without device-detail JSON. |
| AM-46 | How much of the night? / therapy notes | “Compliance” 0–100%, step 5; optional notes. | Conditional on device-used toggle; default 100%. A personal answer, not a device-import measurement. |
| AM-47 | Narcolepsy Symptoms | Expand; Sleep Paralysis, Hallucinations, Automatic Behavior, Fell Out Of Bed, Confusion On Waking toggles. | Collapsed; all off initially. Current booleans do not distinguish unasked from explicitly No. |
| AM-48 | General notes | “Anything else to note?” optional free text. | Empty. |
| AM-49 | Remember last wake-up settings | On/off; UI says it will auto-prefill last morning's setup. | Defaults on when no stored preference. Actual reuse includes nightly outcomes and some symptoms, not just setup. Live form only. |

## 5. Defaults, remembering, validation and corrections

| Area | Current behavior to review | Desired distinction, not yet a universal implementation |
| --- | --- | --- |
| Pre-sleep room setup | Allowlist copies only unanswered room/noise/aids. Editing the same night preserves its existing answers. | Equipment/setup can be remembered; tonight's actual use may still need confirmation. |
| Pre-sleep pain | Saved patterns are separate preferences. Use tonight opens a confirmation/edit step. Final questionnaire save records the observation. | Keep back and foot patterns, but confirm each night's level and which patterns apply. |
| Positive caffeine/alcohol | Selection or hydration fills missing times and quantities. Coffee/Soda 12 oz, Tea 8 oz, Energy Drink 16 oz, aggregate Multiple 24 oz are current caffeine-volume defaults. | Selecting a category must not silently establish precise consumption evidence. Unknown amount/time should remain possible. |
| Positive exercise/naps/screens | Category changes and appearance can fill times, counts and durations. | Suggested, estimated and confirmed values need distinct storage/export meanings. |
| Pre-sleep validation | Positive pain needs entries; positive caffeine/alcohol needs time, last amount and total, with total ≥ last; exercise needs type/time/duration ≥5; naps need count ≥1, total ≥5 and end; screens need last time; food validates time and ≤500-character notes. | Existing automatic defaults can satisfy checks without the person reviewing them. There is no requirement to answer every optional question. |
| Morning remembering | Saved-settings loading or fallback to a previous check-in copies outcomes; fallback can also copy symptom occurrence. Turning the remember toggle changes a preference immediately. | Preferences and recurring patterns must be separated from current-night answers. Blank must not quietly become No or a normal score. |
| Morning save failure | Build 39 keeps the draft open on failure, uses a stable answer identity and skips already committed medication reconciliation on questionnaire retry. | This does not resolve preselected medication actions, every partial-failure case, or owner-observed reminder behavior. |
| History corrections | Questionnaire drafts go through reviewed historical writes; correction reasons and retained prior evidence belong to that flow. | Show why Save is blocked, the treatment night, occurrence versus entry time, and what is being changed. |
| Wake diary correction | Replacing recorded answers requires a reason; adding an unanswered field does not. Earlier revisions are visible. | Correcting an answer is not a second daytime observation. Repeated observations need their own planned event stream. |

## 6. Dose 2 wake selection and Wake & Next Day

This is the canonical Dose 2 wake answer. The older morning `Dose2WakeMethod` enum and alternative `MorningCheckInViewModelV2` wake-survey fields are not evidence of additional visible questions in the current main morning screen.

| ID | Field | Current choices / behavior |
| --- | --- | --- |
| WD-01 | At Dose 2 confirmation | Two checkbox-style, mutually exclusive choices: **Woke naturally** / **Woke to an alarm**. Tap the selected choice again to clear. Both unchecked means Unknown. Selecting alone does not record a dose; the enclosing confirmation owns the write. |
| WD-02 | Wake method, later review | Natural; Alarm; Other; Unknown. No Other-detail field. Picker is disabled without a recorded Dose 2 event. Reviewed in the shared diary, not a second morning-only copy. |
| WD-03 | Backup alarm set | Unknown; Yes; No. Natural waking before a backup alarm remains Natural. Scheduling an alarm does not answer this question. |
| WD-04 | Following day type | Workday; Day off; Unknown. Refers to the day after the treatment night; separate from AM-09/12 context. |
| WD-05 | Final awakening | Record final awakening toggle; date/time no later than now. Save validation requires it at or after recorded Dose 2, or Dose 1 if no Dose 2 is recorded. |
| WD-06 | Next-day sleepiness | Record toggle; personal 0–10 integer rating, 0 fully alert / 10 struggling to stay awake; assessment date/time. Current draft rating starts at 5 when enabled. Storage requires final awakening with a rating; assessment cannot precede final wake or be in the future. |
| WD-07 | Reviewed night window | Optional Save a reviewed window toggle; start/end dates and times; explicit “I reviewed both dates and times.” |
| WD-08 | Window evidence display | Saved bounds checks, local dose/nap conflicts, optional Apple Health coverage check: estimated asleep, recorded awake, unmeasured and conflicting minutes. These are evidence displays, not questionnaire answers. Existing charts/exports are not all switched to this new definition. |
| WD-09 | Correction and save | Nonblank reason for changed existing answers, maximum 500 characters; previous revisions; Save; Reload saved answers after error. **Done currently dismisses without saving.** |

The reviewed window is not measured sleep, a final-awakening answer or out-of-bed time. Manual final wake and provider estimates must not be conflated. The current subjective AM-14 bucket is not the planned precise Dose-2-to-return-to-sleep metric.

## 7. Linked medication picker: collection inventory, not prescribing guidance

PS-20 opens a separate logger: select product, select one of its configured amounts, choose occurrence date/time (initially now, no future time), optional notes, add to a pending batch, then log that batch. Selecting a product sets its catalog default amount. Duplicate prompts can appear. These records are separate from questionnaire completion and from a prescribed medication list.

The table transcribes the **current software catalog**. It has not been clinically verified by this review; values must not be treated as recommended amounts, product strengths, a complete medication list, or an instruction to substitute medications. Nightly-total versus single-administration scope needs particular review.

| Catalog selection | Configured amount choices, mg | Catalog default, mg |
| --- | --- | --- |
| Adderall / Adderall XR | 5, 10, 15, 20, 25, 30 | 10 / 20 |
| Ritalin | 5, 10, 15, 20 | 10 |
| Ritalin LA | 10, 20, 30, 40 | 20 |
| Concerta | 18, 27, 36, 54 | 36 |
| Vyvanse | 10, 20, 30, 40, 50, 60, 70 | 30 |
| Dexedrine | 5, 10, 15 | 10 |
| Modafinil / Provigil | 100, 200 | 200 |
| Armodafinil / Nuvigil | 50, 150, 200, 250 | 150 |
| Sunosi | 75, 150 | 75 |
| Wakix | 5, 9, 18, 35 | 35 |
| XYWAV / Xyrem | 2250, 3000, 3750, 4500, 6000, 7500, 9000 | 4500 |
| Lumryz | 4500, 6000, 7500, 9000 | 6000 |

## 8. Planned work, distinctly marked

Plane status was checked on 2026-09-10. This is a dated navigation snapshot; Plane remains the live authority. In Progress does not mean acceptance is complete. Existing device/privacy/provider gates remain open on their own items.

| ID | Plane / current state | Planned or remaining collection and behavior |
| --- | --- | --- |
| PL-01 | DOSETAP-51, In Progress | Fresh-night answers. Room-setup allowlist exists; substance/activity inferred details and morning carry-forward remain to be repaired. Keep reusable suggestions separate from confirmed observations. |
| PL-02 | DOSETAP-52, Todo | Separate beverage volume/unit from optional caffeine mg, preserve ambiguous legacy data, and carry meaning consistently through export/analytics. Do not assume missing caffeine mass is zero. |
| PL-03 | DOSETAP-53, Todo | Shared Food & Drink history throughout the day: finished-at time, optional identity/amount/context, occurrence versus capture/entry time, source, certainty and revisions. One-tap Finished eating can work without nutrition details. |
| PL-04 | DOSETAP-54, Todo | Pre-sleep review of confirmed intake, later snacks/drinks, fresh alcohol confirmation, stale-review handling after additions/corrections. Remember usual items, not yesterday's consumption. |
| PL-05 | DOSETAP-55, Todo | One-way Foodnoms/Apple Health prototype; verify actual finishing-time semantics, missing nutrients, duplicates, edits/deletions and permission/privacy behavior. Not a working promised integration. Native AI photos/barcodes remain deferred. |
| PL-06 | DOSETAP-56, In Progress | Preserve Apple Health detail; correct treatment-night versus primary-episode boundaries, final awakening versus observation end, provenance/conflicts and coverage. Reviewed-window and calculator groundwork is present; full chart/export/provider integration is not complete. |
| PL-07 | DOSETAP-57, Todo | Dose 1 → estimated sleep; relevant awakening → Dose 2; Dose 2 → estimated return to sleep; full awake-episode duration; awakening/return counts; final-awakening marker. Keep existing Health stage bands and quick logs. |
| PL-08 | DOSETAP-58, Todo | Independent timestamped daytime 0–10 sleepiness observations and unintended sleep/dozing. Separate events, not repeated overwrites of WD-06. Optional fatigue/concentration and dated Epworth are later scope, with instrument review before inclusion. |
| PL-09 | DOSETAP-59, Todo | Clinician-report preset extending current exports/Studio: per-metric usable counts, missingness, source/derivation version, timing, individual readings/medians and optional questions. Preview/redaction and parity required. |
| PL-10 | DOSETAP-60, Todo | Specify explicit planned driving/hazardous-activity time and elapsed time since the actual last recorded dose. Separate from commute burden, work start and confidence scores. Safety wording and implementation acceptance remain open. |
| PL-11 | DOSETAP-61, In Progress | Separate pain entries and reusable patterns exist in pre-sleep. Device/owner acceptance remains; consistent morning library reuse is a review proposal to confirm, not claimed delivered. |
| PL-12 | DOSETAP-67, In Progress | Durable morning saving/retry and recurring-reminder investigation. Build 39 includes targeted repairs; exact phone-message/build and owner save/reopen/reminder evidence remain needed. New findings are not proof of the historical incident's cause. |
| PL-13 | DOSETAP-49 / 50 / 47, In Progress | Existing wake outcomes, last-food collection and both History questionnaires need their remaining acceptance. Preserve these features while fixing flow; do not build competing answer stores. |

Planned counting rules: a continuous awake episode counts once, even across Dose 2; stage changes and split samples do not add awakenings. Keep the Dose-2-spanning episode separate from episodes starting after Dose 2. Final wake is separate from completed overnight returns. Missing coverage is not zero; sleep spanning a dose is a conflict/unresolved latency, not automatic zero latency. Time from **trying to sleep** needs an explicit observation and is not interchangeable with dose time or a plan.

Bathroom, water, noise, dreams, pain and other quick logs remain. A quick-log count is not a provider-derived awakening count. Nothing in this review proposes removing Apple Health sleep stages or replacing them with questionnaire answers.

## 9. Additional review proposals and missing-information checklist

These are questions for feedback, not new implemented fields or approved new work items. Prioritize fixing incorrect defaults and blocked saves before adding questionnaire length.

- **RP-01:** Give every daily observation a clear unanswered/unknown path; distinguish Not applicable from No. Which questions should be required, and why?
- **RP-02:** Reuse the same saved back/foot pattern library at bedtime and morning, with fresh level confirmation. Should patterns have custom names or separate diagnoses? Should two conditions at the same area/side coexist?
- **RP-03:** Separate “equipment I own/use usually” from “used last night”; exact combinations should work consistently in both forms. Keep clinical reference data out of repetitive nightly questions where appropriate.
- **RP-04:** Separate trying-to-sleep time, estimated sleep onset, awakening, return, final awakening and out-of-bed time. Allow source/estimate precision and unresolved times; do not demand a time the person could not observe.
- **RP-05:** Explain the selected treatment night and local timezone on historical/late check-ins. A completion timestamp is not the time of a symptom, meal or awakening.
- **RP-06:** Review duplication across the two sleepiness scales, final-wake categories, workday context, pain/stiffness/headache and dream quick logs. Preserve distinct concepts, but avoid asking the same answer twice.
- **RP-07:** Make Save, Review, Done, Skip and Cancel predictable. Identify independent nested saves; warn before discarding changed answers; preserve drafts on failure and give a visible successful-save receipt.
- **RP-08:** Clarify what happens when a parent toggle is turned off. Hidden draft values must not keep contributing to current symptom summaries or medication actions.
- **RP-09:** Let users select a brief nightly flow versus optional detail without suppressing relevant symptoms. Test one-handed use, VoiceOver, large text, keyboard obstruction, dark mode and fatigue-related mistakes.
- **RP-10:** Record data provenance, answer applicability, confirmation and correction history in exports. Explain sensitive-note inclusion and provide an export preview. A CSV is not a verified complete backup.

## 10. Copy-and-fill feedback form

```text
Review date / reviewer role:
Phone model / iOS / app version and build (if testing):
Treatment night and entry point: Tonight / History / Wake & Next Day
Field or flow ID (PS-, PA-, AM-, WD-, PL-, RP- or IR-):
What I expected:
What I saw or could not select/save:
Choices or wording to add/change/remove:
Required, optional or only conditional? Condition:
Remember as reusable setup, suggest for confirmation, or ask fresh?
Occurrence time / entry time / source / uncertainty needed:
Desired Save / Cancel / Skip behavior:
Priority: blocks use / records wrong information / confusing / preference
Example using made-up data:
Expected test result:
Screenshot reference (avoid unnecessary identifying information):
```

For an independent reviewer: review the inventory before the findings if possible. Identify ambiguous questions, missing choices, inappropriate defaults, inconsistent scales, overlong flows and unclear save boundaries. Distinguish source evidence, phone reproduction and proposed design. A clinician/pharmacist should separately review medication-related wording and catalog semantics; this packet does not provide that approval.

## Source map and limits

- Pre-sleep flow/validation: [PreSleepLogView.swift](../../ios/DoseTap/Views/PreSleepLogView.swift); [timing/stress](../../ios/DoseTap/Views/PreSleepLogTimingStressCard.swift); [pain/substances](../../ios/DoseTap/Views/PreSleepLogBodySubstancesCard.swift); [activity/food/details](../../ios/DoseTap/Views/PreSleepLogActivityNapsCard.swift).
- Shared choices/pain controls: [StorageModels.swift](../../ios/DoseTap/Storage/StorageModels.swift); [stress enums](../../ios/DoseTap/Storage/StorageRecordModels.swift); [PreSleepLogComponents.swift](../../ios/DoseTap/Views/PreSleepLogComponents.swift).
- Morning flow/choices/defaults/save: [MorningCheckInView.swift](../../ios/DoseTap/Views/MorningCheckInView.swift); [models](../../ios/DoseTap/Views/MorningCheckInModels.swift); [view model](../../ios/DoseTap/Views/MorningCheckInViewModel.swift); [reconciliation support](../../ios/DoseTap/Views/MorningCheckInViewModelSupport.swift); [dose/functioning](../../ios/DoseTap/Views/MorningCheckInDoseAndFunctioningSections.swift); [clinical sections](../../ios/DoseTap/Views/MorningCheckInClinicalSections.swift); [submit/preferences](../../ios/DoseTap/Views/MorningCheckInSections.swift).
- Shared diary and coverage: [NightOutcomeView.swift](../../ios/DoseTap/Views/NightOutcomeView.swift); [NightOutcome.swift](../../ios/Core/NightOutcome.swift). Independent records: [supply](../../ios/DoseTap/Views/SupplySettingsView.swift); [medication picker](../../ios/DoseTap/Views/MedicationPickerView.swift); [catalog](../../ios/Core/MedicationConfig.swift); [sleep-plan cards](../../ios/DoseTap/Views/SleepPlanCards.swift).
- Planned scope: [Food & Drink roadmap](../plans/2026-09-08-food-drink-roadmap.md); [sleep-marker roadmap](../plans/2026-09-08-sleep-markers-roadmap.md); [timing addendum](../plans/2026-09-09-sleep-timing-calculation-addendum.md). These older roadmaps are supplemented by the dated live-state table above, not used as proof of completion.

This is a targeted source/UX inventory, not a full clinical, accessibility, security or export audit. Runtime acceptance, the owner's installed-build behavior and future feedback remain separate. No app fixes, data migration, personal-data correction or new build are claimed by this packet.
