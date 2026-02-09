DoseTap Full Codebase Audit — 2026-02-09
Branch: 004-dosing-amount-model (6 commits ahead of origin/004-dosing-amount-model, 15 commits ahead of main)
Working tree: 24 files modified, net -7,125 lines (massive uncommitted refactoring in progress)

A) Critical Findings (P0/P1)
F-01 — iOS App Target Build Broken (Uncommitted)
Severity: P0
Confidence: 1.0
Files: SleepStageTimeline.swift (lines 577, 584, 600–601, 635–636, 656–657, 682–683, 722, 732, 736–738)
Repro: xcodebuild build -project [DoseTap.xcodeproj](http://_vscodecontentref_/2) -scheme DoseTap -destination 'id=00188B7D...' → 16 compile errors
Root cause: Uncommitted diff removed @State private var sleepEvents, @State private var sessionSummary, private var queryRange, private var displayRangeEffective, func loadSessionData(), func loadHealthKitData() from LiveSleepTimelineView, but left 16 references to them in the remaining code (methods lightsOutTime, finalWakeTime, displayRangeText, healthKitSection, recomputeDisplayRange).
User impact: App cannot be compiled or shipped. Zero functionality.
Technical risk: Blocks ALL xcodebuild tests (25 SessionRepositoryTests cannot run).
Fix: Complete the refactoring — either restore the removed members or update all callers to use the new data path (timeRange + loadSleepData).
F-02 — TimePickerSheetRow Missing — Build Blocker
Severity: P0
Confidence: 1.0
Files: ios/DoseTap/FullApp/SetupWizardView.swift:162,167 and ios/DoseTap/SleepPlanDetailView.swift:15,19
Repro: grep -rn "struct TimePickerSheetRow" ios/ → 0 results. The struct is used in 4 call sites but never defined.
User impact: Setup wizard and sleep plan screens cannot compile. New users cannot onboard.
Fix: Create TimePickerSheetRow view (a row with label + sheet-presented DatePicker wheel for time selection) or replace call sites with inline DatePicker.
F-03 — MorningCheckInViewV2 Emptied But Still Referenced
Severity: P0
Confidence: 1.0
Files: MorningCheckInViewV2.swift (emptied, 0 lines), ios/DoseTap/FullApp/TonightView.swift:49
Repro: The uncommitted diff empties MorningCheckInViewV2.swift (1,054 lines deleted) but TonightView.swift:49 still presents MorningCheckInViewV2(...) in a .sheet.
User impact: Morning check-in sheet cannot compile → session cannot be closed via UI → sessions accumulate indefinitely.
Fix: Update TonightView to reference the V1 MorningCheckInView (which appears to have absorbed V2's content in the uncommitted changes), or restore the type alias.
F-04 — Release Builds Ship Without Certificate Pinning
Severity: P1
Confidence: 0.95
Files: ios/Core/DoseTapCore.swift:156–163
Repro: In release builds, makeTransport() checks CertificatePinning.hasConfiguredPins. Currently configuredPins() returns [] (no env var DOSETAP_CERT_PINS, no Info.plist entry). The assertionFailure(...) on line 161 compiles to a no-op in release. Result: unpinned URLSessionTransport is returned silently.
User impact: MITM attacks on API traffic are not prevented. Medical dose data transmitted without pin protection.
Technical risk: Silent security degradation — code looks like it enforces pinning but doesn't.
Fix: Replace assertionFailure with a hard fatalError or refuse to create the transport entirely. Add CI check that DOSETAP_CERT_PINS is set for release builds.
F-05 — 67 Unguarded print() Statements Leak Session Data in Release Builds
Severity: P1
Confidence: 1.0
Files: EventStorage.swift (48 prints), SessionRepository.swift (19 prints)
Repro: grep -rn "print(" ios/DoseTap/Storage/*.swift | grep -v "DEBUG\|#if" | wc -l → 67
Data leaked: Session dates, dose timestamps, session IDs, dose intervals, snooze counts, terminal states, DB path.
User impact: Any user with Console.app or idevicesyslog can observe medical dosing patterns. Violates HIPAA-adjacent privacy expectations.
Fix: Wrap all non-diagnostic prints in #if DEBUG ... #endif or replace with os_log with .private privacy class.
F-06 — All SQLite I/O on @MainActor (3,790-line God Class)
Severity: P1
Confidence: 0.9
Files: ios/DoseTap/Storage/EventStorage.swift:13 (@MainActor)
Evidence: 625 sqlite3_* calls, all bound to main actor. File is 3,790 lines.
User impact: Any query (history load, CSV export, event insert) blocks the UI thread. On older devices with 500+ events, this causes dropped frames, hitches, and watchdog kills.
Technical risk: iOS watchdog will terminate the app if a synchronous DB operation exceeds 10s during applicationDidFinishLaunching.
Fix: Move EventStorage to a dedicated serial DispatchQueue or a custom actor. Keep @MainActor only on the SessionRepository (observer-facing surface).
B) Medium/Low Findings (P2/P3)
F-07 — OfflineQueue Double-Increment on Retry
Severity: P2
Confidence: 0.85
Files: ios/Core/OfflineQueue.swift:65,76
Evidence: task.markAttempt() (line 65) increments attempts to 1. On failure, retryTask.attempts += 1 (line 76) increments again to 2. With maxRetries=3, only 2 total attempts occur instead of 3.
User impact: Offline dose logs have fewer retry chances than configured. Data could be lost on flaky connections.
Fix: Remove retryTask.attempts += 1 on line 76 (markAttempt already handled it).
F-08 — DoseWindowCalculator.remainingMinutes Always Returns nil
Severity: P2
Confidence: 1.0
Files: ios/Core/DoseWindowState.swift:226–230
Evidence: remainingMinutes calls context(dose1At: nil, ...) which always returns .noDose1 phase with remainingToMax: nil.
User impact: Dead API surface. Any caller trusting this property gets nil always.
Fix: Remove the property or require dose1At as a parameter.
F-09 — preSleepSessionKey Dead Ternary Branch
Severity: P3
Confidence: 1.0
Files: ios/Core/SessionKey.swift:58–59
Evidence: let sessionDate = hour < rolloverHour ? date : date — both branches return date. The comparison is dead code.
User impact: No functional impact (behavior is coincidentally correct for pre-sleep context), but misleads maintainers into thinking there's conditional logic.
Fix: Replace with let sessionDate = date and add a comment explaining why pre-sleep always uses the current date.
F-10 — SSOT constants.json Stale (Missing finalizing Phase)
Severity: P2
Confidence: 1.0
Files: constants.json (version 1.0.0, lastUpdated 2025-01-07)
Evidence: states.phases array has 7 entries but lacks finalizing. The SSOT README v3.0.0 and DoseWindowPhase enum both include finalizing.
User impact: None directly, but agents/tools consuming constants.json will have an incomplete phase model.
Fix: Add { "name": "Finalizing", "description": "Wake final logged, awaiting morning check-in" } to the phases array.
F-11 — WHOOP Client Secret in Local File (Not Committed, But Risk)
Severity: P2
Confidence: 0.8
Files: ios/DoseTap/Secrets.swift:8–9 (local only, .gitignore'd)
Evidence: Real WHOOP OAuth clientID and clientSecret are hardcoded as string literals. File is in .gitignore and was never committed (verified via git log --all). However, if .gitignore is ever modified or a dev copies the repo, credentials leak.
User impact: WHOOP API abuse if credentials escape.
Fix: Load from Keychain or environment variables. Rotate the existing secret proactively.
F-12 — setDose1Time() Has No Idempotency Guard
Severity: P2
Confidence: 0.9
Files: ios/DoseTap/Storage/SessionRepository.swift:495–520
Evidence: setDose1Time() unconditionally resets all downstream state (dose2Time=nil, dose2Skipped=false, snoozeCount=0, etc.). A rapid double-tap would wipe any dose 2 state recorded between the two invocations.
User impact: SSOT itself acknowledges this ("Duplicate dose taps are not explicitly de-duplicated"). In practice, the undo mechanism mitigates this, but a race condition window exists.
Fix: Guard: guard dose1Time == nil || undoManager.canUndo else { return }.
F-13 — No WAL Mode for SQLite
Severity: P3
Confidence: 0.9
Files: ios/DoseTap/Storage/EventStorage.swift:64–67
Evidence: Only PRAGMA foreign_keys = ON is set. No PRAGMA journal_mode = WAL.
User impact: Default rollback journal mode has worse concurrent read performance and is more susceptible to corruption on crash.
Fix: Add sqlite3_exec(db, "PRAGMA journal_mode = WAL", nil, nil, nil) after openDatabase().
F-14 — Massive Uncommitted Diff (9,131 Deletions) at Risk of Accidental Loss
Severity: P2
Confidence: 1.0
Files: 24 files modified, -9,131 / +2,006 lines
Evidence: git diff --stat HEAD shows uncommitted changes larger than most feature branches. Includes deletion of entire V2 views, removal of plannerSessionKey, and SessionKey.swift changes.
User impact: If the working tree is lost (disk failure, git checkout .), significant work is gone.
Fix: Stash or commit to a WIP branch immediately.
C) Test Matrix Results
Suite	Framework	Pass	Fail	Flaky	Notes
DoseCoreTests (SwiftPM)	XCTest	296/296	0	0	All green in 2.55s
SessionRepositoryTests (Xcode)	XCTest	Cannot run	N/A	N/A	Blocked by F-01 build errors
DoseTapTests (Xcode)	XCTest	Cannot run	N/A	N/A	Blocked by F-01 build errors
Test warnings observed:

⚠️ TimeIntervalMath: Non-sensical interval -60.0 seconds — This is intentionally triggered by test_minutesBetween_nonsensicalNegative and is expected.
Test gaps (residual risk):

No UI tests — No XCUITest or ViewInspector tests exist anywhere. All SwiftUI views are untested.
No integration tests for AlarmService — Wake alarm scheduling, snooze rescheduling, and notification delivery are untested.
No HealthKit tests — HealthKitService is protocol-abstracted but only NoOpHealthKitProvider is used in tests. No segment parsing tests.
No export round-trip test — CSV export is unit-tested but import/re-import integrity is not validated.
SessionRepository tests blocked — 25 integration tests (SessionRepositoryTests.swift) cannot run due to F-01.
D) Logging/Diagnostics Assessment
Strengths:

DiagnosticLogger is well-designed: actor-isolated, JSONL format, per-session folders, sequence numbers, retention policy.
DataRedactor has comprehensive PII detection (email, IP, UUID) with 25 passing tests.
Tier 1/2/3 event classification follows a defensible prioritization scheme.
Session trace export (exportSession) provides forensic capability.
Weaknesses:

67 unguarded print() statements (F-05) undermine the structured logging approach by leaking data through the system console.
No log sampling or rate limiting — If DiagnosticLogger.isEnabled is true, every event writes to disk. Under rapid sleep-event logging, this could cause I/O pressure.
Retention cleanup is opportunistic — pruneOldSessions(olderThan:) is available but no evidence of it being called on a schedule.
tier3Enabled defaults to false and has no implementation — the feature flag exists but Tier 3 state snapshots are marked "not yet implemented."
E) UX/App Flow Defects
E-01 — Setup Wizard Blocked (F-02)
Missing TimePickerSheetRow means new users cannot complete onboarding. The wizard step 1 (Sleep Schedule) will crash.

E-02 — Morning Check-In Broken (F-03)
TonightView references MorningCheckInViewV2 which was emptied. Users cannot submit morning check-ins → sessions never close → data accumulates in current_session indefinitely.

E-03 — ContentView.swift is 3,339 Lines
ContentView.swift contains 8 views (ContentView, LegacyTonightView, AlarmIndicatorView, HardStopCountdownView, UndoSnackbarView, DetailsView, HistoryView, SelectedDayView). This creates a cognitive load problem and increases merge conflict risk.

E-04 — Duplicate Settings Surfaces
SettingsView.swift (1,641 lines) and EnhancedSettings.swift both exist. The roadmap acknowledges "Retire duplicate/legacy settings surfaces" as P1.

E-05 — SleepTimelineContainer Date Picker UX
The night picker in SleepTimelineContainer (lines 798–852) uses simple chevron buttons but no date picker for jumping to specific dates. Users reviewing historical data must tap back one night at a time.

F) Recommended Updates
Immediate Fixes (Next 24h)
Commit or stash the 9,131-line diff — prevent loss of work (F-14)
Create TimePickerSheetRow struct to unblock SetupWizardView (F-02)
Fix MorningCheckInViewV2 reference in TonightView.swift → point to V1 or restore type (F-03)
Complete SleepStageTimeline refactoring — add back removed properties or update callers (F-01)
Wrap all print() statements in #if DEBUG (F-05)
Short-Term (1–2 Weeks)
Move EventStorage off @MainActor to a database actor (F-06)
Fix OfflineQueue double-increment (F-07)
Remove dead remainingMinutes property (F-08)
Add WAL mode to SQLite (F-13)
Update constants.json with finalizing phase (F-10)
Add CI gate requiring DOSETAP_CERT_PINS for release builds (F-04)
Medium-Term (Quarter)
Split ContentView.swift into focused view files
Add UI tests — at minimum, critical paths (dose tap, check-in, export)
Add SessionRepository integration tests back to CI (requires xcodebuild fix)
Implement secret loading from Keychain/env (F-11)
Add duplicate dose tap guard (F-12)
G) Optional Patch Plan
Commit 1: Fix build — TimePickerSheetRow (F-02)
Create ios/DoseTap/Views/TimePickerSheetRow.swift
Files: 1 new
Commit 2: Fix build — MorningCheckInViewV2 reference (F-03)
Update ios/DoseTap/FullApp/TonightView.swift:49 to use MorningCheckInView
Files: 1 modified
Commit 3: Fix build — SleepStageTimeline (F-01)
Restore missing properties in LiveSleepTimelineView or complete the refactoring
Files: 1 modified
Commit 4: Privacy — Guard print statements (F-05)
Wrap 67 print() calls in #if DEBUG
Files: EventStorage.swift, SessionRepository.swift
Commit 5: Security — Fail hard on missing pins (F-04)
Replace assertionFailure with compile-time check or fatalError
Files: DoseTapCore.swift
Commit 6: Core logic — OfflineQueue fix (F-07) + dead code removal (F-08, F-09)
Remove double increment, remove remainingMinutes, fix dead ternary
Files: OfflineQueue.swift, DoseWindowState.swift, SessionKey.swift
Commit 7: Docs — Update constants.json (F-10)
Add finalizing phase, bump version, update timestamp
Files: constants.json
H) Open Questions / Assumptions
Is the massive uncommitted diff intentional? It appears to be an in-progress consolidation of V2 → V1 views, but the breakage suggests it's incomplete. Clarify whether this should be committed, stashed, or reverted.

Are real certificate pins available? The DOSETAP_CERT_PINS infrastructure exists but no pins are set. If the API server is live, the actual SPKI pins should be generated (generate_cert_pins.sh exists) and deployed.

Is DoseTapCore.apiBaseURL correct? Debug builds point to https://api-dev.dosetap.com, release to https://api.dosetap.com. Are these servers operational? If not, all API calls fail silently (caught by OfflineQueue).

What happened to plannerSessionKey? It was removed in the uncommitted diff from SessionRepository but the CHANGELOG and SSOT reference it. Is this intentional deprecation or accidental deletion?

25 SessionRepository tests are blocked. These tests exist and appear well-written (SessionRepositoryTests.swift, 576 lines, 25 test methods). Once F-01 is fixed, they should be run and validated.

No cloud sync exists. The SSOT correctly documents this, but app uninstall destroys all data. Is this acceptable for a medical logging app? At minimum, CSV export should be periodically prompted.

Completed (8/8) Compile findings report

Summary: 6 P0/P1 findings, 8 P2/P3 findings. The iOS app target is unbuildable due to 3 independent P0 issues (incomplete refactoring, missing view component, dangling V2 reference). The SwiftPM core is healthy (296/296 tests pass). The most urgent action is to stabilize the uncommitted working tree — either complete the refactoring or revert it — to restore buildability.