# Dashboard six-month range, coverage, and iPad access

Date: 2026-09-26. Plane: DOSETAP-45. Candidate: 0.4.19 (76).

## Delivered scope

- 6M is 180 inclusive treatment dates, between 90D and 1Y. The actual date span
  is visible. The 18:00 treatment-night anchor is unchanged; this is not the
  unresolved calendar-day association repair for independent medication.
- The preceding comparison is 180 adjacent dates with no overlap. DST uses civil
  date arithmetic. Accessibility text uses a range menu instead of crowded segments.
- Apple Health previously loaded at most 120 nights. Dashboard now performs a
  separate, read-only history query for current and prior periods plus two boundary
  days (362 for 6M), bounded to 730 days. It does not modify the existing TTFW
  baseline, medication suggestions, doses, reminders, or saved sleep records.
- WHOOP still queries at most 30 days. All Time includes all loaded local dates,
  not a promise of all historical provider records. These limits are shown.
- Data Coverage adds available/recorded-night and missing counts for selected-source
  sleep, explicit following-day work/off answer, timestamped 0–10 sleepiness and
  reported final wake. Explicit zero sleepiness counts; untimed/future/invalid
  sleepiness and failed diary reads do not. No-record calendar days are not zero
  sleep or skipped doses. Existing coverage categories are retained.
- “Avg logged snoozes” clarifies that the measure counts logged events; it does not
  certify complete alarm telemetry or observed zero snoozes.

## Where information lives

| Information | Current owner/location | iPad implication |
| --- | --- | --- |
| DoseTap doses, medication logs/presets, questionnaires, bathroom and other events | Local SQLite through SessionRepository → EventStorage | No automatic transfer to another DoseTap installation |
| Preferences and diagnostics | Local preferences/files; credentials use Keychain | Not a complete export/restore or synchronization promise |
| Apple Health sleep and physiological observations | Apple Health, read with permission; dashboard summaries are queried in memory | Apple Health may sync separately through the same Apple Account; this does not sync DoseTap logs |
| WHOOP observations | WHOOP provider, when feature/connection/permission are available | Provider access is separate from DoseTap local records |
| Excel/ZIP exports | Files destination chosen by the user | A file saved to shared cloud storage is a snapshot, not live app sync |
| Device backup | Controlled by the user's Apple/computer backup settings | Backup/restore is separate from app synchronization; this audit did not inspect those settings |

The shipping DoseTap target sets DoseTapCloudSyncEnabled=NO and uses local
entitlements. DoseTapStaging sets it to YES with cloud entitlements. The deferred
CloudKit implementation is not accepted as complete cross-device coverage,
conflict handling, privacy, or restore. Do not enable it merely to populate iPad.
The app already targets iPhone/iPad and has a wider dashboard layout, but an iPad
installation needs its own data; a responsive layout alone is not synchronization.

Apple reference: [Health data in iCloud](https://support.apple.com/guide/iphone/iph11f1eb698/ios).
Apple distinguishes [backup methods](https://support.apple.com/108771) from sync.
Actual owner backup/sync settings were not inspected or changed.

## Next work and acceptance

A read-only iPad snapshot importer is a bounded first option: import the versioned
Studio ZIP, preserve source IDs and provenance, show source device/export time,
and keep imported evidence separate from locally captured records. This is a
proposal, not delivered functionality. Reliable live sync is a separate project
with complete table coverage, immutable medication history, conflict/deletion
handling, offline/retry behavior, account separation and privacy/device acceptance.

The independent medication occurrence-day/following-sleep association correction
remains under DOSETAP-74. Work/off sleep comparisons must retain explicit answers
and unknown groups, not treat schedule estimates as confirmed attendance. Existing
reviewed sleep-boundary and provider-conflict gates remain under DOSETAP-56/57.

Validation results and exact integration state are maintained in the DOSETAP-45
workpad. Real six-month provider retrieval/performance, signed-phone/iPad visual
acceptance, VoiceOver, privacy and release acceptance remain separate from tests.
