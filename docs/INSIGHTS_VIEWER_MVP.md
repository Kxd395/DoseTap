# DoseTap Insights Viewer MVP

Last updated: 2026-03-09

## Recommendation

Build a read-only companion viewer for the data DoseTap already captures.

Do not build a second full tracker first. `DoseTap` should remain the system of record for capture, timing, and editing. The viewer should consume a stable read model or exported files and focus on analysis, comparison, and presentation.

## Why This Is The Right Next Product

- The repo already has stable session, dose-event, and sleep-event query surfaces.
- The app already exports CSV and support bundles.
- A second write-capable app would duplicate storage logic and recreate split-brain risk.
- The actual product gap is not logging. It is better cross-night viewing, filtering, and interpretation.

## Source Data To Reuse

- `ios/Core/EventStore.swift`
- `ios/Core/CSVExporter.swift`
- `ios/DoseTap/Storage/SessionRepositoryQueries.swift`
- `ios/DoseTap/Views/Dashboard/DashboardAnalyticsRefresh.swift`
- `ios/DoseTap/SettingsActions.swift`
- `ios/DoseTap/Views/NightReviewExport.swift`

## Product Shape

Preferred order:

1. Shared read model inside the existing repo.
2. Read-only companion viewer on macOS or iPad.
3. Optional private web viewer later if remote access matters.

Avoid starting with a second iPhone capture app. The small-screen experience is already covered by `DoseTap`, and a phone-only viewer adds less value than a larger-screen analysis surface.

## MVP Goals

- Compare nights side by side.
- Replay a single night with cleaner event context.
- Show trends for dose timing, skips, late overrides, wakeups, and symptom/event frequency.
- Correlate pre-sleep inputs with morning outcomes.
- Export a cleaner analyst-friendly summary.

## MVP Screens

### 1. Library

- Session list with search, filters, and saved views.
- Filters: date range, late Dose 2, skipped Dose 2, wake count, bathroom count, pain/anxiety/environment markers.
- Quick badges for outlier nights.

### 2. Night Detail

- Read-only timeline replay of Dose 1, Dose 2, snoozes, skip, wake events, sleep events, and check-in markers.
- Session summary panel with total interval, target drift, number of awakenings, event counts, and completion status.
- Notes and exported artifacts preview.

### 3. Trends

- Dose 1 to Dose 2 interval over time.
- Late-dose and skip rate by week and month.
- Sleep-event frequencies over time.
- Morning score and symptom trends.
- Pre-sleep factor overlays against next-morning outcomes.

### 4. Correlations

- Compare selected pre-sleep factors against outcomes:
  - caffeine, food timing, exercise, stress, pain, naps, substances
- Show simple descriptive relationships first, not overfit predictions.

### 5. Export Desk

- Produce clean CSV and summary views for clinician review or personal analysis.
- Bundle nightly timeline snapshots plus normalized tables.

## Read Model Boundary

The viewer should not talk directly to mutable app internals. Create a stable read model such as:

- `InsightSession`
- `InsightDoseEvent`
- `InsightSleepEvent`
- `InsightMorningOutcome`
- `InsightPreSleepFactors`

That model can be built from:

- local repository queries for an in-repo companion target
- exported CSV/JSON for a separate viewer app

## MVP Technical Shape

### Option A: Same repo, companion target

Best first step.

- Add a macOS or iPad target that imports the shared read model.
- Reuse existing query and export code.
- No sync or write path.
- Lowest risk and fastest iteration.

### Option B: Separate app

Only after the read model is stable.

- Ingest exported files or a signed local bundle.
- Keep it read-only.
- Do not duplicate `SessionRepository`, dose registration, or alarm logic.

## Explicit Non-Goals

- No dose logging.
- No alarms or notifications.
- No deep-link write actions.
- No CloudKit-first architecture.
- No clinician portal or multi-user account system in MVP.

## MVP Data Contract

Required fields:

- session date/key
- Dose 1 time
- Dose 2 time
- snooze count
- skipped flag
- wake final time
- sleep events with type, timestamp, notes
- dose events with type, timestamp, metadata
- pre-sleep factors
- morning check-in outcome fields

Nice-to-have fields:

- HealthKit sleep segments
- WHOOP recovery/sleep metrics
- support-bundle diagnostics markers

## Delivery Order

1. Define the shared read model and adapters from current repository queries.
2. Build Library + Night Detail.
3. Add Trends.
4. Add Correlations.
5. Add export-focused presentation.

## Recommendation Summary

Yes, build a better viewer. No, do not start with another full tracker. The right move is a read-only `DoseTap Insights` companion built on a stable exported/shared read model, with macOS or iPad as the best first surface.
