# Collected-night reporting and analytics

Date: 2026-09-07. Candidate: `fix/locked-dose2-system-alarm`, app version **0.4.19 (23)**.

Implementation authority: `/Volumes/Developer/projects/DoseTap-main`. The preserved `/Volumes/Developer/projects/DoseTap` checkout and unrelated Xcode reorder changes were not incorporated.

Plane authority: DOSETAP-45 for dashboard/reporting and DOSETAP-13 for scheduled export completeness. DOSETAP-13 was explicitly brought forward from Backlog under the owner's instruction to proceed. Both remain In Progress pending the acceptance gates below.

## What changed

- iPhone Dashboard > Trends now has a Food timing & next-day diary card. It shows completed last-food records, missing entries, food-to-Dose-1/2 medians, high-fat Yes/No/Unsure-or-blank counts, and paired 0–10 sleepiness and estimated post-Dose-2 sleep observations. Following-day filtering uses the saved Workday/Day off/Unknown answer.
- The existing natural/alarm comparison remains separate from final morning awakening. A backup alarm does not turn an explicitly natural waking into an alarm waking.
- `CollectedNightSummary` is a versioned shared report projection. Manual Studio bundles, scheduled local bundles, single-night text/CSV, and Studio's typed model use its fields. Raw questionnaire payloads and stored revision history remain in the bundle.
- Manual and scheduled Studio exports share `StudioBundleExporter`. Scheduled exports now publish unique ZIPs instead of the old event-only CSV. Cancellation before publication does not publish a new archive or advance the service's last-success date. Previously saved archives are not overwritten.
- Studio imports and reports the new typed records, keeps questionnaire-only nights, and adds a descriptive food/wake diary overview. The older inferred wake analysis is not relabeled as explicit diary evidence.
- CSV readers support quoted commas, doubled quotes, and embedded LF/CRLF. New writers use a reversible apostrophe-plus-zero-width-space prefix for formula/control-leading text. Studio's CSV decoder removes that marker; raw JSON is unchanged. Clinician-safe reports redact the new food notes and exact timestamps too.
- Single-night export resolves pre-sleep records by the repository's session-date lookup and includes available Apple Health-derived post-dose estimates. An unreadable/conflicting diary produces an error instead of a silently incomplete report.

## Field coverage

| Collected information | Reporting behavior |
| --- | --- |
| Last food finish time, meal/snack/calorie-containing drink, high-fat answer, notes | Typed JSON, `collected_nights.csv`, single-night text/CSV, Studio night detail and reports. Food-to-dose intervals use actual elapsed time; negative intervals stay missing. |
| Dose 2 wake method and separate backup alarm answer | Typed JSON and flat columns. Natural, Alarm, Other, and Unknown are not inferred from alarm timestamps in the new diary comparison. |
| Following day, final awakening, sleepiness 0–10, assessment time, diary recorded time | Typed JSON and flat columns. Zero is retained; missing is blank. The older 1–5 questionnaire answer is not converted. |
| Estimated sleep after Dose 2 | Available Apple Health asleep segments are clipped to actual Dose 2 through final awakening, with recorded awake time excluded. Export includes covered minutes, full interval minutes, final-wake boundary, and source. |
| Full pre-sleep and morning questionnaires; diary revisions | Source payloads/check-in submissions remain in `insights_bundle.json`. Convenience columns do not replace those records. |
| Dose events, bathroom/water/noise/dream and other quick logs, medication entries, inventory snapshots | Existing local records remain in the shared bundle writer. This change does not alter dose recording, alarms, or logging controls. |

Each ZIP contains `events.csv`, `sessions.csv`, `inventory.csv`, `collected_nights.csv`, and `insights_bundle.json`. Export version is 2.3; the additive collected-night projection is version 1. Older bundles without the projection remain readable. Unsupported future projection versions are not used in the new comparisons.

Scheduled ZIPs contain local records only. They do not fetch HealthKit or WHOOP enrichment in the background. Provider-only measurements and post-dose estimates therefore remain unavailable in those ZIPs; the bundle warning says so. Use a manual export for available provider measurements.

## Metric and safety rules

- One observation is one session night, not one questionnaire revision or individual event.
- Food analytics use completed pre-sleep logs in the selected range. A draft, a skipped questionnaire, or a legacy late-meal answer does not count as a new last-food observation.
- Every outcome shows its own usable `n`. Unknown high-fat answers are separate from No; missing sleepiness is separate from zero.
- iPhone food comparisons honor the selected sleep provider. WHOOP nightly totals are not substituted for Apple Health post-dose segments.
- Partially measured post-dose intervals remain partial. Covered minutes and the interval boundary are available in reports; unmeasured time is not sleep.
- These are descriptive diary comparisons, not causal evidence, validated clinical scores, dose recommendations, or fitness-to-drive assessments. No medication timing boundary or confirmation action changed.

## Validation record

- Core: `swift build -q` and `swift test -q`; 655 XCTest plus 43 Swift Testing cases passed. Log: `/tmp/dosetap-report-core4.log`.
- Full iPhone app scheme: 350 tests passed, serial iPhone 17 Pro simulator run. Initial log: `/tmp/dosetap-report-app6.log`; final build-23 recheck: `/tmp/dosetap-report-app-final.log`.
- iPhone export suite: 15 tests passed, including raw questionnaires, typed fields, independent sleep coverage, flat column alignment, cancellation, and archive creation. Log: `/tmp/dosetap-report-app5.log`.
- Studio: 59 tests passed with both fixture environment variables set. Log: `/tmp/dosetap-report-studio9.log`. This includes an actual synthetic iOS ZIP imported into Studio, not just separately hand-built JSON.
- Cross-app reproduction: run `ExportIntegrityTests/test_studioExport_preservesCheckInPayloadsAndInventoryRows`, export its `collected-night-roundtrip.zip` XCTest attachment, extract it, and set `DOSETAP_IOS_EXPORT_FIXTURE` to the extracted bundle folder when running Studio tests. The test is explicitly skipped if no fixture path is supplied.
- Studio native text/layout preview: set `DOSETAP_STUDIO_PREVIEW` to a PNG path when running Studio tests. The rendered overview was inspected; AppKit-backed controls are not rendered by ImageRenderer. This is not interactive Studio acceptance.
- Version settings and compiled simulator Info.plist read back as 0.4.19 (23). The owner's phone was not installed.
- Final iPhone UI journey passed: 1 executed test, 0 failures. It selected Day off, verified 3 food records among 4 nights, restored All days, and expanded both high-fat outcome groups. Log: `/tmp/dosetap-report-ui3.log`; result: `/tmp/dosetap-report-ui.pDFZvY/Logs/Test/Test-DoseTapUITests-2026.09.07_23-32-20--0400.xcresult`. The initial added filter assertion failed because the card-level accessibility identifier obscured the control; that identifier was removed and the corrected interaction is present in the passing log.
- Final screenshots inspected: `/tmp/dosetap-report-ui-final-proof/594661F9-AECD-42DC-8783-D98657F360C8.png` and `EECB9AA1-67BA-41FE-A850-5BC3457CE903.png` in the same folder. The filter is single-line, both paired groups are readable, a real zero is shown as 0.0/10 with n=1, and unavailable sleep is shown with n=0.
- Plane workflow, SSOT, architecture, app version, documentation lint, dose-write, legacy safety, repository hygiene, companion-target, and whitespace checks passed. Hygiene reported informational dangling objects; none were deleted. Structured closeout apply/readback on DOSETAP-45 and DOSETAP-13 follows this evidence commit; this file alone is not proof of a tracker update.

## Open acceptance and release boundaries

1. Install build 23 on the signed device and check real food, wake, and sleepiness entries against History, the dashboard, and exported files over several nights. Live HealthKit/WHOOP behavior, travel/timezone context, accessibility/max-text/iPad, and release performance remain open.
2. Verify iOS background scheduling/expiration and Files-provider delivery on the device. Local snapshots are not a verified whole-app backup/restore system; settings, complete supply-recovery workflows, and restore acceptance remain separate work.
3. Check Studio's native filtering, expansion, single-night display, and export interactions with an owner-approved bundle. The offscreen preview does not cover these controls.
4. The existing integration HOLD remains: broader UI regression, incident/device acceptance, credential rotation and provider revocation evidence, protected hosted checks, privacy/legal and release-owner approval. No push or merge to main was performed.

The dashboard-building guidance kept the work in the existing native apps. Data-validation guidance shaped the shared projection, independent sample counts, missing-value rules, and cross-app reconciliation. Copy-editing guidance was used for labels and these notes.
