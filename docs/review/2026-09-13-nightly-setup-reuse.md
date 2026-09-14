# Nightly setup reuse

Date: 2026-09-13
Scope: DOSETAP-70; preserve DOSETAP-51 fresh-observation boundaries
Candidate: 0.4.19 (56)

## Report and source findings

The owner reports that room, bed and sleeping-alone/pet information is not appearing in the next check-in and requests a checkbox to reuse information each night. Source inspection found that sleeping setup had separate Save as usual and Use usual buttons, but no automatic reuse preference. Room reuse consulted only the most recent completed pre-sleep log; a later blank room section could hide earlier choices. This is an identified workflow gap, not proof of lost owner database rows. No personal records were inspected.

## Bounded behavior

The sleeping-arrangement section now offers **Use usual setup every night**. Enabling saves the current setup (or the saved usual setup when the draft is empty) and fills missing fields in future new live pre-sleep drafts. It includes people/bed arrangement, conditional shared space, pets and location. Each draft remains editable and must still be submitted. Save as usual setup explicitly updates future defaults; a one-night edit does not silently change them. Disabling stops automatic reuse while retaining the saved setup. Forget removes the setup and opt-in; past records remain intact. History and existing blank/skipped records do not receive automatic answers.

**Remember room setup** retains only temperature, noise and non-medication sleep aids in a separate local preference after successful live questionnaire completion. New drafts prefer that saved setup over the previous questionnaire; missing fields in a later completed night do not erase it. Explicit new room choices update the remembered values. Disabling stops automatic reuse without clearing the current draft. The explicit Use room setup action still fills only unanswered room fields and opens page 3.

Morning's **Remember room and equipment setup** continues to retain its existing four choices after a successful morning save. Its control and the pre-sleep room control are accessible checkbox-style buttons with explicit On/Off state. Actual morning arrangement, symptoms and sleep results remain fresh observations. Planned setup is shown through the matching night's existing plan snapshot, with an explicit Same as planned choice.

## What can be remembered

| Information | Reuse rule |
| --- | --- |
| Planned bed/location, people and pets | New optional automatic pre-sleep setup; visible and editable before submission |
| Room temperature/noise and non-medication sleep aids | Saved room choices when the room checkbox is enabled |
| Morning room choices and therapy device | Existing morning setup preference; selecting the section still establishes this morning's use/conditions |
| Recurring pain location/sensations | Existing saved pattern library; choose a fresh level before adding a morning observation. Broader recurring prompts and independent pattern identity remain DOSETAP-61 work |
| Actual sleeping arrangement and its effect | Review this night's plan, then explicitly confirm same/different/unsure; do not assume last night's result |
| Food, caffeine, alcohol, exercise, naps and occurrence times | Fresh observations; yesterday's answers are not today's confirmed facts |
| Dose taken/skipped/time, alarm response | Existing explicit medication/diary actions; never reusable questionnaire defaults |
| Pain/severity, stress, mood, sleep quality, sleepiness and symptoms | Fresh answers. Broader optional suggestion/review controls need the planned unanswered-state/model work; this slice does not automatically confirm them |

This gives reusable setup a clear checkbox without treating nearly every prior answer as a new observation. Further per-section preference controls must distinguish a suggestion from a confirmed current answer and preserve existing source/normalized/export semantics.

## Storage, export and validation boundaries

The two new local keys are documented in the [data dictionary](../SSOT/contracts/DataDictionary.md). Preferences remain separate from SQLite questionnaire observations and are not a complete backup. Submitted pre-sleep `sleepingSetup`, room fields and morning `sleepingContext` continue through the existing repository/event-store/source-normalized/export paths. No provider data, quick log, medication record or historical answer is rewritten.

Validation passed: 710 XCTest plus 43 Swift Testing core cases; all 493 iOS tests, including preference, questionnaire persistence and source/export coverage; three native UI journeys for automatic setup at normal/largest text and the existing morning arrangement at largest text. After shortening the checkbox label, both automatic-setup journeys passed again, with native screenshots inspected. Tests cover opt-in/off, reconstructed preferences, fill-only behavior, existing drafts, forgetting, room preservation, exclusion of daily fields, restart/new-draft reuse and one-night corrections. The first UI attempt failed before interaction because the simulator runner was busy; the ready-device retry passed. App version checks passed for DoseTap and DoseTapStaging Debug/Release. SSOT, documentation, Plane, architecture, dose-write, repository hygiene and whitespace checks passed. Exact integration and remaining acceptance evidence belong to the DOSETAP-70 workpad and PR.

Signed-phone exact-night reuse/save/reopen, VoiceOver/full accessibility and sensitive-data privacy/release acceptance remain open until separately observed. A merged build or simulator pass does not close them. The previous sleeping-arrangement delivery and its owner gates remain in [the build-44 record](2026-09-10-sleeping-arrangement-delivery.md).
