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

The detailed recorded-measures disclosure retains the reporting-range/rollover explanation together with source and capture provenance. Final UI verification, candidate signing/installation and owner acceptance follow.
