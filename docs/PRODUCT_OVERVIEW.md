# DoseTap product overview

Status: Presentation candidate. The next-version features identified below are pending integrated delivery and verification. Availability on an installed device must be confirmed separately.
Source review: September 30, 2026.

## What DoseTap does

DoseTap is a local-first iPhone treatment diary that brings together recorded nighttime doses, sleep-related events, morning observations and optional wearable data. It helps a person review their own treatment record alongside the sleep observations supplied by a connected provider.

The person records Dose 1 and Dose 2, can log events such as a bathroom visit or waking during the night, and completes a morning check-in. Medication records, questionnaire answers and wearable measurements retain their own sources. DoseTap does not automatically adjust medication or determine whether a dose is safe to take.

## How Apple Health and Apple Watch fit together

Apple Watch can write sleep information to Apple Health. With the person's permission, DoseTap reads the available sleep records through Apple's HealthKit interface. Apple Health is the integration point: records can also come from other supported apps or devices, so an Apple Health value is not necessarily an Apple Watch-only measurement.

Supported context includes heart rate, respiratory rate, heart-rate variability and resting heart rate when those records are available. Dose logging and check-ins can continue without wearable data. Missing measurements remain unavailable.

## Which time means what?

**The sleep measurements come from the provider's recorded observations. Tapping Wake Up or finishing the morning check-in records a separate diary action and does not extend measured sleep.**

| Record | Where the time comes from | Meaning |
| --- | --- | --- |
| Apple Health sleep onset | Start of the first asleep interval in the selected main episode | Provider-based estimate of when sleep began |
| Apple Health sleep ending | End of the last asleep interval in that episode | Last observed sleep ending. An immediately adjoining awake interval adds evidence of a transition; absent that transition, the exact awakening time remains uncertain. |
| Apple Health total sleep | Available intervals classified as asleep in the selected main episode | Recorded asleep time, with awake time excluded |
| DoseTap Wake Up event | Time the person confirms Wake Up in the app | Logged app action that opens the morning check-in |
| Morning check-in completion | Time the answers are saved and the active session closes | Completion of the diary workflow |
| Diary Final awakening | Time the person explicitly enters and saves | Self-reported final awakening, which can differ from the provider estimate |
| WHOOP original episode start and end, in the forthcoming integration | Original timestamps supplied for the WHOOP sleep record | WHOOP's episode boundaries. Its end is not automatically treated as the last observed asleep instant or the person's reported final awakening. |

For example, Apple Health may show sleep ending at **7:00 AM**, while the person taps **Wake Up at 8:00 AM** and finishes the check-in at **8:05 AM**. The later app actions do not add 65 minutes to the Apple Health sleep total.

The main-episode total can differ from an Apple Health daily total that also includes naps or other episodes. Missing observations do not establish that the person was asleep or awake.

## How dose timing and sleep are compared

DoseTap keeps recorded dose times alongside sleep observations. Its existing estimated sleep after Dose 2 uses the recorded Dose 2 time and the explicitly saved diary Final awakening when available, otherwise the Apple Health sleep-ending estimate. It counts only available Apple Health asleep intervals inside that window. The elapsed interval and measured sleep are different quantities.

A separately reviewed night window lets the person confirm bounds for an Apple Health coverage check. That check distinguishes observed sleep, awake time, unmeasured time and conflicting observations. It remains separately named from the selected main-episode total.

The next dashboard makes the chosen sleep definition, endpoint and missing-data status visible in its comparisons. A one-dose night can still have usable sleep data while having no paired-dose interval. Missing Dose 2 is not automatically recorded as skipped; finishing a check-in does not confirm how many administrations occurred. Historical count and plan reviews remain patient reports, separate from actual medication actions.

## Next-version diary, dashboard and report capabilities

These capabilities are being integrated and verified for the next version. This section describes their intended delivered behavior, not confirmation that they are installed on a particular phone or iPad.

| Capability | What the person can review |
| --- | --- |
| Sleep and dose patterns | Sleep by date, dose-pattern categories and valid paired-dose intervals. Single-dose, explicitly omitted, confirmed no-dose, incomplete and conflicting histories remain distinguishable. Exact tables retain observations that cannot supply a numeric chart point. |
| Session replay | Recorded dose and event times beside available provider intervals, with explicitly selected endpoints for interval inspection. Gaps stay unmeasured; aggregate sleep totals do not create a stage timeline. |
| Work block and sleep | Sleep around reviewed work blocks, with planned schedules and confirmed attendance kept separate. Unknown work status remains unknown; weekday names alone do not establish a shift or actual hours worked. |
| Independent daytime diary | Current or explicitly retrospective sleepiness observations using DoseTap's custom 0–10 scale, with optional activity, coping and event context. An entry does not require or create a nighttime session. Missing, unsure and skipped responses remain distinct. |
| Optional routine reminders | A user-selected reminder with explicit scheduling history, quiet-hours and known-sleep checks. A late response records the actual assessment time. No response is unknown, not a sleepiness score. Device delivery still requires verification. |
| Sleep and nap review | Separate rest-window duration, estimated asleep time and provider-observed sleep. Incomplete, overlapping or changed source records remain visible for review rather than silently adding to a total. |
| Physician review | A preview for an explicit period, including full-period and monthly summaries, recent detail, coverage and missing-data counts, and unscored patient notes and questions. PDF, CSV and JSON sharing uses an explicit action on the captured preview. A completed visit can anchor a period; a future or cancelled appointment cannot. |

The custom daytime diary and visit notes do not supply an ESS, KSS or NSS score. Named clinical questionnaire content and enablement remain separate work.

Reporting keeps the selected time period, timezone, capture time, source and calculation definition. A partial or stale observation is identified, and unavailable values are not charted as zero. A failed provider refresh can retain the last successful result with its earlier query bounds and stale status; disabling or disconnecting a provider clears its retained dashboard data.

## WHOOP: planned near-term DoseTap feature

A forthcoming DoseTap feature is planned to add WHOOP sleep and recovery context alongside dose records and morning observations. This is a DoseTap integration roadmap item, not an announcement of a new feature from WHOOP itself. Production enablement and real-account validation remain open, with no committed release date.

The implementation preserves WHOOP's original episode timestamps and stage amounts. Quantitative sleep requires explicitly scored, complete, nonnegative stage evidence. A supported zero stays zero; positive sub-minute sleep retains its precision. Missing scoring information, incomplete stages and legacy values without scoring provenance do not acquire an invented sleep total. Contradictory identities, invalid supplied bounds or a sleep total longer than the original episode remain reviewable raw evidence and cannot supply an available comparison.

Apple Health and WHOOP remain named, separate sources. Their totals are not added together. WHOOP's aggregate stages do not establish when individual sleep stages occurred or provide the compatible intervals required for the Apple Health sleep-after-Dose-2 calculation. Supported recovery context is shown only when supplied by the connected account.

## Storage and deliberate sharing

DoseTap stores its clinical diary records locally on the iPhone. Apple Health and WHOOP retain their provider records. The shipping DoseTap target does not currently enable CloudKit sync.

Reporting exports support deliberate review and sharing; they are not a complete app backup or automatic clinician transmission. The separate iPad reporting experience reads a deliberately transferred copy. Its Apple Health inclusion has its own opt-in; WHOOP transfer to iPad is not enabled by the new endpoint model. The iPad does not write changes back to the phone's medication ledger.

## Presentation wording

> DoseTap brings together the night's dose record, sleep observations and the person's own morning and daytime reports. With permission, it reads Apple Health data, including sleep records from Apple Watch. Measured sleep follows the provider's observations; opening the morning check-in later does not extend it. The next version is adding clearer sleep and dose-pattern comparisons, work and nap context, and a report preview for clinical discussions. Those features are pending integrated delivery and verification. A planned near-term DoseTap integration will add separately identified WHOOP sleep and recovery context, subject to production connection and real-account validation.

## Supporting references

- [Dashboard, work-block, dose-pattern and daytime roadmap](plans/dashboard-2026-09-30/README.md)
- [Sleep definitions and dose-pattern evidence](SSOT/contracts/dashboard-dose-patterns.md)
- [Replay and interval inspection](SSOT/contracts/dashboard-replay.md)
- [Work-block context](SSOT/contracts/work-block-context.md)
- [Independent daytime diary](SSOT/contracts/daytime-check-in.md)
- [Optional daytime routine reminders](SSOT/contracts/daytime-prompts.md)
- [Sleep and nap review](SSOT/contracts/sleep-naps.md)
- [Physician review](SSOT/contracts/physician-review.md)
- [WHOOP production integration gates](WHOOP_INTEGRATION.md)
- [Collection, storage and reporting export inventory](audit/2026-09-12/README.md)

Source basis: integrated source at `c94c27c`, reviewed alongside WHOOP checkpoints `507d0f3`, `477fa0d` and `a32a999`. This description does not establish installed-build availability or close device, provider, instrument, privacy or owner acceptance. Delivery wording must be updated only after the actual integrated build and its applicable checks.
