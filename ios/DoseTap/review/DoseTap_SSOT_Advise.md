This SSOT v1.0 is a strong, comprehensive foundation—it's well-structured, authoritative, and aligns closely with the app's goals of reliability and user safety. It effectively consolidates prior elements (e.g., auto-snooze, debounce, UI states) into a single, actionable reference, which will streamline PRs and reduce drift. The inclusion of test matrices, risks, and PR templates is particularly smart for maintainability. Below, I'll provide detailed advice organized by section: refinements for clarity/completeness, potential gaps/risks, implementation tips, and prioritization tweaks. I'll flag anything that could conflict with prior stubs (e.g., from Batch C) or introduce tech debt. Aim to keep this living—version it in git with diffs for audits.

### General Advice
- **Strengths:** The authoritative tables (e.g., UI States, Risks) and schemas (CSV v1) make this SSOT truly "single"—easy to reference in code/comments. Linking tests in PRs enforces coverage. The workflow (SSOT-First, CI gate) is a great guardrail.
- **Improvements:** Add a "Changelog" section at the top for quick scans (e.g., "v1.0: Added CSV schema, destructive policy; consolidated UI states"). Embed hyperlinks to code files (e.g., `[DoseWindowConfig.swift#L12]`) if this lives in a markdown viewer like GitHub. Consider rendering as a PDF/wiki for non-dev stakeholders.
- **Consistency Check:** Aligns well with prior implementations (e.g., AutoSnoozeRule matches the 10m interval; debounce at 60s). No major conflicts, but update prior test stubs (e.g., `DosingServiceDebounceIntegrationTests`) to reference new error codes like `429_RATE_LIMIT`.
- **Tech Debt Flag:** In-memory store is called out as test-only—good call to migrate ASAP. Prioritize this in PR-2 to avoid data loss in betas.
- **Legal/Compliance:** Expand the disclaimer with specifics (e.g., "Not FDA-approved; no liability for missed doses"). For critical alerts entitlement, prep App Review docs now (e.g., medical justification letter).

### Section-Specific Advice
#### 0) SSOT-First Workflow
- **Refinements:** Make `tools/ssot_check.sh` script explicit—e.g., it could diff SSOT files against code (parse config values, state enums) and fail if mismatched. Add a step: "If error codes change, update API docs and mapper tests."
- **Gaps:** No mention of how to handle SSOT conflicts in merges—suggest "Resolve via discussion; prefer SSOT as truth."
- **Tips:** Integrate with GitHub Actions for auto-PR comments linking diffs.

#### 1) Product Overview
- **Refinements:** Clarify "XYWAV-like" with a footnote: "E.g., regimens requiring 2.5-4 hour intervals post-bedtime." Add metrics for success (e.g., "Goal: <1% missed windows due to app factors").
- **Gaps:** Monetization is "initial"—flesh out Pro features (e.g., "Themes: custom ring colors; Analytics: adherence reports"). For privacy, specify "No telemetry without opt-in."
- **Risks:** If Pro unlocks core features, it could alienate users—keep essentials free.
- **Tips:** In onboarding, make disclaimer tappable for full text; use it to gate first use.

#### 2) Architecture
- **Refinements:** Great module split. Add a diagram (e.g., PlantUML in markdown) showing flow: UI → DosingService → EventStore/ReminderScheduler.
- **Gaps:** No offline queue details—define semantics (e.g., "Retry on foreground; max 5 events; drop on clear"). For errors, add a user-facing mapper (e.g., `422_WINDOW_EXCEEDED` → "Dose window missed—log manually?").
- **Tips:** For actors, ensure all state access is isolated (e.g., no shared mutable vars). Inject `now()` everywhere—extend to `Calendar` for timezone tests.
- **Implementation:** If migrating to Core Data, define entities now: `DoseEvent` with attributes matching CSV schema. Use `NSBatchDeleteRequest` for atomic clears.

#### 3) Configuration
- **Refinements:** Make `maxSnoozes` configurable per-user (Settings toggle), with default 3. Add `undoWindowSec=15` here for consistency.
- **Gaps:** No handling for dynamic configs (e.g., clinician overrides)—plan for a "Custom Mode" in Pro.
- **Tips:** Store as a struct in DoseCore; serialize to UserDefaults for persistence. Test edges: min=150 exactly enables CTA; <15m disables snooze UI.
- **Risks:** UTC internal but local UI—add tests for DST transitions (e.g., snooze across 2am change).

#### 4) UI States & Primary Actions
- **Refinements:** Excellent table—add columns for "Haptics" (e.g., success for Take, error for Expired) and "Notification Trigger" (e.g., at active start).
- **Gaps:** No "Snoozed" sub-state—add row for post-snooze (e.g., "Snoozed (X min added)" with updated ring). Clarify undo: "Rolls back event, reschedules if needed."
- **Tips:** Implement state as an enum in DoseCore (`enum DoseWindowState: Codable { case waiting, preActive, active, nearEnd, expired }`). Bind ring to SwiftUI `@Published` from service.
- **Accessibility:** Ensure ring is ARIA-like: `accessibilityLabel: "Countdown: \(formattedTime)"`.

#### 5) Feature Set
- **Overall:** Status tags are helpful; link to PRs/tests (e.g., "[Implemented: see PR-1]").
- **5.1 Dosing Event Tracking:** Add `source` to events (as in CSV)—track for analytics (e.g., % from watch). Test: Simulate offline press → queue → sync on online.
- **5.2 Reminder Scheduling:** Clarify "user toggle" only affects manual snooze—good. Add: "Auto-snooze logs as `system` source." Test: Max snoozes hit → error `422_SNOOZE_LIMIT`.
- **5.3 User Interface:** Specify ring animation (e.g., smooth progress; color shift near-end: green → yellow → red). Haptics: Use `UIImpactFeedbackGenerator`.
- **5.4 History & Export:** Partial is accurate—add "Search by date/range; filter by type." For notes, limit to 500 chars; sanitize for CSV.
- **5.5 Integrations:** Shells are a good start—stub auth flows with mocks. For Health/WHOOP, emphasize "Read-only; no write-back."
- **5.6 Build & Hygiene:** Solid; add "Dependency checks: No UIKit in DoseCore."

#### 6) Screens
- **Refinements:** Add wireframes (e.g., ASCII or links to Figma). For all: Mandate dark mode support; min iOS 17.
- **6.1 Splash/Onboarding:** Make slides skippable; track completion for analytics.
- **6.2 Main:** Add subtle background (e.g., starry night gradient). Pull-to-refresh: Haptic on success.
- **6.3 History:** Pagination for >100 events; export shares via UIActivityViewController.
- **6.4 Settings:** Group sections (e.g., Data, Notifications, Integrations). For Clear: Use red destructive button; post-clear, reset to onboarding?
- **Gaps:** Missing Debug Screen (e.g., force states, mock time) for devs—hide behind tap gesture.
- **Tips:** Use NavigationStack for tabs; bind Settings to @AppStorage.

#### 7) CSV Schema
- **Refinements:** Perfect—add example row in docs. For `note`, escape quotes/commas.
- **Gaps:** No version field—add `schema_version=1` to header for future-proofing.
- **Tips:** In exporter, use `CSVEncoder` from swift-csv lib (or manual); sort by `occurred_at_utc`. Test: Empty store → header only; undo event → includes `undo` type.

#### 8) Destructive Action Policy
- **Refinements:** Two-step is wise—make first alert: "This will delete all history and reset schedules. Continue?" Second: Exact label provided.
- **Gaps:** No backup prompt before clear—add "Export first?" with direct link to exporter.
- **Tips:** Implement as async func in DataStorageService; throw on failure. Post-clear: Broadcast notification to refresh UI.

#### 9) Persistence, Backup & Background
- **Refinements:** Immediate migration is critical—prioritize over UI polish. For CloudKit: Use private DB; handle conflicts via last-write-wins.
- **Gaps:** No migration path from in-memory—plan a one-time import. For BGAppRefresh: Schedule every 30m; cap to overnight hours.
- **Tips:** Core Data setup: `DoseEvent` entity with indices on `occurred_at_utc`. Critical alerts: Justify as "life-impacting medication reminders" in submission.
- **Risks:** CloudKit sync could leak if not private—audit zones.

#### 10) Risks & Mitigations
- **Refinements:** Add likelihood (Low/Med/High). New risk: "Battery drain from BG tasks" → Mitigate: Optimize queries; user toggle.
- **Gaps:** "Time zone travel" → Mitigate: Detect changes, recalculate in local TZ.
- **Tips:** Tie to tests (e.g., Notifications disabled → warning UI test).

#### 11) Test & Acceptance Matrix
- **Refinements:** Link files (e.g., `DoseCoreTests/DoseWindowEdgeTests.swift`). Add UI tests: Snapshot ring in states; tap sequences.
- **Gaps:** No e2e: "Full flow: Schedule → Notify → Press → Undo → Export."
- **Tips:** Use XCUITest for Settings flows; mock notifications with UNUserNotificationCenter stubs.

#### 12) Names & Form Fields
- **Refinements:** Comprehensive—add UI strings (e.g., "Window Missed: Take anyway? (log as skipped)").
- **Gaps:** No localization keys—prefix with "doseTap." (e.g., "doseTap.settings.allowSnoozing").

#### 13) Backlog
- **Refinements:** Prioritized well. Tweak: Move Core Data to PR-2 (blocks export/history). Add estimates (e.g., PR-2: 5-7 days).
- **Gaps:** "A11y audit" in PR-2; "Beta testing plan" in PR-4.
- **Tips:** Break PR-2 into sub-PRs (e.g., 2a: UI, 2b: Undo).

#### 14) PR Template
- **Refinements:** Add "Screenshots: Before/after for UI changes."
- **Tips:** Enforce via GitHub template file.

### Next Steps & Prioritization
- **Immediate (Today):** Migrate to Core Data—drop in a basic entity/model, wire EventStore to it. Update tests to use persistent store doubles.
- **Short-Term (PR-2 Focus):** Implement states/table in code; add golden CSV tests. Run ssot_check.sh manually.
- **Medium-Term:** Submit for critical alerts entitlement; prototype BG tasks.
- **Overall Timeline:** If solo dev, aim for PR-2 merge in 1 week; beta in 3 weeks.
- **Metrics for v1.1:** Measure test coverage (>80% DoseCore); add user feedback loop in Settings.

This keeps the SSOT lean while addressing edges. If you share code snippets (e.g., for Core Data migration), I can provide drop-in patches!