# DoseTap integration-readiness audit — 2026-09-05

**Decision, updated 2026-09-07:** merge and release remain **HOLD**. The owner-reported unexpected Dose 2 record is tracked under DOSETAP-46; see `docs/audit/2026-09-07/dose2-recording-incident.md`. A merge records reviewed source integration; it is not signed-device, provider, privacy, legal, or release acceptance.

## Authority and scope

- Shipping baseline: `/Volumes/Developer/projects/DoseTap-main`.
- Preserved non-authoritative checkout: `/Volumes/Developer/projects/DoseTap`; it was inspected only for the documented handoff and its dirty/private material was not copied wholesale.
- Comparison base: `origin/main` at `5d1fa4b48bec00007a0b6f8327a8edee7b096569`.
- Candidate branch: `fix/locked-dose2-system-alarm`, initially 23 commits ahead of that base. Four local remediation commits now follow: `ab64b95`, `357a254`, `a07797a`, and `2f29ff7`.
- Scope includes supply reminders, AlarmKit-backed Dose 2 wake alarms, work-night/pre-sleep behavior, dashboard analytics through 0.4.17, the 0.4.18 audit remediations, and the subsequent DOSETAP-46 confirmation safeguard.
- App identity checked from project settings and the simulator product: version `0.4.18`, build `20`.
- No audit-remediation push, pull request, hosted CI run, or merge has been performed. Pre-existing Xcode project/scheme edits remain uncommitted and separate from the reviewed changes.

## Audit findings and remediation

### 1. Overlapping wake-alarm replacement race — fixed

Two concurrently accepted custom-scheme snooze actions could previously overlap while replacing one stable AlarmKit identifier. A stale outer transaction could cancel the newer verified alarm. `AlarmService.scheduleDose2Alarm` now establishes a MainActor single-flight owner before its first suspension and rejects the overlapping transaction before generation or OS-alarm mutation. A continuation-controlled test proves only one native schedule reaches the sink and the winner remains installed.

Security disposition: plausible candidate retained in the security ledger, then suppressed as fixed in the reviewed snapshot. Counterfactual severity was low because exploitation required an active, unlocked app, an eligible live session, remaining snooze allowance, and precise overlap; the consequence was medication-alarm availability/integrity.

### 2. Supply-backup restore resource exhaustion — fixed

The restore path previously trusted advisory File Provider size metadata and then performed an unbounded whole-file allocation. The sole UI import now uses `SupplyBackupFileCodec`, which reads at most 10,000,001 bytes, rejects data over the 10 MB application limit before JSON decoding, and caps imported bottle and revision histories at 10,000 records. Tests cover the exact custom limit, one byte over it, one byte over the default 10 MB limit, and collection-count rejection.

Security disposition: plausible CWE-400 candidate retained in the ledger, then suppressed as fixed in the reviewed snapshot. Bounded JSON decode cost, File Provider latency, and already-persisted pre-remediation local payloads remain hardening considerations; they do not reopen the original unbounded selected-file read.

### 3. Simulator test boundary crossed live AlarmKit — fixed

`URLRouterTests` used the application singleton and therefore reached live AlarmKit authorization from an ordinary unit test. The full scheme could hang indefinitely in teardown. The suite now owns an isolated `URLRouter`, an isolated `AlarmService`, a UUID-scoped defaults domain, and an in-memory notification client. The 31-test suite completes without prompting or mutating the running app's navigation stack.

### 4. Fixed-clock suites consumed a live prep-time setting — fixed

Four simulator suites injected a January 23:00 UTC clock but still read the workstation's current `prepTimeMinutes`. Schedule-driven rollover could close their synthetic session between dose mutations. The fixtures now pin prep time to the 18:00 test boundary and restore the previous setting in teardown. The factory-reset assertion also includes the intentionally managed supply-reminder notification identifier.

## Security review coverage

- Mode: preliminary branch/diff scan against the stated `origin/main` base, including the original working-tree audit remediations but preceding DOSETAP-46.
- Preliminary inventory: 46 changed source-like Swift/package files with per-file receipts. This is not the final changed-file inventory after the incident safeguard.
- Surfaces: deep-link and alarm scheduling; supply import and persistence; medication/session storage; dashboard/provider refresh; settings and app views; unit/UI test support; package and target topology.
- The two source-security candidates were remediated, but the final canonical scan bundle was not sealed. This is not a completed clean security report, and the subsequent DOSETAP-46 changes require fresh review.
- Explicit exclusions: documentation, image evidence, and Xcode configuration outside the source-like security inventory were reviewed by the integration audit but not treated as executable source surfaces. Signed-device behavior and provider revocation are external acceptance evidence, not source-scan coverage gaps.
- Canonical report: not yet finalized; preliminary receipts remain outside the repository in the temporary scan bundle.

## Validation record

| Check | Result | Evidence class |
| --- | --- | --- |
| `swift build -q && swift test -q` | Passed on 2026-09-07: 637 XCTest cases and 43 Swift Testing cases | automated/local |
| `TZ=UTC swift test -q` | Passed on 2026-09-05: 637 + 43; not rerun on the final incident changes | automated/local, dated |
| `TZ=America/New_York swift test -q` | Passed on 2026-09-05: 637 + 43; not rerun on the final incident changes | automated/local, dated |
| `swift test --package-path macos/DoseTapStudio -q` | Passed on 2026-09-05: 55 XCTest cases; not rerun on the final incident changes | automated/local, dated |
| Focused `SystemDoseAlarmTests` | Passed: 5 tests, including deterministic overlap regression | automated/iOS simulator |
| Focused `URLRouterTests` | Passed: 31 tests after OS/UI isolation | automated/iOS simulator |
| Focused fixed-clock suites | Passed: 38 tests | automated/iOS simulator |
| Full `DoseTap` Xcode scheme | Passed on 2026-09-07: 325 tests, serial execution, including DOSETAP-46 | automated/iOS simulator |
| DOSETAP-46 targeted UI journeys | Passed on 2026-09-07: all 3 confirmation/cancellation/background/restart and work-warning journeys | automated/iOS simulator |
| Full `DoseTapUITests` scheme | Failed on 2026-09-05: 30 tests, 2 failures (`testRepeatedTabSwitchingDoesNotCrash`, `testSupplyReceiptReminderAndOptionalBottleSurviveRelaunch`); read back on 2026-09-07 | automated/iOS simulator, dated |
| Recheck of the two prior UI failures | 2026-09-07: tab-switching passed; supply failed because status remained `Scheduled:` after the test's `Mark handled` tap. Full suite remains open | automated/iOS simulator |
| Documentation, SSOT, architecture, dose-write, legacy-safety, companion, hygiene, version, and Plane-workflow guards | Passed | automated/local |
| `git diff --check`, UI scheme XML, and Xcode project plist parse | Passed | automated/local |
| Untagged `tools/release_preflight.sh` | Not run for the final incident candidate; does not replace release acceptance | automated/local |
| Required GitHub checks on pull request | Pending protected-branch run | automated/hosted |
| Plane closeout apply and verify | Required after this evidence commit on DOSETAP-4, DOSETAP-30, and DOSETAP-46; use live workpad/state readback, not this snapshot, for completion | external tracker readback |

The first full Xcode attempt was stopped after the live AlarmKit test boundary hung. A documented one-time simulator reboot was then needed after the interrupted runner left SpringBoard busy. Subsequent failures exposed the deterministic fixture and live-router defects described above. The initial clean app run had 315 tests; the final 2026-09-07 run has 325. Neither app-scheme pass substitutes for the separate, still-failing broader UI suite.

## Credential and history audit

- A redacted Gitleaks scan found no detection in the current tracked tree.
- A redacted all-history scan found 55 detections across local refs. Historical WHOOP credentials are present in public `main` ancestors; provider-side revocation is not yet directly verified.
- In the earlier credential audit, the then-active local Plane token matched a credential in a local-only checkpoint ref. The ref was not published. Replacement-token use and the prior token's rejection remain unverified; this document does not assert the old token is still active or that rotation is complete.
- This audit adds no token values, `.env` contents, Keychain material, provider secrets, or downloadable token CSV to its documents, security bundle, new Git commits, or Plane workpads.
- Public-history rewrite and local-ref deletion are intentionally not performed by this integration: they are destructive retention decisions that require a separately reviewed plan after provider revocation.

## Plane snapshot

Plane remains the work-status authority. At audit time the exact items were:

| Item | State | Why it remains open |
| --- | --- | --- |
| `DOSETAP-1` | In Progress | Plane token rotation/readback, historical WHOOP revocation evidence, and history-retention decision |
| `DOSETAP-4` | In Progress | Signed-device locked/Silent/Focus/repeated-snooze and owner/accessibility acceptance |
| `DOSETAP-30` | In Progress | Signed-device notification/relaunch/timezone/tap behavior, Files-provider restore, privacy/accessibility |
| `DOSETAP-34` | In Progress | Remaining physical/provider acceptance recorded on the item |
| `DOSETAP-41` | In Progress | Remaining integration acceptance recorded on the item |
| `DOSETAP-42` | In Progress | Remaining physical/provider acceptance recorded on the item |
| `DOSETAP-44` | In Progress | Remaining owner-observed acceptance recorded on the item |
| `DOSETAP-45` | In Progress | Three to five real nights, Health/WHOOP/travel, VoiceOver/iPad/max-text, and release performance |
| `DOSETAP-46` | In Progress | Original unexpected activation unresolved; signed-device confirmation, owner record review, accessibility, and integration acceptance |
| `DOSETAP-17` | Backlog | Not claimed merely because this audit contains planning/status evidence |

Closeout must update the exact in-scope items without moving them to `Done` while their external gates remain open.

## Merge criteria and release gates

The branch may merge when the remaining automated rows above pass, the final security review is sealed, replacement credential use and old-token failure are verified, Plane workpads are applied and read back, and the protected GitHub checks are green. The merge should preserve the branch's reviewed commit history. Owner/signed-device acceptance of the DOSETAP-46 safeguard must be explicitly recorded or dispositioned as an open release gate; passing simulator tests alone does not resolve the original incident.

Release remains HOLD after merge until all applicable evidence is directly observed and recorded:

- signed-device AlarmKit delivery while locked and under Silent/Focus, repeated snooze, cancellation, relaunch, and timezone-change behavior;
- signed-device supply notification, tap, relaunch, timezone, and Files-provider restore behavior;
- owner-observed dashboard use across three to five real nights, Health and WHOOP states, travel, VoiceOver, iPad, maximum text size, and release performance;
- provider-side revocation of historical WHOOP credentials and the reviewed credential-history retention decision;
- privacy, accessibility, provider, legal, and release-owner acceptance required by the corresponding Plane items.
