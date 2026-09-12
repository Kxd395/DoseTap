# Stored field inventory — build 50

Status: Source inventory; paired with the [audit findings](collection-store-export-audit.md).

Baseline: `253cd3e`, 2026-09-12. Verified against the initialized test database (base DDL plus migrations) and app models; this is a field-name inventory, not proof every field has been actively answered. Full meanings remain in the [data dictionary](../../SSOT/contracts/DataDictionary.md). JSON objects use additive fields and do not require a SQL column per answer.

## SQLite columns

There are 18 tables including the internal migration ledger. The table/export ownership map is in the findings report. [Effective schema evidence](evidence/effective-schema.json) is a schema-only PRAGMA readback at user_version 5; no clinical rows were queried. It includes migration-added hazard, terminal-state and sleep-environment columns.

| Table | Columns |
| --- | --- |
| `body_map_points` | `id`, `location_id`, `map_id`, `normalized_x`, `normalized_y`, `zoom_level`, `body_view` |
| `checkin_submissions` | `id`, `source_record_id`, `session_id`, `session_date`, `checkin_type`, `questionnaire_version`, `user_id`, `submitted_at_utc`, `local_offset_minutes`, `responses_json`, `created_at` |
| `cloudkit_tombstones` | `key`, `record_type`, `record_name`, `created_at` |
| `current_session` | `id`, `dose1_time`, `dose2_time`, `snooze_count`, `dose2_skipped`, `session_date`, `session_id`, `session_start_utc`, `session_end_utc`, `updated_at`, `terminal_state` |
| `dose_events` | `id`, `event_type`, `timestamp`, `session_date`, `session_id`, `metadata`, `created_at`, `is_hazard` |
| `inventory_snapshots` | `id`, `as_of_utc`, `medication_name`, `bottles_remaining`, `doses_remaining`, `estimated_days_left`, `next_refill_date`, `notes`, `created_at` |
| `medication_events` | `id`, `session_id`, `session_date`, `medication_id`, `dose_mg`, `dose_unit`, `formulation`, `taken_at_utc`, `local_offset_minutes`, `notes`, `confirmed_duplicate`, `created_at` |
| `morning_checkins` | `id`, `session_id`, `timestamp`, `session_date`, `sleep_quality`, `feel_rested`, `grogginess`, `sleep_inertia_duration`, `dream_recall`, `has_physical_symptoms`, `physical_symptoms_json`, `has_respiratory_symptoms`, `respiratory_symptoms_json`, `mental_clarity`, `mood`, `anxiety_level`, `stress_level`, `stress_context_json`, `readiness_for_day`, `had_sleep_paralysis`, `had_hallucinations`, `had_automatic_behavior`, `fell_out_of_bed`, `had_confusion_on_waking`, `used_sleep_therapy`, `sleep_therapy_json`, `timing_context_json`, `notes`, `created_at`, `has_sleep_environment`, `sleep_environment_json` |
| `pre_sleep_logs` | `id`, `session_id`, `created_at_utc`, `local_offset_minutes`, `completion_state`, `answers_json`, `created_at` |
| `schema_migrations` | `id`, `applied_at` |
| `sleep_events` | `id`, `event_type`, `timestamp`, `session_date`, `session_id`, `color_hex`, `notes`, `created_at` |
| `sleep_sessions` | `session_id`, `session_date`, `start_utc`, `end_utc`, `terminal_state`, `created_at`, `updated_at` |
| `supply_state` | `id`, `payload` |
| `symptom_command_log` | `idempotency_key`, `command_type`, `source`, `source_record_id`, `source_entry_key`, `session_id`, `session_date`, `status`, `created_event_id`, `error_code`, `created_at`, `completed_at` |
| `symptom_events` | `id`, `session_id`, `session_date`, `phase`, `source`, `source_record_id`, `source_entry_key`, `kind`, `noticed_at`, `severity_0_10`, `sleep_disruption`, `still_present`, `functional_impact`, `note`, `schema_version`, `app_version`, `created_at` |
| `symptom_locations` | `id`, `event_id`, `body_side`, `body_region_id`, `anatomy_layer`, `precision`, `confidence` |
| `symptom_summaries` | `session_date`, `session_id`, `symptom_count`, `highest_severity`, `sleep_disruption_count`, `still_present_count`, `summary_hash`, `rebuilt_at` |
| `work_wake_schedule` | `id`, `payload`, `updated_at` |

## Pre-sleep answer fields

The following 44 optional properties are the app source model, including legacy fields. `rawAnswersJson` is a decode/re-encode of this model, not a byte-for-byte SQLite blob backup. Dedicated summary/CSV columns cover only a subset.

| Key | Type |
| --- | --- |
| `intendedSleepTime` | `IntendedSleepTime?` |
| `stressLevel` | `Int?` |
| `stressDriver` | `StressDriver?` |
| `stressDrivers` | `[StressDriver]?` |
| `stressProgression` | `StressProgression?` |
| `stressNotes` | `String?` |
| `laterReason` | `LaterReason?` |
| `bodyPain` | `PainLevel?` |
| `painEntries` | `[PainEntry]?` |
| `painLocations` | `[PainLocation]?` |
| `painType` | `PainType?` |
| `stimulants` | `Stimulants?` |
| `caffeineSources` | `[Stimulants]?` |
| `caffeineLastIntakeAt` | `Date?` |
| `caffeineAmounts` | `CaffeineAmounts?` |
| `caffeineLastAmountMg` | `Int?` |
| `caffeineDailyTotalMg` | `Int?` |
| `plannedTotalNightlyMg` | `Int?` |
| `plannedDoseSplitRatio` | `[Double]?` |
| `plannedDose1Mg` | `Int?` |
| `plannedDose2Mg` | `Int?` |
| `alcohol` | `AlcoholLevel?` |
| `alcoholLastDrinkAt` | `Date?` |
| `alcoholLastAmountDrinks` | `Double?` |
| `alcoholDailyTotalDrinks` | `Double?` |
| `exercise` | `ExerciseLevel?` |
| `exerciseType` | `ExerciseType?` |
| `exerciseLastAt` | `Date?` |
| `exerciseDurationMinutes` | `Int?` |
| `napToday` | `NapDuration?` |
| `napCount` | `Int?` |
| `napTotalMinutes` | `Int?` |
| `napLastEndAt` | `Date?` |
| `lastFood` | `LastFoodEntry?` |
| `lateMeal` | `LateMeal?` |
| `lateMealEndedAt` | `Date?` |
| `screensInBed` | `ScreensInBed?` |
| `screensLastUsedAt` | `Date?` |
| `roomTemp` | `RoomTemp?` |
| `sleepingSetup` | `SleepingSetup?` |
| `noiseLevel` | `NoiseLevel?` |
| `sleepAids` | `SleepAid?` |
| `sleepAidSelections` | `[SleepAid]?` |
| `notes` | `String?` |

Nested records: pain entry = area, side, intensity, sensations, optional pattern/notes; last food = finishedAt, kind, highFat, notes; caffeine amounts = version, source, separate optional last/daily US fl oz and caffeine mg; sleeping setup = version, arrangement, sharedSpace, pets, location.

## Morning source payloads

All scalar columns are listed above. JSON families are physical symptoms (independent pain entries, headache, soreness/stiffness, reflux, restless legs, bathroom urgency), respiratory symptoms (congestion/cough/breathing/allergy details), sleep therapy (device/compliance), environment (temperature/noise/aids and sleepingContext), stress (drivers/progression/notes), timing (night/work/wake/demand, dose reasons, optional clinical context). Exact UI choices and nested groups are inventoried in the [questionnaire review](../../review/2026-09-10-sleep-questionnaire-review.md).

## Literal normalized response keys

Extracted from source mapping literals. The History writers add `history.provenance` for both questionnaires (occurrence/recording times, correction reason and prior-record evidence). Dynamic keys inside nested records and revision payloads remain in their JSON; this list is not a claim that normalized keys are lossless or all actively answered.

### Pre-sleep

`history.provenance`, `notes.anything_else`, `overall.stress`, `pain.any`, `pain.entries`, `pain.level`, `pain.locations`, `pain.overall_intensity`, `pain.sensations`, `pain.type`, `pre.day.exercise.any`, `pre.day.exercise.duration_minutes`, `pre.day.exercise.last_time_utc`, `pre.day.exercise.type`, `pre.day.exercise_level`, `pre.day.late_meal`, `pre.day.late_meal.last_time_utc`, `pre.day.nap.any`, `pre.day.nap.count`, `pre.day.nap.last_end_time_utc`, `pre.day.nap.total_minutes`, `pre.day.nap_duration`, `pre.dose_plan.any`, `pre.dose_plan.dose1_mg`, `pre.dose_plan.dose2_mg`, `pre.dose_plan.off_label_single_dose`, `pre.dose_plan.split_percentages`, `pre.dose_plan.split_ratio`, `pre.dose_plan.total_mg`, `pre.environment.noise_level`, `pre.environment.room_temp`, `pre.food.last.finished_at_utc`, `pre.food.last.high_fat`, `pre.food.last.kind`, `pre.food.last.notes`, `pre.sleep.aids`, `pre.sleep.aids.any`, `pre.sleep.aids_list`, `pre.sleep.intended_time`, `pre.sleep.later_reason`, `pre.sleep.screens_in_bed`, `pre.sleep.screens_in_bed.last_time_utc`, `pre.sleeping_setup.v1`, `pre.stress.driver`, `pre.stress.drivers`, `pre.stress.notes`, `pre.stress.progression`, `pre.substances.alcohol`, `pre.substances.alcohol.any`, `pre.substances.alcohol.daily_total_drinks`, `pre.substances.alcohol.last_amount_drinks`, `pre.substances.alcohol.last_time_utc`, `pre.substances.caffeine.amounts`, `pre.substances.caffeine.any`, `pre.substances.caffeine.last_time_utc`, `pre.substances.caffeine.legacy.daily_total`, `pre.substances.caffeine.legacy.last_amount`, `pre.substances.caffeine.legacy.unit`, `pre.substances.caffeine.source`, `pre.substances.caffeine.sources`, `pre.substances.stimulants_after_2pm`

### Morning

`history.provenance`, `clinical.co_medication_notes`, `clinical.pharmacogenomic_clinician_reviewed`, `clinical.pharmacogenomic_fast_metabolizer`, `clinical.pharmacogenomic_notes`, `clinical.sleep_disorder_notes`, `clinical.sleep_disorders`, `day_demand.type`, `daytime.cataplexy_burden`, `daytime.sleepiness`, `dose2.back_to_sleep`, `dose2.reason_notes`, `dose2.skip_reason`, `dose2.taken_reason`, `dose2.wake_method`, `headache.any`, `headache.location`, `headache.severity`, `mental.clarity`, `morning.stress.driver`, `morning.stress.drivers`, `morning.stress.notes`, `morning.stress.progression`, `narcolepsy.automatic_behavior`, `narcolepsy.confusion_on_waking`, `narcolepsy.fell_out_of_bed`, `narcolepsy.hallucinations`, `narcolepsy.sleep_paralysis`, `night.first_off_after_work_block`, `night.type`, `notes.anything_else`, `overall.anxiety`, `overall.energy`, `overall.mood`, `overall.stress`, `pain.any`, `pain.burden`, `pain.entries`, `pain.locations`, `pain.notes`, `pain.overall_intensity`, `pain.sensations`, `pain.type`, `respiratory.any`, `respiratory.congestion`, `respiratory.congestion_burden`, `respiratory.cough`, `respiratory.feverish`, `respiratory.notes`, `respiratory.sickness_level`, `respiratory.sinus_pressure`, `respiratory.throat`, `safety.driving_confidence`, `sleep.dream_recall`, `sleep.grogginess`, `sleep.inertia_duration`, `sleep.quality`, `sleep.reflux_burden`, `sleep.rested`, `sleep.restless_legs_burden`, `sleep_environment.any`, `sleep_environment.noise_level`, `sleep_environment.notes`, `sleep_environment.room_temp`, `sleep_environment.sleep_aids`, `sleep_therapy.compliance`, `sleep_therapy.device`, `sleep_therapy.notes`, `sleep_therapy.used`, `sleeping_context.v1`, `soreness.level`, `stiffness.level`, `wake.bathroom_urgency_burden`, `wake.required_at_utc`, `wake.requirement`, `wake.type`, `work.commute_minutes`, `work.shift_end_utc`, `work.shift_start_utc`

## Other versioned payloads

- Night outcome: wakeMethod, backupAlarmSet, dayType, finalWakeAt, sleepiness, assessedAt, reviewedSleepWindow, with source identity and revisions in `checkin_submissions`.
- Sleeping context: version, plan snapshot, confirmation, actual setup, impact, factors.
- Work schedule: versioned WorkWakeSchedule JSON with revision, timezone, working weekdays, wake minutes, advisory policy and dated overrides.
- Supply: versioned SupplyBackup JSON with reminder source/corrections and bottle-opening identities, occurrence and entry times.
- Preferences: saved pain patterns, usual sleeping setup, room/therapy setup, reminder choice/interval, alarm session opt-out, Typical Week/sleep plans, display/integration and quick-log settings. These are not clinical event rows and are excluded from the Studio bundle.
