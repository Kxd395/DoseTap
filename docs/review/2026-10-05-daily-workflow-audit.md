# Daily workflow reliability audit

Status: Focused audit and corrected finding; physical acceptance remains open
Date: 2026-10-05, America/New_York
Plane: DOSETAP-58
Baseline: c5446a5, clean feat/sleep-chart-inspection checkout
Fix version: 0.4.19 (102)

## Scope and finding

Reviewed randomized wake planning, stable prompt identity, source revisions,
manual response reconciliation, quiet/sleep/permission suppression, postponement,
persistence and existing reset/race coverage. This is not an application-wide
security audit or a release certification.

Confirmed medium-severity defect: a fractional-second wake and an upper-edge
random draw could silently omit an otherwise valid check-in window. The planner
rounded the chosen time upward after computing its choices, then rejected the
rounded time for exceeding the window end. A fixed schedule seed and a wake at
09:00:00.123Z reproduced only two of three expected windows on the original code.

The fix rounds the earliest eligible instant before computing minute-spaced
choices. Every resulting choice fits the original window. Existing persisted
prompts take the unchanged reuse path; no stored assessments or choices are rewritten.

## Verification

- Red: /tmp/dosetap-audit-red.log, one deterministic case failed two assertions.
- Green: 1196 XCTest plus 43 Swift Testing cases passed in each default-zone and
  UTC run: /tmp/dosetap-audit-core.log and /tmp/dosetap-audit-core-utc.log.
- iPhone17Pro iOS26.5 simulator: 44 reminder/storage tests passed, including
  permission denial, quiet/sleep suppression, restart identity, source revision,
  invalid postponement, failed writes and reset during asynchronous notification work.
  Evidence: /tmp/dosetap-audit-service.xcresult.
- Generic simulator and signed device builds passed. No UI layout changed;
  build101 normal/largest-text UI evidence remains scoped to that prior build.
- Plane workflow, SSOT, documentation, version and whitespace guards passed.

## Recommended next runs

1. Owner-observed phone notification acceptance: record actual wake/work status,
   explicitly enable the routine, observe receipt and open/save, Later/Skip,
   Focus, quiet hours and nap suppression. Never infer delivery from the queue.
2. Broader medication/alarm reliability audit: taken/skip/correct/restart paths,
   interrupted writes, and cancellation readback. Use synthetic fixtures first.
3. Export/privacy audit: compare exact selected records against phone/report
   output, verify deletion boundaries and review sharing scope before release.

The next-day wake still must be explicitly recorded. Missing work/wake evidence
intentionally remains unscheduled. No owner schedule or clinical record was
created by this audit. Physical accessibility, provider, hosted CI, merge and
release approval gates remain open; Plane stays In Progress.
