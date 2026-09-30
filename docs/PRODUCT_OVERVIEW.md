# DoseTap product overview

Status: Current reference, with the WHOOP roadmap explicitly identified as planned
Last verified against the source: 2026-09-30

## What DoseTap does

DoseTap is a local-first iPhone treatment diary that brings together recorded nighttime doses, sleep-related events, morning observations and optional wearable data. It helps a person review what they recorded and what their sleep provider observed for the same night. It does not automatically adjust medication or determine whether a dose is safe to take.

The person records Dose 1 and Dose 2 in DoseTap, can log events such as a bathroom visit or waking during the night, and completes a morning check-in. With permission, DoseTap reads Apple Health sleep records and supported measurements to add sleep context to the diary. Medication records, wearable measurements and questionnaire answers retain their own sources and meanings.

## How Apple Health and Apple Watch fit together

Apple Watch can record sleep information into Apple Health. DoseTap reads the available Apple Health sleep records through Apple's HealthKit interface after the person enables the integration and grants access. Apple Health is the integration point: records can also come from other supported apps or devices, so an Apple Health value is not necessarily an Apple Watch-only measurement.

DoseTap also supports reading heart rate, respiratory rate, heart-rate variability and resting heart rate from Apple Health. Availability depends on the records the provider supplies and the access the person allows. The diary can still record doses and check-in answers without wearable data. Missing measurements remain unavailable rather than being filled in from the time the app was opened.

## Which time means what?

Ending a DoseTap session and completing its check-in do **not** determine the Apple Health sleep total. These are separate records:

| Record | Where the time comes from | What it means |
| --- | --- | --- |
| Apple Health sleep onset | Start of the first asleep interval in DoseTap's selected main sleep episode | The provider-based estimate of when sleep began |
| Apple Health sleep ending | End of the last asleep interval in that episode | The estimated sleep ending; an immediately adjoining awake interval provides additional support. Without that transition, it is only the last observed sleep ending, not proof of the exact awakening time. |
| Apple Health total sleep | Duration of intervals classified as asleep in the selected main episode | Recorded sleep time; awake intervals are excluded. It is not the elapsed time between opening and closing the DoseTap session. |
| DoseTap **Wake Up** event | Time the person confirms Wake Up in the app | A logged app action that opens the morning check-in; it may occur later than the provider's sleep ending |
| Morning check-in completion | Time the answers are successfully saved and the active session closes | Completion of the diary workflow, separate from measured sleep |
| Diary **Final awakening** | Time explicitly entered and saved by the person in Wake & Next Day | A self-reported observation that can differ from the provider estimate |

For example, Apple Health may show sleep ending at **7:00 AM**, while the person taps **Wake Up at 8:00 AM** and completes the check-in at **8:05 AM**. DoseTap keeps these meanings separate. The later app actions do not add an extra hour or five minutes to the Apple Health sleep total.

The current Apple Health summary selects the main sleep episode. Its total may differ from an Apple Health daily total that includes naps or other sleep episodes. A provider-derived sleep ending is an estimate from the available observations, and a gap in recording does not establish that the person was asleep or awake.

## How dose timing and sleep are compared

DoseTap keeps the recorded dose times alongside sleep observations so the person can review their night with context. The current **estimated sleep after Dose 2** uses the recorded Dose 2 time as its starting boundary and the explicitly saved diary Final awakening as its ending boundary when available; otherwise it uses the Apple Health sleep-ending estimate. It counts only the available Apple Health intervals classified as asleep within those boundaries. It does not assume that the entire time after Dose 2 was spent sleeping.

An optional **reviewed night window** lets the person explicitly confirm a start and end for a separate Apple Health coverage check. That window is a reviewed observation period, not a measurement of sleep or a replacement for Final awakening. The coverage check distinguishes sleep, awake time, unmeasured time and conflicting observations. It does not currently replace the existing dashboard sleep totals.

These comparisons describe the recorded night; they do not establish treatment effectiveness or authorize a medication change.

## WHOOP: planned near-term DoseTap feature

A forthcoming DoseTap feature is planned to use **WHOOP data** to provide another source of sleep and recovery context alongside the person's dose records and morning check-ins. The intended experience includes WHOOP sleep measurements and supported recovery indicators, such as recovery score and heart-rate variability, when available from the connected account. This is a DoseTap roadmap item; it is not an announcement of a new feature from WHOOP itself.

Integration code already exists, but production enablement and live end-to-end validation remain open. The feature is planned for the near term, with no committed release date. Availability depends on a reviewed production connection, successful real-account testing and matching privacy disclosures.

Apple Health and WHOOP will remain clearly named sources. WHOOP values must not silently replace Apple Health values or be added to them as if they were additional sleep. A missing or unscored WHOOP result must remain missing. The current dashboard supports selecting a sleep source; that selection does not combine the two providers or make either provider authoritative for dose recording.

## Storage and sharing

DoseTap stores its clinical diary records locally on the iPhone. Apple Health and WHOOP remain the owners of their provider records. The shipping DoseTap target does not currently enable CloudKit sync. Reporting exports support deliberate review and sharing, but they are not a complete app backup and do not imply automatic transmission to a clinician or partner.

## Presentation wording

> DoseTap connects the night's dose record with sleep context and the person's morning observations. With permission, it reads Apple Health sleep data, including records from Apple Watch. The sleep measurements come from the provider's recorded sleep intervals; tapping Wake Up or finishing the morning check-in records separate diary actions and does not extend measured sleep. A planned near-term DoseTap feature will add WHOOP sleep and recovery context, with each provider clearly identified and availability subject to connection and validation.

## Supporting references

- [Current behavior and sleep boundaries](SSOT/README.md#healthkit)
- [WHOOP implementation and production validation gates](WHOOP_INTEGRATION.md)
- [Feature status and validation limits](FEATURE_TRIAGE.md)
- [Collection, storage and reporting export inventory](audit/2026-09-12/README.md)

Source verification: `ios/DoseTap/HealthKitService.swift`, `ios/DoseTap/Views/QuickEventViews.swift`, `ios/DoseTap/Storage/SessionRepository.swift`, `ios/DoseTap/Storage/SessionRepositoryCheckIn.swift`, `ios/DoseTap/Views/Dashboard/DashboardTypes.swift`, `ios/DoseTap/Views/Dashboard/DashboardAnalyticsSupport.swift`, `ios/DoseTap/Views/NightOutcomeView.swift`, `ios/DoseTap/Services/ReviewedNightSleepLoader.swift` and `ios/Core/NightOutcome.swift`. This explanation summarizes current source behavior; it does not establish which build is installed on a particular phone or close production/provider acceptance gates.
