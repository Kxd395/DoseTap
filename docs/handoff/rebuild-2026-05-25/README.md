# DoseTap Rebuild Handoff Package

Date: 2026-05-25
Branch inspected: `feat/phase-2-ux`
HEAD inspected: `abe4ddc`
Purpose: provide a rebuild-ready markdown package for planning a new DoseTap version without losing the validated domain rules, storage history, privacy posture, and known failure modes from the current project.

## Package Map

| File | Use |
| --- | --- |
| `EXECUTIVE_BRIEF.md` | Fast orientation for product, engineering, and stakeholder review. |
| `01-current-state-inventory.md` | What exists today, where it lives, and which docs are authoritative. |
| `02-target-rebuild-scope.md` | Proposed new-version feature set, including dashboards, integrations, storage, watch, widgets, and user workflows. |
| `03-architecture-and-storage.md` | Recommended target architecture, storage strategy, sync model, rollback notes, and migration boundaries. |
| `04-integrations-and-data.md` | HealthKit, WHOOP, Flic, Siri/AppIntents, widgets, exports, and future API/backend boundaries. |
| `05-dashboard-and-analytics.md` | Dashboard product requirements, analytics calculations, data quality rules, and insight governance. |
| `06-backlog-and-roadmap.md` | Prioritized rebuild backlog with acceptance criteria and implementation notes. |
| `07-risks-past-issues.md` | Past issues that must not reappear, open risks, and required remediation checks. |
| `08-testing-observability-security.md` | Required test matrix, diagnostics, logging, privacy, security, compliance, and release gates. |
| `09-delivery-plan.md` | Phased rebuild execution plan, team handoff notes, and rollback strategy. |
| `10-second-pass-gaps-and-recommendations.md` | Second-pass findings: missed refactors, safer interaction model, module boundaries, and priority additions. |
| `adrs/ADR-0001-rebuild-architecture.md` | Initial architectural decision record for the rebuild. |

## Non-Negotiable Sources

The rebuild team must treat these files as source material before changing behavior:

- `docs/SSOT/README.md` for current behavior and state machines.
- `docs/DATABASE_SCHEMA.md` for existing SQLite schema.
- `docs/SSOT/contracts/DataDictionary.md` for domain vocabulary.
- `docs/DIAGNOSTIC_LOGGING.md` and `docs/HOW_TO_READ_A_SESSION_TRACE.md` for support diagnostics.
- `docs/TESTING_GUIDE.md` for current validation gates.
- `docs/audit/2026-02-15/findings.md` for historical risk inventory, with current-HEAD verification required.
- `docs/IMPROVEMENT_ROADMAP.md` and `docs/FEATURE_TRIAGE.md` for planned/deferred feature context, with current-HEAD verification required.

## Immediate Rebuild Rule

Do not start by rewriting the app. Start by freezing the domain contract:

1. Preserve the dose window: Dose 2 is 150-240 minutes after Dose 1.
2. Preserve session lifecycle: sessions close on morning check-in, missed check-in cutoff, or prep-time soft rollover.
3. Preserve local-first behavior: dose logging must work without network, iCloud, WHOOP, HealthKit, or Bluetooth hardware.
4. Preserve explicit confirmation for early, late, after-skip, and extra dose flows across every input channel.
5. Preserve export and diagnostics paths so user support remains possible during migration.
