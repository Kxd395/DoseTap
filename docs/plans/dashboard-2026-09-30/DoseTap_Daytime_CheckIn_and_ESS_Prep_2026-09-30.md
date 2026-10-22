# DoseTap: Daytime Check-In and Sleep-Visit Preparation

Date: September 30, 2026
Status: Proposed implementation addendum. No app code, schedules, reminders, prescriptions, or clinical records have been changed.

## 1. Product decision

Add one optional, brief daytime check-in to the existing morning and pre-sleep workflow. Couple it with an appointment-preparation summary of actual experiences, activity opportunities, coping behaviors, and uncertainty. Do not generate an Epworth Sleepiness Scale (ESS) score from diary data.

The initial product goal is a core interaction taking about 20-30 seconds, with optional details after saving. This is a usability target to test, not a demonstrated completion time or validated clinical protocol.

The user already reports completing morning and night questionnaires. Do not add a second morning or evening diary. Inspect the current repository before adding fields because the supplied export predates possible app changes.

## 2. Evidence boundary and corrections to the supplied Gemini review

The Gemini review recommends a momentary Karolinska Sleepiness Scale (KSS), prospective event logging, and a periodic Narcolepsy Severity Scale (NSS). These are distinct concepts, not interchangeable scores.

- KSS is subjective self-report. A validation study compared ratings with performance and EEG measurements, but the app will collect ratings, not those physiological measurements. [R3]
- The supplied review does not identify an exact validated version for its named daily diary or establish its claimed 30/60-second completion times. Treat that format as a proposed custom diary, not a licensed or validated instrument by default.
- The 15-item NSS evidence cited here is from adults with narcolepsy type 1. NSS-2 was studied in narcolepsy type 2. Do not select a subtype-specific scale by inferring diagnosis from medication. [R5, R6]
- Specific daily prompt times and monthly administration schedules are configurable product or clinician choices. Do not label them a universal medical protocol or promise that six monthly values establish a treatment effect.
- Preserve ESS as a separate assessment when the clinician uses it. Prospective diaries can provide additional context; the new feature is not a validated ESS replacement or conversion.

## 3. Reuse existing records

The supplied `insights_bundle(1).json` and `insights_bundle.json` represent morning and pre-night questionnaires. Relevant examples include:

- `checkInSubmissions`: questionnaire type/version and submission timestamp.
- `morning`: grogginess, mental clarity, recovery-duration category, sleep quality, and reported symptoms.
- `context`: explicit day demand, work-phase context, and wake evidence.
- `normalizedEvents`: dose occurrences and record-entry details.
- `preSleep`: questionnaire answers, with coarse nap/context fields where present.

These examples establish exported fields, not the current UI, reliable per-item confirmation, or actual daytime KSS coverage. Do not rename an existing energy, readiness, grogginess, or sleep-quality score to KSS. Do not convert old ratings to a new scale.

## 4. Keep three observation types separate

### A. Momentary assessment

Record current subjective sleepiness using the selected authorized scale and its documented recent recall window. The published fully labeled nine-level KSS implementation describes the immediately preceding five minutes. Preserve the chosen version rather than substituting a today-wide question. [R4]

### B. Event or interval review

Record reported dozing, interrupted activity, coping actions, or naps since an explicitly displayed previous review boundary. This is retrospective self-report over that interval, not a momentary KSS response.

### C. Periodic clinical assessment

Record an independently completed ESS, NSS, NSS-2, or other clinician-selected instrument using its authorized instructions and scoring. Keep instrument identity, language, version, and administration context. No shared composite score.

## 5. Proposed core check-in

Notification copy: "Daytime check-in: record how sleepy you feel when it is safe to pause."

Actions: Open / Remind me later / Skip this check-in. A skip does not imply absence or presence of symptoms.

### Step 1: Current sleepiness

Render the selected authorized KSS form and labels if implementation rights and review are complete. No preselected score. Include an app-level way to leave the assessment incomplete without converting that action into a scale response.

Do not display a previous score, an expected score, a medication estimate, or a suggested answer before the rating. Store the assessment before opening historical context.

If KSS implementation is not yet cleared, a separate explicitly named custom diary can be available, but it cannot use the KSS name or be merged with KSS results. Do not silently switch scales while continuing the same graph.

### Step 2: Activity and posture

Custom context prompt: "What were you doing during the period you just rated?"

Offer concise selectable categories: seated task/reading, watching a screen, conversation, standing/walking, resting, passenger travel, other, or unsure. Work/off-work setting is a separate field; activity and setting are not synonyms.

Optional duration or a mixed-activity indicator can clarify brief versus sustained situations. This does not re-create all eight ESS items.

### Step 3: Compensating behavior

Custom prompt: "Were you doing anything specifically to keep yourself awake?"

Allow No / Yes / Unsure / Not answered. When Yes, optional choices include movement, changing task, seeking conversation, caffeine, taking a break, or avoiding/stopping an activity.

Ordinary caffeine use or walking is not automatically a coping behavior. Require an explicit report of that purpose. Log actions already taken; do not suggest extra caffeine or medication.

### Step 4: Unrecorded events, optional

Custom prompt: "Any unplanned dozing or activity interrupted by sleepiness since [last reviewed time]?"

Allow No / Yes / Unsure / Not reviewed. For Yes, offer linking to an existing event or adding an event with approximate time, duration if known, and consequence. Keep struggling to stay awake distinct from actually sleeping.

Do not demand exact duration or a clinical label such as cataplexy when the user is uncertain. Sudden weakness and unclear events remain neutral reports for review.

The evening review should show the saved entries and ask only about additions or corrections. A count in the review is not another event record.

## 6. Nudge scheduling

Start with one user-selected daytime reminder. Evaluate usability and completion after a short pilot, for example two weeks, before adding burden. An optional later-day check-in can be enabled when there is a specific observation question. The pilot length and cadence are product choices.

Supported anchors:

- A selected clock time on selected days.
- Elapsed time after the designated main wake, with a visible wake-source status.
- A selected break or midpoint of a saved shift.

For a 13-hour shift, its scheduled midpoint is 6 hours 30 minutes after the saved start. The actual start is not known from weekday names alone. Do not invent a clock time. On off days, use a separately configured wake-relative or clock-time anchor. Do not assume it samples the same waking duration as a shift-midpoint prompt.

Save anchor type and offset, schedule version/effective dates, scheduled time, delivered time only if actually observable, and response time. Analyze actual assessment time, not intended notification time. Show both local time and elapsed time since main wake when valid.

Notification requirements:

- Routine, nonurgent reminders. Do not bypass quiet settings for symptom questionnaires.
- User-controlled busy/quiet windows, defer, skip, pause, and reminder permission status.
- No survey interaction while driving or during safety-critical care. Do not claim that the app can always detect those activities.
- Do not wake a person during a known active nap or main sleep for a diary question; record that a prompt was deferred/suppressed where supported.
- A user who opens a delayed prompt rates the present assessment window. The old slot stays late/unanswered; do not backdate the current state.
- A separate remembered-event entry can document what happened earlier without calling it a contemporaneous KSS measurement.
- Keep questionnaire reminders independent of dose alarms, medication plans, and nap timers.
- No reminders generated by a modeled medication amount, inferred wear-off, or desired ESS value.

## 7. Sleep-visit preparation, not ESS prediction

Create `Reports > Prepare for sleep visit` with a patient-reviewed summary of actual activities and events. The standard ESS asks for best estimates even for activities not recently encountered, within the person's usual life. Uncertainty should be discussed rather than disguised as observed evidence. [R1]

The summary can distinguish:

- Reported opportunity with an observation.
- No recent opportunity explicitly reported.
- Activity avoided or stopped because of sleepiness, explicitly reported.
- Uncertain recollection.
- No information collected.

These are diary metadata, not extra scored response choices inserted into the ESS.

Show actual dated examples, including times the person remained awake, reports of effort to stay awake, and changes in activity. Preserve duration/context differences. A short ride is not silently relabeled as an hour-long passenger journey.

Do not turn the observed fraction of selected diary events involving dozing into an ESS item score. Do not map KSS 1-9 to ESS 0-3, average daily KSS to an ESS total, predict the clinician's rating, or suggest numbers to justify treatment.

The formal ESS stays separate and unmodified. The official guidance describes its broader recall period and states that a total cannot be constructed by interpolating missing items. [R2] A genuinely incomplete assessment remains incomplete, with an opportunity for clinician clarification.

If the clinician elects a diary-aided completion workflow, document that administration context. Do not claim the augmented workflow has the same validation as ordinary administration.

Do not ask the user to withhold medication, skip prescribed naps, provoke sleepiness, or test themselves in traffic to obtain evidence. Record usual life and the instructions actually given by the treating clinician.

## 8. Minimum data contracts

### `DaytimeCheckIn`

- `id`, `revision`, `created_at_utc`, `recorded_at_utc`, `assessed_at_utc`.
- `instrument_id`, `instrument_version`, `language`, `authorized_content_version`.
- `recall_window_start_utc`, `recall_window_end_utc`, `response_value` or null.
- `response_status`: answered, unsure/unanswered at app level, skipped, incomplete. Do not redefine a licensed scale's score codes.
- `prompt_id` or null; `entry_origin`: scheduled, user_initiated, explicitly_retrospective.
- `timezone_identifier`, UTC offset, `time_precision`.
- `activity_category`, posture if captured, activity duration if known, mixed-activity flag.
- `coping_status`, `coping_actions`, and observation interval.
- `work_context_id`, `work_block_id`, `shift_position`, `work_context_source` and confirmation.
- `main_wake_event_id`, `main_wake_source`, linked medication/nap event IDs when relevant.
- `event_review_from_utc`, `event_review_to_utc`, `event_review_status`, linked event IDs.
- `optional_note`, provenance, revision audit data.

Derived elapsed times are calculated from linked occurrences using a shared versioned service. Save source IDs, not an untraceable medication-effect label. Missing or conflicting sources stay missing/conflicting.

### `PromptInstance`

- `id`, `schedule_version_id`, intended anchor and source.
- scheduled time, delivery observation if supported, opened/responded time.
- pending, deferred, suppressed, skipped, expired, or responded status.
- optional user-reported deferral reason; no inference of sleeping from nonresponse.

### `VisitPreparationNote`

- activity/context, date or reviewed period, opportunity status.
- evidence event IDs, patient comment, and optional confidence about recollection.
- source, review timestamp, and share selection.
- No predicted score field.

## 9. Reporting and dashboards

Retain the full interval between appointments, including six calendar months and `since last completed visit`. Also provide recent 2-4-week detail as a separate view, not a replacement for the rest of the interval or an altered ESS recall rule.

Recommended displays:

1. Individual current-sleepiness observations across the day, with actual times and optional medication/nap markers. No continuous-state curve inferred between sparse ratings.
2. Distribution/median of responses within comparable sampling slots and work contexts. Keep morning, middle-of-shift, later-day, and pre-bed samples separate.
3. Work-block comparisons using current shift position for daytime events and separately defined surrounding-sleep phase for overnight data.
4. Assessed-interval counts for unplanned sleep, interrupted activities, and coping reports. Show unreviewed intervals explicitly.
5. Activity-opportunity notes and selected examples for the visit.
6. Independently completed, dated clinical-scale scores on separate panels.

Do not pool symptom-triggered check-ins indiscriminately with scheduled samples. Do not count multiple check-ins in one day as independent days. Record protocol changes because collecting more late-day observations can change a pooled average without a treatment change.

Do not convert ordinal categories to percentage wellness or report a percentage of the entire day sleepy from a few sampled moments. Means, if requested, must disclose the sampling definition; keep the response distribution and coverage available.

For illustrative tests, 4 unplanned sleep events on 12 reviewed days within a 14-day range must display event count, reviewed days, and unreviewed days, without extrapolating a monthly burden. All examples in test fixtures are synthetic.

## 10. Clinical and privacy boundaries

The feature supports discussion with the clinician, not diagnosis, individualized dose selection, or fitness-for-duty/driving certification. Repeated subjective measurements remain subjective data.

Provide reviewed wording directing users to take safety action before logging when an event affects driving or other hazardous activity. NHTSA advises safe stopping when sleepy while driving. [R7] Do not reassure based on a low questionnaire score or defer all concerns until a six-month appointment.

Saving a response does not notify a physician unless an actual separately consented communication service exists. Do not imply monitoring.

No health details in notification previews by default, no patient/client/coworker names in work-event notes, and no raw health values in crash/analytics logs. Use explicit export review and sharing consent. Keep exported snapshots and later corrections versioned.

## 11. Instrument and content governance

ESS use requires the relevant license/permission process, and AASM directs users to the rights holder. [R2, R8] Verify electronic implementation requirements. Do not paste a form from another site.

For KSS and NSS variants, establish the exact authorized wording, language, recall instructions, scoring, reproduction rights, and review status before release. A publicly accessible paper is not automatically a blanket license for every questionnaire artifact. This addendum does not reproduce those full instruments or grant permission.

A custom context questionnaire remains custom even when presented adjacent to a validated scale. Maintain distinct content versions and provenance.

## 12. Acceptance checks

1. Existing morning/bedtime ratings are not relabeled or converted to KSS.
2. No new questionnaire rating starts preselected.
3. A 12:00 prompt answered at 14:00 records the actual present assessment at 14:00 and retains the prompt delay.
4. Retrospective notes remain distinct from contemporaneous scale responses.
5. A missing check-in is not zero sleepiness, zero episodes, or proof of sleep.
6. Scales retain their own units, instructions, recall periods, and versions.
7. KSS and diary data never auto-fill or predict ESS responses or totals.
8. No-recent-opportunity diary metadata never becomes an ESS score of zero.
9. Avoided activities are distinguishable from opportunities with no dozing.
10. A five-minute reading episode is not relabeled as evidence of all-day sleepiness.
11. Saved ratings do not trigger medication recommendations, altered dose alarms, or clearance messages.
12. Scheduled samples and symptom-triggered samples remain separately filterable.
13. A work midpoint uses the saved shift start and duration, not a guessed weekday clock time.
14. Off-day and workday anchor differences are visible in comparisons.
15. A nap ending does not create a second main-wake anchor or reset medication history.
16. A deferred prompt during a known nap stays documented without an invented state rating.
17. A revised wake or work record triggers versioned derived-context recalculation without changing the submitted observation.
18. Existing naps/events linked from the check-in are counted once; evening review does not duplicate them.
19. Partial interval review and uncertain event counts remain explicit.
20. A sparse day cannot be represented as continuously monitored or assigned a full-day percent sleepy.
21. Noncontemporaneous before/after values are not presented as a paired response to a nap or dose.
22. An incomplete formal ESS does not receive a prorated total.
23. A change in questionnaire language/version or sampling protocol is identifiable in exported history.
24. NSS versus NSS-2 selection requires documented configuration, not medication-based diagnosis inference.
25. The report preserves full six-month history, monthly coverage, and recent detail separately.
26. Entering an event sends nothing to the physician by default.
27. Sensitive notification text and identifying work notes are excluded by default from shared output.
28. An unauthorized or unreviewed scale implementation cannot be enabled merely by renaming a custom survey.

## 13. Rollout and action log

Build first: a single daytime reminder, authorized momentary rating, optional activity/coping context, and linked event review.

Build next: comparable-time/work-context reports and an unscored sleep-visit preparation summary.

Add a periodic disorder-specific questionnaire only after the clinician selects the instrument and its implementation requirements are satisfied.

Action log: Created this standalone specification. Prior roadmaps, source exports, and the app were not changed. Acceptance checks are proposed tests, not executed app tests.

## References

R1. CDC/NIOSH, ESS instructions in shift-work training: https://www.cdc.gov/niosh/work-hour-training-for-nurses/longhours/mod2/09.html

R2. Official ESS site, purpose, recall period, scoring/missing items, and use requirements: https://epworthsleepinessscale.com/about-the-ess/

R3. Kaida K et al. Validation of the Karolinska sleepiness scale against performance and EEG variables. Clinical Neurophysiology. 2006;117:1574-1581. PMID 16679057. https://pubmed.ncbi.nlm.nih.gov/16679057/

R4. Akerstedt Miley A et al. Comparing two versions of the Karolinska Sleepiness Scale (KSS). Sleep and Biological Rhythms. 2016;14:257-260. DOI 10.1007/s41105-016-0048-8. https://link.springer.com/article/10.1007/s41105-016-0048-8

R5. Dauvilliers Y et al. Narcolepsy Severity Scale: a reliable tool assessing symptom severity and consequences. Sleep. 2020;43:zsaa009. PMID 31993661. https://pubmed.ncbi.nlm.nih.gov/31993661/

R6. Barateau L et al. Narcolepsy Severity Scale-2 and Idiopathic Hypersomnia Severity Scale to better quantify symptoms severity and consequences in Narcolepsy type 2. Sleep. 2024;47:zsad323. PMID 38197577. https://pubmed.ncbi.nlm.nih.gov/38197577/

R7. NHTSA, Drowsy Driving: https://www.nhtsa.gov/risky-driving/drowsy-driving

R8. AASM, Copyright Access Support: https://support.aasm.org/how-do-i-obtain-copyright-premission

Additional supplied sources: User-pasted Gemini review; September 24 DoseTap JSON export. Product requirements and rollout choices in this addendum are proposals, not validated clinical protocols.
