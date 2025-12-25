# Fix Plan - Session 3 (2025-12-24)

## 1. Documentation Unification
- [ ] **README.md**: Remove Core Data references, update test count to 207, update event count to 13.
- [ ] **docs/architecture.md**: Remove conflicting Core Data section, unify on SQLite.
- [ ] **docs/FEATURE_ROADMAP.md**: Update event types to 13, remove stale cooldowns.
- [ ] **docs/IMPLEMENTATION_PLAN.md**: Update test count to 207.
- [ ] **Archive**: Move `EventStoreCoreData.swift` to `archive/` or delete it to prevent confusion.

## 2. Code Safety (Dose 2 Logic)
- [ ] **Dose 2 Early**: Verify `DoseWindowCalculator` handles early Dose 2 correctly (it seems to based on tests, but need to verify persistence).
- [ ] **Dose 3 Hazard**: Implement logic to prevent silent overwrite of Dose 2.
    - Add `dose3_time` or `hazard_log` to schema? Or just log as a generic event with high severity?
    - *Decision*: Log as a `dose_hazard` event in `dose_events` table if Dose 2 already exists.

## 3. Persistence Cleanup
- [ ] **Delete**: `ios/DoseTap/Storage/EventStoreCoreData.swift` (It's dead code but referenced in project).
- [ ] **Project File**: Remove `EventStoreCoreData.swift` from `project.pbxproj`.

## 4. Verification
- [ ] Run `tools/doc_lint_strict.py` -> Pass.
- [ ] Run `swift test` -> 207 passed.
