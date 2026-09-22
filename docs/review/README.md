# DoseTap review records

Status: Point-in-time review and decision evidence
Last updated: 2026-09-22 (Excel sorting contrast and packaging memory)

Files here record dated reviews, design decisions, migration analysis, and regression runs. They do not override current SSOT, code, or Plane. Promote a lasting rule into SSOT or a maintained architecture decision and link back to its review record.

## Questionnaire feedback packet

- [Questionnaire delivery plan](../plans/2026-09-10-questionnaire-delivery-plan.md): scope decisions, save/reminder semantics, data owners and staged implementation under DOSETAP-69. Qualifies the [supplied revision](2026-09-10-dosetap-questionnaire-revision.md); proposals are not shipped behavior.

- [Pre-sleep and wake-up collection inventory](2026-09-10-sleep-questionnaire-review.md): current selections, defaults, save flows, planned additions and a feedback template, pinned to build 39.
- [Independent questionnaire findings](2026-09-10-questionnaire-independent-findings.md): separate source/UX review with proposed fixes and acceptance cases; not phone reproduction or clinical approval.

## Owner data and dashboard review

- [Excel workbook design](../plans/2026-09-17-excel-workbook-export.md): owner-approved sheet order, sortable tables, source mapping and review/ingestion workflow. The [current contract](../SSOT/contracts/ExcelWorkbook.md) owns implementation semantics; native Excel, phone and release acceptance remain separate.
- [Collected-data inventory and work/off dashboard plan](2026-09-11-dashboard-and-collected-data-review.md): human-facing provider, questionnaire, dosing and quick-log fields; planned means, transition groups and missingness rules. This is a build-45 source inventory with later delivery links, not a claim that the proposed dashboard ships.
- [Collection/store/export audit reading guide](../audit/2026-09-12/README.md): pair the owner inventory with exact stored fields, export coverage and known discrepancies.
- [Awakening-count source review and implementation plan](2026-09-12-awakening-count-review.md): existing count meanings, completed-episode contract, consumer migration and test cases; documentation only, no new app build.

## Delivery records

- [September 12 Plane closeout and validator review](2026-09-12-plane-closeout-review.md): DC-12 local-export validation, exact acceptance boundaries and next provider repair; app remains build 53.
- [Final retained legacy-patch disposition](2026-09-12-legacy-patch-disposition.md): DOSETAP-63 source comparison and protected Xcode policy; preserves the legacy checkout and branches.

Each record identifies its version, bounded changes, validation and remaining gates. Integration and automated checks do not close phone, VoiceOver, provider, privacy or release acceptance.

| Build | Record | Scope |
| --- | --- | --- |
| 64 | [Excel row contrast](2026-09-22-excel-contrast-delivery.md) | Explicit body fills distinct from Normal; native date/duration sorting, filtering and save/reopen readability; phone and broader gates remain separate |
| 63 | [Excel packaging memory](2026-09-22-excel-memory-delivery.md) | One generated XML part at a time; measured memory reduction with identical decompressed workbook contents; phone/release gates remain separate |
| 62; phone save/open accepted | [Styled Excel workbook](2026-09-17-excel-workbook-delivery.md) | Fifteen sortable/filterable sheets, fixed summaries and source evidence; phone sorting/reopen and broader acceptance remain open |
| 44 | [Sleeping arrangements](2026-09-10-sleeping-arrangement-delivery.md) | Planned/actual setup and separate reusable preferences |
| 45 | [Morning pain reuse](2026-09-10-morning-pain-reuse-delivery.md) | One saved pattern reviewed with a fresh morning level |
| 46 | [Dose/sleep metrics](2026-09-11-dose-sleep-metrics-delivery.md) | Read-only intervals with unresolved/conflicting evidence |
| 47 | [Dose completion](2026-09-11-dose-completion-delivery.md) | Conditional morning timing clarification and reminder cancellation |
| 48 | [Timeline awakening inspection](2026-09-11-timeline-awakening-delivery.md) | Selected-night intervals, source samples and timed quick-log context |
| 49 | [Dose 1 reminder review](2026-09-11-dose1-reminder-review-delivery.md) | Explicit dose confirmation and tonight's reminder choice |
| 50 | [No alarm](2026-09-11-no-alarm-delivery.md) | Session-scoped reminder opt-out |
| 51 | [Durable logging](2026-09-12-durable-log-delivery.md) | Quick/general-medication save failures, retained drafts and retry |
| 52 | [Export fidelity](2026-09-12-export-fidelity-delivery.md) | Stored inventory/medication preservation, checked reads and tracker reconciliation |
| 53 | [Event export provenance](2026-09-12-event-export-provenance-delivery.md) | Original dose/sleep row identity, timestamp text, metadata and color |
| 54 | [Apple Health export missingness](2026-09-12-health-export-missingness-delivery.md) | DC-05 partial correction: absent sleep summaries retain biometrics without invented zeros |
| 55 | [WHOOP export request status](2026-09-12-whoop-export-status-delivery.md) | Merged PR #43: independent fetch results, request counts and cancellation; local/hosted validation passed, provider acceptance open |
| 56 installed; owner acceptance open | [Nightly setup reuse](2026-09-13-nightly-setup-reuse.md) | Opt-in automatic planned sleeping setup, durable room preferences and explicit morning reuse scope |
| 57 candidate | [Pre-sleep pain editor loading repair](2026-09-14-pre-sleep-pain-editor.md) | First saved-pattern opening loads the selected entry and mode together; owner acceptance open |

| 59 installed candidate; PR draft | [Settings export failure diagnosis](2026-09-17-export-failure-diagnosis.md) | USB read-only structural finding; truthful errors and empty-row removal; original export blockage remains open |
