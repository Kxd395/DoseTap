# Dashboard and collected-data owner review

Date: 2026-09-11. Inventory baseline: `e98c5a7744d62993ad1a9f8d0bd6cb20bb6f28d1`, app **0.4.19 (45)**.
Plane: **DOSETAP-45** owns this dashboard audit/plan; **DOSETAP-57** owns the next bounded sleep-marker implementation. This is a source audit and proposal, not proof of phone, provider, accessibility, privacy or release acceptance. No personal Health records or questionnaire answers were inspected for this inventory.

## Recommended dashboard plan

The first comparison should be **Sleep before work** versus **Sleep before a day off**, with **Unclassified nights** visible. “Workday sleep” alone is ambiguous: it could mean sleep after a shift or sleep preparing for the next shift. Show both sides of the transition:

| Previous day / following day | Display label | What it helps review |
| --- | --- | --- |
| Off → Work | First workday after time off | Preparation for returning to work |
| Work → Work | Between workdays | Sleep within a work block |
| Work → Off | First day off after work | Recovery after a work block |
| Off → Off | Between days off | Sleep during time off |
| Either side unknown | Transition not recorded | Missing classification; never infer a day off |

The primary two groups use the explicitly confirmed **following day** answer in Wake & Next Day. The four transition groups need an independently confirmed previous-day assignment or an unambiguous adjacent, confirmed day. A gap between recorded nights cannot establish the missing day. Existing “first night off” answers are supporting context; contradictory answers must be shown for review.

For overnight shifts, daytime recovery sleep, rotating schedules and multiple sleeps, label the relationship to the **actual shift** (before/after, absolute start/end, entry timezone) before assigning a transition. A calendar-date label or a scheduled wake warning alone does not establish that relationship. Until that relationship is recorded, retain Unknown. Do not reconstruct historical work from today's recurring schedule or assume Saturday/Sunday means off. Schedule exceptions and planned versus actually worked status need separate provenance.

### Calculations and missingness

- **Mean sleep = sum of usable per-night sleep minutes ÷ usable nights**, one weight per reviewed treatment night. Show hours/minutes, usable `n`, total classified nights, and missing/partial/conflicting nights alongside every mean.
- Keep **reviewed treatment-night total**, **primary sleep episode**, and **daytime naps** separate. Label the selected definition; never silently switch definitions between groups. The existing Apple Health dashboard total uses its legacy primary-episode selection and is not yet the reviewed-window total.
- Offer median and spread (for example the middle 50%) in detail. Show individual nights so one unusually long recovery sleep is visible. Do not average precomputed weekly means with unequal counts.
- Use a single selected provider and definition for both groups. Apple Health and WHOOP are separate estimates; Apple Health may itself contain third-party samples. Do not average providers together or silently substitute one when another is missing.
- A complete observed all-awake window can contain **0 minutes asleep**. No samples, no permission evidence, unknown gaps and incomplete stage data are **not zero**. Partial observed sleep may be shown as a lower-bound observation, but cannot masquerade as a complete-night total in the primary mean.
- Publish per-metric eligibility, not one global completeness score. A night may have a valid total but no resolvable sleep onset, or a recorded dose but no next-day rating. Unknown work status is excluded from work/off means and counted separately.
- Filter using the explicitly defined following-day/shift relationship. Keep session identity and absolute boundaries across midnight, daylight-saving changes and travel. Never add 24 hours merely to make an invalid interval positive.
- Display differences as descriptions of recorded nights. These groups do not establish that work, medication, a partner, or a device caused an outcome. No driving-clearance label or dose-adjustment advice belongs here.

### Proposed layout (not implemented by this document)

1. **Overview:** source, date range and sleep definition; two mean cards with counts; an Unknown card; treatment-night total versus primary episode clearly labeled.
2. **Transitions:** four-row table above, each with mean/median, usable/eligible nights, missingness and a tap-through night list.
3. **Night detail:** reviewed boundaries, provider bands, explicit doses and sleep markers; reason text for unresolved metrics; naps and bathroom logs remain distinct tracks.
4. **Trends:** individual-night points and optional rolling summaries with denominators. Keep next-day sleepiness separate from morning readiness and grogginess.
5. **Data:** searchable collection inventory, source availability, export coverage and correction history. The current dashboard has All / Overview / Trends / Data sections; there is no separate full in-app Docs section yet.

### Existing dashboard audit findings

| Current behavior | Consequence / proposed correction |
| --- | --- |
| Wake-method comparison can filter by confirmed workday/day off; overall averages do not expose the four transitions | Reuse the confirmed following-day field, then add transition classification with explicit missingness |
| Calendar weekday timing charts use `sessionDate` | Weekday is not work status; keep this chart separately labeled |
| “Bathroom wake count” is backed by bathroom event count | Rename to **Bathroom logs** in a later dashboard UI slice; do not claim physiological awakenings |
| “Sleep after Dose 2” estimates sleep within Dose 2-to-final-wake bounds | Keep distinct from **Dose 2 to return to sleep** latency |
| Data category completeness counts dosing, provider, morning and pre-sleep presence | Presence is not accuracy, boundary quality, full coverage or active confirmation |
| Captured-metrics catalog mixes source answers, derived values and optional provider fields | Add Collected / Derived / Preference / Planned / Unavailable labels and links to definitions |
| WHOOP stage completeness masks exist; some legacy summary convenience values use zero | Eligibility must use completeness flags; missing provider data must not enter means as zero |
| Some morning fields have legacy default values | Saved does not prove every default was actively confirmed; audit defaults before new correlations |

Sources: [dashboard calculations](../../ios/DoseTap/Views/Dashboard/DashboardAnalyticsMetrics.swift), [comparison support](../../ios/DoseTap/Views/Dashboard/DashboardAnalyticsSupport.swift), [night aggregates](../../ios/DoseTap/Views/Dashboard/DashboardTypes.swift), [catalog](../../ios/DoseTap/Views/Dashboard/DashboardAnalyticsCatalog.swift), [work schedule](../../ios/Core/SleepPlan.swift).

### Calculation fixtures required before implementing averages

Use synthetic nights with independently known classification and sleep minutes: Off→Work 300, Work→Work 420, Work→Off 480, Off→Off 360. Expected before-work mean = 360 minutes (`n=2`), before-off mean = 420 (`n=2`). An unclassified 600-minute night changes neither mean. A missing sleep value increases the relevant eligible denominator only; a complete all-awake night adds a valid zero. Repeat with missing previous-day answers, a missing calendar day, overnight shifts, split sleep, naps, provider disagreement, duplicated imports, DST transitions, travel and schedule corrections. Recompute after corrections; saved reports retain their calculation date and version.

## Collection inventory: how to read it

**Collected** below means a compiled input/storage path exists, not that this owner supplied a value or authorized a provider. **Optional provider** means the account, permissions and returned records are required. **Derived** means calculated from other records. **Preference** means reusable configuration, not confirmation of a symptom or event. **Legacy/model-only** fields must not be advertised as verified current collection.

Every clinical record needs stable identity, session/source association, occurrence time where known, capture/entry time, timezone context, correction provenance and explicit missingness. Unknown, unanswered, explicit none, skipped and completed are different. `session_date` groups records; it is not a substitute timestamp. The tables below group related fields for readability; exact JSON names and schema ownership remain in [DataDictionary](../SSOT/contracts/DataDictionary.md), [database schema](../DATABASE_SCHEMA.md) and linked source models.

### Apple Health: optional read access

| Information | Current representation / units | Availability and meaning |
| --- | --- | --- |
| Sleep category samples | Start/end, in-bed, awake, asleep/unspecified, core, deep, REM; unknown values retained in evidence handling | Read from HealthKit; source may be Apple Watch, manual entry or another app |
| Heart rate | Samples and summary, beats/minute | Requested read type; absence is missing |
| Resting heart rate | Beats/minute | Separate from night average HR |
| Heart-rate variability | **SDNN**, milliseconds | Not interchangeable with WHOOP RMSSD |
| Respiratory rate | Breaths/minute | Availability depends on data in Health |
| Legacy night summary (derived) | Total sleep, stage minutes, first sleep, first/final wake, last observed sleep end, observation end, time to first wake, wake count, physiological summaries | Uses existing primary-episode selection, including a 90-minute cluster-gap policy; not an accepted treatment-night total |
| Reviewed-window evidence (derived, point-in-time) | Asleep/awake/unmeasured/conflict bands; classified coverage, observed minutes, rejected samples, derivation version, query/check time | Explicit reviewed bounds; unknown time is not invented sleep or awake |
| Provider provenance | Sample UUID, category, source name/bundle/revision, device, available provider timezone metadata | Held in raw evidence for the reviewed query; durable revision/deletion ledger and complete raw-export parity remain open |

The configured read types are sleep analysis, heart rate, resting heart rate, HRV SDNN and respiratory rate. This is not an implemented request for steps, calories, blood oxygen or temperature, and it does not write medication or sleep to Health. Authorization-request completion is not proof that Health granted access; an empty response has multiple possible causes. See [HealthKit service](../../ios/DoseTap/HealthKitService.swift) and Apple's [sleep category definition](https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis).

### WHOOP: conditional integration, live acceptance still open

| Information | Decoded / derived fields | Current boundary |
| --- | --- | --- |
| Connection | OAuth account consent, refresh/access tokens and expiry | Tokens belong in Keychain; never display/export them in the Data catalog |
| Profile | User ID, optional first/last name and email | Profile model/scope exists; not needed for sleep-average grouping |
| Sleep record | Sleep ID, user ID, created/updated, start/end, timezone offset, nap flag, score state | Night-summary consumer uses eligible non-nap sleep records; account and successful query required |
| Sleep stages (aggregate) | In-bed, awake, no-data, light, slow-wave, REM milliseconds; cycle and disturbance counts | Aggregated durations/counts are not per-stage timestamp intervals |
| Sleep scores | Performance, consistency, efficiency percentages; respiratory rate | Provider-defined estimates; incomplete/unscored records are not valid zeros |
| Sleep needed | Baseline, debt, recent-strain and recent-nap adjustments in milliseconds | Provider model, not DoseTap medication guidance |
| Recovery | Cycle/sleep/user IDs, timestamps, score state, calibrating flag, recovery score, RHR, HRV **RMSSD** ms, SpO2 %, skin temperature °C | Optional enrichment; recovery failure must not erase available sleep |
| Flattened night summary | Sleep/stage minutes, awake/in-bed, disturbances, efficiencies, needs, optional recovery/physiology; completeness flags | Used by dashboard source selection; retain missingness flags |
| Cycle model/helper | Start/end, timezone, timestamps, strain, kilojoules, average/max HR | A helper/model exists; normal sleep/recovery summary loading is not proof this is actively collected in Dashboard |
| Stage-series and heart-rate helpers | Code contains separate helper requests | Public API support and live results are unverified; do not advertise these as available interval evidence |

The public [WHOOP API reference](https://developer.whoop.com/api/) documents sleep stage **aggregates**. It does not establish the app helper's proposed timestamped stage-series contract. Consequently this slice must not derive dose-to-sleep boundaries from WHOOP summary totals. Configured scopes include sleep, recovery, cycles, profile and offline refresh; successful local decoding is not live-account acceptance. See [OAuth documentation](https://developer.whoop.com/docs/developing/oauth/), [integration boundary](../WHOOP_INTEGRATION.md), and `ios/DoseTap/WHOOP*.swift`.

### Pre-sleep questionnaire: source record and normalized answers

Source: [app storage models](../../ios/DoseTap/Storage/StorageModels.swift). Do not substitute the older, smaller DoseCore compatibility `PreSleepLogAnswers` for this app payload.

| Group | Collected fields / choices | Interpretation |
| --- | --- | --- |
| Record envelope | ID, session ID/date association, creation UTC, local offset, completion state, answer JSON, questionnaire version | Blank/skipped/completed differ; selected treatment night may initially have a date placeholder |
| Intended sleep | Now / roughly 15, 30, 60 minutes / later; later reason | Intention, not measured onset |
| Stress | Level 1–5, drivers, progression, notes; older single-driver key retained | Independent from pain and anxiety |
| Pain | Coarse burden plus independent structured pain entries; legacy locations/type retained | Separate back and foot entries; see pain table below |
| Planned dose | Planned total nightly mg, split ratio, Dose 1 mg, Dose 2 mg | Plan only; never an administration record |
| Caffeine | Source selections, last intake time, last/daily US fluid ounces and/or mg in versioned amounts; legacy stimulant and amount keys | Volume and caffeine mass are distinct; last consumption differs from entry time |
| Alcohol | Category, last drink time, last amount and daily total drinks | Self-report for this night; not a clearance calculation |
| Exercise | Level, type, last time, duration minutes | Optional context |
| Naps | Today/duration category, count, total minutes, last end time | Self-report separate from paired quick logs/provider evidence; avoid double counting |
| Last food | Finished time, meal/snack/caloric drink, optional high-fat answer, notes; legacy late-meal flag/end | Most recent intake, including later snacks; not a persistent shared Food & Drink diary yet |
| Screens | In-bed use and last-used time | Self-report |
| Room / aids | Temperature category, noise level, sleep-aid selections; legacy single aid | Some reusable setup fields can be filled without submitting |
| Sleeping setup | Arrangement, conditional shared-space detail, pets, location | Optional planned context; see matching morning record below |
| Notes | Free text | Sensitive; can contain identifying details the app did not explicitly request |

### Pain observations and reusable preferences

| Field | Values / meaning |
| --- | --- |
| Area | Head/face, neck, upper/mid/lower back, shoulder, arm/elbow, wrist/hand, chest/ribs, abdomen, hip/glute, knee, ankle/foot, other |
| Side | Left, right, center, both, not applicable |
| Intensity | 0–10 for an individual confirmed entry; separate entries can have different levels |
| Sensations | Aching, sharp, shooting, stabbing, burning, throbbing, cramping, tightness, radiating, pins and needles, numbness, other |
| Pattern / notes | Optional constant/intermittent/unknown and free text |
| Identity / derivation | Area-side entry key; source, source record and source entry key link derived symptom facts |
| Reusable pattern | Local saved preference; selectable pattern fills structure for a fresh confirmation, not tonight's automatic symptom/intensity |
| Build 45 morning reuse | Apply one saved pattern (for example foot only), choose a fresh level, retain independently entered back details; preference writes remain separate from questionnaire save |

Body-map support also represents structured anatomy/side and normalized point coordinates linked to symptom locations. Symptom summaries are rebuildable derivatives, not extra independent observations. See `ios/DoseTap/Storage/EventStorage+SymptomEvents.swift` and the schema. No diagnosis is inferred from a location or sensation.

### Sleeping setup: planned, actual and preference are separate

| Record | Fields / choices |
| --- | --- |
| Planned arrangement | Alone in room; partner same bed; partner same room/separate beds; other people; other arrangement; unsure/prefer not to answer |
| Additional planned context | Conditional shared-space detail; pets on bed/in room/both/no pets/unsure; usual home bed/another home bed or room/away/other |
| Usual setup preference | Explicit Save as usual / Use usual / Forget; fill unanswered fields only; not tonight's confirmation or clinical-history deletion |
| Morning plan snapshot | Copy of the plan shown when the morning answer was made; later pre-sleep edits do not silently change it |
| Actual confirmation | Same as planned / different actual setup / unsure / prefer not; no automatic same answer; actual arrangement fields when relevant |
| Effect | No noticeable effect / helped / disrupted / both / unsure / not applicable |
| Contributing factors | Noise/snoring, movement, schedules/alarms, care responsibilities, pets, comfort/support, other |

All may remain Not recorded. No companion names or exact location are requested. Source keys `sleepingSetup` / `sleepingContext`; normalized keys `pre.sleeping_setup.v1` / `sleeping_context.v1`. These remain sensitive information. See [delivery guide](2026-09-10-sleeping-arrangement-delivery.md).

### Morning questionnaire

Source: [storage record](../../ios/DoseTap/Storage/StorageRecordModels.swift), [view model](../../ios/DoseTap/Views/MorningCheckInViewModel.swift), [answer models](../../ios/DoseTap/Views/MorningCheckInModels.swift). UI/model paths and labels must be checked when changing these fields; some legacy defaults do not capture explicit confirmation separately.

| Group | Collected fields |
| --- | --- |
| Envelope | ID, session ID/date, timestamp, questionnaire version, normalized submission/source association |
| Sleep / waking | Sleep quality 1–5 in quarter-point steps; rested Not at all/Slightly/Moderately/Well/Very well; grogginess None/Mild/Moderate/Severe/Can't function; sleep inertia <5/5–15/15–30/30–60/>60 minutes; dream recall None/Vague/Normal/Vivid/Nightmares/Disturbing |
| Cognitive / emotional | Mental clarity and readiness each 1–5; mood Very low/Low/Neutral/Good/Great; anxiety None/Mild/Moderate/High/Severe; optional stress 1–5, drivers/progression/notes |
| Physical section | Section-presence flag; independent pain entries; legacy pain location/severity/type; derived burden; headache flag/severity/location/migraine; reflux, restless legs, bathroom urgency, stiffness, soreness, notes |
| Respiratory section | Section-presence flag; congestion, throat condition, cough type, sinus pressure, feverish feeling, sickness level, notes |
| Other experiences | Sleep paralysis, hallucinations, automatic behavior, fell out of bed, confusion on waking |
| Sleep therapy | Used-therapy flag, device, self-reported compliance percentage, notes; not imported CPAP telemetry |
| Environment | Section-presence flag, room temperature, noise, sleep aids, notes, independent planned/actual sleeping-context record |
| Timing context | Night type, first night off after work block, wake type, next-day demand, legacy Dose 2 wake method, back-to-sleep <15/15–30/30–60/>60 minutes/Never/Unsure, taken/skipped reasons, reason notes |
| Optional work/safety context | Wake requirement, commute minutes, driving-confidence self-report, daytime sleepiness, cataplexy burden, optional shift start/end UTC and next required wake UTC |
| Optional clinical context | Sleep disorders and notes, co-medication notes, reported pharmacogenomic fast-metabolizer flag, clinician-reviewed flag and notes |
| General notes | Free text |

Readiness, sleepiness, grogginess, anxiety and pain are separate constructs; do not combine them into an unreviewed “safety” score. A driving-confidence answer is not clearance to drive. Morning Save itself never creates a dose. Reconciliation requires an explicit administration/skip choice; confirmed answers survive write failure with retry guidance.

### Wake & Next Day (separate night-outcome record)

| Field | Choices / meaning |
| --- | --- |
| Dose 2 wake method | Natural / alarm / other / unknown; canonical confirmed diary answer requires actual Dose 2 |
| Backup alarm set | Yes / no / unknown; alarm existence/firing does not prove wake cause |
| Following day | Workday / day off / unknown; proposed primary work-average classification |
| Final awakening | Optional absolute timestamp; not inferred from dose or last wearable sample |
| Next-day sleepiness | Optional personal 0–10 rating with assessment time; final awakening required for timing context |
| Reviewed sleep window | Stable session ID, absolute start/end, review time, entry timezone and both UTC offsets, user-reviewed source/version |
| Correction history | Prior answers/windows, correction reason and recorded time |

Current storage has one editable night-outcome assessment per night. **DOSETAP-58** must add independent timed observations before a second daytime assessment can be treated as a new observation instead of an edit. Reviewed boundaries are not measured sleep. See [NightOutcome](../../ios/Core/NightOutcome.swift) and [boundary contract](../SSOT/contracts/DataDictionary.md#reviewed-night-window-dosetap-56).

### Dosing, bathroom and other event logs

| Record | Fields / event vocabulary | Meaning and limits |
| --- | --- | --- |
| Canonical dosing ledger | Event ID, type, absolute timestamp, session date, optional stable session ID and metadata; Dose 1, Dose 2, extra dose, explicit skipped Dose 2, snooze | Only explicit administration confirmation records a taken dose. Missing is not skipped |
| Dose metadata / corrections | Writer-defined amount/context, action/source correlation, early/late/extra classification, snooze information; correction occurrence/entry provenance and reason where defined | Legacy metadata may be absent; planned amount is not necessarily administered amount |
| Session projections | Current active session, durable session lifecycle, dose times, skipped state, snooze count | Rebuilt/maintained from canonical transactions; not extra administrations |
| General medication log | Separate local medication events with their own identity/time/metadata | Does not drive the two-dose state machine; no new multi-medication management proposed |
| Bathroom | Generic event ID/type/time/session, optional notes and display color | Visit log only; no structured urine/bowel distinction, volume, stool scale, duration or return-to-sleep timestamp in this event |
| Other quick logs | Water, snack, nap start/end, lights out, brief wake, in bed, anxiety, dream, heart racing, noise, temperature, pain; final-wake/legacy and unknown event strings retained | Current picker has 14 choices. Other stored vocabulary remains forward-compatible |
| Nap derivation | Paired start/end duration, incomplete and ambiguous pairs | Missing endpoints are not invented; self-report/provider naps are separate evidence |
| Event counts / intervals | Bathroom logs, snoozes, dose interval, timing classifications, event timelines | Counts describe recorded events, not complete physiological counts. No bathroom logs does not prove no visits |

Source: [event models](../../ios/Core/EventStore.swift), [quick-log catalog](../../ios/DoseTap/UserSettingsManager.swift), [event contract](../SSOT/contracts/DataDictionary.md#sleep-events). Alarm fire/open/stop, app lifecycle, elapsed time and questionnaire Save must never generate administration records.

### Configuration, supply, provenance and diagnostics

| Data | Purpose / storage boundary |
| --- | --- |
| Work/wake schedule | Local SQLite versioned schedule with timezone, optional working weekdays, wake time, selected warning policy, cutoff/buffer and dated exceptions; planned schedule, not an actual-shift attendance ledger |
| Other preferences | Dose target, snooze/alarm/reminder options, sleep plans, quick-log arrangement, display/integration options and local reusable questionnaire setup; preferences do not confirm nightly facts |
| Supply / bottle | Local bottle-opening occurrence and recorded times, identity, reminder configuration/source and inventory snapshots; separate from dose administration |
| Normalized check-ins | Questionnaire versions, question IDs, completion state, source IDs and answer payloads; current new pre/morning submissions use v3 dated 2026-09-10 |
| Derived symptoms | Source-linked facts, locations, body-map points, idempotency command results and per-night summaries; editing source answers replaces prior derived facts transactionally |
| Operational data | Schema migration ledger, session lifecycle, diagnostic correlation/events and optional exported support bundles under the diagnostic/redaction contract |
| CloudKit staging | Tombstones and staged sync support exist; this is not proof of accepted production sync or backup coverage |

The clinical inventory intentionally names credential categories without values. Secrets, tokens and private drafts are not report content. See [diagnostic contract](../DIAGNOSTIC_LOGGING.md) and [storage boundaries](../SSOT/contracts/DataDictionary.md).

## Persistence, export and the proposed Data/docs view

Source pre-sleep/morning JSON and normalized submissions retain sleeping and pain context. Collected-night JSON/CSV and Studio expose mapped fields; Studio also retains raw questionnaire payloads. A field's presence in source JSON does **not** prove it has a dedicated flat CSV column, chart or clinician-report label. Reviewed-window metadata/assessment has explicit export mapping; the point-in-time provider projection and new metrics need separately reviewed export adoption. Saved usual/pain preferences are outside the clinical-event export and full-backup claim. Do not equate a local database copy, report export and accepted recoverable backup.

For each Data-view entry, propose: human label; stable field/key; Collected/Derived/Preference/Planned status; choices and units; source; occurrence versus entry time; optional/default/missing semantics; treatment-night association; current persistence and export format; correction/deletion behavior; derivation version and denominator when relevant; sensitivity; screens that use it; owner decision **Keep / Optional / Change / Remove / Need more information**. Generate the app catalog and Markdown from one reviewed manifest in a later slice to prevent drift. This document does not change collection or delete existing history.

### Owner review queue and implementation order

| Priority | Decision / gap | Next bounded action |
| --- | --- | --- |
| Now | Review necessity of optional clinical/pharmacogenomic, co-medication, driving-confidence, companion and free-text data | Owner/privacy wording review; retain existing records meanwhile |
| Now | Build 45 foot-only preference reuse on exact night | Install/verify reachable phone, owner chooses fresh actual level, completes/reopens; confirm back entry and saved preferences unchanged |
| Next engineering | Dose-to-sleep / return-to-sleep with observed transitions, missingness and conflicts | DOSETAP-57 consumes DOSETAP-56 reviewed provider evidence read-only; do not borrow WHOOP aggregates or invent awakening counts |
| Next dashboard | Work/off summary definition and transition classification | DOSETAP-45 implements the above fixtures and denominator UI after source/anchor contract review; no implied acceptance from this plan |
| Following | Separate timed daytime ratings and actual dozing | DOSETAP-58, new observations rather than overwriting earlier ratings |
| Following | Shared Food & Drink history, then questionnaire reconciliation | DOSETAP-53 before dependent DOSETAP-54; finish/capture times, later snacks and fresh alcohol answers |
| Later | Independent last-recorded-dose to planned hazardous activity readout | DOSETAP-60 specification and current primary-source wording review first; no “safe to drive” claim |
| Ongoing | Provider availability/deletion/revision, export parity, accessibility and privacy | Maintain explicit live-account, signed-phone, VoiceOver and release gates |

Dashboard redesign and work/off means above are a **plan**, not a delivered UI. DOSETAP-56's merged foundation does not establish DOSETAP-57 acceptance. DOSETAP-68/69's completed review/scoping records are not reopened by downstream work.
