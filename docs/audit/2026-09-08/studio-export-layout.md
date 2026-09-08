# Studio export layout update

Date: September 8, 2026. Baseline: `c7cbccc` on `fix/locked-dose2-system-alarm` in `DoseTap-main`.
Plane: DOSETAP-45 and DOSETAP-13, both In Progress. Local preview only; existing integration HOLD remains.

## Changes

- Export actions use an adaptive grid instead of one unbroken row. Save results appear beneath the actions.
- Archive metadata and availability cards also adapt to the available width.
- "Source iPhone build" replaces the ambiguous "App Version" label. Adjacent text explains that this is imported archive provenance, not the running Studio build or the current phone installation.
- Export text states that redaction applies to generated reports; copying the imported bundle preserves its original data. No export transformation or encryption behavior changed.

The prior clipped action row was reproduced in the native app. Native verification of the updated app used both a fitted full window and Window > Move & Resize > Left. At half-screen width all seven actions, the source-build label and save-status text were visible without horizontal clipping. General accessibility, other screens and arbitrary display sizes remain unverified.

## Local preview

Opened `macos/DoseTapStudio/.build/acceptance/DoseTapStudioExportPreview.app`, displayed as **DoseTap Studio Export Preview**, with isolated bundle identifier `com.dosetap.studio.export.preview` and local preview build `20260908.2`. Its binary matches the tested SwiftPM executable. This ignored QA bundle is not a signed/notarized production installer. Existing app copies and phone data were not replaced; no security protections were bypassed.

The preview contains only the synthetic one-night iOS export described in [build-23 acceptance](build23-acceptance.md): 2 events, 1 session and 28 inventory doses. Its source build remains 0.4.19 (22). The iPhone candidate remains 0.4.19 (23); no iPhone app code changed in this pass.

## Checks

- Studio: 68 tests passed, zero failures/skips. Command: `swift test --package-path macos/DoseTapStudio --scratch-path /tmp/dosetap-report-studio-build -q` with `DOSETAP_STUDIO_PREVIEW`, `DOSETAP_EXPORT_LAYOUT_PREVIEW` and `DOSETAP_IOS_EXPORT_FIXTURE` enabled. Log: `/tmp/dosetap-export-layout-tests.log`.
- New optional layout test renders the imported Export view at 640 and 1000 points. Offscreen AppKit snapshots have native-control rendering limitations, so image generation is not treated as a no-clipping assertion. Actual native screenshots and interaction supplied that evidence for the tested window sizes.
- At half-screen width, native Save Timing Comparison CSV displayed Saved confirmation for `/tmp/dosetap-ios-roundtrip/timing-layout-20260908.csv` and its `timing-layout-redacted-20260908.csv` counterpart.
- Ruby CSV readback verified one row per file, Natural wake, Day off and sleepiness zero. The normal file retained the food note; the redacted file left food notes and the exact food timestamp empty.
- Core build/tests passed: 655 XCTest plus 43 Swift Testing cases. Log: `/tmp/dosetap-export-layout-core.log`.
- Generic unsigned iOS Simulator build passed. Log: `/tmp/dosetap-export-layout-ios.log`.
- Plane workflow, SSOT, Studio export, questionnaire export, app version, document lint, plist syntax and `git diff --check` passed.

## Remaining gates and rollback

No push, main merge or phone installation. Signed-device medication/notification acceptance, owner-approved real archives, full final-revision UI checks, providers/background delivery, restore, security/credential and protected hosted checks, privacy and release approval remain open as listed in [integration readiness](../2026-09-05/integration-readiness.md). Legacy composite-score validity remains unvalidated.

Two unrelated Xcode project/scheme reorder diffs are preserved and excluded. This update is UI/documentation only and performs no data migration. The local preview can be closed without changing the phone app or existing exports; its isolated bundle can be removed later without removing other Studio copies.
