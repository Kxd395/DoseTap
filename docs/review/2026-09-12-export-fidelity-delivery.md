# Stored-record export fidelity and tracker reconciliation

Date: 2026-09-12. App: **0.4.19 (52)**. Studio export: **2.4**, schema 2.
Tracking: DOSETAP-13 (export), DOSETAP-39 (documentation/lifecycle).
Baseline: main `1f186465884738e71ff295536e3e7e99c31c81b0`, build 51.
Branch: `fix/export-record-fidelity`. Exact review/merge evidence lives in the PR and Plane workpads.

## Delivered scope

This repairs [audit DC-02 and DC-03](../audit/2026-09-12/collection-store-export-audit.md). Inventory CSV includes every stored snapshot, including its ID, medication name and original creation text. The first six columns stay in place; appended columns carry provenance. Notes retain their stored text, with source in a separate column. A 501-row fixture exports all 501 distinct IDs.

Medication JSON uses stored units and formulation, including unknown medication IDs and custom values. It preserves session identity/date, offset, nullable duplicate confirmation and exact occurrence/creation text. The existing parsed occurrence remains compatible; its companion raw text retains fractional precision. Missing creation metadata stays missing. No current configuration or clock reconstructs historical facts.

Checked medication/inventory reads reject malformed rows and SQLite errors. Review found that failed date discovery could bypass these reads and publish an empty bundle. Export now uses throwing discovery too. Tests exercise the actual local/scheduled writer, a medication-only session, an unreadable row after a readable prefix, and a missing medication table. Failed runs publish no final ZIP. Other readers and whole-export snapshot consistency remain separate work.

Studio retains the additive fields, reads old bundles with missing provenance, and accepts fractional or whole-second inventory timestamps. Appended inventory metadata is addressed by header. Runtime UUIDs remain separate from source record IDs. New metadata is absent from generated clinician-safe reports; copying an imported source bundle continues to preserve the original data.

No SQL migration, medication write, alarm change, provider calculation change or historical data rewrite is included. CSV empty cells still cannot distinguish NULL from empty text. This archive is not a complete backup.

## Validation

- Core: 710 XCTest plus 43 Swift Testing cases passed.
- iOS: full final implementation run passed **466 tests**; all **5 export regressions** passed again after placing the malformed row after the valid row in read order.
- Studio: **72 tests executed, 3 conditional skips, no failures**. With both actual app-generated questionnaire and medication archives supplied, the full suite passed again: **72 executed, 2 existing visual-preview skips, no failures**.
- Actual app-generated ZIPs retained the expected questionnaire data and a medication-only row with `mL`, `liquid`, stable ID, precise occurrence text and absent creation time.
- Signed generic iOS build and strict signature verification passed. All four app/staging Debug/Release configurations identify **0.4.19 (52)**. The artifact is retained in the shipping checkout at `.build/deliveries/0.4.19-52/DoseTap.app`; no phone installation is claimed.
- Version, SSOT/docs, storage boundaries, dose writes, legacy safety, companion targets, hygiene, check-in/export guards, Plane workflow (15 tests/80 assertions) and whitespace checks passed.

Evidence is retained at `.build/audits/2026-09-12-export-fidelity` in the shipping checkout. Synthetic SQLite and simulator exports are not owner data or signed-phone share/background acceptance. No new native layout or VoiceOver journey was performed for this data-export slice.

## Documentation and Plane reconciliation

The documentation, planning, audit and review indexes now provide an owner reading order and build 44–52 delivery navigation. Earlier snapshots are labelled by date. Dated evidence was not moved or rewritten, and private legacy drafts were not transferred.

Exact post-merge CI readback cleared stale CI-only gates on DOSETAP-45 (`da45253`), DOSETAP-57 (`7d402ff`), DOSETAP-67 (`5c5c74c`) and DOSETAP-71 (`253cd3e`). DOSETAP-56 now identifies DOSETAP-57 as In Progress with delivered read-only foundations. All five workpad updates were applied and independently verified. They remain In Progress. Documentation/scoping items DOSETAP-66/68/69 were already Done; no active item was found eligible for a new Done transition.

## Remaining gates and next slice

DOSETAP-13 remains In Progress: DC-04 event identity/recording provenance, DC-05/06 provider missingness and wake-cause parity, same-date session ambiguity, defaults, broader format coverage/read failures and DC-12 strict-validator/local-only-consent mismatch remain open. The earlier strict-validator failure has not been repaired or relabelled as a pass. DOSETAP-39 retains whole-project CRUD, clear-all and content-equal restore acceptance.

Phone Settings → Files/share → Studio parity on actual records, iOS background scheduling, provider permissions/data, VoiceOver, privacy/security and release acceptance remain open. Failed quick-log drafts from build 51 remain in-process only. The next bounded engineering repair should preserve event identities and occurrence/recording provenance in exports before reconciling provider-derived numbers.
