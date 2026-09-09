# Sleep boundary evidence, first correction

Date: 2026-09-09
Scope: DOSETAP-56 first implementation slice; DOSETAP-57 remains planned.
Baseline: `ced7ab13dc68d81a01b65f88ab5cfce86e43360a`, shipping checkout `DoseTap-main`.
Candidate: 0.4.19 (33).

## Implemented

- Adopted the supplied v2 timing review as revision 1.2 in `docs/plans/2026-09-09-sleep-timing-calculation-addendum.md`. Preserved both supplied originals. Added reviewed-window requirements, endpoint rules, per-metric reasons, correction invalidation and a bounded delivery order.
- The primary-episode helper now uses the last asleep end for its final-wake estimate, retaining the selected observation end separately. A basis field distinguishes contiguous sleep-to-awake evidence from a last-sleep-end fallback.
- Unknown HealthKit category values remain unclassified and retain their raw value in adapter segments. Unspecified-asleep remains sleep. Unknown overlapping observations exclude that slice from classified coverage. This conservative handling is not the future full source-selection policy.
- Unknown and in-bed-only observations no longer become awake chart bands. Existing sleep-stage bands and quick logs remain available.
- iOS Studio bundles carry optional observation-end, final-wake-basis and derivation-version fields. Studio decodes and re-encodes them; older archives leave them absent. This does not add a new clinician report or claim full archive restoration.

## Validation

All fixtures are synthetic, not owner sleep observations. Local commands ran from the shipping checkout with the candidate changes and the two preserved unrelated Xcode edits.

- Red regression: `HealthKitProviderTests` reproduced two defects with three failed assertions. A 20-minute trailing awake sample moved final wake 20 minutes later; category 999 became 60 minutes of sleep. `/tmp/dosetap56-red.xcresult`.
- `swift build -q` and `swift test -q`: passed, 655 XCTest cases plus 43 Swift Testing cases. `/tmp/dosetap56-final-core.log`.
- `xcodebuild test`, DoseTap scheme, iPhone 17 Pro Max / iOS 26.5, `HealthKitProviderTests` and `DashboardAnalyticsAuditTests`: 37 passed. Includes contiguous/gapped/in-bed terminal evidence, unknown overlap, reorder/repeat inputs, valid unspecified sleep, DST and export-field round trips. `/tmp/dosetap56-final.xcresult`.
- `swift test --package-path macos/DoseTapStudio`: 69 executed, 66 passed, three optional fixture/visual tests skipped, zero failures. The new boundary-metadata and old-archive compatibility test passed. `/tmp/dosetap56-studio.log`.
- `xcodebuild test`, DoseTapUITests scheme, same simulator, `testTimelineReviewMetricsAndCapture`: one passed. Review/capture attachments were inspected for rendering. The fixture disables Apple Health and supplies display-only metrics, so this is navigation/capture evidence, not live provider-stage or clinical-record parity. `/tmp/dosetap56-ui.xcresult`.
- Generic iOS Simulator build with signing disabled: passed. Existing unrelated compiler warnings remain. `/tmp/dosetap56-build.log`.
- Plane workflow (10 tests / 64 assertions), documentation lint, SSOT, architecture, dose-state writes, legacy safety paths, app version and `git diff --check`: passed.

Targeted command form: `xcodebuild test -project ios/DoseTap.xcodeproj -scheme DoseTap -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -parallel-testing-enabled NO -only-testing:DoseTapTests/HealthKitProviderTests -only-testing:DoseTapTests/DashboardAnalyticsAuditTests CODE_SIGNING_ALLOWED=NO`. UI command uses the DoseTapUITests scheme and the exact UI selector above.

## Remaining acceptance

DOSETAP-56 remains In Progress. The largest-cluster selector, its existing duration/gap thresholds, raw wake count and primary-episode biometric range are unchanged. Reviewed treatment-night aggregation, overlapping-sample queries/clipping, full raw sample identity/source revisions, conflict selection, read-state wording and complete per-metric missingness remain open. Do not label this slice as completion of those requirements.

DOSETAP-57 remains Todo: shared dose-to-sleep/return calculator, associated awakening episodes/counts, marker detail, same-night Timeline/History/dashboard/export/Studio parity and correction invalidation remain to implement. The synthetic 02:40 / 02:48 / 03:02 example still belongs to that work.

Signed-phone import, provider-stage rendering, comparison with the owner's Apple Health data, VoiceOver and owner-observed acceptance remain open. No phone installation is proved by a simulator build. Medication, alarm, persistence/restart and release gates remain independent.

## Preservation and tracking

The existing Xcode project reordering and UI-test scheme edits were excluded. Reversing only the candidate's 32-to-33 build bump yields the original unrelated-diff SHA-256 `ddeb26bea1da005efc68bfe3039d31e83c9e91b95d5e6f7c23d8eb5f4a78b81a`. The preserved feature checkout and retained historical branches were not cleaned up or committed.

Exact Plane preflight read DOSETAP-56/57 as Todo. DOSETAP-56 start was applied and read back as In Progress. Both descriptions now include the complete adopted addendum, verified by readback; DOSETAP-57 remains Todo. The structured DOSETAP-56 workpad carries current validation, Git state and open gates.
