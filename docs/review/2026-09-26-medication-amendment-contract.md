# Medication amendment domain foundation

Date: 2026-09-26 · Plane: DOSETAP-74 · Slice: B3c foundation
App remains 0.4.19 (72); no app-facing delivery or phone installation.

The existing independent preset ledger is append-only. This slice adds a pure
DoseCore correction/reversal contract and deterministic audit projection, before
introducing durable amendment writes or Edit/Reverse controls.

A correction keeps the original ID and a full revised report. A reversal withdraws
that report without claiming a skipped dose. Original reports, reasons, explicit
predecessor links and all corrected snapshots remain available. Projection rejects
forks, duplicates, orphan/cross-root links, cycles, unknown presets, causal timestamp
violations and any attempt to append after a reversal. Known, approximate and
unknown occurrence evidence and Decimal amounts retain their existing semantics.

## Validation

- Tests written first: missing model symbols failed compilation before implementation.
- Eight focused regression tests pass, including malformed decoding, exact Decimal
  round-trip, shuffled/equal-time chains, cross-root links and timestamp evidence.
- Full core suite: 797 XCTest plus 43 Swift Testing cases, no failures.
- `swift build -q` and unsigned simulator `tools/dt-build sim` pass, with isolated
  DerivedData `/tmp/dosetap-amendment-contract`.
- SSOT, Plane workflow (15 tests/80 assertions), architecture, documentation and
  whitespace checks pass. Independent source review found no blockers.
- Prior build72 post-merge CI, Swift CI and Documentation CI were freshly verified
  successful at main `897658f941400947ce47acbd495e25f3ca9992f6`.

## Remaining implementation and acceptance

This contract is not yet a database table or Settings export field. Before writes
are enabled, integrate transactional persistence, idempotency and stale-edit guards,
explicit export versioning and updated workbook/Studio readers together. Old
readers must not silently ignore corrections. Then add reviewed Edit/Reverse UI,
failure/retry journeys and native visual validation.

Build72 phone setup/log/reopen/export, VoiceOver, privacy and release acceptance
remain open. Existing unrelated Xcode project and Info.plist edits are preserved.
No historical rows, nighttime medication actions, alarms or PK estimates changed.
