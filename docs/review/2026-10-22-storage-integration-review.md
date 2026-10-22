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


## Hosted UI follow-up

At `183168d`, required checks, production iOS export fixtures and Studio passed.
The iPad run passed nine model tests and three UI tests, but its normal-text
calendar-range test timed out after five seconds on the third selection. The
subsequent screenshot visibly contains the expected selected 6M range and exact
April 23–October 22 dates. One unchanged-head rerun was requested; the failed
result is retained separately rather than counted as a pass.

The iPhone safety job passed four cases but failed the reset-warning case: its
captured hierarchy showed setup without the required warning. This is retained
as a real missing-presentation signal. The modal alert could compete with the
reset confirmation and replaced Settings hierarchy; its binding also allowed an
implicit dismissal to erase persistent warning state. The precise hosted
callback sequence was not captured. The warning is now a declarative app-root
panel, whose only acknowledgment write is its explicit button. The UI test also
checks background/foreground persistence before restart and acknowledgment.


The original five-case safety sequence passed locally unchanged, confirming that
the hosted missing-warning signal was intermittent. The first panel candidate
passed all five safety cases with the stronger background/foreground check.
Direct agent interaction then performed another synthetic reset and verified the
persisted warning after restarting at the largest accessibility text size.
The panel was readable but occupied almost the whole screen, so the final layout
reserves space above setup and uses a bounded, scrollable panel when needed.
An initial large-text test stopped while trying to reach Clear All Data within
its Settings-scroll budget, before warning presentation. Its failed bundle is
retained. The focused large-text test now changes text size on restart after
reset, directly exercising the persisted panel and reachable acknowledgment.


A second large-text candidate could not address the fallback scroll container.
The final panel uses an explicit scroll view with one stable identifier, a
text-size-scaled height capped at 320 points, and reserved layout space above
setup. Final-source standard and largest-text reset tests both passed on the
smaller iPhone 17e / iOS 26.5 (`reset-panel-scroll.xcresult`). They verify warning
survival through background/foreground and restart, reachable acknowledgment,
and dismissal that survives another restart. The four other safety flows passed
with the preceding panel candidate; the final hosted job now requires all six
cases. Earlier local candidate failures and the original hosted failure remain
separate evidence. No physical alarm verification is claimed.


Final direct visual inspection on iPhone 17e confirmed the warning scrolls to a
fully visible acknowledgment button while setup retains its own heading and
Continue button. `reset-panel-final-largest-top.png` and
`reset-panel-final-largest-ack.png` capture that inspection. This final visual
check used an injected presentation value; functional persistence and dismissal
come from the two passing reset tests, not from that injected value. Launch
arguments were cleared afterward and the task-opened simulators shut down.
