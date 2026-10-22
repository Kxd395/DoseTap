# DoseTap: Work Block & Sleep Dashboard

Date: September 30, 2026
Status: Proposed product and data-contract addendum. No application code, source records, calendar events, or alarms were changed.
Companion: DoseTap_Dashboard_Blueprint_2026-09-30.md. Preserve that document unchanged.

## Decision

Add a dedicated Dashboard > Work Block & Sleep view. Make work-context filters available in Timing, Sleep & Naps, Patterns, Medications, and Physician Review as well. Implement one shared classification service rather than a separate interpretation in every chart.

The purpose is to examine where an observation sits relative to a block of shifts. A simple workday/off-day flag loses the distinction between preparing for the first shift, sleeping between shifts, and sleeping after the final shift. This feature describes context; it does not diagnose fatigue, calculate an optimal dose, or establish causation.

## User-provided schedule and limits

The user reports three 13-hour shifts on Tuesday, Wednesday, and Thursday. Shift start/end times, the date this schedule became effective, and historical exceptions have not been established in this request.

The mapping below assumes daytime shifts and main overnight sleep. It is a proposed interpretation of the stated usual schedule, not confirmation of attendance on historical dates. Overnight shifts or a different main-sleep pattern require actual event-based association. Do not invent start/end times to fill a 13-hour template.

| Main sleep episode | Previous waking day | Following waking day | Phase | Detailed position |
| --- | --- | --- | --- | --- |
| Monday night into Tuesday | Off | Shift 1 | Entering block | Before shift 1 of 3 |
| Tuesday night into Wednesday | Shift 1 | Shift 2 | Between shifts | Between shifts 1 and 2 |
| Wednesday night into Thursday | Shift 2 | Shift 3 | Between shifts | Between shifts 2 and 3 |
| Thursday night into Friday | Shift 3 | Off | After block | First post-block main sleep |
| Friday night into Saturday | Off | Off | Off-block | Second post-block main sleep |
| Saturday night into Sunday | Off | Off | Off-block | Third post-block main sleep |
| Sunday night into Monday | Off | Off | Off-block | Fourth post-block main sleep |

Monday being a non-work calendar day does not make Monday night's sleep unrelated to Tuesday's work. Thursday is a work calendar day, while Thursday night's main sleep is after the block. The first post-block main sleep is Thursday night into Friday under this assumption, not Friday night into Saturday.

Keep four high-level phase categories. Retain finer cycle positions as metadata rather than assigning a new color to every weekday. Add Unknown and Needs review as data-quality states. Off-block does not mean rested or fully recovered.

## Reuse existing information carefully

The September 24 insights bundle already contains `context.explicitNextDayDemand`, `explicitNightType`, `firstNightOffAfterWorkBlock`, `previousScheduleDayType`, `scheduleDayType`, `nextScheduleDayType`, and `scheduledWakeByUTC`. Some questionnaire submissions contain `day_demand.type`, `night.type`, and `night.first_off_after_work_block`.

For the September 21 treatment session, the source contains `explicitNextDayDemand: shift_13h` and `explicitNightType: transition_into_work_block`. Its collected-night `followingDayType` is `unknown`. These are reasons to reconcile definitions and provenance, not proof that one value should blindly overwrite another.

Trace the existing derivation before reusing any schedule field: 'previous' or 'next' may refer to adjacent treatment sessions rather than previous or next work dates. Do not assume these anchors are interchangeable. Existing false/default flags are not necessarily explicitly confirmed answers.

The export establishes a prior data model, not the current implementation after later agent changes.

## Proposed records

### Schedule template, versioned

- `schedule_template_id`, `version_id`, `effective_from`, `effective_to`
- `time_zone_identifier`
- `work_weekdays`: Tuesday, Wednesday, Thursday as the user's proposed default
- `planned_shift_minutes`: 780, explicitly a reported planned duration
- `planned_start_local`, `planned_end_local`: optional until entered
- `source`, `recorded_at`, `confirmation_status`

Do not apply today's template to all historical sessions without an effective date and confirmation of that historical coverage.

### Shift occurrence

- `shift_id`, `schedule_version_id`, `work_block_id`
- `scheduled_start_at`, `scheduled_end_at`
- `actual_start_at`, `actual_end_at`, `actual_time_precision`
- `status`: scheduled, worked, cancelled, not_worked, uncertain
- `source`: user_entered, calendar_imported, template_derived, other
- `confirmed_at`, `recorded_at`, `revision_id`
- Optional exception: overtime, extra_shift, swapped_shift, shortened_shift, leave, illness, other

Calendar import proves a scheduled event, not attendance. Scheduled length does not establish actual hours worked. User confirmation may establish worked/not-worked without establishing exact start/end times.

### Sleep-session context

- `sleep_session_id`, `main_sleep_role`, `role_confirmation`
- `context_basis`: planned_at_sleep_time or retrospectively_confirmed
- `preceding_wake_work_status`, `following_wake_work_status`: work, off, unknown
- `preceding_shift_id`, `following_shift_id`: nullable, explicitly linked
- `work_block_id`, `shift_position_before`, `shift_position_after`
- `phase`: entering_block, between_shifts, after_block, off_block, unknown
- `post_block_main_sleep_index`: nullable, counts main sleep episodes, not naps
- `phase_source`, `classification_version`, `computed_at`
- `review_status`, `conflict_reasons`, `override_reason`

Preserve planned context as known before sleep separately from subsequently confirmed work. A shift cancelled in the morning should not erase the fact that work had been anticipated at bedtime. Exports must identify which context basis their charts use.

Do not force sleep context onto every daytime event. A Wednesday afternoon nap can be 'during shift 2'; Wednesday night's main sleep can be 'between shifts 2 and 3'. Link both to the block but preserve their distinct temporal roles.

## Classification rules

Classify main sleep by work in its adjacent waking periods, using an explicitly selected context basis:

| Work in preceding waking period | Work in following waking period | Phase |
| --- | --- | --- |
| No | Yes | Entering block |
| Yes | Yes | Between shifts |
| Yes | No | After block |
| No | No | Off-block |
| Unknown or unresolved | Any, or conversely | Unknown / needs review |

For a between-shifts label, confirm that the shifts belong to the same block under the versioned roster rule. Otherwise preserve the event links and request review. Default blocks may be runs of consecutive work dates in the effective roster; do not use a hidden arbitrary hourly cutoff. Support blocks other than three shifts.

Associate using the main sleep episode and its relevant waking periods. Do not use the UTC date, the calendar weekday alone, Dose 2's midnight rollover, or the next shift anywhere in the future. If sleep boundaries or associations are ambiguous, preserve uncertainty instead of stretching a waking period across multiple unobserved days.

A night started after midnight remains associated with its intended main sleep episode. Naps do not advance shift position or the post-block main-sleep index. If a main sleep was not recorded, do not silently treat the next recorded sleep as the next consecutive off-night; mark the index uncertain unless schedule/confirmation resolves it.

Preserve the raw observations and version derived classifications. Corrections can regenerate a current analysis but must not silently mutate reports already shared with a clinician.

## Visual meaning and palette

Use a categorical work-phase palette only when the active grouping is work phase:

| Phase | Suggested color family | Visible short label |
| --- | --- | --- |
| Entering block | Blue | Entering |
| Between shifts | Purple | Between |
| After block | Amber | After |
| Off-block | Teal | Off |
| Unknown / needs review | Neutral gray with explicit status | Unknown / Review |

These are proposed categorical roles, not severity levels. Do not use red/green pass/fail meanings or make Off imply good and Work imply bad. Validate actual palette tokens against light/dark backgrounds, increased contrast, grayscale, and color-vision differences before release.

Prefer labeled row headers or phase panels so color is supplementary. In a combined scatter display that needs redundant markers, use four clearly different, consistently mapped shapes for the same four phases. Do not assign color to phase and shape to dose-reference status in that display. Symbols in plot, legend, detail, and export must share a single mapping.

A reference-spacing view may retain its own inside/outside symbols. Switching to work-phase grouping must replace that encoding and visibly update the legend. It must not stack both schemes onto every point. The built-in 150-240 minute spacing reference may remain as a neutral vertical band with the visible label: 'Built-in spacing reference; not a prescription.' Do not recolor that band for work phases.

D1 and D2 are administration labels on event timelines. Neither work-phase colors nor reference symbols represent dose number.

## Dashboard composition

### 1. Primary view: Work-cycle profile

Question: How does a selected outcome vary across positions in the work cycle?

Show labeled positions for before shift 1, between shifts 1 and 2, between shifts 2 and 3, first post-block main sleep, and later off-block sleep. Allow expansion of later off-block sleep into its known successive positions.

On mobile portrait, use horizontal labeled rows with individual dots and one common numeric axis. Display a median and middle-50% interval for continuous measures when estimable; do not label that interval a confidence interval. Do not assign numerical midpoints to categorical recovery answers. Use category distributions for those answers.

Choose one outcome at a time: dose interval, observed main-sleep duration, observed sleep after Dose 2, elapsed Dose 2 to required wake, or a compatible morning outcome. Each has its own eligibility and count. Also show the number of distinct work blocks represented.

Do not connect points from unrelated blocks to invent a recovery trajectory. A single selected block may have a connected, time-ordered view with explicit missing gaps. Do not label the lowest or highest value the best interval.

### 2. Secondary view: Week-by-week block matrix

Rows are blocks identified by their first-shift date; columns are cycle positions. Cell value is one chosen measure and includes the originating sleep-session date. Missing stays visible. Nonstandard blocks have their actual position counts rather than being forced into three shifts.

For a value heatmap, fill intensity represents the metric. Put phase colors in the column headers or a context strip, not also in the same cell fill. Expand cells to the underlying session and metrics.

At six-month scale, show blocks and monthly summaries without inventing values for missing cells or pooling incompatible regimen periods. On mobile, use a subset of positions with explicit navigation or a full-width detail view rather than unreadable seven-column labels.

### 3. Supporting view: Interval versus outcome, split by phase

Reuse the existing interval scatter in four labeled panels or a single selected-phase view, with matching x/y scales. For a combined display, enable 'Group by: Work phase' with the work-phase palette and redundant work-phase symbols. Keep the same neutral spacing reference boundaries where applicable.

Make the x-axis interval definition and y-axis sleep definition explicit. Total main sleep, sleep after Dose 2, and sleep quality are not interchangeable outcomes.

No default regression line, automatic best-dose conclusion, or 'work causes poor sleep' assertion. Compare sleep opportunity, medication regimen, source policy, and outcome timing alongside any group difference.

### 4. Optional context detail: Hours and timing around a shift

Once actual shift times are available, show shift end to main-sleep start, actual time between shifts, last administration to required wake, and recorded work hours in a stated lookback interval. Label scheduled versus actual separately. Elapsed time off work is not automatically available sleep time; commute and other obligations may be unknown.

Before/after-shift symptom observations and morning observations must be separate series or explicitly aligned at comparable times. An after-shift symptom belongs to the shift that just happened, not automatically the next work day.

## Controls and interaction

- Date range: 7 days, 28 days, 90 days, 6 calendar months, since last completed visit, custom.
- Context basis: planned-at-sleep-time or confirmed work history. Default must be visible. Optional 'include schedule-derived' toggle shows the number added.
- Group by: none, work phase, spacing reference. Only one point-grouping meaning at a time.
- Phase and shift-position filters, regimen period, and source/coverage policy.
- Tap/focus selects a record; offer previous/next and a table view. Show all candidates when points overlap.
- Selection detail includes main-sleep date span, phase, previous and following shift, source/status, exact interval, exact outcome, and missingness.
- Mobile: one dominant chart; controls in a compact sheet. Tablet/desktop: the selected record can populate a side inspector. Preserve selection across views and refreshes.
- Unknown work context remains visible and is counted separately, not discarded or treated as Off.

## Collection burden and overrides

Set the usual schedule once. Ask only for relevant changes or quick confirmation. Example: 'Scheduled: shift 2 of 3. Did this change?' A lack of response preserves Scheduled, not Worked.

Support extra shifts, overtime, leave, illness, swapped days, and changed hours. A change to one shift can change adjacent sleep phases. Version those derivations and explain why a label changed.

Phase colors and work-context changes cannot reschedule medication alarms, change prescribed doses, or alter an existing nighttime session. Scheduling remains an independently configured feature.

## Physician review

Add a Work-block comparison section to the six-month/since-visit report. Include phase and detailed position where enough observations exist; show individual sessions, duration summaries, categorical outcomes, nap counts per assessed day, and distinct-block counts.

Keep first post-block main sleep separate from later off-block sleep. Include schedule version/effective dates, actual-versus-planned basis, unresolved context count, regimen markers, and the selected outcome definition. Do not portray the schedule association as proof of medication effectiveness or fatigue caused by work.

Do not infer that 'after block' means recovered. Recovery is something to review using reported functioning and sleep, not an automatically assigned physiological state.

## Acceptance checks (specification, not executed app tests)

1. Under the stated daytime schedule, Monday night into Tuesday is Entering, even though Monday daytime is Off.
2. Tuesday night into Wednesday is Between shifts 1 and 2.
3. Wednesday night into Thursday is Between shifts 2 and 3, not After block.
4. Thursday night into Friday is the first post-block main sleep.
5. Friday night into Saturday is a later off-block main sleep, not the first post-block main sleep.
6. Sunday night into Monday is Off-block, not automatically Entering solely because Tuesday is the next shift in the future.
7. A main sleep beginning after midnight keeps its reviewed episode association.
8. A nap ending on a work date does not change main-sleep phase or advance the cycle.
9. A missing work-status answer remains unknown or schedule-derived, never confirmed Off or Worked.
10. A calendar-imported shift remains Scheduled until attendance is confirmed.
11. Adding a Friday shift changes the relevant prospective block and adjacent phases; prior planned snapshots are preserved.
12. A cancelled Wednesday shift is reflected in the selected context basis, with revised block association and history retained.
13. A new effective schedule does not overwrite all prior months' classifications.
14. Unknown actual shift times cannot produce precise actual work-hour or between-shift totals.
15. Switching Group by updates markers, colors, legend, accessible descriptions, and export together.
16. In work-phase mode, shapes do not simultaneously encode reference status or D1/D2.
17. The 150-240 minute built-in reference remains labeled as non-prescriptive in every relevant display and export.
18. A work-phase heatmap and a value heatmap do not give the same fill two different meanings.
19. Each metric reports its own eligible observations, missing observations, and distinct blocks.
20. A six-month report separates first post-block sleep, later off-block sleep, regimen changes, and incomplete periods.
21. Historical reports remain versioned when a shift or sleep association is corrected.
22. Phase changes cannot alter medications, alarms, or nap timers.
23. Mobile, grayscale, color-vision simulations, VoiceOver, large text, and table navigation preserve category identity.
24. Exporting a selected chart preserves its date range, context basis, categories, denominators, and reference wording.

## Evidence and design references

- User statement, September 30, 2026: usual Tuesday/Wednesday/Thursday schedule, three 13-hour shifts; interest in entering/leaving the work block.
- Supplied `insights_bundle(1).json`, original lines 1643-1694: collectedNight following-day status; context explicit demand, transition label, schedule flags, and required wake.
- Supplied `DoseTap_Dashboard_Blueprint_2026-09-30.md`: shared context, classification, interval, accessibility, and reporting requirements.
- Apple Human Interface Guidelines, Charts: https://developer.apple.com/design/human-interface-guidelines/charts
- W3C WCAG 2.2, Understanding Use of Color: https://www.w3.org/WAI/WCAG22/Understanding/use-of-color

The phase rules, palette roles, UI composition, and build priorities are proposed design decisions, not a clinically validated scoring instrument. Exact colors and contrast remain to be tested in the app. No live outcomes were reanalyzed for this addendum.

## Action log

Created this addendum only. The earlier dashboard blueprint and source files were preserved. No app code, schedule, external calendar, medication instruction, or alarm was modified.
