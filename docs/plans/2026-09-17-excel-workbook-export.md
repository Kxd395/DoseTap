# DoseTap Excel workbook plan

Status: Owner-approved design, September 17, 2026. Implementation is tracked in DOSETAP-13. The current behavior contract is ../SSOT/contracts/ExcelWorkbook.md; delivery evidence records which acceptance gates are complete.

Tracking: DOSETAP-13 owns export completeness and the proposed workbook. DOSETAP-45 owns dashboard comparisons. New collection and measurement work retains its existing owners. Existing phone, provider, accessibility, privacy and release gates remain separate.

## First implementation, build 62

The owner approved app integration after this plan. The [workbook contract](../SSOT/contracts/ExcelWorkbook.md) describes the delivered first version and takes precedence over the proposed mechanics below. All 15 sheets are named, styled Excel tables with sorting/filtering, typed values and frozen headers. Overview uses fixed summaries; Night Review uses ordinary date/group filters instead of a dynamic selector. Links go to table headers so sorting cannot send a link to a different record. Source Fields retains associations in its Source record and Date groups columns, rather than adding a second table. Empty sources have an explicitly labeled blank compatibility row and zero observations.

The first version exports an XLSX or the existing Studio ZIP as separate Settings actions. A combined workbook-plus-source package and dynamic cross-sheet filters remain later work. Accepted reviewed dose/sleep metrics and unavailable HealthKit sample provenance are identified as unavailable; direct exported interval evidence is visible. The implementation does not add clinical collection or reinterpret historical answers. See the [delivery record](../review/2026-09-17-excel-workbook-delivery.md) for actual validation and open gates.

## Recommendation

Deliver one dated `DoseTap Review.xlsx` for everyday reading, with the original Studio archive retained for exact source evidence and software ingestion. Put the overview first, the list of nights second, and a selected-night review third. Place detailed records and the field guide to the right. Use one sheet per distinct kind of record, not one sheet per date, month, symptom location or provider.

The workbook should be understandable without reading code or importing individual CSVs. Most use should involve the first three tabs. All other tabs remain visible and reachable from a navigation list on Overview.

The existing package has four CSV files and detailed JSON. These are related views with different row meanings, not five independent datasets to concatenate. CSV supports a single table; worksheet tabs require a workbook format such as XLSX. Microsoft documents that saving as CSV retains only the active worksheet: [CSV export behavior](https://support.microsoft.com/en-us/excel/save-a-workbook-to-text-format-txt-or-csv).

## Sheet order, contents and sorting

| Order | Sheet | What one row or view represents | Contents | Default order |
| --- | --- | --- | --- | --- |
| 1 | Overview | A summary measure for a named period and population | Export date/version, coverage, 7/14/30-day and full-range mean/median sleep, usable counts, confirmed work/off comparisons, separate schedule estimates, concise review notice and navigation | Most recent reporting period first; chart time runs left to right |
| 2 | Nights | One exported treatment-date group; a combined night only when identity is resolved | Treatment date, identity status, separate dose outcomes and interval, selected-provider sleep, questionnaire completion, confirmed work context, pain summaries, coverage and links | Treatment date newest first; stable group key breaks ties |
| 3 | Night Review | One selected treatment-date group | Readable dose, sleep, awake interval, bathroom/event, questionnaire and next-day review; unresolved groups show their separate source records | Select a date/group; within the view, events run earliest to latest |
| 4 | Events | One original dose or quick-log event | Dose 1/2, explicit skips, bathroom, water, noise, dreams, pain logs, nap markers, food and every other exported event type; occurrence versus recording times and correction links | Treatment date newest first, then occurrence UTC ascending, then source key |
| 5 | Pre-sleep | One original pre-sleep source record | Completion, intended sleep, room temperature/noise/aids, bed/partner/pet setup, stress, caffeine, alcohol, food, exercise, naps, screens, plans and notes | Treatment date newest first, then capture time and source record ID |
| 6 | Morning | One original morning source record | Completion, sleep quality/restedness, mood, symptoms, actual sleeping setup/effects, final waking context, timing/work context and notes | Treatment date newest first, then submission time and source record ID |
| 7 | Pain | One pain observation within a source questionnaire or event | Back/foot/other area, side, sensations, intensity, pattern, notes and source entry identity; separate pre-sleep and morning observations | Treatment date newest first, then assessment time, source, area and side |
| 8 | Daytime | One exported next-day/outcome observation, or independently timed assessment where supported | Following-day type, reported final wake, sleepiness value and assessment time, shift context when exported, and associated source pointers | Observation date newest first, then assessment time ascending |
| 9 | Sleep Measures | One provider summary for its exported episode/window | Provider, source names, window/basis, sleep/stage/awake/in-bed totals, HR, resting HR, HRV with method, respiration, and WHOOP measures when present | Treatment date newest first, provider, window start |
| 10 | Sleep Intervals | One exported provider interval | Start/end, asleep/awake state, duration, provider, available provenance and overlap references to events; retain overlapping source intervals | Treatment date newest first, then start/end UTC and source key |
| 11 | Medications | One separate general-medication log record | Original medication ID/label, amount and unit, formulation, taken time, recorded time, confirmed duplicate flag and notes | Taken date newest first, then taken time and record ID |
| 12 | Inventory | One recorded supply snapshot | As-of time, medication, bottles/doses remaining, supplied estimates/refill date, capture time and notes | As-of timestamp newest first |
| 13 | Source Fields | One typed source field or JSON value at a specific path | Exact field/path, source record, original code/value, type, array position, representation and pointers to preserved original data; future/unmapped fields remain visible | Source file/table, record key, path/array position |
| 14 | Review Issues | One issue or exclusion reason | Conflicting identities, missing measurements, unknown event codes, unparsed fields, unavailable provenance and source reconciliation discrepancies | Severity/category, then newest treatment date |
| 15 | Field Guide | One exported field or defined metric | Human label, stable key, source/table/path, type/unit, meaning, missingness, derivation, eligibility, confirmation and availability; user review columns | Topic, then field name |

Keep an empty dataset's sheet and header with a short note above the table, such as “No inventory records in this export.” Do not insert a fake zero row. Use stable Excel table names independently of display labels.

Nights is a complete date-group index. A conflicting date remains visible there as “Needs record review”; its combined measurements stay blank. Its events and original questionnaires remain in the detail sheets with their separate identities. A treatment date is not sufficient authority to join two different sessions.

## What the opening view should answer

Overview should answer four questions: how much usable sleep evidence exists, how long the recorded sleep was, how work-related groups differ descriptively, and which records need review.

Show:

- The covered treatment-date range, fixed reporting end date, export timestamp, display timezone, app/export/workbook versions and provider availability.
- A compact 7/14/30-day comparison with mean, median, usable observations and missing/excluded counts. Anchor periods to the latest exported treatment date, including dates excluded from analytics, rather than the latest usable sleep measurement or the computer's current date.
- A simple chronological sleep-duration chart with visible gaps where evidence is missing. Do not connect gaps as measured sleep or plot missing values at zero.
- Confirmed work-after-sleep versus confirmed off-day means and sample counts. Use the same provider and sleep definition for both groups.
- A separate, clearly labeled schedule-estimate comparison when confirmed work answers are unavailable. Preserve that estimate as it was exported. It must not masquerade as historical attendance.
- A count of distinct date groups needing review and, separately, the count of issues. One date can have several issues.

Every average must state its population and denominator. For example, a label should explain that it is average primary-episode sleep from a selected provider across a stated number of usable nights. A completed questionnaire is not evidence of provider sleep coverage.

The first release should offer fixed 7/14/30-day and full-export summaries. This avoids making an old file change just because it is opened next week. Ordinary filters on a detail sheet affect that sheet; they do not silently change Overview. A later shared date/provider selector is reasonable only after its recalculation and cross-view behavior are verified.

## How a user reviews one night

Open Overview, find a date in Nights, then select that date/group in Night Review. Use an explicit selector or reliable links; do not promise that a hyperlink changes a selector unless that behavior is implemented and tested. No macros are needed for the intended workflow.

The selected-night view should show:

1. Original Dose 1 and Dose 2 outcomes, actual occurrence times where known, entry times and timing precision.
2. Reported/provider-estimated sleep onset and final wake, separately labeled with their basis.
3. Dose 1 to observed sleep onset when calculable under the accepted measurement rules.
4. Any exported awake interval intersecting Dose 2, its bounds, and the next observed sleep interval. Distinguish dose-to-return-to-sleep, total observed awake-interval duration, and actual asleep minutes after Dose 2.
5. Bathroom and other logs on the same clock. An event inside an awake interval establishes time overlap, not the cause of waking or how long the person was awake.
6. Planned versus reported actual room/bed/pet setup, separate pain entries, morning answers and timed daytime observations.
7. Missingness, conflicts and source links beside the affected measurement.

Do not infer sleep onset from dose time. Continuous wearable asleep coverage across a confirmed dose can be a conflict, not zero latency. Gaps remain unknown. If no suitable awake interval or following sleep transition exists, show the specific reason instead of inventing a duration. Medication/alarm state is never changed by opening or calculating a workbook.

## Work and shift interpretation

Keep three independent meanings: work before sleep, work after sleep, and the relationship to a work block. Explicitly distinguish planned, confirmed, schedule-estimated, unsure and unanswered.

Where actual schedule evidence exists, future comparisons can separate ongoing work-block sleep, sleep before the first work period, first sleep after finishing a block, and continuing time off. Do not derive those categories from a simple “Work Night” label or a wake-time heuristic alone. Daytime sleep after a night shift still belongs to its treatment session.

For the current export, some of these fields are unavailable. Show that fact in Field Guide and use the existing recorded categories without converting them into a richer confirmed work history. A later collection change needs its own schema/acceptance work; the workbook cannot recover facts that were never recorded.

## Formatting and navigation

- Use readable body text, restrained table headers and text labels for status. Color should support, not replace, meaning. Put daily review tabs first and technical evidence tabs last.
- Freeze table headers and the smallest useful set of date/identity columns. Use filters, consistent column order and links back to Overview. Keep detail fields and notes available without placing every field in the first screenful.
- Keep each detail table rectangular: one header row, unique column names, no merged cells, embedded subtotals or decorative rows inside the data.
- Show elapsed durations as hours and minutes, with typed numeric minutes available for analysis. Retain full precision in source/underlying values and round only display values.
- Display local date and time together with an identified timezone. Retain exact UTC strings, offsets and source timezone evidence where supplied. An export's current offset is not necessarily the offset on every historical date.
- Keep IDs and original codes as text, including numeric-looking identifiers. Keep numbers numeric. Store notes and other user-supplied strings literally so they cannot become formulas or external links.
- Keep source tables separate from any workbook-only review comments. Field Guide can have “Keep / Optional / Change / Remove / Need information” and a review-note column for the owner's collection review. Those choices do not change app records.

## Source mapping and fidelity

Use a versioned mapping manifest that assigns each available field to its sheet/table, type, unit and source path. Reuse the same manifest for Field Guide and future app documentation. Unknown fields must be retained and identified rather than dropped because a current model does not recognize them.

| Current source | Workbook treatment |
| --- | --- |
| `events.csv` and JSON raw/normalized event views | One original event in Events, with raw/normalized/source representations linked by identity. Do not append each representation as a new event. Preserve event vocabulary that the older Studio typed reader omits. |
| `sessions.csv` | Legacy dose-pair projection used for reconciliation. Its start/end fields describe Dose 1/Dose 2, not bedtime/final wake; it must not become a sleep-episode table. |
| `collected_nights.csv` and JSON collected-night data | Populate corresponding Nights/Daytime fields using validated date-group identity and original source links. These are overlapping projections, not additional observations. |
| `inventory.csv` | Inventory table with original snapshot identities and timestamps. |
| JSON date groups, typed source rows and questionnaire submissions | Identity status, original questionnaires, Source Fields, correction evidence and provenance. Pre-sleep/Morning/Pain views derive from these records without counting normalized copies as additional answers. |
| JSON Health/WHOOP sections | Sleep Measures and available Sleep Intervals, retaining provider-specific meaning and missingness. |
| JSON medication rows | Medications, separate from the canonical two-dose treatment events. |
| Root metadata, warnings and enrichment status | Export metadata/Field Guide and relevant Review Issues; request counts remain separate from usable measurement counts. |

Use stable source record IDs and session IDs where present. A workbook row number is never an identity. Where a source lacks an ID, a deterministic workbook key can reference its file/path/position, clearly labeled as derived and unsuitable for pretending to be a provider sample ID. Joining on date alone or row position is unsafe.

Within one export, identify an original record by source table and source record ID. If multiple date groups reference the same record, display it once in its original-record detail table and retain all associations in a separate named `RecordAssociations` table on Source Fields. Its columns should include source record key, date-group key, association basis and identity status. Do not assign the record arbitrarily to one treatment date or count it as multiple questionnaire or pain observations. Show “Multiple dates — review” in its human date label. Night Review may display the same record through each association, with the conflict visible. If one source key has different payloads, retain the variants with explicit variant keys and flag the conflict instead of choosing one silently.

Retain source representations even when they disagree; attach a review issue and exclude the unsupported combined result. Rebuildable symptom facts and normalized answers are linked projections, not additional pain observations. Zero intensity remains a real observation. A saved preference is not a confirmed nightly symptom or outcome.

Missing numeric values remain blank with an explicit status/reason field. Keep unanswered, explicitly unsure, explicit none, skipped, unavailable, conflicting and not applicable distinct. A numeric zero remains zero. Provider data-request completion does not prove read authorization or complete coverage.

Source Fields should enumerate nested answers, unknown keys, array members and typed SQLite values. Preserve explicit null, empty text and container state. Retain original JSON bytes in the companion archive; parsed worksheet cells are a readable projection. Long values must never be silently truncated: use numbered text parts or a clearly identified pointer to the original archive plus a completeness warning. Binary data stays in the original archive with type/size/reference metadata. Microsoft documents a 32,767-character cell limit and finite row limits: [Excel specifications](https://support.microsoft.com/en-gb/excel/excel-specifications-and-limits).

## Known limits the workbook must expose

- Current exported `RecordedSleepInterval` has start, end and an asleep boolean. It does not contain per-interval REM/core/deep labels, sample UUIDs or device identities. Stage totals can appear in Sleep Measures; per-sample stage/source details require an additive export change before the workbook can display them.
- Aggregate source names do not establish which device produced each interval. Do not label all Apple Health rows “Apple Watch.”
- Current provider query selection is not a complete raw HealthKit extraction. Awake-only, in-bed-only and short observations may be excluded upstream. Workbook coverage describes the supplied archive, not all of Apple Health.
- WHOOP aggregate durations and disturbance counts do not establish dose-adjacent sleep transitions. WHOOP absence remains unavailable with the exported request status where present. Apple Health HRV SDNN and WHOOP HRV RMSSD need separate method labels.
- Primary-episode sleep, reviewed treatment-night sleep, naps and a complete 24-hour total are different measures. Show each only when its own evidence and definition are supported. Do not add self-reported naps to overlapping provider sleep without an accepted deduplication rule.
- Some saved room/pain/setup preferences and other settings are outside the clinical export. The workbook can show exported nightly answers; it cannot claim to contain every local preference or serve as a full app backup.
- Legacy answer confirmation and historical medication-window snapshots may be unavailable. Keep that missing provenance explicit; do not reinterpret default values or today's settings as confirmed historical facts.

## Viewing, ingestion and refresh workflow

For the user, the intended app action is `Export Excel Workbook` followed by the existing native share sheet and Save to Files. Keep `Export Studio Bundle` available for software analysis and complete source review. The workbook should open offline without credentials, macros or refresh prompts.

For a complete handoff, offer a package containing the workbook plus the unchanged Studio JSON/CSV files. Keep the machine files at their supported paths or verify any layout change against Studio before shipping. Workbook-only export should state that the complete source archive is a separate option. Saving a workbook must not become dependent on network enrichment that is unavailable.

For Studio or another analysis tool, prefer the versioned JSON/archive. If a tool consumes Excel, it should read named detail tables and Field Guide metadata, not screenshot charts or parse formatted text. Include export ID, source hashes, workbook schema, table grain and record keys so an importer can check compatibility and distinguish snapshots. Date-group safety and unknown-field preservation remain mandatory.

Each export is a dated snapshot. Generate it from one finalized archive, rather than re-querying phone state separately for each sheet. This keeps workbook/CSV/JSON parity for that archive; it does not by itself solve the separate concurrent-write consistency gate in the app exporter. Do not refresh an old workbook silently from live providers.

Do not append two complete snapshots together as if every row were new. A future multi-export importer must reconcile stable source IDs and corrections, report conflicts, and make replacement rules explicit. For the first release, use the latest full export as its own snapshot and retain earlier files for comparison.

Editing Excel does not write clinical corrections back to the phone. Corrections belong in the app followed by a new export. Workbook-only review comments need to be preserved separately if later exports are compared; they must not be mistaken for recorded answers.

## Delivery sequence and acceptance

1. **Mapping contract and synthetic fixtures:** document exact field-to-table mapping, record grains, identities, missingness, unsupported fields and calculation definitions. Include resolved, raw-only, empty, zero, legacy and future-key cases.
2. **Local workbook prototype:** generate the proposed tabs from one existing archive outside the repository. Deliver Overview, Nights and record tables first, then the selected-night view from the same prepared data. No new phone build is needed for this prototype.
3. **Completeness and calculation verification:** independently reconcile source IDs/counts, every event type, questionnaires, medications, inventory, provider totals and exclusions. Prove no duplicated counting across projections and no source changes. Confirm representative means/medians and all denominator labels.
4. **Native Excel review:** open in Excel on the Mac and verify table filtering/sorting, selected-night navigation, duration/date display, long notes, blank-versus-zero behavior, save/reopen and visible warnings. Test the actual owner workflow and any secondary viewer before claiming its compatibility.
5. **App integration:** after the workbook layout is accepted, add the export option and mapping documentation, increment the next available build, and validate native sharing/Save to Files on the installed phone. Keep existing Studio ingestion working. Do not close privacy/accessibility/release gates from workbook unit tests.

Acceptance cases must include crossing midnight and DST; approximate/unknown dose times; repeated daytime assessments; multiple pain entries; valid zero values; provider absence/failure; conflicting session identities; one source questionnaire referenced by multiple date groups without duplicated pain/answer counts; conflicting variants of a source key; unknown event and questionnaire fields; corrections; repeated exports; and strings that resemble spreadsheet formulas. Empty datasets must remain visibly empty and must not produce misleading averages.

The first bounded engineering slice is a local workbook prototype from a finalized export plus exact parity checks. New clinical collection, a new overall sleep score, provider-query expansion and automatic record repair are outside that slice.

## Evidence for this plan

The original design review checked the supplied export structure, the prior independent export review, current export 2.8/schema 3 identity rules, `SettingsStudioExport.swift`, `NightOutcome.swift`, `EventStorage+Exports.swift`, the collection inventory and the data dictionary. An independent source review identified the cross-date source-record association case; the plan and fixtures cover it. That planning review did not itself perform a workbook export, app build, clinical correction or provider fetch. Subsequent implementation evidence belongs in the delivery record linked above.
