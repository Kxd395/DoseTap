# Pre-sleep last-food logging

Date: 2026-09-07. Plane: DOSETAP-50, High, In Progress.
Implementation: `/Volumes/Developer/projects/DoseTap-main`, `fix/locked-dose2-system-alarm`.

## Research and scope

The existing questionnaire had an optional late-meal size and end time, but no explicit last-food record or high-fat answer. The owner requested food timing and oily-food tracking.

The [official XYWAV prescribing information](https://pp.jazzpharma.com/pi/xywav.en.USPI.pdf), revised July 2025, was checked on September 7, 2026. Section 2.4 instructs administration at least two hours after eating. Section 12.3 reports that dosing immediately after a high-fat meal reduced mean peak concentration by 33% and total exposure by 16%. These group pharmacokinetic results are not personal effectiveness percentages or dose-correction factors. The label does not establish an additional oily-food waiting period.

The form therefore records food observations and links to the label. It does not recommend dose changes, infer fasting, certify readiness to dose, or alter medication/alarm actions. Meal, snack and calorie-containing drink are diary categories; a heavy legacy meal is not assumed to be high-fat. The Unslop writing skill informed the short, direct wording and separation of observations from dosing instructions.

## Changes

- Visible Last food section on pre-sleep page 3, above optional details: finished date/time, optional meal/snack/calorie-containing drink, high-fat/oily Unsure/No/Yes, and optional food notes up to 500 characters.
- Missing entry means not recorded. Unsure stays absent rather than false. Food observations are cleared when carrying settings into a new night. Existing questionnaire edits preserve them.
- Legacy late-meal answers remain stored and visible separately; no fabricated last-food timestamp or fat classification is derived from them.
- The optional JSON object and normalized response keys save atomically through existing storage. Normal and historical writes validate finite timestamps, occurrence-time ordering and note length. History retains prior answers and requires the existing correction reason and confirmation.
- Night review, text/CSV and Studio exports include the new fields. Full date/time is retained across midnight. No SQLite migration is required.
- Existing dosing, wake choices, Quick Log and automatic Night Mode are unchanged. No real medication records were edited.

## Validation

- Tests-first compile failed as expected for missing `lastFood`, then implementation passed the first 108 focused app tests. `/tmp/dosetap-food-red.log`, `/tmp/dosetap-food-tests.log`. The first test draft also used a nonexistent fetch helper; it was corrected to the existing fetch API before the passing run.
- Core build and regression: 652 XCTest cases plus 43 Swift Testing cases passed. `/tmp/dosetap-food-core.log`.
- Studio regression: 55 XCTest cases passed. `/tmp/dosetap-food-studio.log`.
- Full unsigned DoseTap app-scheme regression on iPhone 17 Pro, iOS 26.5: 349 tests passed. `/tmp/dosetap-food-full-app.log`. Covers missingness, legacy decode, persistence, clearing food, no carry-forward, historical future-time rejection, injected commit failure rollback, correction provenance, and Studio JSON date/type/fat/notes export.
- Initial end-to-end History UI run: one test passed, including food notes/high-fat save, cancellation, restart and restored answers, plus morning questionnaire correction and no inferred doses. `/tmp/dosetap-food-ui.log`. Visual inspection of exported screenshots caught a missing visible food-type label; a final UI run verifies that label and type selection.
- Final clean-derived-data UI run: one end-to-end test passed with explicit Meal menu selection and restored type/fat/notes after restart. `/tmp/dosetap-food-clean-ui.log`, `/tmp/dosetap-food-clean-ui.xcresult`. Inspected `/tmp/dosetap-food-clean-proof/CEBD106A-8043-4EBB-954D-69D780394199.png`: visible food-type label and Meal, correct date/time, selected Yes and saved notes. The intermediate incremental run passed but did not execute newly added type-selection steps; it is not counted as that coverage. A clean rebuild resolved the stale test behavior.
- Plane workflow (10 tests, 64 assertions), SSOT, app version 0.4.19 (21), architecture, dose-write boundary, documentation, legacy safety, repository hygiene and companion-target guards passed. `git diff --check` passed. Informational dangling Git objects were preserved.

## Open acceptance

Signed-device and owner acceptance remain open, including entering a real remembered finish time, testing keyboard/Dynamic Type accessibility, and confirming this fits the nightly routine. Simulator fixtures are not real clinical evidence.

The existing integration HOLD is unchanged: broader UI suite, final security and credential/provider-revocation evidence, protected hosted checks and release-owner acceptance remain separate. No phone installation, push or merge to main. The existing project and UI-scheme reorder diffs remain uncommitted and excluded from this work.
