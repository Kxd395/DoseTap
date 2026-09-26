# Confirmed saved-preset administration capture

Date: 2026-09-25
Plane: DOSETAP-74, B3b bounded capture/history
Candidate: 0.4.19 (72)

## Delivered behavior

Settings → Saved medication presets → Log taken opens the selected immutable
prescription revision. Counts start from that saved plan but require explicit
actual-amount confirmation. Zero omits a component; at least one positive count
is required. Milligram totals use checked Decimal arithmetic. Now, Earlier,
Approximate and Time unknown are explicit choices; none is preselected. Earlier
and approximate show the calendar date and time. Unknown never invents a time.

Prior saved-preset administrations are reviewed across all dates, including
unknown times. Matches use preset identity or normalized entered ingredient and
release description; this is not clinical equivalence. The UI always explains
that legacy medication-picker entries are outside this review. A fresh read just
before writing invalidates acknowledgement when matching history changed. Read
failure removes stale candidates and blocks writing.

The first confirmation freezes the ID, payload and timestamps. A failed save
retains that command for Retry; Return to editing first checks whether the same
command committed before discarding it. Success produces a receipt. Taken records
show actual components, occurrence precision/original offset and recording time.
Revising a preset cannot alter an administration's embedded original revision.
Older revisions remain available for retrospective capture.

No SQL/export migration is needed: schema-5 bundle and existing dedicated Excel
sheets already retain exact snapshots, independent of treatment-night groups.
No nighttime dose, reminder, inventory or session is created. This does not enable
amphetamine estimates, PK curves, new regimen alarms or treatment recommendations.

## Validation record

Eight capture-model/repository tests cover explicit review/time, exact counts,
locale digits, all time choices, unknown/cross-midnight prior records, new-record
review invalidation, injected commit failure, frozen retry, uncertain-commit
readback and restart/export persistence. Core: 789 XCTest plus 43 Swift Testing
passed. Full native app suite before the final read-status refinement: 535 passed.
Final targeted capture rerun: eight passed after the read-status refinement.
Final native UI results are recorded below when completed.

Independent review identified indistinguishable amount accessibility labels and
stale review availability after save-time read failure. Both were corrected.
Native journeys cover preset creation, confirmation with unknown time, receipt,
app restart and saved administration. Normal text also covers later revisions.
The initial normal run passed; the largest-text run correctly refused an
unacknowledged prior record because the test skipped a virtualized off-screen
checkbox. The test now reviews it while scrolling. Save is disabled until
required acknowledgement, and the receipt resets to its top after a long form.
Model coverage of failure/retry is not native UI failure/retry acceptance.

## Remaining gates

- Signed-phone installation and owner create/revise/log/reopen/export acceptance.
- VoiceOver, privacy and release acceptance; largest text is not VoiceOver.
- Audited correction/reversal, individual retention controls, non-taken/uncertain
  outcomes, liquids/other units, named groups and complete B3 acceptance.
- Cross-ledger canonical medication identity and cross-process duplicate review.
- Separate DOSETAP-58 daytime observations/ESS licensing and DOSETAP-75 reviewed
  estimate profiles/independent alarms. No numerical model is enabled here.

The UI discloses that individual Edit/Undo/Delete is not yet available. Drafts are
retained only while the editor stays open. No signed-phone installation occurred
in this run. Exact final PR/main and Plane readback belong in the workpad.
