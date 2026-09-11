# Timeline Dose 2 awakening inspection

Status: Bounded DOSETAP-57 delivery; acceptance remains open
Version: 0.4.19 (48)
Baseline: main `5c5c74c`, PR #33, build 47

## Behavior

Timeline Review now offers Check dose and sleep timing for the selected treatment
night. It reads the existing saved reviewed night window through SessionRepository,
using the same provider/dose snapshot and calculator as Wake & Next Day. A missing
window explains what is missing and offers Review night window; no chart bounds
are silently saved as an observation.

A matched Dose 2 awakening displays awake start, recorded dose time, and observed
return. The four existing duration rows retain missing/conflict explanations.
Quick logs during the observed awake portion remain timed context, including when
the return is unresolved. They do not establish duration or wake cause. Alarm
history is not included or implied complete. Matching logs use a half-open interval:
a log exactly at the observed end belongs to the following interval, not this awakening.

Expandable source details retain original sample bounds on both sides of the
transition, category, source app and available device/timezone/version metadata.
If no episode resolves, the disclosure instead identifies reviewed-window samples.
The query time remains visible. Refresh, local changes, backgrounding, leaving the
view and Health preference changes clear results; generation checks reject late
responses for invalidated checks. Changing the selected night creates fresh state.

This slice leaves the existing stage chart, strict initial-onset rule, medication,
alarms, questionnaires, HRV model and legacy provider normalization unchanged.
The existing capture/share path does not include these checked results; the card
states that limitation. No SQL migration or new permissions are required.

## Evidence and remaining gates

Exact local and hosted validation and integration are recorded in the DOSETAP-57
workpad. Tests cover known 8-minute pre-dose plus 14-minute post-dose timing,
original boundary samples, unresolved return with retained bathroom context,
refresh invalidation and late responses. Native UI journeys cover duration rows,
source inspection, normal/largest text and the real Timeline missing-window entry.

Final local validation on this slice:

- Core: 710 XCTest and 43 Swift Testing cases passed.
- Targeted iOS repository/model integration: 55 tests passed.
- Native UI: five journeys passed across two final runs on the same source:
  normal/largest-text metrics, normal/largest-text source and bathroom inspection,
  and the real Timeline entry plus existing capture regression.
- Initial source-inspection runs exposed a disclosure that stayed collapsed after
  tapping its label. Full-width 44-point expand/collapse buttons fixed the issue;
  final tests assert expanded state and visible source/bathroom content. Native
  screenshots were inspected; the earlier failed bundles are not passing evidence.
- Unsigned simulator and signed device builds passed; all four configurations
  identify 0.4.19 (48). Signing does not establish installation or phone acceptance.

Phone installation, actual Health source/sample parity for the owner's night,
VoiceOver/full accessibility, privacy and release acceptance remain open. The
synthetic UI fixture does not read or write personal Health records. Awakening
counts, first-recorded-sleep wording, HRV identity, full chart/source unification,
Dashboard averages and export/Studio parity remain separate work. The prior
[build-46 delivery](2026-09-11-dose-sleep-metrics-delivery.md) and
[collected-data review](2026-09-11-dashboard-and-collected-data-review.md) remain
context for those gates.
