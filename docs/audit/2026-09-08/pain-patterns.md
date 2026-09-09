# Separate and reusable pre-sleep pain entries

Date: 2026-09-08
Status: Local implementation evidence; DOSETAP-61 remains In Progress
Candidate: 0.4.19 (29)

The existing editor applied the same details to every selected area. It now edits
one area/side per save. Add another pain creates another entry, preserving each
entry's intensity, sensations, pattern and notes. The existing array and normalized
questionnaire storage/export remain the source of nightly observations.

Remember this pain saves an independent reusable preference. Saved pain patterns
show separate Use and Forget buttons. Use opens review; only saving that editor
adds the pattern to the current form. The questionnaire must still be submitted
to persist the nightly record. Patterns survive restart but never automatically
populate nightly pain answers. Forgetting a pattern does not remove current or
past observations. Settings Clear All Data also reloads the in-memory preference
list after clearing the persistent domain.

Tests cover two different back/feet entries, independent sensations and intensity,
source-row round trip, normalized entry count, preference restart, copy isolation,
forgetting, clearing preferences and refusal to overwrite unreadable data. The new
preference tests first failed to compile before their implementation existed.

The first UI run confirmed separate patterns and restart persistence, then failed
to activate a text-row target. Replacing the implicit tappable row with a visible
Use button repaired that interaction. The same journey then passed in 74.136
seconds on iPhone 17 Pro iOS 26.5; its screenshot was inspected. It confirms cancel
does not add an observation, choosing one pattern does not add the other, and
forgetting does not remove the reviewed nightly entry.

Evidence: `/tmp/dosetap-pain-ui.xcresult` (failed interaction),
`/tmp/dosetap-pain-ui2.xcresult` (passing journey),
`/tmp/dosetap-pain-final.log` (focused app tests), and
`/tmp/dosetap-pain-core.log` (655 XCTest plus 43 Swift Testing passes).
App/staging Debug/Release all report build 29. Repository checks passed.

Open limits: one entry/pattern per area and side; multiple distinct problems in the
same area/side need a separate identity change. Templates are preferences stored
in UserDefaults, not clinical events; they are not included in the clinical export
or a promised full backup. Confirmed nightly entries retain their existing export
path. Signed-device, owner, largest Dynamic Type/VoiceOver and full restoration
acceptance remain open. No diagnosis is inferred from sensations or notes.

Pre-existing project ordering and UI-test scheme changes were present during local
tests but are excluded from the commit. Hosted checks validate committed source.
