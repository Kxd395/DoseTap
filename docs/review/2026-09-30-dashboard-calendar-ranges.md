# Dashboard calendar-range implementation

Status: Implementation candidate; signed-device, owner and release acceptance remain open
Date: 2026-09-30
Tracker: DOSETAP-45; related test navigation repair DOSETAP-80
Baseline: main `db209547540715f7318e4562b71770e582bead64`
Candidate versions: iPhone 0.4.19 (87), separate iPad Dashboard 0.1.0 (10)

## Delivered behavior

The shared [calendar contract](../SSOT/contracts/dashboard-calendar-ranges.md) replaces the phone's 180/365-day approximations and the iPad's independently labeled 180-day six-month range. Both use Gregorian calendar months for 6M/1Y, civil days for 7D/14D/30D/90D, an explicit timezone and the existing 18:00 treatment-night anchor. At September 30 after rollover, six months includes April 1–September 30; the former 180-date filter began April 4. The preceding period is adjacent and nonoverlapping.

Phone refresh freezes its instant, timezone and selected range. The finished-night streak uses that same reporting anchor. iPad membership is frozen to the received report's capture time. Dose rows, questionnaire rows and diary selection consume the same core window. Malformed/future keys are excluded; filtering retains eligible source rows without collapsing their identities. Unsupported era/year bounds are rejected.

The phone shows its exact treatment-date span and timezone. Apple Health query metadata shows the requested interval/as-of time and its bounded number of treatment nights. The query and summary grouping receive the captured Gregorian calendar. If a leap-year preceding period exceeds 730 nights, the omitted beginning is disclosed; changing range labels the prior query as pending refresh. WHOOP's 30-day limit remains explicit. Query bounds do not establish complete measured sleep data.

This is the reporting-range portion of roadmap stage 1. Stable session/provider episode associations, provider snapshot retention, the broader metric-state contract, 28-day/custom/since-visit periods and subsequent dashboard stages remain separate work. Medication records, timing windows, alarms and provider sleep calculations are not changed by range membership.

## Regression and native evidence

- New domain cases cover calendar-month ends, leap years, adjacent preceding periods, spring/fall DST, exact rollover, explicit timezones, strict date keys, future keys, duplicate-row preservation, phone/report membership and invalid era bounds.
- The old phone implementation failed five calendar/parity assertions. A separate clock-advance regression reproduced the streak changing from two to three finished nights without a report refresh; the corrected frozen anchor keeps two.
- Full core suite: 879 XCTest plus 43 Swift Testing tests passed. The shared calculation suite also passed with full-suite runs under UTC and America/New_York.
- Phone: 26 dashboard audit plus 28 HealthKit provider tests passed on iPhone 17 Pro, iOS 26.5. All three affected native UI journeys passed: six-month coverage, largest-text range menu and Night Mode selection/readability. Normal and largest-text screenshots were inspected.
- Generic iOS Simulator build passed. All four shipping/staging Debug/Release version configurations resolve to 0.4.19 (87).
- iPad: all nine model tests and all four native UI journeys passed, including normal and largest-text reporting and provider inspection. Final normal-size and largest-text screenshots were inspected; the requested Wake & sleepiness section and diary outcome are visible.
- Plane workflow (15 tests/80 assertions), SSOT, documentation lint, architecture boundaries, dose-write guard and whitespace checks passed.

Evidence is retained under `.build/calendar-evidence/` in the reviewed feature worktree. Logs include `core-full.log`, `core-utc.log`, `core-new-york.log`, `phone-range-red.log`, `streak-red.log`, `phone-calendar.log`, `phone-calendar-ui.log`, `final-ios-build.log` and `ipad-calendar-fixed.log`. Result bundles contain synthetic test records and screenshots. No real phone installation or owner acceptance is inferred from simulator evidence.

## iPad test navigation repair

The first native run reproduced DOSETAP-80: a partially clipped Wake & sleepiness sidebar row accepted a tap while a different section was selected. The helper now reveals the entire row in either scroll direction and requires the requested navigation title before continuing. Failure retains a screenshot and accessibility hierarchy. Original diary metric and Connection assertions remain intact. The range picker's accessibility modifier ordering also now matches the phone so normal-size segments expose the full range names.

## Open acceptance

The calendar increment requires protected PR integration and owner review on actual reports. Signed phone/iPad installation, live historical Apple Health coverage/performance, WHOOP production validation, VoiceOver, privacy/security and release acceptance remain open. Existing DOSETAP-45 gates are preserved. A saved iPad report lacks an original source timezone in its current envelope, so its explicitly displayed viewing timezone controls membership; equal phone/iPad membership requires equal evaluation instant and timezone.
