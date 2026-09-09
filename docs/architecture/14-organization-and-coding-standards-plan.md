# Organization and coding-standards adoption plan

Status: Proposed staged work; not a claim that restructuring is implemented
Date: 2026-09-09
Planning evidence: DOSETAP-63
Existing implementation owners: DOSETAP-17, DOSETAP-19, DOSETAP-20, DOSETAP-22

## Recommendation

Keep the current SwiftPM core, iOS app and read-only Studio separation. Organize new and extracted code around clear responsibilities, then enforce those boundaries with tests and build checks. A standard-looking folder tree is not a substitute for correct persistence, timing or data interpretation.

Swift's [API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) prioritize clarity at the call site and consistent names. SwiftPM's [package description](https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html) supports explicit target paths and target dependencies. Those are useful foundations; neither requires a universal `src` folder or a package for every screen. This proposal does not claim medical-device, regulatory, security or release certification.

## Keep these existing decisions

- One medication action boundary: coordinator, pure policy, repository, transactional SQLite. No view or analytics component writes a second medication history.
- A UI-framework-free core is the target boundary, not a fully achieved baseline. `ios/Core/DoseTapCore.swift` conditionally imports SwiftUI, and `ios/Core/DiagnosticLogger.swift` conditionally imports UIKit and uses `UIDevice` for OS metadata. Reconcile these dependencies under DOSETAP-22 with characterization tests and app-side adapters where appropriate. Conditional imports do not establish platform independence. Retain the root `Package.swift` rather than rename its source root for appearance alone.
- `DoseTapStaging` remains distinct from the shipping local-first app. Keep non-shipping companion proposals outside shipping target membership.
- Absolute timestamps, stable session identity, injected clocks, explicit missingness and provenance remain contracts, not formatting preferences.
- Characterize behavior before extracting it. Update all references and target membership in the same independently buildable change.

## Where organization would help

| Area | Recommended responsibility | First useful cleanup |
| --- | --- | --- |
| App composition | Entry point, navigation, dependency wiring | Keep feature behavior out of the root view; document dependencies rather than introduce a new global service locator. |
| Feature UI | Tonight, Timeline, History, questionnaires, Dashboard, Settings | Extend existing feature folders. Move one coherent component only after a full reference and target-membership scan. Do not invent a ViewModel for every leaf view. |
| Domain | Timing policies, identities, calculations, typed results | Reuse DoseCore. Distinguish diary observations, estimates and derived summaries. Avoid duplicate math inside views. |
| Persistence | Transactions, migrations, projections, sync adapters | Continue existing storage extensions by responsibility. A cross-file extension is not a new architectural boundary if all state is still globally accessible. |
| External integrations | HealthKit/WHOOP reads, alarm delivery, staging sync | Define adapter inputs/results and failure states. Keep provider evidence separate from user-entered observations. |
| Exports and Studio | Shared versioned transport contracts, read-only analysis | Separate archive orchestration from row construction and provider enrichment without creating competing schemas. |
| Tests and tools | Deterministic fixtures, layer-specific tests, reproducible commands | Prefer in-memory stores and fixed clocks. Keep dedicated integration tests for persistence/restart and explicit serial tests where shared settings require it. |

## Adoption batches

### 0. Correctness and preservation first

Finish DOSETAP-63 retained-work review. Fix the source-reviewed Timeline observation/timing issue in DOSETAP-64 before extracting its presentation calculations. Signed-phone medication confirmation and restart gates remain independent priorities. Never archive unreviewed fixes just to reach a target branch count.

### 1. Reconcile the standards already present

Under DOSETAP-17/20, reconcile the constitution, current behavior, lint configuration and build ownership before adding more scaffolding. The constitution still contains older watch, CSV and product-scope language; changes to governance require the documented amendment process and owner review, not an agent silently relaxing it.

The current `.swiftlint.yml` has stale Core Data explanations and obsolete include/exclude paths. It configures some rules that it also disables, so its comments are not proof of enforcement. Discover the actual lint baseline, select and pin a compatible tool version, agree on useful rules, and enforce no new violations before attempting whole-repository formatting. Do not install a global formatter or rewrite thousands of lines in a bug-fix PR.

Define one primary owner per CI gate. Current doc lint appears in multiple workflows; keep required checks intact until branch-protection references and replacement coverage are verified. Do not remove jobs merely because their names look redundant.

### 2. Document boundaries and contributor commands

Under DOSETAP-22, keep `13-component-boundaries.md` as the existing decision and add only verified ownership updates. Provide a concise contributor guide linking existing `tools/dt-*`, SwiftPM, repository checks and release runbooks. The workstation's project standard proposes a common task interface; adapt it to an Apple app only after mapping current commands. No Docker, backend or directory relocation is needed merely for conformity.

Inventory each shipping source and test target before physical moves. Root SwiftPM uses explicit source lists; the app and UI-test targets use explicit Xcode entries. The unit-test target is different: `DoseTapTests` uses a `PBXFileSystemSynchronizedRootGroup` attached through `fileSystemSynchronizedGroups`, so its files do not need individual project entries. A membership checker must handle both mechanisms, including synchronized-group exceptions if introduced, then verify actual test discovery/execution. Do not flag synchronized unit tests as missing merely because no per-file project entry exists. Prefer this automated inventory over a hand-maintained source-count document.

### 3. Extract one responsibility at a time

Choose seams from current dependency and change patterns, not a universal line cap. Candidates observed in this review are dose persistence, Studio export orchestration, alarm scheduling and session-support UI. Existing architecture ceilings are migration limits, not evidence that a file beneath the limit is well designed.

For each extraction: document the responsibility and dependencies, add characterization tests, perform the move with all call sites and Xcode entries, run the relevant checks, and commit it separately from behavior changes. Keep the previous step independently revertible. Avoid adopting a new state-management framework or splitting every feature into a package during this cleanup.

### 4. Make drift harder to reintroduce

Once the baseline is understood, add negative-fixture tests for membership/forbidden-dependency checks and enforce changed-code naming/formatting rules in CI. Public and safety-relevant APIs should document units, optional values, failure behavior, clock ownership and side effects. Private implementation details should remain private unless a tested boundary requires broader access.

Keep synthetic examples separate from real exports. Retain local credentials and private drafts outside committed artifacts. Document recoverable cleanup targets; do not add a broad `clean` command that can remove local databases or exports.

## Acceptance for a structural slice

- No intentional schema, medication, alarm or export-contract changes mixed into a move.
- Full-repository reference scan and verified SwiftPM/Xcode source and test membership.
- Required core build/tests, app build and focused tests pass. UI changes also need simulator inspection; physical acceptance stays open where required.
- Existing architecture, dose-write, legacy-safety, documentation and Plane guards stay green; baseline exceptions are explicit and do not expand silently.
- Only reviewed files are committed. Pre-existing Xcode edits and preserved checkouts remain separate.
- Plane owns status. DOSETAP-17/20 remain Backlog until explicitly scheduled; DOSETAP-19/22 keep their current acceptance gates. This plan does not silently claim or complete them.

## First structural move after the review

Start with a source/test membership inventory and standards reconciliation, then a small export-orchestration extraction supported by its existing tests. Prioritize the Timeline correctness defect and medication device evidence over cosmetic directory renaming.
