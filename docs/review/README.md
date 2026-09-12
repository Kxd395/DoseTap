# DoseTap review records

Status: Point-in-time review and decision evidence
Last updated: 2026-09-12

Files here record dated reviews, design decisions, migration analysis, and regression runs. They do not override current SSOT, code, or Plane. Promote a lasting rule into SSOT or a maintained architecture decision and link back to its review record.

## Questionnaire feedback packet

- [Questionnaire delivery plan](../plans/2026-09-10-questionnaire-delivery-plan.md): scope decisions, save/reminder semantics, data owners and staged implementation under DOSETAP-69. Qualifies the [supplied revision](2026-09-10-dosetap-questionnaire-revision.md); proposals are not shipped behavior.

- [Pre-sleep and wake-up collection inventory](2026-09-10-sleep-questionnaire-review.md): current selections, defaults, save flows, planned additions and a feedback template, pinned to build 39.
- [Independent questionnaire findings](2026-09-10-questionnaire-independent-findings.md): separate source/UX review with proposed fixes and acceptance cases; not phone reproduction or clinical approval.

## Owner data and dashboard review

- [Collected-data inventory and work/off dashboard plan](2026-09-11-dashboard-and-collected-data-review.md): human-facing provider, questionnaire, dosing and quick-log fields; planned means, transition groups and missingness rules. This is a build-45 source inventory with later delivery links, not a claim that the proposed dashboard ships.
- [Collection/store/export audit reading guide](../audit/2026-09-12/README.md): pair the owner inventory with exact stored fields, export coverage and known discrepancies.

## Delivery records

Each record identifies its version, bounded changes, validation and remaining gates. Integration and automated checks do not close phone, VoiceOver, provider, privacy or release acceptance.

| Build | Record | Scope |
| --- | --- | --- |
| 44 | [Sleeping arrangements](2026-09-10-sleeping-arrangement-delivery.md) | Planned/actual setup and separate reusable preferences |
| 45 | [Morning pain reuse](2026-09-10-morning-pain-reuse-delivery.md) | One saved pattern reviewed with a fresh morning level |
| 46 | [Dose/sleep metrics](2026-09-11-dose-sleep-metrics-delivery.md) | Read-only intervals with unresolved/conflicting evidence |
| 47 | [Dose completion](2026-09-11-dose-completion-delivery.md) | Conditional morning timing clarification and reminder cancellation |
| 48 | [Timeline awakening inspection](2026-09-11-timeline-awakening-delivery.md) | Selected-night intervals, source samples and timed quick-log context |
| 49 | [Dose 1 reminder review](2026-09-11-dose1-reminder-review-delivery.md) | Explicit dose confirmation and tonight's reminder choice |
| 50 | [No alarm](2026-09-11-no-alarm-delivery.md) | Session-scoped reminder opt-out |
| 51 | [Durable logging](2026-09-12-durable-log-delivery.md) | Quick/general-medication save failures, retained drafts and retry |
| 52 | [Export fidelity](2026-09-12-export-fidelity-delivery.md) | Stored inventory/medication preservation, checked reads and tracker reconciliation |
