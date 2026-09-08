# Build 23 acceptance follow-up

Date: 2026-09-08. Candidate: `fix/locked-dose2-system-alarm` in `/Volumes/Developer/projects/DoseTap-main`. Studio correction: commit `83f2572`.

Merge and release remain HOLD. This pass uses synthetic local records, not the owner's phone or medical history. The [September 5 integration gates](../2026-09-05/integration-readiness.md) and [September 7 reporting evidence](../2026-09-07/collected-night-reporting.md) remain applicable.

## Changes

- Updated two iPhone UI journeys that still expected the removed Timing Groups and Recent interval change labels. They now check the requested natural-versus-alarm table, the full-range timing/status section, the food diary, and explicit missing-data and inclusive-boundary explanations. No dosing or alarm code changed.
- Corrected Studio's older 30-day timing cards. With no recent pairs, they displayed `0% / Needs Attention` and `0 min / Early Window`. They now show `No data` and explain that no recorded pairs exist in the last 30 days.
- Studio timing percentages now use valid recorded timestamp pairs, not all sessions or legacy `adherence_flag` values. Pair classification uses unrounded seconds. The cards disclose the pair count and no longer label average intervals Optimal or Good.
- Reconciled the SSOT's observed iPhone build identity to `0.4.19 (23)`. This pass changes desktop code and UI tests, not the shipping iPhone binary, so its build number stays 23.

The pre-existing Xcode project and UI scheme reorder changes remain excluded from these edits and commits.

## Native Studio acceptance

Created ignored local test app bundles under `macos/DoseTapStudio/.build/acceptance/`, using the compiled Studio executable. These are isolated test instances, not signed releases or installations in Applications.

Imported the synthetic archive produced by the real iOS scheduled exporter in the previous pass:

`/tmp/dosetap-ios-roundtrip/DoseTap_AutoExport_2026-09-07_220803_18A3D209-91B3-4046-B47B-40EE1D1FD7E7`

The imported bundle records app build 22, which is its export provenance, not the current iPhone build. Its SHA-256 is `7b71d302092ea11c1247726ff542dce2a12cea59ce7b8f8aea9770d8c2b2792b`. The synthetic night is June 16, outside the current 30-day range.

Observed through native UI controls:

- Import showed 2 events, 1 session and 28 doses in the supplied inventory snapshot. Missing Apple Health/WHOOP enrichment remained an explicit warning.
- Library night detail showed food type, finish time, high-fat answer and notes; 155/365-minute food-to-dose intervals; explicit natural Dose 2 waking; a separately set backup alarm; Day off; final awakening; and sleepiness `0` with its assessment time. Post-dose sleep remained unavailable.
- Dashboard All days showed 1 food record out of 1 night. Workday showed 0 of 0; Day off restored 1 of 1. Food answer expansion preserved the observed zero rating with `n = 1`, while missing groups showed unavailable with `n = 0`.
- Export preview included the new diary fields. Native Save Night CSV wrote `night-ui-20260908.csv`. Turning redaction on and saving again wrote `night-ui-redacted-20260908.csv`. Both saved files were read from disk with Ruby CSV: food/wake/day values and zero survived; redaction removed notes and exact diary timestamps; missing post-dose sleep stayed empty.
- After the timing-card correction, a separately launched test app imported the same folder. Accessibility readback and screenshot inspection confirmed both 30-day cards display No data instead of zero or a timing-quality judgment.

Generated CSV files are under the ignored `.build/acceptance/` directory. No provider data was fetched or uploaded. Interactive filter, detail, expansion and save behavior now have synthetic native-runtime evidence; owner-approved real-bundle acceptance remains open.

## Validation

| Check | Result | Evidence |
| --- | --- | --- |
| Core build and tests | Passed: 655 XCTest + 43 Swift Testing cases | `/tmp/dosetap-sep8-core.log` |
| Studio timing regression, test-first | Failed before implementation because the new summary did not exist | `/tmp/dosetap-sep8-studio-red.log` |
| Full Studio suite with actual iOS fixture and preview enabled | Passed: 62 tests, no failures/skips | `/tmp/dosetap-sep8-studio-green.log` |
| Native Studio import, filters, details, normal/redacted CSV | Passed on synthetic records | UI readback and on-disk CSV assertions described above |
| Full iPhone UI suite | 38 executed: 36 passed, 2 stale dashboard-label expectations failed. All 8 launch checks passed | `/tmp/dosetap-build23-full-ui.log` |
| Updated dashboard journeys | Passed: 2 tests, zero failures | `/tmp/dosetap-sep8-dashboard-rerun.log`, same simulator, serial execution |
| Plane, SSOT, version, export, inventory, architecture, dose-write and documentation guards; diff whitespace | Passed | Repository helpers and `git diff --check` |

Full-suite result bundle: `/tmp/dosetap-build23-acceptance.aZFxsn/Logs/Test/Test-DoseTapUITests-2026.09.08_08-07-04--0400.xcresult`.

The corrected tests passed All/Trends/Data navigation, the replacement comparison table, and sparse/empty states. The successful two-test rerun supersedes the obsolete assertions, but it is not a second full 38-test run. A full run on the final integrated revision and protected hosted checks remain integration gates.

The supply-reminder journey passed, including Mark handled after relaunch. No supply code changed, so the earlier intermittent failure is not explained by this pass. The native system-alarm background-delivery test also passed. Exported screenshots were inspected: `/tmp/dosetap-sep8-supply-proof/8E69AB23-0E26-44FC-8A61-1F3459677FC9.png` shows Handled; `/tmp/dosetap-sep8-alarm-proof/628E9F94-DF22-4623-BEB7-3F44E8EA7B04.png` shows the system alarm over the simulator Home Screen. Neither is signed-device locked/Silent/Focus acceptance.

## Remaining review

The older Studio Timing Insight and recommendation package still uses its existing composite score and inferred/legacy wake context. It is separate from the new explicitly recorded wake/food diary comparison. This pass does not certify that older recommendation engine against the new diary contract. A follow-up under DOSETAP-45 must reconcile those outputs before claiming complete analytics parity.

General desktop window sizing, owner-approved exports, real background scheduling and Files delivery, signed-device alarm/dose behavior, provider authorization and records, accessibility, privacy, credential revocation, hosted protected checks and release-owner acceptance remain open. No phone install, push, or merge to `main` was performed.

Plane closeout and exact post-write verification are required on DOSETAP-45, DOSETAP-13, DOSETAP-30 and DOSETAP-4 after this evidence is committed. Keep them In Progress while their gates remain open. Live Plane readback, not this document, establishes whether the workpad update was applied.
