# Daytime check-in access — DOSETAP-58

The September 30 plan called for one optional daytime observation alongside the
existing morning and pre-sleep workflow. The implemented entry point was under
History, while reminder setup was separately under Settings. This increment makes
that existing feature accessible from Tonight without changing its instrument,
ledger, prompt schedule or nighttime session rules.

Tonight now provides Record now, Review check-ins and Daytime reminder before the
nightly workflow. The card remains available when a prior night requires review
and after morning closeout. The existing editor starts unanswered; Cancel records
nothing. Only its successful repository-save callback shows a recording timestamp
on Tonight. The history page also links directly to reminder setup. Reminder
configuration still requires explicit Save reminder; opening the route does not
opt in. No prior rating is displayed on the card before another observation.

Implementation checkout: `feat/sleep-chart-inspection`, based on `d9abf41`.
The preserved `/Volumes/Developer/projects/DoseTap` checkout was not edited.
`DoseTap-main` was fetched and remained clean and aligned with `origin/main`.
Phone/staging Debug and Release configurations use `0.4.19 (99)`.

Validation completed during implementation:

- SwiftPM build passed; 1,191 XCTest cases and 43 Swift Testing cases passed.
- Generic iOS Simulator build passed with signing disabled.
- Plane workflow: 15 tests, 80 assertions passed.
- SSOT, documentation, architecture, dose-state and legacy-safety guards passed.
- App version check passed in all four phone/staging configurations.
- `git diff --check` passed.

The existing independent-observation UI journey now enters from Tonight and
checks unanswered entry, cancellation, committed-save feedback, direct review,
restart persistence and existing trend inspection. Its largest-text variant
exercises the same flow. The first invocation selected the app-only scheme and
ran no tests; the corrected invocation uses `DT_SCHEME=DoseTapUITests`.
The first executed run failed in test navigation: its full-screen swipe helper
overshot a trend filter, and it expected the offscreen rating to exist before
scrolling at largest text. The helper now uses shorter drags, reveals offscreen
controls before assertions and retains the same save/restart/trend assertions.
The corrected normal-text journey passed in 73.403 seconds and the largest-text
journey passed in 76.611 seconds (2 tests, zero failures), retained in
`/tmp/dosetap-daytime-access-ui-final.xcresult`. Both new reminder routes were
also opened through the simulator UI without changing their configuration.
Earlier failed
artifacts remain under the same evidence prefix and are not counted as passes.

The signed device build passed deep/strict signature verification and was
installed without uninstall/reset on Kevin Cell 1996, iPhone 15 Pro Max
(`00008130-00121861360A001C`). Independent app inventory changed from build 98
to `0.4.19 (99)`, and launch returned process 86672 on CoreDevice
`34BDEAB4-D443-547A-93E3-16D314C538BD`. iPhone Mirroring reported a connection
timeout due to phone use and requested the phone be locked; no phone-screen or
owner-use acceptance is claimed from installation or launch.

Evidence logs use `/tmp/dosetap-daytime-access-*`. Owner usability,
actual reminder delivery/actions, Focus and lock-screen privacy,
background renewal, known-sleep suppression and VoiceOver remain separate gates.
Existing iPad/report/provider/privacy/instrument-authorization/release gates on
DOSETAP-58 are retained. A local build or simulator pass does not close them.
