# Dashboard provider-access invalidation

Status: Implementation candidate; integration and signed-device acceptance recorded separately
Date: 2026-09-30
Tracker: DOSETAP-45
Baseline: main `2a6e6db934a3ae162bebdbf36ade6c3ad2dd59ae`
Candidate phone version: 0.4.19 (88); separate iPad Dashboard remains 0.1.0 (10)

## Problem and correction

The dashboard could retain provider summaries after an integration was disabled and publish an older asynchronous result after an off/on or disconnect/reconnect cycle. Before adding failed-refresh snapshot retention, this slice establishes an explicit access invalidation boundary. The [access contract](../SSOT/contracts/dashboard-provider-access.md) defines the scope.

A thread-safe, provider-specific in-memory revision advances on preference changes, known HealthKit access loss, WHOOP disconnect, account identity change and credential replacement. The monitor has no singleton dependencies and releases its lock before notifying observers. Replacement credentials advance the revision before assignment; ordinary token refresh is unchanged. Production integration preference writes use the monitored settings setter. WHOOP startup normalization runs in a main-actor task after construction and skips equal values; this avoids publishing settings during SwiftUI rendering.

The model removes affected provider summaries and query metadata on the main actor, retains local records and the other provider, and rejects obsolete results after every suspension and before publication. Delayed notifications cannot erase results already published under the current revision. Cancelling an invalidated generation settles loading. No provider measurements or credentials are persisted by the monitor.

## Regression evidence

The original Apple Health-disable test failed because displayed summaries remained. Independent review then identified a snooze-only preservation edge; the added test reproduced five retained rows instead of six before correction. Final coverage includes preference no-ops, known authorization loss, both provider disable paths, disconnected WHOOP, suspended authorization/history requests, off/on epochs, background notifications, delayed notifications, and local diary/unreadable/event/nap/snooze/other-provider preservation.

- Full core suite: 879 XCTest and 43 Swift Testing tests passed.
- Targeted iPhone simulator suite: 10 access-invalidation, 26 dashboard audit and 28 HealthKit tests passed (64 total).
- Generic iOS Simulator build passed. Three native dashboard journeys passed: six-month coverage, largest-text range menu, and Night Mode chart selection/legends.
- Final launch control passed after removing the new SwiftUI startup-publication warning; its result bundle completed normally.
- App/staging Debug/Release version checks, Plane workflow, SSOT/docs, architecture, dose-write and whitespace checks passed.

Evidence is retained in `.build/provider-access-evidence/` in the provider-access worktree. The failed test runners stalled after reporting their assertion failures and were terminated by their verified exact process IDs; final passing tests produced a successful result bundle.

## Remaining scope

This change does not retain stale provider snapshots, classify transient HealthKit authorization-preparation errors, extend provider history, or reconcile provider revisions/deletions. Known true-to-false HealthKit access changes conservatively invalidate; Apple may still conceal read revocation as an empty success. WHOOP production enablement and real-account validation remain open. The owner deferred physical iPad launch; do not retry it as part of this phone change. Owner/provider, VoiceOver, privacy/security and release acceptance remain under DOSETAP-45.
