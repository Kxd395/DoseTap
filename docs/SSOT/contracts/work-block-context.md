# Work-block context

Version 1, DOSETAP-45. Dashboard work context is independent of wake scheduling, medication, alarms and session lifecycle. No existing schedule is migrated into attendance or historical roster coverage.

- Roster revisions have explicit inclusive effective dates, timezone, weekday set, recorded time and optional planned duration. Unknown start/end times stay absent. Overlapping effective revisions resolve by recorded time for the selected analysis snapshot.
- Planned context uses roster/exception records available at the reviewed sleep association's planning timestamp; confirmed context uses explicit attendance only. Scheduled never means Worked. Corrections append revisions and preserve earlier snapshots.
- A reviewed main-sleep association explicitly supplies adjacent waking dates in one timezone. Consecutive local dates support the daytime-shift rule; ambiguous/overnight associations remain Unknown. Naps cannot classify or advance a main-sleep index.
- No/Yes is Entering; Yes/Yes is Between only in the same consecutive-date work block; Yes/No is After; No/No is Off. Unanswered work status is Unknown. Block identity includes the roster revision and first work date; unknown boundaries retain unknown block counts.
- First post-block main sleep has index 1. Later off-block index stays unknown without a reviewed uninterrupted episode sequence. No recovery, exact actual hours, causation or optimal-dose result is inferred.
- Explicit phase overrides require a reason, preserve underlying observations, and carry override provenance. Analysis exports contain basis, classification version, schedule revision, phase, missingness and metric definition.
- SQLite retains the append-only context revisions behind SessionRepository. Failed/stale writes publish no success; read failures block editing. Dashboard profile/matrix use one selected outcome, separate labels for phase, eligible/missing counts and distinct known blocks. Actual outcomes never use planned shift duration as measured sleep.
- Work-date revisions may explicitly update or clear scheduled start/end and planned break timestamps. Shared date resolution keeps their source IDs and document revision; a midpoint requires two valid scheduled endpoints and planned work. A cancellation or unknown work plan cannot become a scheduled prompt. Scheduled times never establish attendance.
