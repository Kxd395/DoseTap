# Daytime reminder sleep-state reconciliation

Status: Implementation evidence; final review and physical acceptance remain open
Date: 2026-10-05, America/New_York
Plane authority: DOSETAP-58
Baseline: cfe5ad4, build 0.4.19 (103)
Candidate: build 0.4.19 (104), feat/sleep-chart-inspection
Checkout: /Volumes/Developer/projects/_DoseTap_Active/DoseTap-chart-inspection

## Physical inspection and diagnosis

iPhone Mirroring connected to the previously verified iPhone 15 Pro Max. On build
103, Tonight showed Record now, Review check-ins and Daytime reminder. Record now
opened an unanswered 0–10 diary with optional details, and Cancel returned to
Tonight without a success message. No observation or medication was saved.
Mirroring did not expose the phone's accessibility tree; these are pixel-based
interaction observations, not VoiceOver acceptance.

The existing reminder controls showed enabled randomized wake reminders. The
saved status reported suppression during known sleep or nap. Timeline showed no
active dose session and a completed previous session. This suggested a stale
sleep-state problem, but did not establish the exact blocking record on the phone.
The agent did not enable, select, save or change the existing routine or record a
wake/nap end to manufacture eligibility. The phone was returned to Tonight.

The source audit found that suppression scanned only 500 recent display events,
ignored explicit questionnaire final-wake answers, included future transitions,
and treated an unreadable event read as an empty history. Three pre-fix regression
tests produced eight assertion failures: /tmp/dosetap104-sleep-red.log and
/tmp/dosetap104-sleep-red.xcresult.

## Repaired behavior

Strict storage reads retain all relevant transitions and reject malformed or
partial data. An injected capture filters future events. Validated questionnaire
wake revisions visible at that capture end earlier main-sleep suppression. Later
lights-out and equal-time starts remain suppressors. An explicit main wake does
not supply a missing nap end or duration. The active-dose guard remains intact.
Foreground presentation fails closed on unreadable evidence. Reconciliation uses
throwing reads, clears verification and cancels owned requests on read failure.
It does not modify the saved routine, history, dose alarms or provider records.

## Validation

- First repaired service/storage run: 54 tests, zero failures;
  /tmp/dosetap104-sleep-green.xcresult.
- Expanded coverage includes later sleep, unfinished naps, 501 unrelated history
  rows, malformed sleep/wake values, future wakes, equal timestamps, corrected
  wake revisions at capture, and nap start during asynchronous OS work.
- The first expanded run failed because its malformed-wake fixture referenced a
  nonexistent updated_at column. The fixture now saves a valid night outcome via
  storage and corrupts only responses_json. That failed run is retained in
  /tmp/dosetap104-sleep-expanded.log and is not counted as a pass. Its owned Xcode
  runner was terminated after completed assertions stalled in teardown; exit143
  is not a successful or naturally completed test run.
- Swift build passed. Default and UTC full core suites each passed 1,203 XCTest
  and 43 Swift Testing cases, zero failures; /tmp/dosetap104-core.log and
  /tmp/dosetap104-core-utc.log.
- Final expanded service/storage suite passed 60 tests, zero failures;
  /tmp/dosetap104-sleep-final.log and /tmp/dosetap104-sleep-final.xcresult.
- Plane workflow (15 tests, 80 assertions), SSOT, documentation, architecture,
  dose-write and app-version guards passed. Four app configurations read 104.
- Reminder UI journeys passed at normal text (15.640 seconds) and largest text
  (43.293 seconds), two tests with zero failures; /tmp/dosetap104-ui.xcresult.
- Signed-device build passed; strict codesign verification passed and the product
  Info.plist reads 0.4.19 (104); /tmp/dosetap104-device.log. This original product
  predates the review fixes below and is not the final delivery candidate.
  No signed build104 installation is claimed at this checkpoint.
- The repository pre-commit script passed without overrides, including SwiftPM,
  print checks, the generic simulator build and the commit-size cap;
  /tmp/dosetap104-precommit.log.

## Daybreak round-one findings and remediation

Daybreak Blue completed the independent source review and found two actionable
issues in the initial candidate: an early real wake-context failure could retain
an old verified OS queue, and repeated per-night history reads caused N+1 query
growth on the main actor. The original passing tests did not cover those paths.

- The real-source stale-queue regression reproduced six assertion failures for
  regular and randomized wake routines; /tmp/dosetap104-early-source-red.log.
  Assertions completed, but the owned Xcode runner stalled in teardown and was
  terminated (exit143). This is reproduction evidence, not a passing run.
- Once mutation validation passes, all subsequent read failures clear verification
  and cancel owned requests. Rejected actions preserve the previous queue; the
  durable commit marker remains separate from the reconciliation boundary.
- The pre-batch trace reproduced clock query growth 61 to 493, and wake query
  growth 146 to 1,298, comparing 4 with 40 retained nights. The stale-queue test
  passed in that run while the query test failed twice; exit65,
  /tmp/dosetap104-query-red.log.
- Three batched wake statements validate dates, identities, readable dose rows,
  current answers and revisions. A scoped SQLite savepoint keeps transitions and
  wake records coherent. Planning reuses one immutable snapshot; fresh snapshots
  before adds and after pending readback retain concurrent-change detection.
- The first refactor run caught retry misclassification of source conflicts and
  reset (62 tests, four failures); /tmp/dosetap104-review-fixes.log. Separate
  conflict and OS-readback error paths repaired it. The next run's sole failure
  was a fixture comparing subsecond input with the existing whole-second night
  JSON codec (64 tests); /tmp/dosetap104-review-fixes-final.log. Its owned runner
  was terminated after completed assertions stalled in teardown (exit143).
- The corrected final service/storage run passed 65 tests with zero failures and
  TEST SUCCEEDED; /tmp/dosetap104-batch-final.log and
  /tmp/dosetap104-batch-final.xcresult. It includes real wake correction during
  OS add, conflicting and cross-night identity checks, malformed dose history,
  and a concurrent WAL writer proving coherent sleep/wake snapshots. Both clock
  and wake reconciliation measured 18 SELECT statements with either 4 or 40 nights,
  superseding the reproduced 61/493 and 146/1,298 counts. Exact physical-device
  latency is not measured.
- Default and UTC core suites each passed 1,203 XCTest and 43 Swift Testing cases;
  /tmp/dosetap104-fixes-core.log and /tmp/dosetap104-fixes-core-utc.log. Plane,
  SSOT, documentation, architecture, dose-write and version guards passed.
- Final reminder UI journeys passed at normal text (16.210 seconds) and largest
  text (44.950 seconds), two tests with zero failures;
  /tmp/dosetap104-fixes-ui.log and /tmp/dosetap104-fixes-ui.xcresult.
- The revised signed build passed, strict codesign verification passed and product
  Info.plist reads 0.4.19 (104); /tmp/dosetap104-fixes-device.log.
- Repository pre-commit checks passed without overrides, including the generic
  simulator build; /tmp/dosetap104-fixes-precommit.log. Legacy safety, companion
  target and repository hygiene guards passed.
- Daybreak round two independently confirmed the query-growth repair, but found
  one remaining cancellation-verification failure path. The candidate was not
  installed; verified phone delivery remains build103.

## Daybreak round-two cancellation recovery

A failed cleanup removal had been discarded before ordinary OS work began. A
transiently ignored removal could therefore retain owned requests after the
initial source read failed, despite empty visible queue verification.

- A new test reproduced eight assertion failures across regular and randomized
  wake routines and transient/persistent removal cases;
  /tmp/dosetap104-cancel-red.log. Assertions completed, but the owned Xcode runner
  stalled in teardown and was terminated (exit143); this is not a passing run.
- Failure cleanup now verifies removal, retries cancellation once, and returns an
  explicit success/failure result. This recovery does not reread or replan an
  unreadable source. Persistent failure prevents the ordinary recovery path from
  replanning and shows that cancellation could not be verified; it never claims
  that OS removal passed. Round three below found a separate coalesced path.
- Durable action outcomes remain separate. A saved Later stays deferred and retains
  precise cancellation-failure guidance instead of replacing it with generic text.
- The complete service/storage run passed 67 tests, zero failures and natural
  TEST SUCCEEDED; /tmp/dosetap104-cancel-final.log and .xcresult. New coverage
  verifies exactly two cleanup attempts, one failed wake read, retained ledger,
  preserved unrelated dose request, transient recovery and persistent failure
  bounds. A committed Later test verifies the separate normal cancellation plus
  two cleanup attempts with no automatic replanning. Query probes remain 18/18.
- Default and UTC core suites each passed 1,203 XCTest and 43 Swift Testing cases;
  /tmp/dosetap104-cancel-core.log and -cancel-core-utc.log. SwiftPM build and
  required Plane/SSOT/docs/architecture/dose-write/version guards passed.
- Revised signed build and strict codesign passed; product reads 0.4.19 (104),
  /tmp/dosetap104-cancel-device.log.
- Final UI journeys passed at normal text (15.505 seconds) and largest text
  (45.260 seconds), two tests with zero failures;
  /tmp/dosetap104-cancel-ui.log and .xcresult.
- Repository pre-commit checks passed without overrides, including SwiftPM and
  generic simulator builds; /tmp/dosetap104-cancel-precommit.log.
- Daybreak round three found one Medium/P2 coalesced-refresh escape, described
  below. No build104 installation is claimed; physical delivery remains build103.

## Daybreak round-three coalesced refresh recovery

Daybreak confirmed the earlier source-boundary, query-growth and standalone
cancellation repairs, but found that an overlapping lifecycle refresh could set
`again` while cleanup was suspended. The unconditional completion path then
launched a second reconciliation despite persistent cleanup failure. It could
also overwrite the status of an explicit queued action.

- The first red fixture repeatedly fulfilled an inverted expectation and crashed;
  /tmp/dosetap104-coalesced-red.log and .xcresult, exit65. This fixture error is
  retained and is not counted as a successful reproduction or validation.
- After guarding that expectation, the corrected red test naturally failed with
  18 assertion failures; /tmp/dosetap104-coalesced-red-corrected.log and .xcresult,
  exit65. It measured two wake-source reads instead of one, eight pending reads
  instead of four, and four owned-removal attempts instead of two.
- A local completion policy consumes plain refreshes coalesced during unreadable
  evidence or persistently unverified cleanup. Explicit queued notification
  actions still drain through normal validation. A later independent refresh can
  retry. Successful operations retain ordinary coalescing.
- The regression holds the first cleanup pending read, overlaps a lifecycle
  refresh, and optionally queues a stale explicit action. Eight scenarios cover
  regular/randomized wake routines, transient/persistent removal and refresh
  alone/queued action. They verify one source read, two cleanup attempts, retained
  ledger, no new adds, no false queue verification, unrelated ownership, action
  completion and status. A positive control verifies two healthy refresh passes.
- The first repaired build exposed a tuple-label inference error in the new test;
  /tmp/dosetap104-coalesced-final.log and .xcresult. Corrected tuple access compiled.
- The final focused suite naturally passed 75 tests with zero failures: 41 service,
  28 storage and six supply-reminder tests, including the shared mock's new optional
  async pending-read hook; /tmp/dosetap104-coalesced-final-corrected.log and .xcresult.
- Default and UTC core suites each passed 1,203 XCTest and 43 Swift Testing cases;
  /tmp/dosetap104-coalesced-core.log and -coalesced-core-utc.log. SwiftPM build,
  Plane workflow (15 tests, 80 assertions), SSOT/docs/architecture/dose-write/version
  guards passed. The earlier 18/18 query probes remain unchanged.
- Revised signed-device build and strict codesign passed; product Info.plist reads
  0.4.19 (104); /tmp/dosetap104-coalesced-device.log. Installation is still pending.
- Final UI journeys naturally passed two tests with zero failures at normal text
  (27.565 seconds) and largest text (57.775 seconds);
  /tmp/dosetap104-coalesced-ui.log and .xcresult. These simulator test durations
  include UI interaction and are not physical-device latency measurements.
- Repository pre-commit checks passed without overrides, including SwiftPM,
  print policy, generic simulator build and the commit-size cap;
  /tmp/dosetap104-coalesced-precommit.log. The normal commit uses the same hook.
- Daybreak round four is pending for the committed revision. No build104
  installation is claimed; independently verified physical delivery remains103.

## Acceptance boundaries

The phone inspection establishes bounded read-only navigation on build103 only.
It does not establish a saved symptom observation, delivery of a notification,
Open/Later/Skip, background renewal, Focus/lock-screen privacy, physical suppression
and recovery, VoiceOver, performance or owner usability. Existing prior-night,
provider, privacy/content, iPad/report, hosted integration and release gates remain
open. DOSETAP-58 remains In Progress.
