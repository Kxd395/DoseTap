# Event identity and recording provenance in exports

Date: 2026-09-12. App: **0.4.19 (53)**. Studio export: **2.5**, schema 2.
Tracking: DOSETAP-13 (export), DOSETAP-39 (lifecycle/documentation).
Baseline: main `6cc77e7acdc455964fa86ffee6e3b45b3cbdefd0`, build 52.
Branch: `fix/event-export-provenance`. Exact review/merge evidence lives in the PR and Plane workpads.

## Delivered scope

This is the bounded follow-up to [audit DC-04](../audit/2026-09-12/collection-store-export-audit.md). Successful Settings and local/scheduled archives preserve table-qualified event identity, nullable stored session identity, treatment date, original occurrence text, nullable creation text, color and unchanged dose metadata or sleep notes in raw JSON, normalized JSON and events CSV. Raw and normalized representations identify the same rows; normalization changes only event vocabulary.

A checked export-only UNION reads both source tables directly. It has no row cap or canonical-session filter and does not assign identities to legacy rows. Invalid required occurrence text, unreadable text and SQLite failures stop export. Neither the clock nor a default source reconstructs missing history. Metadata can remain unparsed text; correction evidence is not expanded into additional current medication events.

Occurrence, recording and row creation remain separate. `occurredAtUTC` is the compatible parsed occurrence; `timestampStoredUTC` preserves original precision. `createdAtStoredUTC` is row creation, not proof of when medication was recorded. Explicit `recorded_at_utc` stays in dose metadata when supplied. Missing recording information stays missing.

CSV retains its first four columns and canonical fractional occurrence format. Seven appended columns add provenance. The legacy date-valued `device_time` remains for compatibility; `session_date` supplies the accurate name. CSV empty cells still cannot distinguish NULL from empty text.

Studio reads old bundles with missing provenance and retains new fields through model re-encoding. Runtime UUIDs remain separate from stored IDs. Unknown event strings remain in raw/normalized JSON and the original imported archive. Studio's typed CSV analytics still exclude unsupported event types; that view is not the complete event inventory. New identifiers/timestamp text do not enter generated clinician-safe reports.

No SQL migration, medication action, alarm change, source-record rewrite, provider calculation or additional sensitive collection is included. Documentation indexes link this delivery; the root README now distinguishes SQLite records from preferences, local files, Keychain and external providers.

## Validation and review

- Core: **710 XCTest plus 43 Swift Testing cases**, no failures.
- iOS: **470 tests passed** on iPhone 17 Pro / iOS 26.5 with isolated DerivedData; the final run includes all 9 export-fidelity regressions.
- Studio: **74 tests executed, 3 conditional skips, no failures**; with actual questionnaire, medication and event archives, **74 executed, 2 existing visual-preview skips, no failures**.
- Fixtures cover same-date session identities, NULL legacy identity, identical IDs across tables, whole/fractional occurrence text, unchanged quoted/multiline notes, nullable creation, unparsed metadata, and invalid rows after a readable prefix. The actual scheduled ZIP retains all three synthetic source keys; Studio imports their raw/normalized representations.
- Independent review found a CSV compatibility regression. Its new whole-second fixture failed once, then passed after restoring the legacy occurrence-column format. Review recheck cleared the final source diff.
- Unsigned simulator and signed generic iOS builds, version checks across four app/staging configurations, SSOT/docs, architecture/dose-write/legacy/companion/hygiene/export guards, Plane workflow and whitespace checks passed. A signed build is not a phone installation.

Logs, test attachments, the signed candidate and integration/Plane receipts are retained under the shipping checkout's ignored `.build` evidence/delivery directories. No owner database, live HealthKit/WHOOP data, native Settings share journey or VoiceOver session was inspected in this slice.

## Remaining gates

The shared dose reader now accepts absolute whole-second and fractional timestamps and orders mixed formats by parsed instant. A reproduced whole-second dose previously blocked the actual archive through the History snapshot count guard. The parser repair recognizes that existing row while preserving malformed-date rejection and identity/count guards. Existing records can consequently participate in duplicate/state checks; no rows are added or rewritten. Date-level `collectedNightSummary` still rejects ambiguous same-date UUIDs. DC-07 population/aggregate redesign and DC-11 broader readers/coherent export snapshot remain open.

DOSETAP-13/39 remain In Progress. Other open work includes provider missingness/boundaries and wake-cause parity, questionnaire defaults, wider format/lifecycle coverage, full CRUD/clear-all/content-equal restore, and the previously observed DC-12 local-only-consent validator mismatch. No new Done transition is justified by this code delivery. All three build-52 post-merge workflows were verified successful during this run; build-53 integration checks are tracked separately.

Phone Settings → Files/share → Studio comparison, background execution, provider permission/data cases, VoiceOver, privacy/security and release acceptance remain open. The next engineering slice should reconcile provider-derived numbers, explicit missingness and consistent boundaries before adding new dashboard averages.
