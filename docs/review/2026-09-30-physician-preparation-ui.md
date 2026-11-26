# Physician preparation and immutable-preview UI checkpoint

The Dashboard now opens an explicit visit-preparation flow. Opening the form or a saved preview does not query providers. Prepare selected period captures the exact date bounds, timezone, selected sleep source, overnight filters and partial-value policy using a fresh isolated dashboard model. Cancellation and changed selections invalidate pending preparation. Daytime observations keep independent occurrence-time membership.

The form records completed visits separately from future appointments, supports several unscored activity notes and original recorded examples, and requires an unfinished activity draft to be included or cleared before saving. Saved previews are immutable. Later form edits cannot modify an archived preview. Sharing requires the separate preview Share action; cancelling its sheet does not send or save the report elsewhere.

## Validation evidence

- Native preparation and adapter regression suite: 9 passed on iPhone 17 Pro simulator `21E15B3C-E6DD-4107-82B3-3AFF80BEB65C`; `.build/physician-evidence/preparation-native-tests-2.xcresult` and matching log.
- Native UI journeys: normal (112.528 seconds) and largest accessibility text (418.195 seconds) passed; `.build/physician-evidence/preparation-ui-tests-3.xcresult` and matching log. Journeys exercise explicit 28-day preparation, a completed visit, two notes, a question, saved preview, explicit share cancellation, and archive reopening after changing the unsaved form.
- Initial UI discovery returned zero tests because the UI target requires explicit project membership. The test was registered and that run was not counted. The first real normal-size journey passed; largest-text traversal exposed an offscreen-field scrolling assumption in the test helper. Its direction is now explicit when revisiting earlier fields.
- Plane workflow: 15 tests / 80 assertions. Architecture, SSOT, project syntax and whitespace checks passed in `.build/physician-evidence/preparation-guards.log`.
- No DoseCore behavior changed in this checkpoint; its existing full-suite evidence is recorded in the preceding adapter checkpoint. The enabled commit hook supplies the generic simulator compile gate; `.build/physician-evidence/preparation-commit.log` records its result.

Exported screenshots in `.build/physician-evidence/preparation-ui-proof-3` were inspected: report fields wrap and Share/Close remain usable. The system large navigation title truncates at maximum text size; its inline title is complete after scrolling. The tested production tree includes the Dashboard navigation link, route, form, project registrations and simulator-only in-memory synthetic fixture. The fixture neither reads nor writes real patient records and makes no provider query. No temporary navigation accommodation is omitted from this checkpoint.

Shared work/daytime context, reminder chronology, independent nap evidence and provider endpoint compatibility must still be consumed by the final canonical report adapter. Integrated acceptance, physical-device observation, provider/privacy review and parent Plane closeout remain open. This checkpoint does not change build version or install an app.
