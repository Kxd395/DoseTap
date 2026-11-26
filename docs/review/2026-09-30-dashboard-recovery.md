# Dashboard recovery — September 30, 2026

Status: Implementation candidate; owner acceptance remains open
Tracker: DOSETAP-45

## Scope and preservation

The owner rejected phone build 89 appearance and responsiveness. Recovery starts from
its exact application source `153095e`, in `fix/dashboard-recovery`. Main was fetched
and remained `fac445c`. The paused dashboard/iPad branch at `da3467e` and the original
dirty checkout are preserved. This is not a merger of the pending feature stack.

## First correction

Overview is the default. Short Overview/Trends/Explore/Records navigation retains
all detailed routes through Explore. The reporting period remains accessible with
short labels; source explanations in recorded-measure panels expand on demand.
Legacy unconfirmed questionnaire averages remain withheld.

Reporting windows, filtered period rows and replay projections are cached in memory.
Published changes invalidate caches after mutation; coverage changes and provider
access revisions invalidate replay evidence. No cached result is persisted.

## Evidence

Evidence directory: `.build/dashboard-recovery-evidence/`.
The baseline UI tests both failed because the initial build-89 page did not show
Recorded Nights. Baseline simulator performance: 40 period projections over 336
synthetic nights averaged 118 ms; a 365-session local snapshot averaged 74 ms.
After caching, the same projection benchmark averaged about 0.6 ms including its
first cache fill; subsequent samples were 0.026–0.041 ms. These are microbenchmarks,
not phone launch or scrolling measurements. The subsequent background-decoding correction is described below.

Focused native tests passed 66 cases; core passed 1191 XCTest and 43 Swift Testing.
Normal and maximum-text landing tests and the replay exact-selection/export journey
passed. Visual inspection found an unnecessarily wrapped large-text navigation label;
it was shortened to View, with the complete selected destination retained for VoiceOver.
Expanded normal/maximum-text first-value and landscape checks passed; screenshots
were inspected. The simulator Busy launch artifact is retained separately. Signed-phone,
provider, VoiceOver, privacy, broader feature integration and owner acceptance remain
open; this document does not establish a replacement phone installation.

## Background decoding and first local display

Candidate phone version: 0.4.19 (90); not yet an installed/accepted release.
The SQLite owner captures immutable typed rows and closes the transaction before
background decoding. Existing synchronous consumers use the same decoder. Local
revision, provider revision, reporting period, timezone and generation guards reject
obsolete publication. Per-worker timestamp formatters replace shared formatter use
in that decoder. An immutable-copy regression proves concurrent later writes cannot
change an earlier captured snapshot.

67 affected native cases passed for the background snapshot slice. For 365 synthetic
sessions, the capture phase retained on the UI actor averaged 27 ms (23–26 ms warm),
versus approximately 68–74 ms for full capture and decoding. SQL capture is still
synchronous; this is a reduced main-thread workload, not a zero-hitch guarantee.
First-load local records now publish before provider preparation/history waits;
readiness flags remain false until final publication. The suspended-provider test
reproduced the previous blank-local-display behavior before this correction.

Final focused native rerun: 69 cases passed, including the previously failing changed-custom-bounds test. Empty local histories do not publish a provisional reporting period. The other 35 identity/provider matching/shared-sleep/storage cases passed in the preceding combined run; its one range failure is retained as diagnostic evidence. Core remains 1191 XCTest plus 43 Swift Testing passed.

Latest 365-session capture benchmark averaged 24 ms (about 23 ms warm); full synchronous capture and decoding averaged 68 ms. Repeated period projections averaged about 0.6 ms including the first cache fill. These are synthetic simulator measurements with warm-cache variance, not device interaction timings.

The detailed recorded-measures disclosure retains the reporting-range/rollover explanation together with source and capture provenance. Final UI verification passed: Overview normal and maximum text (including full first-metric bounds in landscape), night-mode chart selection/readable legends, and detailed recorded-measures large-text/landscape navigation. The earlier missing range-description failure is retained; final-details-ui passed after restoration. Screenshots were inspected. The detailed-page screenshot establishes navigation/reachability, not full visibility of every lower metric at once.

Recovery application commits: `7555aa5` and `6e313f1`. Normal enabled precommit hooks passed SwiftPM and generic simulator builds for arm64 and x86_64. Required Plane workflow, SSOT, version90, architecture, dose-write, legacy, companion, repository hygiene, documentation lint and diff checks passed. Signed installation evidence and owner acceptance remain separate.

## Recommendation and remaining sequence

1. Review candidate90 on the owner's phone with existing records: initial dashboard, scrolling, switching ranges, returning from a detail view, and refresh with providers available/unavailable. Judge appearance and responsiveness before more dashboard expansion.
2. If a visible hitch remains, capture a targeted device trace for that interaction. SQL capture is still on the UI actor; migrate it only if measured device evidence identifies it as the remaining bottleneck. Keep the coherent read transaction and stale-publication guards.
3. Verify actual-night chart/table/export consistency and physical VoiceOver focus/order. Synthetic UI and microbenchmarks do not close these gates.
4. After phone acceptance, reconcile these two focused fixes into the pending integration branch and rerun affected checks against that combined head. The recovery begins from an unmerged phone89 stack; do not open a misleading whole-stack main PR or reset main to the feature branch.
5. Resume iPad work separately when requested. Keep DOSETAP-45 In Progress and preserve all inherited provider/privacy/release gates until their own evidence is complete.

Do not broadly roll back the stored-data or medication features to recover appearance. Keep the build89 artifact for comparison; an older executable is not assumed compatible with newer stored state without an explicit compatibility check.

## Signed phone delivery

Installed 0.4.19 (90), bundle `com.dosetap.ios`, on the paired iPhone 15 Pro Max
without uninstall/reset. Signed source is `6e313f11d3ee12b4a26c8f54f2384c592cdb51fa`.
Executable SHA-256: `bb8e83cad98dcdb467b69a0e48c6b2d722b6471283fc915576e4a9b34488e0ba`.
Strict/deep code-signature verification passed. Original ignored local signing
configuration was used and the recovery template restored afterward; no config
values were printed or staged. Independent device inventory reports version90;
launch succeeded and an independent process readback confirmed PID47651.
Receipts: `phone90-artifact.json`, `phone90-install.log`,
`phone90-installed-apps.json`, `phone90-launch.json`, `phone90-processes.json`.
The signed build89 artifact remains preserved with its verified original hash.
Installation/launch is not owner-observed display, performance, data, or provider acceptance.
