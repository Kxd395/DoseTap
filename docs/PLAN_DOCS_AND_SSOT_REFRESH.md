# Docs + SSOT Refresh Plan

## Phase 1: Inventory and Accuracy Audit

- [x] Enumerate documentation files and last updated metadata
- [x] Identify SSOT location and current doc set
- [x] Flag docs that are stale, duplicate, or misleading

Acceptance:
- Inventory table completed with actions per doc
- Archive plan defined

## Phase 2: SSOT Update

- [x] Rewrite SSOT to reflect current code behavior
- [x] Add domain entities and invariants
- [x] Add dose flow and session rollover state machines
- [x] Add event flow and HealthKit interaction diagrams

Acceptance:
- `docs/SSOT/README.md` matches code behavior
- All SSOT claims cite file/symbol references

## Phase 3: Schema and Diagnostics Truth

- [x] Update data dictionary to match SQLite schema
- [x] Update database schema doc to match EventStorage
- [x] Update diagnostic logging docs for session_id semantics and new fields
- [x] Update session trace guide for UUID session IDs

Acceptance:
- Schema docs match `EventStorage.createTables()`
- Diagnostic docs match `DiagnosticEvent` and `DiagnosticLogEntry`

## Phase 4: README and Dev Docs Refresh

- [x] Update root README with current core behavior
- [x] Update docs index to point to canonical docs
- [x] Update testing guide with current checklist and references

Acceptance:
- README includes data retention and HealthKit notes
- Developer docs point to SSOT state machines

## Phase 5: Feature Triage and Archive

- [x] Create feature triage doc
- [x] Archive outdated planning and contract docs

Acceptance:
- `docs/FEATURE_TRIAGE.md` created
- Archived docs moved under `docs/archive/`

## Phase 6: Final Consistency Check

- [ ] Verify links in `docs/README.md` and `docs/SSOT/navigation.md`
- [ ] Confirm no remaining references to archived docs

Acceptance:
- No broken doc links
- Canonical docs set is minimal and accurate

## Test Checklist

- Build: `swift build`
- Tests: `swift test`
- Manual: follow `docs/TESTING_GUIDE.md`

## Files Edited/Created

- `README.md`
- `docs/README.md`
- `docs/SSOT/README.md`
- `docs/SSOT/navigation.md`
- `docs/DATABASE_SCHEMA.md`
- `docs/SSOT/contracts/DataDictionary.md`
- `docs/DIAGNOSTIC_LOGGING.md`
- `docs/HOW_TO_READ_A_SESSION_TRACE.md`
- `docs/architecture.md`
- `docs/TESTING_GUIDE.md`
- `docs/FEATURE_TRIAGE.md`
- `docs/PLAN_DOCS_AND_SSOT_REFRESH.md`

Archived (moved):
- `docs/FEATURE_ROADMAP.md`
- `docs/PRD.md`
- `docs/PRODUCT_DESCRIPTION.md`
- `docs/USE_CASES.md`
- `docs/user-guide.md`
- `docs/SLEEP_PLANNER_SPEC.md`
- `docs/APP_SETTINGS_CONFIGURATION.md`
- `docs/TESTING_GUIDE_FIXES.md`
- `docs/accessibility-implementation.md`
- `docs/NIGHT_MODE.md`
- `docs/NIGHT_MODE_IMPLEMENTATION_2026-01-03.md`
- `docs/ADVERSARIAL_AUDIT_REPORT_2025-12-26.md`
- `docs/RED_TEAM_AUDIT_2026-01-02.md`
- `docs/SECURITY_REMEDIATION_2026-01-02.md`
- `docs/SSOT/contracts/Inventory.md`
- `docs/SSOT/contracts/MedicationLogger.md`
- `docs/SSOT/contracts/PreSleepLog.md`
- `docs/SSOT/contracts/ProductGuarantees.md`
- `docs/SSOT/contracts/SetupWizard.md`
- `docs/SSOT/contracts/SupportBundle.md`
- `docs/SSOT/contracts/SchemaEvolution.md`
- `docs/SSOT/contracts/api.openapi.yaml`
- `docs/SSOT/ascii/`
- `docs/SSOT/contracts/diagrams/`
- `docs/SSOT/contracts/schemas/`
- `docs/SSOT/TODO.md`
- `docs/SSOT/PENDING_ITEMS.md`

