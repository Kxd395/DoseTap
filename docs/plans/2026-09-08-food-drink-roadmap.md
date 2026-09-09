# Food and Drink feature roadmap

Date: 2026-09-08
Status: Planned work, not current shipping behavior
Authority: Plane owns priority, assignment, dependencies and completion. This file records scope, sequence and acceptance evidence.
Baseline: `DoseTap-main` on `main`, `eae0f7ad3afcdebb986903c67845150d5ac7dcee`; fetched upstream was equal at planning time.
Scope of this pass: planning and Plane updates only. No app code, clinical policy, personal records, build number or phone installation changed.

## Decision

Repair consumption freshness and units before adding a shared daytime log. Then connect pre-sleep review and test a one-way Foodnoms/Apple Health prototype. Keep the existing quick logs and dosing confirmations. Manual logging must work without AI, a subscription or internet.

Existing last-food functionality belongs to DOSETAP-50. This roadmap does not duplicate it or replace the current SSOT. Write reviewed SSOT/schema contracts before implementing each behavior change.

## Sequence and ownership

| Order | Plane item | Priority | Depends on |
| --- | --- | --- | --- |
| 1 | DOSETAP-51: fresh nightly answers | High | No new prerequisite |
| 2 | DOSETAP-52: explicit volume and caffeine units | High | DOSETAP-51 or coordinated repair |
| 3 | DOSETAP-53: shared intake history and quick logging | High | DOSETAP-51, DOSETAP-52 |
| 4 | DOSETAP-54: pre-sleep review and fresh alcohol status | High | DOSETAP-53; pharmacist review before new medication prompts |
| 5 | DOSETAP-55: one-way import feasibility prototype | Medium | DOSETAP-53, DOSETAP-10 read-state contract |

All five new items were created in Todo. Dependencies are recorded explicitly in Plane descriptions, not asserted as configured native dependency edges. No assignee was guessed. Start an item only when implementation begins.

## Verified code findings

- `ios/DoseTap/Views/PreSleepLogView.swift`: remembering settings defaults on; `carriedForwardForNewNight` copies prior answers and shifts caffeine, alcohol, exercise, nap and screen times to a new date. Last food is cleared. This prefills a form; it does not prove the earlier automatic Dose 2 incident's cause.
- `ios/DoseTapTests/UIStateTests.swift`: carry-forward tests currently require preservation and shifted timestamps. Replace the old expectations with fresh-night versus same-night versus History cases.
- `ios/DoseTap/Views/PreSleepLogBodySubstancesCard.swift`: beverage ounces use `caffeineLastAmountMg` and `caffeineDailyTotalMg`; bootstrap supplies quantities and time.
- `ios/DoseTap/Storage/EventStorage+EventStore.swift`: the compatibility adapter inserts 95 and the current time from a boolean caffeine answer. Treat ambiguous legacy semantics explicitly.
- `ios/DoseTap/Views/NightReviewExport.swift` labels these quantities as ounces, while `ios/DoseTap/SettingsStudioExport.swift` retains Mg-named fields.
- `ios/DoseTap/Views/PreSleepLogActivityNapsCard.swift` already records last-food finishing time, type, optional high-fat/oily status and notes. Extend it instead of creating a competing copy.

## Planned tasks

### DOSETAP-51: Require fresh nightly consumption answers without copying prior observations

- Separate remembered preferences and reusable drink templates from night-specific observations. Do not copy caffeine, alcohol including None, food, exercise, nap, stress, pain or daily notes into a new night as confirmed facts. Audit the full pre-sleep answer model.
- Preserve same-night draft resume and explicit History editing. Loading prior answers may offer suggestions, but applying consumption requires fresh action. No historical rows are erased or reclassified.
- Remove silent current-time and default-quantity fabrication in substance bootstrap and legacy adapters. Unknown amount/time remains unknown; positive consumption can be saved without inventing missing details.
- Tests: fresh night, same-night resume, History backdate, alcohol yes/no/unanswered, default bootstrap, legacy adapter, restart, cancel and failed-save rollback. Prove questionnaire-only actions cannot write doses or affect alarms.
- Update carry-forward tests that currently require shifted timestamps; validate visible save/edit/restart on simulator plus signed-device and owner acceptance.

### DOSETAP-52: Separate beverage volume from caffeine milligrams and preserve legacy units

- Depends on the fresh-answer repair, or a coordinated non-overlapping implementation. Inventory every caffeineLastAmountMg/caffeineDailyTotalMg read/write across iOS, Core, raw and normalized storage, manual/scheduled exports and Studio.
- Add explicit beverage volume with unit and separate optional caffeine mass in mg. Distinguish label-derived, user-reported, estimated and unknown values; no universal ounces-to-mg conversion.
- Version the contract and migration. Existing UI values are ounces despite Mg field names; the legacy adapter injects 95. Preserve raw legacy values and mark ambiguous semantics instead of guessing units from magnitude or silently converting all history.
- Stop fabricated amount/time defaults from boolean legacy answers. Old readers/imports need explicit compatibility handling; unsupported new schema must be reported, not silently misread.
- Tests: known-ounce, known-mg, ambiguous legacy, absent values, zero versus unknown, decimal/unit conversion, failed migration rollback, restart, old/new archive imports and all export parity.
- DOSETAP-45 and DOSETAP-13 own analytics/export acceptance; this unit repair must include its necessary writer/reader changes in the same delivery.

### DOSETAP-53: Add shared local Food and Drink history with quick daytime logging

- Depends on fresh-answer and unit repairs. Through SessionRepository and transactional SQLite, introduce one versioned intake-event history used by manual entry, future imports and pre-sleep review.
- Provide Finished eating now, editable finishing date/time, optional meal/snack/calorie-containing drink classification and high-fat Yes/No/Unsure, plus saved beverage shortcuts. Exact calories, ingredients and caffeine mg are optional.
- Store stable event ID, consumed/finished time distinct from captured and entered time, timezone provenance, optional session association, per-field certainty, source and revision chain. A daytime food log must not create or reopen a medication night just for association.
- Unknown alcohol/caffeine is distinct from No/zero. Saved items are templates, not recurring consumed events. Capture before eating creates a draft; no confirmed finish until user action.
- Preserve existing Last food and legacy questionnaire records. Do not turn historical questionnaire summaries into precise intake events without provenance and review. Reuse DOSETAP-47 correction principles.
- Keep bathroom, water, noise, dreams and other quick logs. Define Snack/Water bridging without duplicate intake or pretending a quick-log timestamp proves quantity or finish time.
- Tests: offline add/edit/cancel/delete/undo/restart, duplicate tap and stale edit, transaction failure, cross-midnight/DST/travel, no active session side effects, export and clear-all coverage. Coordinate DOSETAP-13 and DOSETAP-39; do not claim whole-app restore.

### DOSETAP-54: Review confirmed Food and Drink history in pre-sleep with fresh alcohol status

- Depends on shared intake history. Replace duplicate consumption questions with a compact review, Add/Correct actions and explicit confirmation of additional intake since the listed entries.
- Show last confirmed food finish, source/unknown details, caffeine time and amount when known, and alcohol Yes/No/Not confirmed with a defined review period and confirmed-at time.
- Store review occurrence/submission time and referenced intake IDs/revisions. Later relevant food/drink additions, corrections, deletions or imports invalidate the current review; historical snapshots remain auditable.
- Existing food information stays informational. Any new elapsed-food display must say it describes recorded food only, never Safe to dose. No fatty-food extra wait, alcohol-clearance estimate, caffeine-cleared indicator or dose/alarm adjustment.
- Pharmacist-reviewed handling of caloric drinks, overnight food and reported alcohol is required before automated medication-related prompts. Positive alcohol warning cannot depend on completing quantity fields; retrospective medication history remains accurate and separate.
- Support intended sleep periods and overnight review without treating midnight as abstinence or clearance. Preserve Dose 2 wake method, morning wake and next-day sleepiness.
- Tests: snack after review, partial/unknown answers, imported timestamps lacking finish semantics, DST, backdated History snapshot, failure/restart, screen-reader and large-text layout. DOSETAP-45/13 must retain missingness and usable observation counts in reporting.

### DOSETAP-55: Validate a one-way Foodnoms Apple Health intake import prototype

- Discovery/prototype only, dependent on the shared intake schema and DOSETAP-10 read-access semantics. No paid subscription, permission grant, cloud upload or production integration is approved by this task.
- Verify current Foodnoms tier capabilities and actual exported product names, grouping, nutrient units, caffeine/alcohol presence and timestamp meaning. A logged time is not a confirmed finish time.
- Use consented synthetic/test entries. Empty HealthKit results remain ambiguous; missing caffeine/alcohol never becomes No or zero. Imported fields remain identifiable and require relevant user confirmation.
- Use stable source/sample identity for idempotency; test edits, deletions, duplicates across apps, repeated imports, revoked access, interruption, anchor/reconciliation recovery and timezones.
- Keep import read-only toward HealthKit; no echo writes. Reconcile upstream deletion separately from a user's correction and invalidate affected current reviews.
- Deliver a go/no-go evidence matrix, limitations, permission/privacy/data-retention design and measured UX tradeoffs. Promote only after end-to-end device verification; manual offline logging is not blocked by prototype failure.
- Defer native meal AI, barcode catalog and cloud photo processing until this result and owner choice. Any later cloud path needs explicit consent, minimal disclosure, metadata handling and deletion/retention policy.

## Existing work to reuse

- DOSETAP-50 retains ownership of the existing last-food implementation and its device acceptance. Its workpad records this follow-up roadmap.
- DOSETAP-45 owns dashboard and Studio analytics. New data must retain unknown groups, source labels, per-outcome usable counts and descriptive rather than causal wording. Do not aggregate beverage volume as caffeine mg or use ambiguous legacy values in caffeine-mass comparisons.
- DOSETAP-13 owns manual/scheduled archive coverage and export parity. Each new schema slice must include matching raw/normalized/collected-night exports, schema versions and compatible Studio imports in the same delivery.
- DOSETAP-47 owns audited History editing. Food edits reuse stable identities, reasons for corrections, stale-review rejection and failure handling.
- DOSETAP-39 remains the whole-project CRUD/clear-all/restore authority. Adding intake rows and optional attachments requires explicit inventory and deletion/recovery coverage; CSV export is not a full backup claim.
- DOSETAP-10 owns HealthKit read-state semantics. Empty results cannot establish no consumption or denied/granted permission.
- DOSETAP-43 owns common tab layout/capture controls. New Food and Drink screens should follow the existing shared header, theme and capture conventions, with scrolling preserved for accessibility.
- Existing DOSETAP-46 dose-recording incident and DOSETAP-4 alarm/device acceptance retain priority. Food planning does not resolve them.

## Proposed data contract to review before implementation

An intake event has stable identity and a revision chain. Consumption/finish time is distinct from capture and entry time. Record timezone provenance and optional treatment-night association without creating a medication session for daytime food.

Separate beverage volume and unit from optional caffeine mass in mg. Store per-field provenance/certainty, confirmed-at time where applicable, and import source identity. Unknown is not zero or No. Preserve legacy raw values when their meaning cannot be established.

A pre-sleep review references intake IDs and revisions and retains a historical snapshot. New relevant intake or a correction makes the current review stale. An imported logging timestamp cannot become a confirmed finishing time without evidence or user confirmation.

## Deferred and prohibited scope

Deferred pending the prototype and owner choice: native AI meal recognition, a barcode product catalog, label OCR, cloud photo processing and full nutrition tracking. USDA lookup can supply composition data later; it cannot measure the eaten portion.

No AI dose adjustments, alcohol-clearance countdown, caffeine-cleared indicator, extra oily-food wait, automatic dose logging or broad Safe to dose claim. Do not purchase a service, grant Health permissions or upload photos as part of planning. Cloud processing needs separate consent, minimal disclosure and a reviewed retention/deletion policy.

## Research basis and remaining review

The preceding source review checked the [XYWAV label](https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=1e0ae43a-037f-42af-8e23-a0e51d75abe8), [caffeine timing trial](https://doi.org/10.1093/sleep/zsae230), [52-photo evaluation](https://pubmed.ncbi.nlm.nih.gov/41081011/), [714-image validation](https://pubmed.ncbi.nlm.nih.gov/41138916/), [Foodnoms features](https://foodnoms.com/plus) and [Health export documentation](https://foodnoms.com/help/writing-to-health).

Keep medication-related guidance limited to supported labeling. Food photos supply reviewed estimates, not verified alcohol/caffeine absence. The Foodnoms export route is untested; actual finishing-time semantics, missing nutrients and edit/delete behavior remain prototype acceptance questions. Pharmacist review of caloric drinks, overnight intake and reported alcohol precedes new medication prompts. No arbitrary confidence percentage is used.

## Validation and release gates

For this planning pass: Plane duplicate search and exact readback; documentation lint; Plane workflow check; whitespace validation. App tests were not rerun because there is no app change.

For implementation: SSOT/schema first, failing regression tests before logic, all touched iOS/Core/Studio tests, migration rollback/restart, exports and import fixtures, and visible simulator journeys. Test midnight/DST/travel, unknown values, duplicate/stale actions and persistence failures. Confirm medication and alarm records remain untouched by intake-only actions.

Before release: signed-device save/edit/restart, actual Apple Health permission/import matrix where applicable, owner workflow acceptance, VoiceOver/largest text, privacy and release-owner review. Existing security/provider/whole-app restore gates remain separate. Do not mark feature items Done on this planning evidence.
