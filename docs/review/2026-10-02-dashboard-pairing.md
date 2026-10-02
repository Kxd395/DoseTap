# Empty interval/sleep chart — pairing recovery

DOSETAP-45 remains In Progress. The owner's build92 screenshot reaches Trends correctly but shows zero paired interval/sleep points. The previous display-only fixture prejoined provider sleep to dose sessions and therefore did not exercise the failing path.

## Diagnosis

A narrow read-only copy of the phone's DoseTap SQLite database passed quick_check and contained 230 sleep sessions, 383 dose-event records and zero saved dashboard provider associations. It contained 30 treatment dates in the selected range. The private copy stays in the ignored, permission-restricted evidence directory; no raw records are committed.

Build88 joined summaries by treatment date. Commit 4e295d5 separated exact session/provider identities; cbd5a0e added explicit versioned matches. The resulting mandatory-manual-match behavior means zero paired records when there are no saved associations, even when both independent data sources exist. A date-only join is still insufficient for ambiguous sessions.

## Correction

Explicit saved relationships retain precedence and fingerprint validation. Without a saved relationship for either the episode or session/provider, the selected primary episode may attach transiently to the sole resolved session for that treatment date when observed times fit:

- Exactly one canonical Dose 1; no duplicate Dose 2, additional administration or skip/taken conflict.
- Positive, finite provider bounds no longer than 16 hours.
- Dose 1 is between 120 minutes before and 30 minutes after observed sleep onset and precedes the episode end.
- Any Dose 2 is after Dose 1 and before the observed end.
- Missing/ambiguous times, multiple same-date sessions, and stale explicit relationships remain separate.

These are conservative matching rules, not clinical timing recommendations or proof that a relationship was manually reviewed. Automatic associations are recomputed from current records, labeled by provider, and never saved as explicit relationships. Removing an explicit match may allow an unambiguous automatic match; the removal dialog states this. Doses, source sleep measurements and alarms are unchanged.

Trends shows dose-pair/sleep/paired counts, labels automatic matches, distinguishes missing sleep from unresolved matches, and links directly to review unmatched sleep. The Overview sleep comparison also links to unresolved matches and exposes association provenance in selected-source details.

## Validation

Evidence: `.build/dashboard-pairing-evidence/`.

- Production-refresh regression failed with automatic matching disabled: a valid 180-minute interval and 420-minute sleep episode remained separate. It passes with the correction, producing X=180 and Y=420 without a stored association.
- Targeted native suite: 38 tests passed, covering identity, provider snapshots, dose patterns, explicit matching and automatic pairing. Provider correction, stale explicit relationship and Dose 2 outside the observed episode exclude the pair.
- UI: 3 executed tests passed. The new fixture seeds an isolated repository and provider query, then uses production refresh; it does not prejoin chart rows. Manual match/unlink and single-dose/work filtering also passed. The production-path chart screenshot was inspected.
- Core suite and repository guards passed; final source-label, commit-hook and device receipts are recorded at delivery.

## Acceptance

The copied database establishes the zero-association condition, not live Apple Health episode coverage. Current physical-phone chart population and pairing correctness remain open until observed. iPhone Mirroring reported iPhone in Use during this run. Owner speed, accessibility, provider/privacy/release and inherited gates remain open. No claim that simulator dots prove the owner's records are paired correctly.
