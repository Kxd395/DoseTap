# Durable quick-log and general-medication delivery

Date: 2026-09-12. Tracking: DOSETAP-3 and DOSETAP-39. App: **0.4.19 (51)**.
Baseline: main `4de858dbc8beaa1f5c55fda4ec44003ab1008a6d` (audit PR #37).
Implementation: `fix/durable-quick-logging`; final review/integration evidence is in the exact Plane workpads and PR.

## What changed

This repairs the create/write portion of [audit finding DC-01](../audit/2026-09-12/collection-store-export-audit.md). Quick logs, including bathroom entries, publish the event and success haptic/cooldown only after SQLite commits. Creating a new active session and its first event is one transaction. Explicit final wake and both finalizing projections also commit together. Failed inserts, projection updates and commits cannot leave a successful-looking event or an empty new session.

A failed quick tap retains its original occurrence and event ID in the current app process. Retry is explicit and bound to the same session; a changed session requires discarding the draft and reviewing its time in History. Another quick tap cannot silently replace a pending failed entry. This is not a disk-backed draft or a promise to recover an unsaved entry after process termination. Manual Add retains its selections and stays open on failure. Siri, deep links and Flic return failure instead of their previous success acknowledgement. Medication vocabulary remains excluded from the quick-log route.

General-medication logging now throws on write failure and returns a separate duplicate-review result. The medication picker retains explicit Add Anyway consent, removes only committed entries from its pending batch, and shows saved/unsaved counts on failure. Retry processes the remaining entries without replaying the saved prefix. A newly detected duplicate remains in the draft while it is reviewed; cancelling that review does not silently lose it. The sheet reports completion only after every entry commits. Category rows now have a full-width 44-point tap target, fixing an empty-space tap that did not expand the category during native validation.

No SQL migration, export format change, provider calculation change or reinterpretation of old records is included. General-medication rows do not drive Dose 1/2, skipped outcomes, or alarms. The code still uses Views → SessionRepository → EventStorage → SQLite.

## Validation and evidence limits

- Core: 710 XCTest plus 43 Swift Testing cases passed.
- Final full iOS app run: **460 tests passed**, after a 78-test targeted repository pass. The earlier full run had 459 tests before the additional stale-session retry regression.
- New regression coverage exercises SQLite insert rejection, commit rejection, final-wake projection rollback with an unchanged Dose 1, retry with the original occurrence, cooldown after success, and confirmed general-medication duplicates after failure.
- **Two native simulator journeys passed individually**: largest-text quick-log failure/retry, and a two-entry medication batch with explicit duplicate consent and a rejected second write. Native screenshots were inspected. The medication harness also needed to wait for the newly added row before tapping a moving control; the final rerun passed. Screenshots/logs are retained at `.build/audits/2026-09-12-durable-logs` in the shipping checkout.
- The initial unsigned UI runner failed to launch before tests began. Local ad-hoc simulator signing and explicitly waiting for simulator boot readiness allowed it to launch. The first medication journey then exposed the category hit-target issue; that was repaired rather than treating the earlier run as a pass.
- Signed iPhone build succeeded and passed `codesign --verify --deep --strict`. The installable artifact is retained at `.build/deliveries/0.4.19-51/DoseTap.app` in the shipping checkout; it was **not installed on a phone** in this run. Simulator content size read back as normal `large` after the accessibility journey.
- All four app/staging Debug/Release configurations identify 0.4.19 (51). Required version, SSOT/documentation, architecture, dose-write, legacy safety, Plane and whitespace guards are recorded in closeout.

## Remaining gates and next repair

Signed-phone install/save/reopen, real Siri/Flic operation, VoiceOver, privacy and release acceptance remain open. Largest-text simulator interaction is not VoiceOver or phone acceptance. No owner database or live provider data was read in this slice.

DC-01 is not a claim that every CRUD operation now fails closed: sleep-event deletion/time/note edits, undo retention, other legacy session lifecycle helpers, staging imports, and query-error handling need separate review. Manual-entry treatment-night selection and durable partial drafts are also separate work. Existing Dose 1/2 transaction, alarm and reminder acceptance gates remain unchanged.

The audit's DC-02 through DC-12 export/analysis findings remain open. The next engineering slice should preserve stored export identities and medication metadata and remove silent inventory truncation, with source-to-export count/ID checks. The Settings bundle remains a reporting archive, not a full backup or a proof of whole-project split-brain elimination.
