# Computer-use smoke and layout repair

Status: Point-in-time engineering evidence; release gates remain open
Date: 2026-09-04, America/New_York
Checkout: `/Volumes/Developer/projects/DoseTap-main`
Code commit: `d3b00ef50b9da046c0a76511e363227f8172e09e` (also includes `585ab68801d844adda831d49bbe71b56a77e73b9`)
Destination: iPhone 17 simulator, iOS 26.5, `E024A428-1500-4CB6-B56B-0E5A3458B690`
Tracker: DOSETAP-41, DOSETAP-42, DOSETAP-43, DOSETAP-44

The owner requested a simulator test mode, computer-use smoke test, and layout/design repairs. Testing used the Debug simulator fixture and synthetic medication records. Normal restart checks omitted the fixture flag so saved records and exceptions were not reseeded. The preserved source checkout was not used as the shipping authority.

## Findings repaired

1. Cold launch with an expired session crashed in `_dispatch_once_wait`: repository initialization performed rollover, alarm cancellation looked up `SessionRepository.shared`, and initialization reentered itself. Cancellation now receives the closing session identity explicitly.
2. A separate blank launch was sampled in synchronous HealthKit status XPC on the main thread. The status lookup now runs off the main actor. The app subsequently drew Tonight and accepted navigation while provider initialization remained asynchronous.
3. A session spanning the 18:00 grouping boundary changed its displayed night after Dose 2. Reload, time-change handling, and writes now preserve the active session's stored date; wall-clock grouping resumes after closure. A deterministic repository regression covers reload, recording, and reconstruction.
4. The floating capture button overlapped Tonight's theme control and other screen headers. Capture now occupies each screen's header or native toolbar. Tonight's status and dose action precede planning cards, and header controls have independent space.
5. The warning sheet now separates its dated summary, explicit dose-recording action, and date-only schedule actions. Wake editing uses a focused form with a visible time picker and Save action.
6. Completed dose state no longer displays a stale wake-deadline badge. Screen capture uses rendered view hierarchy rather than a blank SwiftUI backing layer; its preview fits the available width and scrolls vertically.

## Computer-use observations

| Flow | Observed result |
| --- | --- |
| Launch after repairs | Tonight rendered and navigation responded |
| Warning Cancel | Returned to a pending Dose 2 action |
| Dated wake edit | Changed 7:00 AM to 8:00 AM; saving left Dose 2 pending |
| Wake edit readback and normal restart | Reopened warning displayed 8:00 AM before and after restart |
| Nonworking exception | Dismissed without recording; survived normal restart and suppressed the warning on the later explicit recording action |
| Explicit warning continuation | Recorded the synthetic Dose 2; active night stayed unchanged after the identity fix |
| Tonight, Timeline, History, Dashboard, Settings | All loaded; review screens reported the same roughly three-hour interval, with one completed record and no missing or duplicate nights in Dashboard |
| Completed state | Obsolete wake-deadline badge absent |
| Page capture | Local preview opened, contained the Settings page, and fit the preview width; no external sharing or Photos permission flow was exercised |

Computer use initially exposed iOS accessibility nodes. After XCTest, Simulator stopped exposing its iOS subtree, so subsequent interactions used observed screenshot coordinates. This does not constitute VoiceOver acceptance.

## Automated validation

- `swift build -q` and `swift test -q`: passed, 628 XCTest plus 43 Swift Testing cases. DoseCore did not change during the app-only follow-up fixes.
- `DT_SIMULATOR_NAME='iPhone 17' tools/dt-test all -derivedDataPath /tmp/dosetap-smoke-main-derived -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO`: passed, 287 iOS tests. Schedule-dependent tests now explicitly set and restore their schedule fixture instead of depending on simulator preferences.
- `DT_SCHEME=DoseTapUITests DT_SIMULATOR_NAME='iPhone 17' tools/dt-test all` with five explicit `-only-testing` selectors: passed, five tests. Coverage includes expired-session cold start/restart, continuation with stable night and no completed alarm badge, nonworking exception, all three saved target choices, and a visible wake-editor Save action that leaves Dose 2 pending.
- Simulator Debug builds, Plane workflow guard, SSOT/doc lint, app version check, architecture and dose-write guards, repository hygiene, and `git diff --check`: passed.

Local logs: `/tmp/dosetap-smoke-final-app-tests.log`, `/tmp/dosetap-smoke-final-ui-tests.log`, `/tmp/dosetap-smoke-core-test.log`. The initial launch crash is `~/Library/Logs/DiagnosticReports/DoseTap-2026-09-04-182210.ips`; the HealthKit stall sample is `/tmp/dosetap-smoke-launch-sample.txt`.

Computer-use screenshots were saved through Simulator's Save Screen control to the Desktop at `2026-09-04 at 18.42.25` (warning with saved 8 AM wake) and `2026-09-04 at 18.59.01` (corrected capture preview). Hosted checks, merge identity, and final tracker readback are recorded in the PR and exact Plane workpads.

## Remaining acceptance

Signed-device medication/notification/background behavior, owner design review, VoiceOver and larger text sizes, timezone travel, retrospective historical-data acceptance, provider authorization/data behavior, and full restore/release gates remain separate. This run did not authorize or prove a release, credential rotation, or external data transmission. The existing HealthKit read-authorization semantics review remains DOSETAP-10; moving a blocking call does not resolve that separate issue.
