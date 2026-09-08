# Compact Tonight and History insights

Date: 2026-09-07, America/New_York
Tracker: DOSETAP-43, In Progress
Checkout: DoseTap-main, fix/locked-dose2-system-alarm

The owner supplied phone screenshots showing a tall two-row History summary and a Tonight page with slight vertical overflow. This follows the earlier DOSETAP-43 work merged through PR #7; that evidence remains in `docs/audit/2026-09-04/computer-smoke.md`.

## Changes

- History uses four equal-width metric columns at standard text sizes. Labels wrap; detailed definitions keep two columns, and accessibility text uses one column.
- Tonight no longer adds a 100-point spacer above the tab bar. ContentView already reserves the tab bar's safe area. A 12-point content inset remains.
- Cards use a single horizontal inset. Header, pre-sleep and weekly-summary spacing is smaller. The previous-check-in banner has a shorter title and separate accessible Finish and dismiss controls.
- Scrolling is size-dependent on iOS 16.4 and later, not disabled. Larger text, extra records and warnings can still extend the page. Dose controls, Quick Log touch targets, medication timing and storage behavior are unchanged.

## Verification

- Before the layout change, the new populated Tonight regression failed: a swipe moved the heading by about 99 points. After the change, the same test passed without movement and confirmed all four History metrics share a row.
- The fixture includes a prior-night reminder and seven synthetic weekly summaries. Weekly numbers are display-only; test initialization clears only the simulator's test night. The fixture is excluded from physical-device and Release builds.
- Standard portrait screenshots were inspected on the iPhone 17 Pro simulator, iOS 26.5. The weekly card fits above the tab bar and History labels remain readable.
- Core build/tests passed: 646 XCTest tests and 43 Swift Testing checks. Plane, SSOT, architecture, dose-write and whitespace checks passed. Both app targets and configurations report 0.4.19 (21).
- The unsigned app build and 20 home-state/analytics tests passed. The Dose 2 confirmation/cancel/background/restart journey passed on the updated layout.
- The initial large-text reflow check passed. A stricter screenshot check verified the weekly card's bottom is reachable. An added History scroll-to-last assertion overscrolled to Recent Sessions and failed; its video confirmed the test was no longer looking at the metrics. That extra assertion was removed, leaving the bounded first-metric reflow check. A subsequent runner attempt terminated before starting tests; it is not an app test result.
- The final bounded large-text retry passed on iPhone 17 Pro / iOS 26.5, including reaching the weekly card's bottom and stacking History metrics. Logs: `/tmp/dosetap-compact-large-retry.log`, `/tmp/dosetap-compact-ui-final.log`, `/tmp/dosetap-compact-app.log`. Screenshots and diagnostic video frames are in `/tmp/dosetap-compact-proof.4CmkJa/`. Computer-use inspection of the original app succeeded; later computer-use observations timed out, so updated visual evidence comes from the simulator test screenshots.

## Open gates

Owner review on the phone, VoiceOver, smaller-phone/iPad/landscape coverage and signed-device notification acceptance remain open. Largest-text screenshots still show awkward wrapping in the existing Wake by and weekly heading, so the bounded reflow check is not full accessibility acceptance. The unrelated integration HOLD still applies. No phone installation, owner medication correction, push or merge was performed by this change.
