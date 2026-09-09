# Explicit caffeine answer choices

Date: 2026-09-08
Status: Implementation evidence; DOSETAP-51 acceptance remains open
Candidate: 0.4.19 (28)

The pre-sleep form now offers an explicit No caffeine today action. Clear answer
and deselecting the last source return the question to Not recorded. A text label
shows the current answer. This aligns the form with the missing-answer storage
repair in c9151ad and replaces the misleading instruction to leave the field blank
when no caffeine was consumed.

Scope: the earlier room-setup-only carry-forward and missing-answer storage
repairs are included in this branch. Substance time/amount bootstrap, optional
detail fields, legacy boolean adapters and caffeine unit migration are still open
under DOSETAP-51/52. No medication or Apple Health behavior changes in this slice.

Validation uses the iPhone 17 Pro iOS 26.5 simulator. The new UI test first failed
because the No caffeine today control did not exist. With the implementation, its
initial run passed, as did the supply/remembered-room-setup journey. The History
questionnaire journey failed while trying to reveal morning notes; its captured
accessibility snapshot was empty. There was no new DoseTap crash report. This
failed attempt is retained in `/tmp/dosetap-caffeine-choice-ui.xcresult` rather than
treated as a pass. The unchanged History journey passed on rerun (137.829 seconds),
as did the extended caffeine test (13.552 seconds), in
`/tmp/dosetap-caffeine-choice-retry.xcresult`.

The extended caffeine UI test also checks selecting and deselecting Coffee.
Screenshots of the new answer controls were inspected. Core validation passed:
655 XCTest and 43 Swift Testing cases. App and staging Debug/Release build settings
all report 0.4.19 (28). Repository guards passed. Simulator results are not signed
phone, accessibility, or owner acceptance.

Pre-existing Xcode project ordering and UI-test scheme edits remain excluded from
the changes being integrated. They were present during local tests. Hosted checks
validate the committed branch separately. Plane remains the work-status authority.
