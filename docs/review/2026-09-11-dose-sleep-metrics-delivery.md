# Read-only dose/sleep metrics delivery

Date: 2026-09-11. Plane: **DOSETAP-57**, with **DOSETAP-45** dashboard/data review and **DOSETAP-61** phone-install follow-up. App identity: **0.4.19 (46)**. This record separates source/runtime evidence from owner, provider, accessibility, privacy and release acceptance.

## Delivered scope

Wake & Next Day → saved reviewed night window → **Check Apple Health coverage** now shows:

- Dose 1 to initial sleep.
- Observed awakening to recorded Dose 2.
- Recorded Dose 2 to observed return to sleep.
- The whole observed Dose 2 awakening.

Each value uses the same freshly revalidated dose/window/provider snapshot. Available rows show elapsed time and both endpoints. Missing and conflicting rows explain why a value cannot be resolved. The view retains coverage, source and check time. Local changes and unsuccessful refreshes discard stale results. This action does not record doses, submit questionnaires, save preferences, or change alarms.

The synthetic example yields 10 minutes from Dose 1 to initial sleep, 8 minutes awake before Dose 2, 14 minutes after Dose 2 and 22 minutes for the whole awakening. A continuous asleep band across a dose is a conflict; it does not yield automatic zero. Initial onset requires an observed awake prefix; a later sleep block cannot replace an initial onset before Dose 1. Known pre-dose waiting can remain available when the eventual return is missing. Unknown/conflicting boundaries remain unresolved even when most of the night is covered.

No SQL migration, automatic backfill, new questionnaire fields, medication guidance, awakening counts, dashboard averages or new public export fields are included. WHOOP aggregate stage durations are not timestamped transitions and are not used here. Provider raw evidence remains with the existing point-in-time query; durable provider revision/deletion history and consumer/export parity remain separate work.

## Owner dashboard/data review

The [complete collected-data inventory and dashboard plan](2026-09-11-dashboard-and-collected-data-review.md) covers Apple Health/conditional WHOOP, pre-sleep and morning questionnaires, Wake & Next Day, independent pain and sleeping context, doses, bathroom and other quick logs, settings/preferences, supply, provenance and export limits. It is linked from `docs/README.md`.

The proposed primary comparison is **Sleep before work** versus **Sleep before a day off**, with Off→Work, Work→Work, Work→Off and Off→Off detail and explicit Unknown classification. It defines eligible versus usable counts, complete-night versus partial evidence, provider separation, actual-shift/timezone problems and synthetic expected means. These averages and the proposed in-app Data catalog are a plan, not implemented UI in build 46.

## Phone build 45

The owner reported **0.4.19 (44)**. The initial device query failed with CoreDevice 4000 / connection reset by peer. A retry connected and confirmed build 44. The previously reviewed signed build 45 artifact passed signature verification, was installed using `tools/dt-device install`, and a fresh `devicectl device info apps` query confirmed **com.dosetap.ios 0.4.19 (45)** at 08:25 Eastern on September 11. Build 46 has not replaced that phone install.

The requested check is in **morning check-in**: reuse only the saved foot pattern, choose a fresh actual level, complete/reopen the same treatment night from History, and confirm the independent back entry and saved reusable patterns stayed unchanged. If no back entry was present, confirm none was added. Do not fabricate symptoms for testing. The owner asked which questionnaire to use and was given these instructions. The owner subsequently confirmed that a morning-check-in correction remained saved after reopening the selected night and after closing/reopening the app in build 45. The owner also reported that other edits worked. This is owner-observed persistence evidence. Whether the saved foot pattern was reused versus an existing entry edited, and unchanged back/preferences, remain unconfirmed. Personal answer values and night identifiers belong in the local workpad rather than public evidence.

## Validation and review record

- Core tests were written before implementation and failed because the new calculator did not exist. The completed suite passes **710 XCTest + 43 Swift Testing** cases, including 11 new calculator cases. Tests cover exact/adjacent endpoints, missing/skipped/conflicting doses, gaps, provider disagreement/deletion, corrected inputs, same-episode association, stage splits/duplicates/reordering, session identity, malformed projection, midnight and both DST transitions.
- Initial iOS integration pass: **52 tests**, including new no-write snapshot coverage and existing stale/disabled/cancelled/failed provider checks. A final rerun passes **53 tests**, including the display rule that a positive subsecond duration cannot round to zero, and explicit stale-result metric invalidation.
- Initial native UI bundle: the two new normal/largest-text journeys passed. The existing saved-window journey failed to focus a text field at the navigation edge; it was adjusted to scroll the field fully into view. This bundle is not an overall passing run.
- Final native rerun: **3 passed, 0 failed**, normal text (22.781 s), largest text (85.416 s), and the saved-window save/reopen/restart/correction/disabled-Health journey (96.823 s). Largest-text teardown restores normal app text.
- Native screenshots were inspected; no off-screen ImageRenderer output was used. Review added explicit timezone/endpoint abbreviations so repeated local hours and travel do not silently share ambiguous labels, and `<1 sec` for positive subsecond delays. A dedicated native subsecond regression verifies the latter.
- Unsigned simulator build-for-testing passed. Signed development build was refreshed after the display review; signature verification passed. App and staging Debug/Release metadata all report **0.4.19 (46)**.
- SSOT, documentation, architecture boundary, dose-write boundary, Plane workflow and whitespace checks passed. The original project/scheme edits were compared against the preserved build-44 patch after normalizing intentional version increments; unrelated content remains intact. Legacy checkout and private icon drafts were not transferred.

Local artifacts: `/tmp/dosetap-metrics-core-final.log`, `/tmp/dosetap-metrics-app.xcresult`, `/tmp/dosetap-metrics-ui.xcresult`, `/tmp/dosetap-metrics-ui-final.xcresult`; isolated simulator DerivedData `/tmp/dosetap-sleep-markers-build`; signed development artifact `/tmp/dosetap-sleep-markers-device/Build/Products/Debug-iphoneos/DoseTap.app`. Temporary artifacts may be removed; this record and committed screenshots are durable evidence.

## Open gates and next action

- DOSETAP-61: build-45 owner-observed correction/reopen/restart now has evidence; foot-only pattern reuse and unchanged back/preferences remain unconfirmed; VoiceOver, broader recurring-pattern identity, privacy and release gates stay open.
- DOSETAP-57: signed-phone/live Health transitions and permissions, same-night real-data parity, VoiceOver/full accessibility and privacy/release acceptance. Awakening-count rules/implementation, wider Timeline/Dashboard/exports/Studio adoption and provider revision/deletion persistence remain outside this bounded delivery.
- DOSETAP-45: owner review of the inventory and work/shift classification contract, implementation of the planned means, real-night Dashboard/History/export/Studio parity and its existing provider/security/release gates.
- DOSETAP-70's exact-night sleeping-context, VoiceOver and privacy/release gates remain open. Build 45 installation does not close them.

Once the owner check is recorded, the next dashboard slice should implement the confirmed following-day work/off mean with separate usable/eligible/unknown counts and a clearly named sleep definition. Add four-way transition comparisons only when previous/following work status is explicit and unambiguous. Keep DOSETAP-58 independent daytime observations and DOSETAP-53 before dependent DOSETAP-54 in the delivery sequence.

Native synthetic evidence: [normal text](2026-09-11-dose-sleep-evidence/normal-text.png), [largest text](2026-09-11-dose-sleep-evidence/largest-text.png). These images show the actual SwiftUI controls; they do not close VoiceOver acceptance.
