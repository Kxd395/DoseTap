# Plane closeout and local export validation review

Date: 2026-09-12. Baseline: `00f5675f04d4e2a396279050c76226737c3ae73a`, **0.4.19 (53)**.
Scope: repository review, export validation tools and documentation. App source,
database contents, medication behavior and build number are unchanged.

## Work selection and closure boundaries

The live inventory contained 71 items: 40 In Progress, 6 Todo, 14 Backlog,
10 Done and 1 Cancelled. Parallel reviews inspected export validation, provider
mapping, retained legacy patches, and the acceptance of DOSETAP-19/27/63.
Plane remains authoritative; this inventory is a dated snapshot.

| Item | Result of this review | Acceptance boundary |
| --- | --- | --- |
| DOSETAP-63 | [Final per-patch disposition](2026-09-12-legacy-patch-disposition.md), including protected Xcode changes and retained branch policy. | Repository review only; final Done requires independent review and exact Plane readback. New source findings have separate owners. |
| DOSETAP-13 / DC-12 | Strict validation now recognizes explicitly local archives whose writer did not capture provider consent. | The individual validator defect can be resolved; complete export/backup, provider and phone acceptance remain open. |
| DOSETAP-19 | Legacy safety and dose-write guards passed. Current source retirement matches the [architecture decision](../architecture/12-safety-sensitive-legacy-retirement.md) and [plain-SQLite boundary](../SSOT/encryption-at-rest.md). | Its existing owner architecture-decision review remains open. Automated guards do not supply that decision. |
| DOSETAP-27 | The requested `SupplyCycleEstimate` contract is absent. Existing inventory forecasts retain bottle/tolerance/ledger semantics excluded by this item. | Reconcile confirmed plan inputs, cycle-end meaning and timezone policy with DOSETAP-15/17/24 dependencies before implementation. Characterization tests are not acceptance of the new contract. |

DOSETAP-25 warning cleanup, DOSETAP-8 hosted native UI coverage and DOSETAP-23
CSV consumer/runtime inspection are plausible later tasks, but were Backlog and
were not claimed. DOSETAP-66/68/69 were already Done and were not reopened.

## DC-12 validator repair

The actual synthetic build-50 scheduled ZIP failed strict validation solely with
`consent must be an object`. It contained the required three questionnaire
families and six morning raw payloads. The local writer deliberately omits
consent and records `Local snapshot only; provider enrichment was not fetched.`

The validator accepts an absent consent key only for known schema 2 with a
sessions array, that exact string-array element and no structured provider contradiction. Provider payloads, availability,
metric provenance, collected-night provider measurements and nonblank provider
CSV values reject the local declaration. Explicit malformed consent and invalid
boolean provider-state fields fail. Ordinary archives still require consent.
The output describes local consent as **not captured**, without inventing false
authorization. Required metadata, raw questionnaires and ZIP safety still apply.

This changes two repository tools, not the app or archive schema. See the
[current field contract](../SSOT/contracts/DataDictionary.md) and the dated
[DC-12 finding](../audit/2026-09-12/collection-store-export-audit.md). The prior
failure remains historical evidence; the same archive is used for red/green
verification. Synthetic data does not prove an owner's export or background run.

## Provider findings retained for the next app slice

DC-05 remains a confirmed missingness problem: Apple Health biometrics without
usable sleep can export fabricated zero sleep/awake/stage measurements. WHOOP
export similarly loses availability distinctions and can choose a different
same-date episode from Dashboard. Recovery retrieval errors also lose their
specific status. These are source-trace findings, not new phone reproductions.

Correction to the older DC-05 wording: current `fetchSegmentsForTimeline` already
applies primary-episode selection. A primary-total versus full-query-reduction
mismatch is therefore not established. The remaining boundary difference is
the exporter’s fixed 18:00–noon primary episode versus the reviewed loader’s
explicit window and conflict-aware evidence. The next bounded repair should
preserve missing Apple Health sleep measurements while retaining biometrics;
query policy, WHOOP selection and full source provenance need separate coverage.

## Validation and integration evidence

- The actual build-50 synthetic ZIP changed from strict failure (consent only)
  to no audit issues. All three questionnaire families and six morning raw
  payloads remained present. The harness passed 62 positive/adversarial cases
  plus a local ZIP, retaining its earlier raw-payload and ZIP traversal guards.
- Independent review reproduced and then verified fixes for unknown-schema and
  absent-sessions bypasses. Final validator review is clear. Existing P2 warning
  policy for missing offsets is unchanged; this is not a complete schema validator.
- `swift build -q` and `swift test -q` passed: 710 XCTest and 43 Swift Testing
  cases. Documentation/SSOT, legacy safety/dose-write, shell syntax and Plane
  workflow checks (15 tests / 80 assertions) passed, as did whitespace and 52
  relative documentation links. These are fresh local repository results.

Build-53 post-merge CI `34712566018`, Swift CI `34712566036` and Documentation CI
`34712566019` were re-read as successful on the exact baseline. New tool checks,
independent review, commit/PR integration and structured Plane apply/verify
receipts are recorded under `.build/audits/2026-09-12-plane-closeout` and in the
exact workpads. This source record does not predeclare those later results.

No phone installation, owner-record inspection, VoiceOver, privacy or release
acceptance is claimed. The installable app remains **0.4.19 (53)** from the
[preceding delivery](2026-09-12-event-export-provenance-delivery.md).
