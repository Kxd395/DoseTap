# 10 - Second Pass Gaps and Recommendations

Date: 2026-05-25
Scope: static second pass over source, CI, build files, and handoff package.
Validation: no build, tests, secret scan, or device runtime validation was run.

## Executive Finding

The first handoff captured the major rebuild themes, but it underweighted three concrete engineering risks:

1. The app still has multiple dose mutation paths that do not actually use the canonical `DoseRegistrationPolicy`.
2. Several "future" surfaces are compiled into the main app or visible from dashboard paths, creating product-boundary confusion.
3. The codebase needs dependency-boundary cleanup before a rebuild; otherwise a new storage/sync layer will inherit global singletons, N+1 dashboard queries, and oversized view/service files.

## Missed or Underweighted Improvements

### 1. Make `DoseRegistrationPolicy` the only decision engine

Evidence:

- `ios/Core/DoseRegistrationPolicy.swift` declares that all entry surfaces must call the same policy.
- `ios/DoseTap/DoseActionCoordinator.swift` duplicates phase logic internally instead of delegating to `DoseRegistrationPolicy`.
- `ios/DoseTap/URLRouter.swift` still calls `core.takeDose()` / `core.takeDose(lateOverride:)` directly.
- `ios/DoseTap/Views/TonightView.swift` has legacy early and extra-dose flows that call `core.takeDose(...)` and `sessionRepo.saveDose2(...)` directly.
- `ios/DoseTap/FlicButtonService.swift` still calls `sessionRepository.saveDose1/saveDose2/skipDose2` directly in several paths.

Required improvement:

- Move all dose registration decisions into `DoseRegistrationPolicy`.
- Make `DoseActionCoordinator` translate policy decisions into UI actions and persistence calls, not reimplement rules.
- Remove coordinator-optional fallback behavior from production views.
- Add a CI guard that rejects direct dose mutation from views, routers, Flic, widgets, watch, or intents.

Acceptance:

- The only allowed files to call `SessionRepository.setDose*`, `saveDose*`, `skipDose2`, or `DoseTapCore.takeDose` are the canonical use-case/coordinator layer and tests.
- URLRouter, Flic, Tonight, History, Siri, Watch, and Widget code have parity tests for early, active, near-close, closed, after-skip, completed, and extra-dose states.

### 2. Split mutation use cases from `DoseTapCore`

Current problem:

- `DoseTapCore` is both a state computer and a mutating orchestrator.
- `URLRouter`, `DoseActionCoordinator`, and views call it directly.
- Core also contains API queue actions (`takeDose`, `skipDose`) that look backend-oriented but the product remains local-first.

Recommended target:

- `DoseStateReader`: read-only state and window context.
- `DoseMutationUseCase`: dose1, dose2, snooze, skip, extra-dose, undo.
- `DoseRegistrationPolicy`: pure decisions.
- `SessionRepository`: persistence contract, not UI-facing singleton.

This makes storage migration, watch actions, widgets, and deep links safer because every surface has one interaction model.

### 3. Treat widget source as mis-targeted until proven otherwise

Evidence:

- `ios/DoseTap/Widget/DoseTapWidgets.swift` says it should live in a WidgetKit extension target.
- `ios/DoseTap.xcodeproj/project.pbxproj` includes `DoseTapWidgets.swift in Sources` for the main app source phase.
- The widget `@main` entry point is commented out.

Risk:

- The code may compile as inert app code rather than a real widget extension.
- App Group state may be assumed in product docs but not actually provisioned or tested as a widget target.

Required improvement:

- Create a real Widget Extension target.
- Move widget-only files into that target.
- Keep only shared DTO/state code in a shared module.
- Add App Group entitlement validation and stale-state tests.

### 4. Separate CloudKit staging from production dashboard code

Evidence:

- `DeferredCloudKitSyncService.swift` is under `ios/DoseTap/Legacy/` but compiled by the app project.
- `DashboardTabView` and `DashboardAnalyticsModel` instantiate `DeferredCloudKitSyncService.shared`.
- Build settings include local and cloud entitlement variants with `DoseTapCloudSyncEnabled` toggles.

Risk:

- A deferred/staging sync feature appears in a primary product surface.
- Shipping-local and staging-cloud behavior are too easy to confuse.

Required improvement:

- Move CloudKit UI to a staging-only diagnostics screen or compile-time product module.
- Dashboard should show "Local data" by default, not operational CloudKit controls.
- Keep CloudKit tombstones and schema code only if the selected storage/sync architecture requires them.

### 5. Fix tracked hygiene artifacts and `.gitignore` debt

Evidence:

- `git ls-files` shows `.cache_ggshield` is tracked.
- `.gitignore` contains many repeated `.cache_ggshield` entries.
- The root `.gitignore` still does not visibly cover all common signing/secret artifacts such as `*.p12`, `*.pem`, `*.key`, `.env*`, `*.mobileprovision`, `*.xcarchive`, `*.dSYM`, and `*.ipa`.

Required improvement:

- Remove `.cache_ggshield` from git tracking.
- Collapse repeated `.gitignore` entries.
- Add explicit Apple signing, environment, and archive artifact patterns.
- Add a CI guard for tracked secret/signing artifacts.

### 6. Resolve `Secrets.swift` build ergonomics

Evidence:

- `ios/DoseTap/Secrets.swift` is gitignored but included in Xcode project sources.
- CI creates it by copying `Secrets.template.swift`.
- A missing local file can block Xcode builds for new developers if setup was skipped.

Recommended improvement:

- Prefer `Secrets.generated.swift` created by setup/CI and ignored by git.
- Keep `Secrets.template.swift` checked in.
- Add `make setup` or `tools/setup_local.sh` that creates the generated file idempotently.
- Document the local secret lifecycle in README and the handoff.

### 7. Remove or quarantine nested `ios/DoseTap/Package.swift`

Evidence:

- Root `Package.swift` is Swift tools 5.9 and defines `DoseCore`.
- `ios/DoseTap/Package.swift` is Swift tools 6.1 and defines a broad package rooted at the app folder.
- Historical audit already flagged this as vestigial.

Risk:

- Developers can open or build the wrong package.
- Tooling may infer different platform requirements and include unintended files.

Recommendation:

- Delete or archive the nested package unless there is a documented, tested use.
- If kept, rename and document its purpose explicitly.

### 8. Convert dashboard refresh from N+1 queries to aggregate queries

Evidence:

- `DashboardAnalyticsRefresh.performRefresh(days:)` loops up to 730 day keys.
- For each key it calls multiple repository methods: dose log, dose events, sleep events, session ID, morning check-in, pre-sleep log, nap summary.

Risk:

- Dashboard performance scales poorly with longer history.
- Storage migration may preserve this shape and make sync/cache invalidation harder.

Recommended improvement:

- Build a `NightlyAggregateRepository`.
- Fetch range data in batched queries.
- Cache deterministic nightly aggregates by `session_id` / `updated_at`.
- Invalidate only changed sessions.

Target complexity:

- Current shape is effectively O(days * query_count) repository round trips.
- Target should be O(range query count + changed sessions), with bounded per-session aggregation.

### 9. Refactor oversized files before feature expansion

Largest app files from static line count:

- `SettingsActions.swift`: 1,645 lines.
- `SessionRepository.swift`: 1,249 lines.
- `MorningCheckInSections.swift`: 1,132 lines.
- `MorningCheckInViewModel.swift`: 950 lines.
- `SessionSupportViews.swift`: 852 lines.
- `DeferredCloudKitSyncService.swift`: 789 lines.
- `StorageModels.swift`: 766 lines.
- `DosingAmountSchema.swift`: 762 lines.
- `FlicButtonService.swift`: 734 lines.
- `TonightView.swift`: 683 lines.

Recommended cuts:

- Settings: split export, import/delete, diagnostics, integrations, and account/privacy actions.
- Session repository: split command use cases from read models and migration/sync helpers.
- Morning check-in: split field groups, mapping, validation, and persistence adapter.
- Flic: split hardware adapter, action policy adapter, notification confirmation, and settings.
- Dashboard: keep cards small; move aggregation into model/repository layer.

### 10. Make dependency injection real, not partial

Evidence:

- `AppContainer` exists.
- Several app models still call singletons directly: `SessionRepository.shared`, `HealthKitService.shared`, `WHOOPService.shared`, `DeferredCloudKitSyncService.shared`, `UserSettingsManager.shared`.
- `InsightsCalculator` reads `SessionRepository.shared` directly.

Recommended interaction model:

- App root owns dependencies.
- Views receive view models.
- View models receive protocols.
- Domain services are pure or injected.
- Singletons are allowed only as app composition conveniences, not inside reusable logic.

This is the best way to interact with the codebase during rebuild because it makes behavior testable without HealthKit, WHOOP, CloudKit, App Group, or notifications.

## Best Codebase Shape for Rebuild

Recommended module layout:

```text
DoseDomain
  DoseRegistrationPolicy
  DoseWindowCalculator
  SessionKey
  NightScoreCalculator
  DoseEffectivenessCalculator
  Codable domain models

DosePersistence
  Repository protocols
  SQLite adapter
  Migration tools
  Aggregate read models

DoseIntegrations
  HealthKit adapter
  WHOOP adapter
  Notifications adapter
  Flic adapter
  Widget/shared-state adapter

DoseApp
  SwiftUI views
  View models
  Navigation
  Composition root

DoseDiagnostics
  Structured logs
  Session traces
  Redaction
  Support bundle
```

If creating multiple Swift packages is too much for the next sprint, still enforce the same boundaries by folders, protocols, and CI import guards.

## Best Way to Interact With State

Use this sequence for every state-changing feature:

1. Build a `Command` object with source, timestamp, correlation ID, and user intent.
2. Evaluate the command with `DoseRegistrationPolicy`.
3. If confirmation is required, return a typed confirmation requirement to the surface.
4. If allowed, call one mutation use case.
5. Persist transactionally through one repository.
6. Emit a diagnostic event.
7. Schedule/cancel notifications.
8. Update derived widget/watch/dashboard state.
9. Register undo if eligible.

Do not let views, routers, widgets, watch code, or hardware integrations directly mutate repository state.

## New Backlog Items to Add

| Priority | Item | Why |
| --- | --- | --- |
| P0 | Enforce one dose mutation path | Prevents clinical state divergence across entry channels. |
| P0 | Remove direct dose writes from URLRouter/Tonight/Flic fallbacks | These are bypass paths around the stated policy. |
| P1 | Real widget extension target | Current widget source appears compiled into the app, not activated as a target. |
| P1 | Dashboard aggregate repository | Required before expanding dashboards and storage migration. |
| P1 | CloudKit staging isolation | Prevents deferred sync from leaking into shipping product UX. |
| P1 | Setup automation for generated secrets | Reduces clone-to-build friction. |
| P2 | Remove nested app `Package.swift` | Avoids wrong build entry point and toolchain drift. |
| P2 | `.gitignore` and tracked hygiene cleanup | Prevents repeated secret/signing artifact problems. |
| P2 | Split largest files before adding features | Reduces blast radius and review risk. |
| P2 | CI import/path guards | Keeps architecture from drifting after cleanup. |

## Documentation Updates Needed

- Update `README.md` to point to the correct build entry point and setup command.
- Update `docs/FEATURE_TRIAGE.md` from current HEAD instead of older status.
- Update `docs/architecture/11-known-issues.md`; it currently contains contradictory WHOOP status statements.
- Update `docs/CLOUDKIT_GO_LIVE_CHECKLIST.md` after deciding whether CloudKit remains staging-only.
- Add a `docs/rebuild/CURRENT_STATE_AUDIT.md` before code implementation starts.

## Second-Pass Limitations

- Static source inspection only.
- No build/test execution.
- No simulator launch.
- No App Group, widget, watch, HealthKit, WHOOP, Flic, notification, or CloudKit runtime validation.
- No fresh full secret scan or git-history scan.
