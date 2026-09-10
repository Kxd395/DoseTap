# Plane delivery and acceptance reconciliation

Date: September 9, 2026 (America/New_York)
Tracker: DOSETAP-66
Source baseline: `9000d9b33f78d820370455e7f456fb57c0c2dd64`, merged PR #19
Scope: tracker inventory and targeted evidence reconciliation, not a fresh application or security audit.

## Findings

Plane had 65 items: 35 In Progress, 9 Todo, 14 Backlog, 6 Done and 1 Cancelled. No exact duplicate titles were found. All items lacked an assignee and parent; this is a planning gap, not proof that nobody performed the work.

The board combines unfinished engineering with merged implementations awaiting acceptance. Several workpads retain earlier “no push or merge” statements alongside later merge evidence. The source checkout matched remote main, and GitHub had no open pull requests at the inventory check. Branch cleanup is not the immediate bottleneck.

Thirteen In Progress items lack a structured agent workpad: DOSETAP-1, 2, 3, 5, 6, 7, 10, 19, 22, 26, 27, 37 and 38. Their descriptions can contain implementation and validation evidence. Missing workpads must not be interpreted as missing implementation or populated with invented passes. Review each exact item before its next implementation or acceptance run.

## Targeted cleanup

The companion [reconciliation manifest](plane-reconciliation-notes.json) contains the exact delivery classification and next-action text for 18 tickets:

| Classification | Items | Next action |
| --- | --- | --- |
| Merged source; substantial acceptance remains | 4, 13, 45, 46, 48, 49, 50 | Replace stale pending-merge interpretation with current integration evidence; retain device, incident, provider, restore and release gates. |
| Partial implementation; do not duplicate existing work | 8, 10, 17, 23, 51 | Audit remaining CI, authorization consumers, documentation, CSV paths and substance defaults. |
| Active sleep work and dependent feature | 56, 57 | Complete the provider-backed treatment-night projection before marker/count UI. |
| Merged pain, Timeline and History changes | 61, 64, 65 | Obtain signed-phone and owner/accessibility acceptance. |
| Partial retained-patch review | 63 | Compare remaining legacy UI/questionnaire patches and resolve local Xcode policy before deleting anything. |

These are delivery classifications in a dated description section, not new workflow states or filter labels. The section explicitly supersedes only the identified stale integration claims. Original descriptions remain intact below it, and workpad comments retain historical failures, passes and open gates. No ticket is deleted, reprioritized, reassigned or silently moved out of Backlog. Unattended dispatch remains disabled; DOSETAP-40 still owns the required non-dispatchable handoff policy.

The audit item is separate from the product items: completing this reconciliation does not complete any of their acceptance criteria.

## Disposition of all original items

This roster records workflow state, not a claim that every implementation was retraced during this audit. Identifiers below have the DOSETAP prefix.

| Existing state | Identifiers | Disposition |
| --- | --- | --- |
| In Progress (35) | 1, 2, 3, 4, 5, 6, 7, 10, 13, 15, 19, 22, 26, 27, 30, 34, 37, 38, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 56, 61, 63, 64, 65 | Preserve state. Use current delivery notes and existing gates to distinguish engineering from acceptance. |
| Todo (9) | 39, 52, 53, 54, 55, 57, 58, 59, 60 | Preserve planned scope and dependencies; no new feature started. |
| Backlog (14) | 8, 9, 11, 12, 14, 16, 17, 20, 23, 25, 28, 29, 31, 32 | Preserve state; partial source evidence on 8, 17 and 23 is not acceptance. |
| Done (6) | 18, 21, 24, 35, 36, 62 | Leave historical completion untouched; no new re-certification claimed. |
| Cancelled (1) | 33 | Keep cancelled; do not revive the superseded pharmacy/container workflow. |

DOSETAP-66 was created after reviewing the inventory for equivalent work. DOSETAP-40 concerns tracker integration and dispatch, not this dated reconciliation.

## Recommended sequence

1. **Next engineering slice: DOSETAP-56.** Combine current local window checks with conflict-aware provider evidence; verify freshness after asynchronous reads. Retain existing Apple Health data, charts and source limitations. Durable source revision/deletion handling and permission wording remain explicit work.
2. **Then DOSETAP-57.** Add dose-to-sleep, return-to-sleep and awakening markers/counts using that projection. Unknown gaps and wearable-asleep conflicts must not become fabricated zero latency or sleep duration.
3. **Run a separate acceptance session on the signed phone.** Start with DOSETAP-46/4/3: alarm actions and cancelled confirmation must not create doses; confirmed actions must persist once across restart/export. Then verify pain patterns (61), Timeline (64), History (65) and associated accessibility. The historical unexpected Dose 2 activation remains unexplained.
4. **Keep security and recovery ahead of release.** DOSETAP-1 needs actual revocation evidence; DOSETAP-13/39 need complete recovery evidence. Do not treat a new token, merged source or CSV export as proof of these outcomes.
5. **Use a bounded maintenance slice, not a rewrite.** DOSETAP-17 should reconcile semantic documentation drift. DOSETAP-8/23 should finish CI/export coverage rather than rebuilding existing components. DOSETAP-63 owns retained Git/Xcode decisions. Future food/daytime/report features remain planned.

Assignee and parent changes need an agreed ownership model; this audit does not assign all acceptance to one person or pretend an agent is a project member. Recommended next-action roles are engineering, owner/device testing, and provider/security administration. Splitting acceptance into child tickets later must preserve the parent acceptance contract and must not turn a release hold into Done.

## Evidence and limitations

- Live Plane inventory, descriptions and structured workpads; exact-ID updates and independent description readback.
- Git main ancestry: PR #8 `f1e38c0`, #11 `ae7373a`, #12 `1927dbd`, #13 `d6ee21e`, #14 `ced7ab1`, and #19 `9000d9b`. The detailed app validation in those workpads is historical, not rerun device evidence from this audit.
- [Reviewed-window audit](reviewed-window-assessment.md), [fresh pre-sleep audit](../2026-09-08/fresh-pre-sleep-answers.md), and [Dose 2 incident evidence](../2026-09-07/dose2-recording-incident.md). Earlier documents retain their dated local-only statements; current integration status is clarified in Plane.
- `ios/Core/ReportCSV.swift`, the tracked shared UI-test scheme, and `.github/workflows/ci.yml` establish existing components, not complete feature acceptance.
- README and SSOT still characterize `isAuthorized` as authorization/system grant. The constitution forbids multi-medication CRUD while current product scope has expanded. Passing documentation lint does not resolve either semantic conflict; they remain under DOSETAP-17/10, without silently amending governance.
- No phone installation, new UI run, credential rotation, medication-record correction, provider-data inspection or complete security audit was performed.

The two pre-existing Xcode edits and the separate preserved checkout remain untouched. The Xcode diff SHA-256 before cleanup was `4192a4dec82352e433ce46944ab5d5410121624e8bd1bbc0f6e4ebf57efb0116`; verify it again at handoff. The audit changes only its two documentation artifacts and scoped Plane descriptions. Validation and final tracker state are recorded in the verified DOSETAP-66 workpad.
