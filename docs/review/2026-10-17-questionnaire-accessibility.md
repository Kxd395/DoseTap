# Questionnaire accessibility and morning completion — build 108

Status: Product implementation, independent source review, required questionnaire simulator checks, signed installation and launch verified. Physical accessibility, owner usability and integration/release acceptance remain open.
Date: 2026-10-17
Tracker: [DOSETAP-81](http://plane.localhost:3301/dark-water-drones/browse/DOSETAP-81/), In Progress.

## Source and scope

Implementation checkout: `/Volumes/Developer/projects/_DoseTap_Active/DoseTap-chart-inspection`, branch `feat/sleep-chart-inspection`. The preserved legacy checkout and `DoseTap-main` were not modified. This is local branch delivery, not a merge or release claim.

- Review baseline: `71d3d60f36934ba2340965f5f57d4ac9abc17f46`.
- Main implementation: `078c2c27bbac92e849996e3baff07727b51f483a`.
- Final product source, including redundant-heading removal: `38dfb54d503c9021a00319d0b7500d29d6e01110`.
- App version: `0.4.19 (108)` in all four app build configurations.
- SwiftUI Pro: repository-local version 2.0.0, pinned upstream `ce32af1693b9e78a7d22ff48001c97a304d32063`. See the [integration record](2026-10-17-swiftui-agent-skill.md) and [original findings](2026-10-17-swiftui-pro-app-review.md).

The exact Plane item was preflighted and started before implementation. SSOT was updated before behavior changes. The work addresses SUI-01, SUI-02, SUI-03 and the morning completion proposal; it does not claim an exhaustive application audit.

## Delivered behavior

- Shared single-select, multiselect, stress and grogginess choices expose selected traits and values, plus a visible outlined check badge. The badge supplies its own adaptive foreground/background, so it does not inherit a low-contrast tile foreground.
- Those controls use a single column at accessibility text sizes. Stress text adapts to Light/Dark and Increased Contrast. No questionnaire answers, scales or persisted option values changed.
- Mental clarity, readiness, driving confidence and daytime sleepiness sliders identify their question and announce a score out of five. The two clinical questions have visible labels; the existing mental-clarity/readiness card titles are not repeated.
- Bedtime page changes use a nil animation when either the app preference or system Reduce Motion is enabled. The same page/draft state owner remains alive. Child-card expansion animations are outside this paging fix.
- Morning completion lives once in the bottom safe area, above the keyboard. Save errors and reminder warnings have a bounded, independently scrollable status area. The existing submission coordinator retains failure/retry and saved-with-warning handling.
- History retains Review History Answers and its separate explicit confirmation. Close/Cancel does not submit.

The synthetic SQL-save failure fixture is Debug-and-simulator-only, requires UI-test arguments and a valid per-run UUID, and creates a connection-local temporary trigger in the isolated test database. It is excluded from the physical-device build.

## Independent review

Daybreak Blue reviewed immutable patches and frozen files against the baseline:

| Round | Patch SHA-256 | Result |
| --- | --- | --- |
| 1 | `d3f5039baa8a1878239f3e88ba1629ea436cd195561bb4dfb32cbf7fa4364faf` | P2 marker-contrast and P3 coverage findings; remediated. |
| 2 | `74da95aeb0f2a1ab93ee7458335291625baa8df5079973224b4dc85720756383` | No actionable source/SSOT findings. Runtime gates were still open. |
| 3 | `2a5038ce71d7cfce2798ffee07ce52f338d18092497e19ff1e819f7efa368a5d` | No actionable source/SSOT findings, including final warm-color contrast and visible-label polish. |

Independent SHA-256 comparison in `final-source-readback.json` confirms Round 3 matches all 13 current reviewed product, SSOT and rendered-test files; only the UI journey harness differs. Subsequent edits are confined to UI-test scrolling/assertions, committed as `90c8b286b91f5067deb96b5164c88f09ea93ce87`, `34a7fb859d0c40048528582817fa9f2c1ed93547` and `5807eafab7b75d34ca16ea9efe089b5412b5de97`. The second checks visibility after the last allowed drag and permits up to 50 drags when traversing directly to Notes at the largest text size. The final UI-test target compiled successfully with `xcodebuild build-for-testing`. A separate agent reviewed the test changes and identified a weakened exhaustion guard; it now fails unconditionally instead of accepting a clipped but nominally hittable control. A final bounded review of `5807eafab7b75d34ca16ea9efe089b5412b5de97` found no actionable issue: retained notes are read directly without requiring another scroll while the keyboard and status occupy the viewport. This proves retained draft text and an enabled retry control, not a successful retry or full post-failure field visibility.

## Validation and evidence

Raw local artifacts are under `.build/swiftui-questionnaire-fixes/`. Questionnaire screenshots and test data use synthetic simulator records. Device receipts contain installation/process metadata; no questionnaire record was read from the physical phone. A pass in one row does not imply another acceptance layer passed.

| Check | Result and artifact |
| --- | --- |
| SwiftPM core | 1,203 XCTest + 43 Swift Testing cases passed; `swift-test.log`. |
| Repository, alarm and UI regression | 100 tests passed; `regression.xcresult`. Includes transactional save/failure/retry and warning behavior. |
| Final rendered UI checks | 7 tests passed; `visual-final2.xcresult`. Four Light/Dark × Normal/Increased Contrast marker images exported and inspected in `visual-final-attachments/`. |
| Bedtime normal and largest text | 2 tests passed; `bedtime-system-final.xcresult`. Selection changes, Next/Back retention, setup navigation, save and reopen. |
| History questionnaires | 1 journey passed; `history-final.xcresult`. Cancel confirmation, confirmed save, restart, correction and unchanged medication records. |
| Morning at largest text | 1 test passed; `morning-ax-corrected.xcresult`. Selected traits, all four sliders, notes, keyboard clearance and successful save. |
| Morning at normal text | 1 test passed; `morning-normal-final.xcresult`. Final harness on iPhone 17 Pro; selection, all four sliders, notes, keyboard clearance and successful save. Initial and keyboard screenshots exported and inspected. |
| Morning forced-save failure at largest text | 1 test passed in 262.487 seconds; `morning-failure-final.xcresult`. Exact notes retained, retry enabled, completion above keyboard, status scroll verified. Keyboard/error/status screenshots exported and inspected in `morning-failure-final-attachments/`. |
| Repository checks | Plane workflow: 15 tests / 80 assertions; SSOT, version, documentation, architecture, dose-write, legacy-safety and whitespace checks passed. |
| Normal commit hooks | SwiftPM build, print policy, unsigned simulator app build and commit-size checks passed for both product commits. |
| Signed device build | `tools/dt-build device -jobs 2` passed; `codesign --verify --deep --strict` passed. This establishes a signed candidate only. |

For reproducibility, the test routes use `tools/dt-test all -parallel-testing-enabled NO` with exact test selectors. UI journeys use `DT_SCHEME=DoseTapUITests`; the rendered checks use the default DoseTap scheme. Destinations were iOS 26.5 iPhone 17 Pro (`21E15B3C-E6DD-4107-82B3-3AFF80BEB65C`) and iPhone 17 Pro Max (`59B53B2A-7736-488A-A6DD-838B0F7F648B`). Each UI case uses a fresh UUID database.

Earlier development results remain non-passes: interrupted `ui-round1/2/3` runs, the two initial rendering-harness compilation failures, and `morning-final` with two failed interactions. That morning harness accepted partly clipped controls as hittable; one switch tap reached the pinned completion button instead. The corrected helper checks usable bounds, excludes the error region and verifies the work switch actually turns on. The earlier `morning-final` process hung after reporting its two failures and was terminated (exit 143); its log remains failure evidence. In `morning-normal-failure-corrected.xcresult`, normal text passed in 143.545 seconds, while direct traversal to Notes at the largest text exhausted the 35-drag test limit. That bundle remains failed; the bounded traversal allowance was adjusted for the final failure-only rerun. The forced-failure case focuses on notes, keyboard clearance, retained draft, scrollable status and an enabled retry action; the two successful-save cases cover all four sliders. A shared Xcode build-database lock prevented `visual-final` from running; the serialized `visual-final2` run passed. The `morning-failure-complete` iteration reached the error, keyboard-clearance and scrollable-status assertions, then performed unnecessary scrolling before reading the retained note value. It was interrupted and terminated (exit 143), then superseded by the direct-value assertion in `5807eafab7b75d34ca16ea9efe089b5412b5de97`. No failed or interrupted run was reclassified as a pass.

## Recorded motion proof

The completed `system-motion-bedtime.mp4` was independently reviewed using AVFoundation frames requested every 50 ms and actual encoded presentation timestamps. No visible questionnaire slide/cross-fade was observed in the four captured Next/Back transitions:

| Settings during journey | Next first destination frame | Back first destination frame |
| --- | ---: | ---: |
| App ON, system ON, largest text | 106.313 s | 107.803 s |
| App OFF, system ON, normal text | 219.633 s | 221.185 s |

The recording has 93–212 ms gaps across content replacement, followed by dense samples after Next. This is bounded recorded evidence, not a claim that every display frame or every app animation was examined. Standard button press/release feedback remains visible. Full methods and frame evidence are in `motion-review/review.md`.

Simulator system Reduce Motion was read back as `1` during the journeys and restored to its original `0`; receipts are `system-motion-enabled.txt` and `system-motion-restored.txt`. No macOS settings were changed.

## Signed candidate and physical gate

Signed app: `.build/swiftui-questionnaire-fixes/signed108/DoseTap.app`, bundle `com.dosetap.ios`, version `0.4.19 (108)`. Executable SHA-256: `678e5e9ea2b71db1bed290de9910d22784450d3c5c12e2f1c9c2d97ca1da32c4`. The full receipt is `signed108-identity.json`.

The intended device is Kevin Cell 1996, iPhone 15 Pro Max. The initial developer-access attempt failed with CoreDevice 12040 / underlying 10003 while the phone was locked. After the user unlocked it, the preserved signed candidate was installed in place. Independent app readback verified bundle `com.dosetap.ios`, version `0.4.19`, build `108`; iOS launched process `86290`, and a subsequent process query confirmed it remained running. Receipts: `device-install108.log`, `phone-installed108.json`, `phone-launch108.json`, `phone-process108.json`. No uninstall, data reset or synthetic questionnaire entry was performed on the phone. This establishes installation and process launch, not physical questionnaire usability or accessibility acceptance.

## Tracker and remaining gates

DOSETAP-81 final delivery workpad `b3869e704252e845` was applied and independently verified as In Progress. Input: `.build/swiftui-questionnaire-fixes/final-closeout.json`. Implementation and local validation are delivered; named physical and release gates prevent Done. The completed repository-local skill installation is tracked separately in [DOSETAP-82](http://plane.localhost:3301/dark-water-drones/browse/DOSETAP-82/), Done, closeout `40756c3e1ea6dc43`.

Remaining gates: physical VoiceOver and Switch Control; owner-observed keyboard, usability and motion comfort; integration and release acceptance. Earlier notification/provider/privacy gates remain separate.

The existing inventory guard still fails on unchanged baseline paths in `EventStorage+DashboardSnapshot.swift` and `SettingsStudioExport.swift`. It is outside this questionnaire patch and remains a broader application/release concern. This report does not claim the entire app is release-ready.
