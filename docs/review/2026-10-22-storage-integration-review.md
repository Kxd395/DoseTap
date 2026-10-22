# Storage integration review — 2026-10-22

Status: Integration evidence; final hosted validation belongs to PR #74.
Plane: bounded DOSETAP-39, DOSETAP-20 and DOSETAP-8 work.

## Source identity and scope

PR #74 started at `3442d2343185d81f0c7425a111b11d862058fe66` and was reconciled
with main `a45074825e9807bb3417510e658c9cf986fd88de` in the isolated
`fix/storage-integrity-reconcile-74` worktree. Existing feature and preserved
checkouts were not transferred wholesale or modified. The owner authorized the
agent to audit, operate the simulator UI and merge when validation is sufficient.
Agent-operated review does not establish physical alarm delivery or owner comfort.

The reset and initialization transactions, migration/version refusal, alarm
readback, and synthetic iOS-to-Studio fixture handoff were traced against their
callers and failure tests. Existing legacy identity/deduplication rules are
unchanged; linked-record migration and complete backup/restore remain separate.
Current main's inventory classifier and 33 fixture methods are retained byte for
byte. The old shell fixture now copies the Python helper and uses ordinary `try`
so its derived-source case reaches the intended check. CI invokes the current
inventory guard and Python suite without a duplicate legacy guard step.

## Findings and corrections

1. A second reset after a rollback failure replaced the restart-required failure
   with a generic retry message. Two failing assertions reproduced this. The
   unavailable handle now retains its original failure; the regression passes.
2. Post-commit cleanup warnings were owned by Settings, which is replaced by
   setup after reset, and were not retained on restart. A native UI regression
   reproduced the missing warning after restart. The app root now presents a
   persisted warning until acknowledgment. A generation check rejects a cleanup
   result from an older reset, and a new active session suppresses reset-only
   reporting. Tests cover both invalidation cases.
3. Restart after reset treated freshly written default preferences as completed
   legacy setup. The UI regression caught the unexpected Tonight screen after
   acknowledgment. Reset now explicitly marks setup incomplete.
4. A skip-warning test inherited the simulator's prep-time preference and rolled
   over its fixed session before skipping. The test now sets and restores its
   own prep time; production skip rules are unchanged.

## Interactive review

On iPhone 17 Pro Max / iOS 26.5, the agent used the device panel and accessibility
controls to log one synthetic water event, open Settings, and confirm Clear All
Data. A task-owned SQLite rejection trigger caused a real deletion failure.
The visible failure alert was inspected, and an independent database read
confirmed the exact record ID/type/time remained. After removing only that
trigger, a second UI reset removed the event, retained schema version and
migration ledger, and returned to setup. No personal phone records were used.

The unverified-alarm UI test uses an explicit DEBUG/simulator-only verification
failure. Its screenshot was inspected with the warning over setup; this proves
presentation, not an actual system-alarm cancellation failure. The warning test
is included in the hosted safety job alongside the four previous safety flows.

## Validation and limits

Local artifacts are under `.build/pr74-reconciliation/` in the isolated checkout.
The initial focused run passed 113 of 114 cases before the prep-time fixture fix;
the subsequent 118-case run passed. The repeated-reset red run retained its two
assertion failures; the lingering diagnostic collection was terminated after
assertions completed, so it is not a successful test invocation. The first UI
red run failed on warning persistence; the next failed on setup persistence.
These failed runs are retained separately from final results.

Final native reset UI regression passed, including warning persistence, acknowledgment and setup after restart. The full iOS app suite passed 595 tests, including the cleanup-generation and new-session controls. Core validation passed 879 XCTest cases plus 43 Swift Testing cases. Inventory
fixtures passed 33 methods; archive-handoff fixtures passed six methods. Plane
workflow validation passed 15 tests / 80 assertions. All six production iOS archives were extracted from the passing app result bundle and supplied to Studio; exact Studio results and the hosted head are recorded in the PR and Plane workpads.

Signed-phone alarm/reset/background behavior, real-record export/share,
accessibility, provider/privacy/release acceptance, complete backup/restore,
and linked legacy migration coverage remain open under their existing items.
The current product version is unchanged; this is source integration, not a
phone installation or release. The merge includes already-reviewed upstream
main changes; the hook's documented large-commit option is needed for that
integration, with all normal build and guard hooks still enabled.

## Hosted guard correction

The first hosted run on `ad6cc19` rejected SettingsActions at 101 lines against
its existing 100-line ceiling. A local invocation had also failed, but its
nonzero status was obscured by later commands in the same shell invocation; the
earlier architecture-pass claim was incorrect. The reset-warning coordinator
was moved unchanged into `DataResetPresentation.swift` and added to the Xcode
source list. A full reference scan and fail-fast architecture check now pass.
The ceiling is unchanged. Final hosted validation must use the correction commit.
