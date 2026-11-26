# Daytime reminder status — DOSETAP-58

The reminder service verified queued notification requests but exposed only the
end of its scheduling horizon. Its status was below all configuration controls.
This increment presents saved status first, including the earliest future
verified attempt, queue horizon and last-check time. Permission denial provides
an explicit iOS Settings shortcut. Status times name the device timezone, while
the routine retains its separately saved timezone.

Queue evidence is published only after request identity/time readback and the
final ledger write succeed. It is cleared at the start of reconciliation and on
cancellation, suppression and failure. Passing attempt times are not presented
as upcoming. Verification is not notification-delivery evidence.

Save is also in the navigation toolbar. The draft initializes once after a valid
ledger load and reconciliation completion. Busy or unreadable state disables
editing and saving. Retry can recover the draft; refresh preserves unsaved edits.
Opening the page does not opt into reminders or select a schedule for the owner.

Checkout: `feat/sleep-chart-inspection`, based on `427bf0b`. The preserved legacy
checkout was not edited. `DoseTap-main` was fetched and remained clean and aligned
with `origin/main`. All four phone/staging configurations use `0.4.19 (100)`.

Validation:

- New queue and unreadable-ledger tests were written first; missing-member
  compilation failures are retained in `/tmp/dosetap-reminder-status-red.log` and
  `/tmp/dosetap-reminder-draft-red.log`.
- All 17 `DaytimePromptServiceTests` passed, including next-attempt rollover,
  pause, denied permission, silent OS add failure, capacity limits, sleep,
  cancellation failure, source changes and corrupt-read recovery. Evidence:
  `/tmp/dosetap-reminder-status-service-verified.xcresult`.
- Core: 1,191 XCTest cases and 43 Swift Testing cases passed.
- Plane workflow: 15 tests / 80 assertions passed. Architecture and dose-write
  guards passed; app version checks passed for all four configurations.
- Final reminder UI journeys passed at normal and largest accessibility text
  sizes (15.199s and 31.609s; 2 tests, zero failures). Normal text verifies that
  refreshing saved status retains an unsaved enable choice, then restores the
  paused draft before Save. The initial draft test tapped the switch label
  instead of its child control; it was corrected without weakening assertions.
  Final evidence: `/tmp/dosetap-reminder-status-ui-release.xcresult`.
- Simulator visual inspection confirmed the top status section and toolbar Save;
  an empty row when no reminder was queued was removed before the final run.
- The signed build passed deep/strict signature verification. Installed without
  uninstall/reset on Kevin Cell 1996, iPhone 15 Pro Max. Independent inventory
  confirmed `0.4.19 (100)`, launch returned PID 92617 and a separate process list
  confirmed that PID. Evidence: `/tmp/dosetap-reminder-status-phone-*.json`.
- iPhone Mirroring showed “iPhone in Use” and requested locking the phone.
  Installation/launch evidence is not physical-screen or notification acceptance.

Physical delivery/actions, Focus and lock-screen privacy, background renewal,
quiet hours and known-sleep behavior still need device/owner acceptance. Existing
iPad/report/provider/privacy/instrument-authorization and release gates remain
open. No new reminder schedule or clinical observation was created on the phone.
