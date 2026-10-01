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
not phone launch or scrolling measurements. Full-history snapshot work remains
synchronous at this checkpoint and requires a separate bounded correction.

Focused native tests passed 66 cases; core passed 1191 XCTest and 43 Swift Testing.
Normal and maximum-text landing tests and the replay exact-selection/export journey
passed. Visual inspection found an unnecessarily wrapped large-text navigation label;
it was shortened to View, with the complete selected destination retained for VoiceOver.
Expanded normal/maximum-text first-value and landscape checks passed; screenshots
were inspected. The simulator Busy launch artifact is retained separately. Signed-phone,
provider, VoiceOver, privacy, broader feature integration and owner acceptance remain
open; this document does not establish a replacement phone installation.
