# Medication preset foundation

Date: 2026-09-25
Plane: DOSETAP-74, In Progress
Scope: B1 core contract; app version remains 0.4.19 (68)
Baseline: PR57 / main `0d1c84d`

## Result

The new platform-independent contract separates a patient-entered label preset
from a reported actual administration. Presets have immutable revision IDs,
effective dates, instructions and source, with release profile separate from
physical form. Multiple strengths remain individual components of one ingredient
and release profile. Exact Decimal totals reject invalid or inexact arithmetic.

An actual snapshot requires separately supplied components and confirmation time;
it cannot inherit an amount or create a dose simply by constructing a preset.
It retains the full original revision, recording time, exact/approximate/unknown
occurrence evidence, and historical timezone/offset when occurrence is known.
Unknown occurrence remains absent. Decoding validates the same invariants as
direct construction, including unsupported versions and malformed components.

This is a prerequisite, not a delivered saved-preset workflow. No SQLite schema,
Settings export, medication quick-log UI, reminder or inventory behavior changes.
No existing patient records are modified. Build 68 remains the app version;
there is no new phone installation in this slice.

## Validation

Tests were written before each new type. Initial runs failed for the absent
types; the subsequent implementations satisfy the focused regression suite.
Coverage includes fractional/multi-strength totals, empty/duplicate components,
invalid decoded records, revision snapshot preservation, release/form separation,
effective boundaries, unknown/future occurrence and the repeated DST hour.

An extreme Decimal multiplication on the local Foundation runtime returned
success with an incorrect positive result after exponent underflow. Exact inverse
verification now rejects that case in addition to checking arithmetic status.
The fixture uses representational limits, not a clinical dose limit.

Local validation: 770 XCTest and 43 Swift Testing cases passed, including 10
preset/snapshot regression tests. The unsigned generic simulator build passed.
SSOT, documentation, architecture, version and Plane workflow checks passed;
Plane helper coverage was 15 tests / 80 assertions. All four app/staging
configurations remain 0.4.19 (68). Independent source review found no blocking
finding; its optional multiplication-precision fixture and positive-sum guard
were added. Hosted checks and integration references are recorded in the
DOSETAP-74 workpad. No native UI, phone, accessibility or export acceptance is
claimed from value-model tests.

## Next bounded delivery

Persist immutable revisions and administration snapshots through the existing
SessionRepository → EventStorage → SQLite boundary. Enforce revision identity,
predecessor/concurrency checks and stable retries there; then verify every new
field in source and workbook exports before exposing preset controls. The legacy
whole-mg/required-time row cannot silently stand in for fractional/unknown-time
records. Audited corrections/reversals, liquids, other mass units, combination
products, named groups and broader outcomes need their own explicit contracts.

Build 68 phone save/reopen/export, VoiceOver/largest text, privacy and release
gates remain open. DOSETAP-58 and DOSETAP-59 remain separate planned work.
