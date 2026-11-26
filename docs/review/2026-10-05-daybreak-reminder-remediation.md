# Daybreak review remediation: randomized daytime reminders

Status: Implementation and local validation evidence; physical acceptance remains open
Date: 2026-10-05, America/New_York
Plane authority: DOSETAP-58
Baseline: 429adc0, build 0.4.19 (102)
Candidate: build 0.4.19 (103), feat/sleep-chart-inspection
Checkout: /Volumes/Developer/projects/_DoseTap_Active/DoseTap-chart-inspection

## Repaired behavior

- New randomized choices and Later attempts enforce 7,200 seconds from all retained
  randomized attempts in the current schedule, including adjacent wake dates. New
  windows enumerate their minute grid deterministically; saved choices never redraw.
- Wake/work corrections suppress only future outstanding attempts and now compare
  work source identity as well as wake/work revisions. Due or past attempts retain
  their prior status and unknown-delivery meaning. Corrections do not resample windows.
- Original nonretrospective manual assessments reconcile before permission or sleep
  early returns. Permission, quiet-hours and known-sleep suppressions use a typed
  allowlist and can become responded; explicit skip, source/schedule-change, expiry
  and prior responses remain final for automatic window matching.
- Rejected mutations and stale Skip actions return before saving or canceling the
  notification queue. Verified attempts remain intact. Later uses one action-clock
  sample and validates the canonical fire instant before changing the ledger.
- Partial notification work is canceled on failure. One fresh reconciliation is
  permitted; persistent errors stop with no verified queue and visible retry guidance.
  Source conflicts and invalid/unreadable state never enter that automatic retry.
- A fall-back bedtime uses the next absolute occurrence after wake across both folds.
- The SSOT version marker now matches the build 103 candidate.

## Regression evidence

Before implementation, the new core cases produced 33 assertion failures in 15
selected tests. The iOS reminder-service cases produced 10 assertion failures in 21
selected tests. Logs: /tmp/dosetap103-core-red.log and
/tmp/dosetap103-service-red.log. An intermediate service compilation failure caused
by a tuple return in a Boolean filter was corrected; it is not counted as a pass.

The literal incomplete two-prompt payload embedded in DaytimePromptAnchorTests was
captured by compiling DaytimePrompt.swift from c5446a5 with the fixed schedule seed
00000000-0000-0000-0000-000000000035 and fractional wake 2026-10-05T09:00:00.123Z.
It contains windows 1 and 2 only. Decode, reconciliation and repeated encode/decode
preserve both occurrences byte-semantically without backfilling window 0.

First increment automated checks:

- swift build -q: passed; /tmp/dosetap103-core-build-final.log.
- swift test -q: 1,202 XCTest and 43 Swift Testing cases passed, zero failures;
  /tmp/dosetap103-core-final.log.
- TZ=UTC swift test -q: the same 1,202 plus 43 cases passed, zero failures;
  /tmp/dosetap103-core-utc-final.log.
- iPhone 17 Pro, iOS 26.5: DaytimePromptServiceTests and DaytimeCheckInStorageTests,
  49 tests passed, zero failures; /tmp/dosetap103-service-final.xcresult.
- Plane workflow: 15 tests, 80 assertions, zero failures. SSOT, documentation,
  architecture, dose-write, app-version and whitespace guards passed.

- Simulator UI: four journeys passed, zero failures: reminder settings at normal
  (15.505 seconds) and largest text (45.540 seconds), independent diary save/reopen
  (69.890 seconds) and largest-text trend (54.284 seconds); /tmp/dosetap103-ui.xcresult.
- Signed-device build: tools/dt-build device passed; codesign --verify --deep --strict
  passed and the product Info.plist reads 0.4.19 (103). Installation followed the
  clean final independent review recorded below.

The independent second Daybreak Blue review confirmed the original repairs but
found two medium follow-up defects: retained pre-fix cross-day collisions still queue,
and committed Later/Open actions can be misreported as rejected when OS reconciliation
fails. It also identified contradictory known-sleep recovery text in the contract.
The follow-up increment reproduces and repairs all three findings. Its core fixture
came from actual c5446a5 code and contains six saved prompts, including a 10:58/11:14
collision. Chronological reconciliation suppresses the later conflicting future
attempt with an explicit review reason; original times/identities and past statuses
remain intact. Typed action results distinguish rejection from committed actions
with unverified scheduling. Saved Later shows scheduling-failure/retry guidance;
saved Open still navigates after independently reading the original prompt back.
The known-sleep contract now explicitly describes suppression and future recovery.

Follow-up red evidence: one core test produced three assertion failures, and two iOS
service tests produced five assertion failures. Logs:
/tmp/dosetap103-followup-core-red.log and
/tmp/dosetap103-followup-service-red.log. The second core boundary was tightened from
12:00:01 to 10:58:01 so it explicitly verifies a past attempt constraining the next
future conflicting occurrence while preserving past records.

Follow-up validation: swift build -q passed; both default and UTC full suites passed
1,203 XCTest plus 43 Swift Testing cases, zero failures. The iOS service/storage run
passed 51 tests, zero failures. Evidence: /tmp/dosetap103-followup-core.log,
/tmp/dosetap103-followup-core-utc.log and
/tmp/dosetap103-followup-service.xcresult. Normal (15.370 seconds) and largest-text
(44.732 seconds) reminder journeys also passed on the final source:
/tmp/dosetap103-followup-ui.xcresult. The signed device rebuild passed and strict
codesign verification succeeded; /tmp/dosetap103-followup-device.log.

A third independent Daybreak Blue review returned "No actionable findings."
Task: dosetap-build103-daybreak-remediation-round3. It reassessed the original
findings, the two medium follow-ups and the known-sleep contract contradiction.
The reviewer independently read source, tests, contracts and red/green logs, and
confirmed that reviewed file hashes remained identical through commit c582743.
It did not rerun Xcode/SwiftPM or operate a simulator or physical phone.

After that clean review, the final signed product was installed without uninstall
or data reset on the verified iPhone 15 Pro Max (iPhone16,2, iOS 27.2).
The separate app inventory reads com.dosetap.ios, version 0.4.19, build 103:
/tmp/dosetap103-phone-after.json. Launch succeeded, and a separate process inventory
confirmed PID 93773 at the installed DoseTap.app executable:
/tmp/dosetap103-phone-launch.json and /tmp/dosetap103-phone-processes.json.
These receipts establish signed installation and launch only. The installed source
is c582743; the subsequent evidence-only documentation commit does not change it.

## Open acceptance

No owner reminder schedule has been enabled or selected. Real iPhone notification
receipt, Open/Later/Skip, background renewal, Focus/lock-screen privacy, quiet-hours,
known-sleep suppression, physical save/reopen, VoiceOver and owner usability remain
unverified. Signed installation and process inventory prove delivery and launch only.
Provider coverage, received iPad/report parity, privacy/content authorization, hosted
integration, merge and release approval remain separate open gates. DOSETAP-58 stays
In Progress until its full acceptance criteria are met.
