# Body Map Symptom Check-in Decision

Date: 2026-06-13
Status: Backlog design decision
Tracker: DOS-22

## Decision

Build Body Map Symptom Check-in as a DoseTap-native feature. Do not import `review/dosetap_bodymap_checkin_dropin` as a wholesale package.

Use that folder only as design reference.

## Why

The current pre-sleep and morning check-ins can capture general symptom context, but they cannot precisely capture location, side, distribution, severity, and overnight change. A longer questionnaire is the wrong shape. The right product shape is a body map plus symptom events.

The durable source of truth should be symptom events and linked location records:

```text
Pre-sleep context -> SymptomCheckInCoordinator -> symptom_events
Night quick log   -> SymptomCheckInCoordinator -> symptom_events
Morning review    -> SymptomCheckInCoordinator -> symptom_events
Body map picker   -> SymptomCheckInCoordinator -> symptom_events
```

Summaries, trend cards, and exports should be rebuildable from those events.

## Non-negotiable Boundaries

- The feature records symptoms, locations, patterns, context, and change over time.
- The feature does not diagnose, triage, recommend treatment, or make urgency claims.
- Pattern labels are internal data groupings, not user-facing diagnoses.
- Raw notes, precise body map points, and detailed symptom text must not go to analytics.
- Existing pre-sleep pain fields and morning physical symptom JSON must not become a second live symptom source.
- Cloud sync for symptom events stays out of scope until conflict rules exist.

## First Implementation Slice

Do this before any body map UI:

1. Add symptom event models.
2. Add SQLite migration for events, locations, points, interventions, command log, and summary cache.
3. Add one coordinator or write gate.
4. Add tests proving all symptom writes go through that gate.
5. Add reducer tests proving summaries rebuild from events.
6. Add migration/idempotency tests.

Only after that, add the first UI slice:

1. Hand and finger picker.
2. Wrist and forearm point picker.
3. Back map.
4. Recent locations.
5. Quick night log with "same as earlier".
6. Morning review status: same, better, worse, gone, still present.

## MVP UI Rules

- Use 2D maps first. No 3D anatomy model in MVP.
- Store normalized coordinates from 0.0 to 1.0, not screen pixels.
- Keep night quick logging under 10 seconds for common symptoms.
- Use non-diagnostic labels such as "finger numbness pattern" or "hand area affected".
- Prefer recent locations so the user can repeat common symptoms without re-picking a map.
- Support Dynamic Type, Reduce Motion, and one-handed use.

## Integration With Current Check-ins

Pre-sleep:

```text
Ask if symptoms are present before sleep.
If yes, launch body/location picker and create baseline symptom event.
Context such as sleep position, wrist position, watch strap, caffeine, stress, and stretching remains context.
```

Night quick log:

```text
Offer Pain, Numbness, Tingling, Weakness, More.
Default to time now.
Support same location as earlier.
Commit through the coordinator with undo.
```

Morning:

```text
Show symptom events from the night.
Ask whether each is same, better, worse, gone, or still present.
Write review events or outcomes through the coordinator.
```

## Release Gates

- All symptom writes pass through the coordinator.
- Summaries rebuild from event history.
- Unknown body region IDs fail tests.
- Migrations are idempotent.
- No diagnosis or treatment language in UI.
- No raw symptom notes or coordinates in analytics.
- Clinician export is reviewed before shipment.

## References

- Local design reference: `review/dosetap_bodymap_checkin_dropin`
- Roadmap item: `docs/ROADMAP_TODO.md`
- FDA mobile medical app overview: https://www.fda.gov/medical-devices/digital-health-center-excellence/device-software-functions-including-mobile-medical-applications
- FDA general wellness low-risk device policy: https://www.fda.gov/regulatory-information/search-fda-guidance-documents/general-wellness-policy-low-risk-devices
- Apple App Store Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
