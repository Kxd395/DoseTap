# Apple Health export missingness

Date: 2026-09-12. Status: implementation, local validation and independent review passed; integration pending.
Baseline: `3577d9f256c09ed43a3f92865dd8704f21e8572b`, app **0.4.19 (53)**.
Signed candidate: **0.4.19 (54)**, verified across both app targets and Debug/Release configurations. Studio export **2.6**, schema **2**.
Tracking: DOSETAP-13 and DOSETAP-56; related lifecycle audit DOSETAP-39. None is Done.

## Bounded contract

The [SSOT](../SSOT/README.md) and [data dictionary](../SSOT/contracts/DataDictionary.md) define this repair to the Apple Health portion of DC-05. A Health object may contain usable biometrics without an eligible primary sleep summary. That object must retain its biometrics without publishing fabricated zero sleep measurements.

Without an eligible primary summary, sleep duration, stage durations, awake duration, WASO, in-bed duration and awakening-count numeric summaries are absent. Received intervals, source labels and independently observed bedtime remain separate evidence. Sleep-metric provenance is emitted only for measurements that are present. Existing numeric zeros within an eligible primary summary remain zeros.

The provider query and episode prefilter are unchanged. This repair does not recover awake-only, in-bed-only or under-20-minute observations already excluded upstream. Received evidence is not a complete provider ledger or a reviewed treatment-night total.

Matching Studio treats absent Health totals/counts as missing, excludes them from measurement facts and usable denominators, and shows its unavailable placeholder. Existing Health-object precedence also governs stages and report columns: missing Health sleep must not be filled from WHOOP or labelled as Apple Health. WHOOP's own fields remain available separately.

Older archives retain their recorded numeric values, including historical zeros. Newly omitted fields require the updated Studio decoder; older versions with required totals/counts cannot read those omissions. There is no SQL migration, historical rewrite, medication/alarm action or provider-policy change.

## Validation status

The preceding PR #41 post-merge workflows passed on the baseline. Those results do not validate this candidate.

| Validation | Result / evidence class |
| --- | --- |
| Tests-first regressions | iOS: 6 tests reproduced 50 expected missingness/provenance assertions; Studio: 3 expected decode failures before repair |
| Targeted iOS regressions | 6 passed; synthetic mapper and production archive writer |
| Full iOS integration suite | 476 passed, zero failures; iPhone 17 Pro simulator, iOS 26.5, unsigned app build |
| Core | 710 XCTest + 43 Swift Testing passed; Swift build passed |
| Studio with four actual generated archive fixtures | 77 executed, 2 optional preview skips, zero failures; new Health fixture plus prior event/medication/questionnaire archives |
| Strict archive validator | Passed; schema 2/export 2.6/build 54, complete consent metadata; expected header-only inventory advisory for synthetic fixture |
| Native Studio import | Generated archive imported through Choose Folder; Health total/count/stages show unavailable dashes, all four biometrics retained; screenshot and AX readback captured |
| Repository gates | SSOT, documentation, architecture, medication-write boundaries, legacy safety, companion targets, hygiene, Plane workflow (15 tests/80 assertions) and whitespace passed |
| Build identity | DoseTap and DoseTapStaging Debug/Release all 0.4.19 (54); unsigned simulator build and signed generic iOS build passed; codesign deep/strict verification passed |
| Independent source review | iOS mapper/DTO/provenance, Studio consumers and tests reviewed; no blocking findings |

Local evidence: `.build/audits/2026-09-12-health-export-missingness/` in the
`DoseTap-health-export` worktree. Logs include `ios-red.log`, `ios-green.log`,
`ios-full.log`, `studio-fixtures.log`, `strict-bundle-validator.log`, version and
repository guards, `signed-artifact.json`, and `studio-native-health.png`/`.txt`.
The signed candidate is `/tmp/dosetap-health-export-signed-build/Build/Products/Debug-iphoneos/DoseTap.app`.
Xcode: 26.6 (17F113). No phone installation or live Health provider fetch was
performed; the archive contains synthetic records. Native evidence covers the
changed missing-value presentation, not full layout or accessibility acceptance.

Studio compatibility/contract commit: `8eb2bc1`; app repair commit: `0058aa7`.
[PR #42](https://github.com/Kxd395/DoseTap/pull/42) contains the reviewed change.
Hosted checks and main integration are pending in this committed snapshot; their
exact final readback is recorded in the PR and Plane closeout. Build 54 is a
validated signed candidate, not an accepted phone or release build.

## Remaining acceptance

DC-05 is only partially addressed. WHOOP availability, same-date episode selection and recovery-error status remain separate work. The exporter's existing primary-episode query policy still differs from the reviewed-window projection; broad chart/report adoption and source parity remain open. See the [preceding review](2026-09-12-plane-closeout-review.md) for the source findings and corrected query-scope description.

Preserve these gates on their existing Plane owners:

- Provider revision/deletion reconciliation, durable provenance, permission-versus-query-readiness wording, conflicts, incomplete naps and broader reader/snapshot consistency.
- DC-06 wake semantics; same-date session ambiguity, defaults, wider format coverage, legacy CSV and typed unknown-event consumer parity. Scheduled exports still omit provider enrichment.
- Actual-record phone Settings export through Files/share to Studio; background scheduling/expiration, HealthKit permission/data changes and travel/DST parity.
- Whole-project CRUD, clear-all, content-equal restore, concurrent changes, legacy/staging paths and failed drafts across process termination. This archive is not a complete backup.
- DOSETAP-39's separate migration dependency-ID coverage and live generic event-list/count reproduction questions, related to DOSETAP-42/45, are unchanged.
- VoiceOver/full accessibility, privacy/security, prior credential-review gates, release performance and owner/release acceptance. Medication/alarm reliability and the historical unexpected-dose investigation retain their separate owners.

The next acceptance step after validated integration is an owner-authorized real-record Health export comparison. Synthetic fixtures cannot establish phone/provider correctness or close DOSETAP-13/56/39.
