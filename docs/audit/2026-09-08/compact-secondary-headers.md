# Compact Timeline, Dashboard, and Settings headers

Status: implementation and simulator verification. Signed-device and owner acceptance remain open.

## Scope

DOSETAP-43. The owner reported that Timeline and Dashboard headers sat too low, then included Settings. Build 0.4.19 (24) uses inline titles on compact screens and removes Timeline's second 16-point top inset in both Live and Review. Regular-width title behavior is unchanged. This patch does not change dose actions, alarm behavior, stored records, exports, or analytics calculations.

## Evidence

- Before the fix, the new header regression failed: Settings reserved 106 points for its navigation header, exceeding the 64-point compact-header limit. Screenshots also showed Dashboard's expanded title and Timeline's extra gap. Baseline log: `/tmp/dosetap-header-baseline.log`.
- After the fix, the header regression, existing largest-text Tonight/History check, and Dashboard large-text/landscape check passed (3 tests). Log: `/tmp/dosetap-header-fixed.log`.
- The before/after screenshots for all three screens were visually inspected. Titles and toolbar actions remain legible; Dashboard and Settings no longer reserve an expanded title row. Timeline's first control moves up by the removed inset. Local attachment manifests: `/tmp/dosetap-header-before/manifest.json` and `/tmp/dosetap-header-after/manifest.json`.
- The unsigned DoseTap simulator build passed: `/tmp/dosetap-header-build.log`.
- Plane workflow, SSOT integrity, documentation lint, app-version checks, and whitespace checks passed. Debug and Release configurations for DoseTap and DoseTapStaging resolve to 0.4.19 (24).

The final regression run passed both standard-text and largest-accessibility-text header tests (2 tests, zero failures). It also checks the header-to-first-control gap. Log: `/tmp/dosetap-header-final-tests.log`. The built app's Info.plist was read back as 0.4.19 (24).

## Integration and remaining acceptance

The preceding update was merged through PR #8 at `f1e38c0ca6e0e71656235f3f06011a9b80a78b79` after protected CI checks passed. This header adjustment is a separate follow-up. Source integration is not release acceptance. Owner review on the signed phone, full accessibility acceptance, and the previously recorded security/provider/release gates remain open. No phone installation was performed for this change.

The pre-existing project-file ordering edits and UI-test scheme edits are preserved locally and excluded from this patch. Only the four app build-number settings are included from the project file.
