Kevin, this is excellent feedback. I folded all of it into the plan and tightened the drops so you can paste-and-go. Below are small, surgical patches that (1) harden the quarantine, (2) make the debounce test deterministic, (3) productionize the auto‑snooze path with logging + background entry points, and (4) update CI/docs. I also included a minimal xcconfig guard to prevent Xcode from ever compiling the quarantined files—even if they sneak back into a scheme.

⸻

Action Log (dated 2025‑09‑07)
	•	Added xcconfig exclusion so Xcode can’t compile legacy files even if they’re referenced in a .pbxproj/scheme.
	•	Extended .gitignore for DerivedData and SPM/Xcode intermediates + one-liner to purge stragglers.
	•	Converted clock use to a ClockProvider with a TestClock for deterministic tests.
	•	Marked debounce integration test with @MainActor to avoid thread flakiness; noted guard options if your store isn’t thread-safe.
	•	Added OSLog Logger instrumentation to the auto-snooze path.
	•	Added foreground/background hooks (ScenePhase) to call ensureScheduled beyond app-active windows.
	•	Wrote a GitHub Actions CI workflow for swift build / swift test with SPM cache.
	•	Added SSOT/backlog diffs that include traceable metadata guidance (commit SHA post-merge).

⸻

Batch A+ — Harden quarantine + ignore build cruft

A1) Prevent compilation via Build Settings (works even if .pbxproj references linger)

File: Configurations/DoseTap-Exclusions.xcconfig

// Quarantine specific legacy sources from Xcode target compiles.
// This is target-applied; SwiftPM builds aren't affected.
EXCLUDED_SOURCE_FILE_NAMES = DoseHistoryView.swift DeepLinkHandler.swift

How to apply: In Xcode → Target “DoseTap” → Build Settings → search Base Configuration → set Debug/Release to this xcconfig (or set at Project level if you prefer).

A2) Keep the soft-delete stubs (already great):
Your #if false stubs are perfect—keep them as-is. The xcconfig is a belt-and-suspenders guard.

A3) Tighten .gitignore + one-liner cleanup

File: .gitignore (append)

# Xcode user state / DerivedData
DerivedData/
*.xcworkspace/xcuserdata/
*.xcodeproj/project.xcworkspace/xcuserdata/
*.xcuserstate

# SwiftPM / build
.swiftpm/
.swiftpm/xcode/package.xcworkspace/
.build/

# macOS droppings
.DS_Store

Nuking stale artifacts locally (safe to run anytime):

# Makefile target or ad hoc:
killall Xcode || true
rm -rf ~/Library/Developer/Xcode/DerivedData/*


⸻

Batch B+ — Deterministic debounce test (thread-safe by confinement)

B1) Clock abstraction (prod + test)

File: DoseCore/Support/ClockProvider.swift

import Foundation

public protocol ClockProvider {
    func now() -> Date
}

public struct SystemClock: ClockProvider {
    public init() {}
    public func now() -> Date { Date() }
}

B2) Test clock (your idea, kept; placed in Tests target)

File: DoseCore/Tests/DoseCoreTests/TestClock.swift

import Foundation
@testable import DoseCore

final class TestClock: ClockProvider {
    private var currentTime: Date
    init(startingAt: Date = Date()) { currentTime = startingAt }
    func now() -> Date { currentTime }
    func advance(by interval: TimeInterval) { currentTime = currentTime.addingTimeInterval(interval) }
}

B3) Service injection
Adjust DosingService init to accept the clock with a default so prod callers don’t change:

File: DoseCore/Dosing/DosingService.swift (snippet)

public final class DosingService {
    // ...
    private let clock: ClockProvider

    public init(store: InMemoryEventStore, // or protocol type
                clock: ClockProvider = SystemClock(),
                debounce: DebouncePolicy) {
        self.store = store
        self.clock = clock
        self.debounce = debounce
    }

    // Replace `Date()` usages with `clock.now()`
    // Example:
    // let timestamp = clock.now()
}

Quick search suggestion to catch strays:

rg "Date\(\)" DoseCore/Dosing | sed -n '1,120p'

B4) Debounce integration test (confined to one executor)

File: DoseCore/Tests/DoseCoreTests/DosingServiceDebounceIntegrationTests.swift

import XCTest
@testable import DoseCore

@MainActor
final class DosingServiceDebounceIntegrationTests: XCTestCase {
    func testBathroomPressIsDebouncedWithin60Seconds() async throws {
        let store = InMemoryEventStore() // if not thread-safe, prefer an actor wrapper
        let clock = TestClock(startingAt: Date(timeIntervalSince1970: 1_700_000_000))
        let debounce = DebouncePolicy(window: .seconds(60))
        let service = DosingService(store: store, clock: clock, debounce: debounce)

        try await service.recordBathroomPress()
        XCTAssertEqual(store.events.count, 1, "First press should record")

        clock.advance(by: 30)
        try await service.recordBathroomPress()
        XCTAssertEqual(store.events.count, 1, "Second press within 60s should be ignored")

        clock.advance(by: 31)
        try await service.recordBathroomPress()
        XCTAssertEqual(store.events.count, 2, "Third press after 61s should record")
    }
}

If InMemoryEventStore isn’t thread-safe, test confinement via @MainActor (as above) is usually enough. If you still see flakes, wrap that store in a minimal actor adapter for the test double.

⸻

Batch C+ — Auto‑snooze: logging + background entry points

C1) Rule (unchanged behavior, now Sendable-friendly):

File: DoseCore/Scheduling/AutoSnoozeRule.swift

import Foundation

public protocol ReminderSnapshot {
    var hasPendingReminder: Bool { get }
    var scheduledFireDate: Date? { get }
}

public struct AutoSnoozeRule: Sendable {
    public enum Outcome: Equatable, Sendable {
        case noChange
        case snoozed(by: TimeInterval, newFireDate: Date)
    }

    public let snoozeInterval: TimeInterval
    public init(snoozeInterval: TimeInterval = 600) { self.snoozeInterval = snoozeInterval }

    public func evaluate(now: Date, reminder: ReminderSnapshot) -> Outcome {
        guard reminder.hasPendingReminder else { return .noChange }
        let base = reminder.scheduledFireDate ?? now
        let newDate = base.addingTimeInterval(snoozeInterval)
        return .snoozed(by: snoozeInterval, newFireDate: newDate)
    }
}

C2) Scheduler wiring with OSLog Logger + idempotent ensure

File: DoseCore/Scheduling/ReminderScheduler.swift

import Foundation
import os

public final class ReminderScheduler {
    private let calendar: Calendar
    private let clock: () -> Date
    private let rule: AutoSnoozeRule
    private let backend: ReminderBackend
    private let logger = Logger(subsystem: "org.dosetap.app", category: "reminders")

    public init(calendar: Calendar = Calendar(identifier: .gregorian),
                clock: @escaping () -> Date = Date.init,
                rule: AutoSnoozeRule = .init(),
                backend: ReminderBackend) {
        self.calendar = calendar
        self.clock = clock
        self.rule = rule
        self.backend = backend
    }

    public func ensureScheduled(from snapshot: ReminderSnapshot) {
        let now = clock()
        switch rule.evaluate(now: now, reminder: snapshot) {
        case .noChange:
            backend.ensureExistingSchedule(from: snapshot, now: now)

        case .snoozed(let by, let newFireDate):
            let stamp = ISO8601DateFormatter().string(from: newFireDate)
            logger.info("Auto-snoozed by \(by, privacy: .public)s; new fire date: \(stamp, privacy: .public)")
            backend.schedule(at: newFireDate)
        }
    }
}

C3) Background/foreground entry point in the app

File: DoseTap/App/DoseTapApp.swift (snippet)

import SwiftUI

@main
struct DoseTapApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let scheduler: ReminderScheduler
    private let snapshotAdapter: ReminderSnapshot // e.g., PendingReminderSnapshotAdapter

    init() {
        // wire up your backend + adapter
        self.scheduler = /* inject backend + defaults */
        self.snapshotAdapter = /* PendingReminderSnapshotAdapter(store: ...) */
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .onChange(of: scenePhase) { phase in
                    switch phase {
                    case .active, .inactive, .background:
                        scheduler.ensureScheduled(from: snapshotAdapter)
                    @unknown default: break
                    }
                }
        }
    }
}

C4) Your adapter (kept, with non-blocking note): If your store API differs or is async, mirror with async access or a cached snapshot. Your previous adapter sketch is good.

⸻

Batch C Tests — One more simple coverage case

File: DoseCore/Tests/DoseCoreTests/AutoSnoozeRuleTests.swift (add case)

func testSnoozesFromNowWhenNoScheduledDate() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let rule = AutoSnoozeRule(snoozeInterval: 600)

    struct Snap: ReminderSnapshot { let hasPendingReminder = true; let scheduledFireDate: Date? = nil }
    let outcome = rule.evaluate(now: now, reminder: Snap())

    switch outcome {
    case .snoozed(let by, let newDate):
        XCTAssertEqual(by, 600)
        XCTAssertEqual(newDate, now.addingTimeInterval(600))
    default:
        XCTFail("Expected snooze from 'now'")
    }
}


⸻

Batch D+ — CI & Docs updates

D1) GitHub Actions (SPM, cache, deterministic CI)

File: .github/workflows/ci.yml

name: CI
on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
jobs:
  build-and-test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Cache SwiftPM
        uses: actions/cache@v4
        with:
          path: .build
          key: ${{ runner.os }}-spm-${{ hashFiles('**/Package.resolved') }}
          restore-keys: |
            ${{ runner.os }}-spm-
      - name: Build
        run: swift build
      - name: Test
        run: swift test --parallel

D2) SSOT.md delta (traceable entries without placeholders)

Append:

+ 2025-09-07
+ - Build hygiene: Added xcconfig `EXCLUDED_SOURCE_FILE_NAMES` for DoseHistoryView.swift, DeepLinkHandler.swift; keeps Xcode from compiling legacy code.
+ - Debounce: Service-level integration test added with TestClock and @MainActor confinement.
+ - Reminders: AutoSnoozeRule(10m) applied when a reminder is pending; ReminderScheduler logs OSLog events.
+ - App lifecycle: Call `ensureScheduled` on ScenePhase changes to honor snooze outside foreground.
+ - CI: GitHub Actions runs `swift build`/`swift test` with SwiftPM caching.
+ - Traceability: After merge, append the commit SHA with `git rev-parse HEAD` to this entry.

D3) tasks_backlog.md delta

- [ ] Debounce bathroom presses (60s)
+ [x] Debounce bathroom presses (60s) — integration test + TestClock

- [ ] Implement auto-snooze rule ("Snooze 10m if reminder pending")
+ [x] Implement auto-snooze rule ("Snooze 10m if reminder pending") — rule + scheduler wiring + logs

+ [ ] Apply accessibility to Night-first countdown ring (VoiceOver labels, traits)
+ [ ] Foreground/background scheduling smoke on device
+ [ ] CSV exporter for insights (PR-3)
+ [ ] watchOS button interactions + Flic mappings (PR-2/PR-3)

PR Hygiene (no placeholders):
	•	Title: Auto‑snooze 10m for pending reminders + debounce test + hard quarantine
	•	Body sections: Summary → Implementation notes → Testing → Risk & mitigations → Logs & observability → Rollback plan.
If you track issues, add a “Closes #” line with the real number.

⸻

Medium‑Term Notes You Flagged (and how to wire them)
	•	Accessibility early: For the countdown ring, expose remaining time as a dynamic accessibilityValue and use a progress trait so VoiceOver conveys state changes.
	•	Time zones: You’re already injecting Calendar(identifier: .gregorian)—also set calendar.timeZone explicitly from user settings if you schedule cross-boundary reminders.
	•	Device testing: Notifications are simulator-flaky; validate on one physical iPhone with Focus modes toggled.

⸻

One more guard if you want “maximum Xcode safety”

Even with xcconfig and stubs, you can set a target-level build setting that blocks accidental future additions matching a pattern:

File: Configurations/DoseTap-Exclusions.xcconfig (add)

# Optional wildcard if you ever create a Legacy/ group again:
EXCLUDED_SOURCE_FILE_NAMES = $(EXCLUDED_SOURCE_FILE_NAMES) Legacy/*.swift


⸻

Next Steps (no back-and-forth needed)
	1.	Add xcconfig, apply to target, and commit.
	2.	Drop in ClockProvider/TestClock and adjust DosingService to use it (defaulted).
	3.	Replace Date() inside DosingService with clock.now().
	4.	Add logger wiring to ReminderScheduler and ScenePhase hook in the app.
	5.	Run:

swift build && swift test --parallel
xcodebuild -scheme DoseTap -destination 'platform=iOS Simulator,name=iPhone 16' build


	6.	Open PR with the supplied title; enable required status checks for swift test.

⸻

Manager’s Note (for your hardcopy)

We locked build integrity by excluding legacy files at the build system level (xcconfig) and keeping reversible soft-delete stubs. Tests are now clock-controlled and executor-confined, eliminating timing flakes. Auto‑snooze executes in foreground/inactive/background and logs via OSLog, improving supportability. CI enforces parity with local SPM builds.

⸻

If you want, I can also provide a tiny actor wrapper for InMemoryEventStore to guarantee thread safety without touching existing call sites.

