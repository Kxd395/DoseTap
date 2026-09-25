# Daytime medication, sleepiness and physician review delivery plan

Date: 2026-09-25
Status: Owner-authorized staged development; only the bounded capture slice below is being implemented.
Authority: Plane owns work status. SSOT defines implemented behavior.

## Source and review

The owner supplied Physician Review Roadmap v1 and v2. Version 2 is the design
input for individual naps and six-calendar-month/visit-to-visit reporting; v1
remains source history. Neither attachment establishes existing implementation,
clinical verification, a prescription or questionnaire permission. This plan
records the reviewed requirements without copying private patient examples.

Repository baseline: main `062f8e0` / app 0.4.19 (67). All three post-merge PR56
workflows passed on fresh readback. Existing dirty main/legacy worktrees remain
preserved. Implementation uses an isolated worktree.

## What exists and what needs repair

- General medication entries already use `medication_events` independently of
  `dose_events`. Entry is buried in pre-sleep. Catalog defaults preselect amounts,
  the picker retains old entry times, and settings selection is not honored.
- A NULL medication session link is initially possible, but legacy startup
  backfill manufactures a date-string link. New independent entries need NULL
  to remain NULL. Historical links must not be silently cleared or repaired.
- Medication retries lack stable submitted IDs; the duplicate warning searches
  only one date group. Existing deletion is not an audited Undo operation.
- `night_outcome.v1` holds one sleepiness answer per night and requires a night
  and final awakening. A later rating is a correction, not another observation.
- Nap Start/End markers and pre-sleep summaries exist. Marker elapsed time is
  not measured sleep. Orphan/overlapping markers do not establish complete naps.
- The workbook retains source records; its Daytime sheet has nightly diary
  grain. Independent observations need their own source grain and export tests.

## Delivery order and exact ownership

| Slice | Owner | Result and boundary |
| --- | --- | --- |
| A: independent manual medication capture | DOSETAP-74 | Direct Medications entry, explicit amount and Now/Earlier review, stable retry ID, cross-date duplicate review, durable NULL night link and truthful errors. Existing whole-mg catalog only; no preset or Undo claim. |
| B: saved prescription presets | DOSETAP-74 | Immutable revisions and administration snapshots, product components, explicit confirmation, last-log receipts, checked reversal/edit, then optional named groups. |
| C: Sleepiness now | DOSETAP-58 | Independent timed observations with new ID per save, optional night references, no defaults and no required wake/night record. |
| D: day review and naps/rest | DOSETAP-58 | Separate waking-day completeness and functional-impact review, linked nap/rest episodes and durable independent timers. |
| E: periodic ESS | DOSETAP-58, separate licensing gate | Authorized instrument/version/presentation only; original recall period and complete-response scoring. No copied questionnaire ships in A–D. |
| F: physician review | DOSETAP-59 | Full selected period, monthly and recent-detail layers, preview and reproducible report snapshot. Reuse DOSETAP-13/45 exports and DOSETAP-56/57 measurements. |

A is deliberately before one-tap presets: a convenient button cannot safely sit
on implicit amounts, stale times or non-idempotent writes. Complete each bounded
slice and its storage/export tests before exposing its promised controls. Record
phone, accessibility, privacy, licensing and release acceptance separately.

## Medication contract for slice B

Use Medications & Treatment, with daytime, nighttime, other medications and
non-medication supports clearly separated. IR and XR stay visibly distinct.
Names and formulations must be confirmed from the prescription label; do not
silently substitute a guessed brand. Patient-entered is not clinician-verified.

Keep three records: prescribed regimen, intended administration, reported actual
administration. A preset revision stores identity/brand/ingredient, formulation,
optional standardized identifier, components with strength/concentration and
unit count, instructions/schedule including PRN, effective dates, recorded date,
source/verification status and display order. Several presets may refer to the
same medicine. One multi-strength administration retains all its components.

An administration references an immutable preset revision and snapshots the
confirmed identity, actual amount/unit/components, outcome, occurrence, recording
time, named timezone/offset, precision and source. Changing/deactivating a preset
cannot rewrite historical logs. Unknown time requires a real missing timestamp,
not zero or now. Taken, explicit not-taken, uncertain and no report differ.

Log taken now confirms exactly the displayed preset/amount at confirmation time.
Log earlier explicitly reviews date/time; approximate/unknown remain identified.
Persist before feedback, provide last-log receipt, checked Undo/reversal and Edit
with original history. Duplicate submission IDs are idempotent; a genuine extra
administration remains recordable with scoped duplicate review. Groups show each
member/amount before confirmation, create separate administrations, and never
implicitly include PRN medicines. No generic Take all action.

No ordinary daytime action creates, closes or modifies nighttime sessions,
Dose 1/2 outcomes, reminders or inventory. Optional preceding/following sleep links
are independent relationships. No generic total stimulant mg, effectiveness score,
wear-off countdown or automatic dose advice.

## Three distinct sleepiness records

**Sleepiness now:** custom 0–10 rating with explicit anchors, observed-at and
recorded-at times, optional activity and dozing yes/no/unsure. Start unset. Each
new assessment appends a stable ID; editing one ID retains its revisions. Keep
fatigue and concentration separate. No prompts to interact while driving.

**Day review:** custom diary of an explicitly identified waking interval. Ask
about difficulty staying awake, unintentional dozing, functional interruption
and already logged naps. No composite clinical total. Complete/partial/not
reviewed is a separate confirmation. A new contradictory event requires review
of completeness; one logged event does not prove an assessed day. No answers
carry forward. Existing morning questions are reused only with their original
meaning and answer-confirmation limitations visible.

**ESS:** dated periodic assessment of usual dozing propensity over recent weeks
to months, not a daily or momentary measure. Official guidance requires a license
and an arrangement for electronic implementation. All eight authorized responses
are required for a total; missing does not mean zero. No inherited answers or
scale mixing. Reminder cadence is configurable product planning, not a universal
clinical schedule. Until authorization is documented, do not embed question text.

Sources checked 2026-09-25: [official ESS guidance](https://epworthsleepinessscale.com/about-the-ess/)
and [license access](https://epworthsleepinessscale.com/licenses/). The indexed
official guidance was readable; direct page opening returned a tool error, so
license acquisition and presentation permission are still unverified.
[DailyMed identifies Provigil as modafinil](https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=0391f182-1958-9fef-a944-53b229ce99e7);
this does not confirm the owner's prescription or authorize any dose.

## Nap/rest and report rules from roadmap v2

- Each rest attempt has its own durable ID and optional start/end. End minus
  start measures rest opportunity; reported sleep and provider estimates remain
  separate. No sleep, unsure, missing duration and unfinished timer differ.
- Allow multiple episodes and duration-only retrospective records without
  invented timestamps. Midnight/DST/travel cannot duplicate an episode. Main
  daytime sleep and post-Dose-2 return to sleep are not automatically naps.
- Manual/provider/dozing links preserve both sources without double counting.
  Unknown overlap blocks a claimed complete total. State the exact window and
  source policy; waking-cycle totals are not automatically 24-hour totals.
- Physician reports support since-last-completed-visit, six and twelve calendar
  months, recent 14/28/90 days and custom ranges. A six-month view may touch seven
  partial months. No 90-day truncation, 180-day substitution or average of averages.
- Follow-up targets differ from booked appointments; cancellation/rescheduling
  never moves the last completed-visit anchor. Report cutoff cannot be future.
- Full-period significant events remain visible alongside recent detail. Each
  measure has eligible-record and assessed-day denominators. Features introduced
  mid-period are Not collected historically, not symptom-free.
- Regimen changes are dated markers, not causal claims. Actual work/shift,
  required wake, sleep opportunity and recorded source conflicts remain visible.
- Preview, selected sensitive-content inclusion, versioned report snapshots and
  explicit sharing are required. Generated/shared/clinician-reviewed differ.
  Reports and exports are not a promised full-app restore or monitoring service.

## Acceptance matrix

A: no-night save/restart; existing active night unchanged; retry after failure;
same-ID conflict; cross-date duplicate and changed consent; invalid timestamp;
explicit amount/time UI; original creation/occurrence and nullable identity in
JSON/Excel; no success on failed read/write.

B: changed preset preserves old actuals; components total correctly without
cross-drug sums; group partial failure does not replay prefix; reversal/edit
retains original; retry and correction survive restart.

C–D: two same-day observations stay distinct; unknown/unanswered/zero differ;
no night required; failed saves retain answers; nap timers survive restart;
rest/asleep duration separation; overlap/DST/midnight and duration-only evidence;
complete/partial/unassessed-day denominators; full export/Studio parity.

E–F: authorized instrument/version and incomplete-score behavior; calendar-month
and visit anchors; full-period/recent-panel separation; metric-specific coverage;
source corrections create a new report version; privacy preview and explicit share.
