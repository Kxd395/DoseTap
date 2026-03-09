# DoseTap Insights Viewer Implementation Plan

Last updated: 2026-03-09

## Decision

Implement the viewer by extending the existing macOS app target at `macos/DoseTapStudio`.

Do not create a second write-capable iPhone app.

## Why `DoseTapStudio`

- It already exists and builds.
- It already imports exported data from a folder.
- It already has a sidebar, dashboard, import flow, and analytics store.
- It is naturally better suited than iPhone for cross-night review and comparison.

## Current Reusable Pieces

- App shell:
  - `macos/DoseTapStudio/Sources/App/DoseTapStudioApp.swift`
  - `macos/DoseTapStudio/Sources/Views/ContentView.swift`
  - `macos/DoseTapStudio/Sources/Views/SidebarView.swift`
- Imported-data state:
  - `macos/DoseTapStudio/Sources/Store/DataStore.swift`
  - `macos/DoseTapStudio/Sources/Import/Importer.swift`
  - `macos/DoseTapStudio/Sources/Models/Models.swift`
- iOS reference/query logic:
  - `ios/DoseTap/Storage/SessionRepositoryQueries.swift`
  - `ios/DoseTap/Views/Dashboard/DashboardAnalyticsRefresh.swift`
  - `ios/Core/CSVExporter.swift`
  - `ios/Core/EventStore.swift`

## Architectural Target

Keep three layers:

1. Import layer
   - Reads exported CSV and later optional JSON bundles.
2. Read model layer
   - Normalizes imported data into stable viewer entities.
3. Presentation layer
   - Library, Night Detail, Trends, Correlations, Export Desk.

The read model must be the single source of truth for the viewer. Views should not compute business meaning directly from raw CSV rows.

## New Read Model

Add these types under `macos/DoseTapStudio/Sources/Insights/Models/`:

- `InsightSession`
- `InsightDoseEvent`
- `InsightSleepEvent`
- `InsightMorningOutcome`
- `InsightPreSleepFactors`
- `InsightNightSummary`
- `InsightFilterState`

Rules:

- `InsightSession` is the main aggregate root.
- Raw imported CSV rows stay separate from normalized viewer models.
- Derived values like interval, late-dose flag, wake count, and completeness score belong in the read model layer, not in SwiftUI views.

## Phase 1: Normalize Current Import

Goal: stop treating all imported rows as flat event/session arrays.

Add:

- `macos/DoseTapStudio/Sources/Insights/Builders/InsightSessionBuilder.swift`
- `macos/DoseTapStudio/Sources/Insights/Builders/InsightMetricsBuilder.swift`

Change:

- `macos/DoseTapStudio/Sources/Store/DataStore.swift`

Outcome:

- `DataStore` publishes `insightSessions: [InsightSession]`
- existing dashboard analytics derive from `InsightSession`
- event/session pairing logic moves out of ad hoc store methods into builders

## Phase 2: Library Screen

Goal: replace the current dashboard-first workflow with a real session browser.

Add:

- `macos/DoseTapStudio/Sources/Views/Library/LibraryView.swift`
- `macos/DoseTapStudio/Sources/Views/Library/LibraryFiltersView.swift`
- `macos/DoseTapStudio/Sources/Views/Library/LibrarySessionTable.swift`

Change:

- `macos/DoseTapStudio/Sources/Views/SidebarView.swift`
- `macos/DoseTapStudio/Sources/Views/ContentView.swift`

Library columns:

- session date
- Dose 1 time
- Dose 2 time
- interval
- late flag
- skipped flag
- event count
- wake count
- quality/completeness

First filters:

- date range
- late Dose 2
- skipped Dose 2
- missing outcome
- high event count
- bathroom-heavy nights

## Phase 3: Night Detail

Goal: make one night understandable at a glance.

Add:

- `macos/DoseTapStudio/Sources/Views/NightDetail/NightDetailView.swift`
- `macos/DoseTapStudio/Sources/Views/NightDetail/NightTimelineView.swift`
- `macos/DoseTapStudio/Sources/Views/NightDetail/NightSummaryCards.swift`
- `macos/DoseTapStudio/Sources/Views/NightDetail/NightEventsTable.swift`

Behavior:

- selecting a session in Library opens Night Detail
- render dose milestones, snoozes, skips, and sleep events on one timeline
- show derived metrics in cards, not only raw rows

## Phase 4: Trends

Goal: make repeated patterns visible.

Add:

- `macos/DoseTapStudio/Sources/Views/Trends/TrendsView.swift`
- `macos/DoseTapStudio/Sources/Views/Trends/TrendCharts.swift`
- `macos/DoseTapStudio/Sources/Views/Trends/TrendControls.swift`

First trend panels:

- Dose 1 to Dose 2 interval over time
- late-dose rate by week
- skipped-dose rate by week
- event count by night
- wake-final and bathroom frequency over time
- morning outcome trends

## Phase 5: Correlations

Goal: compare pre-sleep inputs to next-morning outcomes.

Precondition:

- importer must understand exported pre-sleep and morning-check-in data

Add:

- `macos/DoseTapStudio/Sources/Views/Correlations/CorrelationsView.swift`
- `macos/DoseTapStudio/Sources/Insights/Analysis/CorrelationAnalyzer.swift`

Start simple:

- grouped comparisons
- distributions
- before/after summaries

Avoid fake precision:

- no predictive scoring
- no “AI insight” copy without defensible math

## Phase 6: Better Import Contract

Current CSV import is workable but too thin for the full viewer.

Add support for a richer export bundle:

- `sessions.csv`
- `events.csv`
- `inventory.csv`
- `pre_sleep.csv`
- `morning_checkin.csv`
- optional `metadata.json`

If needed later:

- `insight_bundle.json` as a normalized portable export

Do not change the existing CSV export contract casually. Add richer export alongside it.

## Concrete File Moves And Additions

First pass file layout:

- `macos/DoseTapStudio/Sources/Insights/Models/InsightModels.swift`
- `macos/DoseTapStudio/Sources/Insights/Builders/InsightSessionBuilder.swift`
- `macos/DoseTapStudio/Sources/Insights/Builders/InsightMetricsBuilder.swift`
- `macos/DoseTapStudio/Sources/Views/Library/LibraryView.swift`
- `macos/DoseTapStudio/Sources/Views/NightDetail/NightDetailView.swift`
- `macos/DoseTapStudio/Sources/Views/Trends/TrendsView.swift`

Existing files to shrink:

- `macos/DoseTapStudio/Sources/Store/DataStore.swift`
- `macos/DoseTapStudio/Sources/Views/DashboardView.swift`
- `macos/DoseTapStudio/Sources/Views/SidebarView.swift`

## Testing Plan

Add tests under `macos/DoseTapStudio/Tests/`:

- `InsightSessionBuilderTests.swift`
- `InsightMetricsBuilderTests.swift`
- `ImporterBundleTests.swift`

Key assertions:

- interval classification is correct
- skipped vs late vs completed nights do not alias
- event grouping is stable across timezone boundaries
- missing files degrade cleanly
- duplicate rows do not inflate metrics silently

## MVP Delivery Order

1. Normalize import into `InsightSession`.
2. Ship Library.
3. Ship Night Detail.
4. Rebuild Dashboard on top of `InsightSession`.
5. Add Trends.
6. Add richer export contract.
7. Add Correlations.

## Non-Goals For The First Build Pass

- iCloud sync
- editing imported nights
- direct database access into the iOS app sandbox
- real-time phone-to-Mac transport
- clinician multi-user sharing

## Recommended Next Coding Pass

Start in `macos/DoseTapStudio` with:

1. `InsightModels.swift`
2. `InsightSessionBuilder.swift`
3. `DataStore.swift` migration to publish `insightSessions`
4. `LibraryView.swift`

That is the shortest path to a useful viewer without destabilizing the shipping iOS app.
